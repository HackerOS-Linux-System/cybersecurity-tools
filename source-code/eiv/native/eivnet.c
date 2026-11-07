#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
#include <stdint.h>

static unsigned char g_req[4096];
static int g_req_len = 0;
static unsigned char g_resp[8192];
static int g_resp_len = 0;
static char g_text[8193];

void eiv_req_reset(void) { g_req_len = 0; }
void eiv_req_push(int64_t b) { if (g_req_len < (int)sizeof g_req) g_req[g_req_len++] = (unsigned char)(b & 0xFF); }
int64_t eiv_resp_len(void) { return g_resp_len; }
int64_t eiv_resp_byte(int64_t i) { return (i >= 0 && i < g_resp_len) ? g_resp[i] : -1; }

/* response as printable text (non-printables -> '.'), NUL-terminated */
const char *eiv_resp_text(void) {
    for (int i = 0; i < g_resp_len; i++) {
        unsigned char c = g_resp[i];
        g_text[i] = (c == '\r' || c == '\n' || (c >= 32 && c < 127)) ? (char)c : '.';
    }
    g_text[g_resp_len] = '\0';
    return g_text;
}

static int wait_fd(int fd, short ev, int timeout_ms) {
    struct pollfd p = { fd, ev, 0 };
    int rc;
    do { rc = poll(&p, 1, timeout_ms); } while (rc < 0 && errno == EINTR);
    return rc > 0 ? (p.revents & (ev | POLLERR | POLLHUP)) != 0 : 0;
}

static int fill_addr(struct sockaddr_in *a, const char *ip, int64_t port) {
    memset(a, 0, sizeof *a);
    a->sin_family = AF_INET;
    a->sin_port = htons((uint16_t)port);
    return inet_pton(AF_INET, ip, &a->sin_addr) == 1;
}

static int read_resp(int fd, int timeout_ms) {
    g_resp_len = 0;
    if (!wait_fd(fd, POLLIN, timeout_ms)) return 0;
    ssize_t n = recv(fd, g_resp, sizeof g_resp, 0);
    g_resp_len = n > 0 ? (int)n : 0;
    return g_resp_len;
}

/* Non-blocking connect with a real SO_ERROR check. Returns an fd (blocking) or -1. */
int64_t eiv_tcp_connect(const char *ip, int64_t port, int64_t timeout_ms) {
    struct sockaddr_in a;
    if (!fill_addr(&a, ip, port)) return -1;
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int fl = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, fl | O_NONBLOCK);
    int rc = connect(fd, (struct sockaddr *)&a, sizeof a);
    if (rc < 0 && errno != EINPROGRESS) { close(fd); return -1; }
    if (rc < 0) {
        if (!wait_fd(fd, POLLOUT, (int)timeout_ms)) { close(fd); return -1; }
        int err = 0; socklen_t el = sizeof err;
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &el) < 0 || err != 0) { close(fd); return -1; }
    }
    fcntl(fd, F_SETFL, fl);
    return fd;
}

void eiv_close(int64_t fd) { if (fd >= 0) close((int)fd); }

/* send the request buffer (if any) and read one response; returns response length */
int64_t eiv_tcp_exchange(int64_t fd, int64_t timeout_ms) {
    if (fd < 0) return -1;
    if (g_req_len > 0 && send((int)fd, g_req, g_req_len, MSG_NOSIGNAL) < 0) { g_resp_len = 0; return 0; }
    return read_resp((int)fd, (int)timeout_ms);
}

/* one UDP datagram out, one back; returns response length (0 = no answer, -1 = error) */
int64_t eiv_udp_exchange(const char *ip, int64_t port, int64_t timeout_ms) {
    struct sockaddr_in a;
    if (!fill_addr(&a, ip, port)) return -1;
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return -1;
    g_resp_len = 0;
    if (sendto(fd, g_req, g_req_len, 0, (struct sockaddr *)&a, sizeof a) < 0) { close(fd); return -1; }
    int n = read_resp(fd, (int)timeout_ms);
    close(fd);
    return n;
}
