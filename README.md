# Cybersecurity Tools — co to jest?

Kompletny ekosystem własnych narzędzi cyberbezpieczeństwa HackerOS, napisanych
niemal wyłącznie we własnych językach projektu: **H#**, **HackerScript** i
**Hacker Lang**.

> Wszystkie narzędzia służą do pracy na systemach, do których masz prawo
> dostępu (własnych lub z pisemną zgodą właściciela). To zestaw defensywny /
> edukacyjny — audyty, detekcja, twardnienie konfiguracji — a nie zestaw do
> ataku na cudzą infrastrukturę.

## Skład pakietu (37 narzędzi)

| Język | Udział | Liczba |
|---|---|---|
| H# | ~54% | 20 |
| HackerScript | ~38% | 14 |
| Hacker Lang | ~8% | 3 (pojedynczy plik `.hl` na narzędzie) |

### H# (`source-code/<tool>/src/main.h#`, budowane przez `bit build`)
- **eic** — instalator/dopasowywacz wariantów kernela (przepisany z Odin)
- **eiq** — dopasowywacz wariantu kernela do mikroarchitektury CPU (przepisany z Odin, bez wywołań Pythona)
- **eiv** — skaner rekonesansu SCADA/IoT/Web3 (przepisany z Odin; warstwa sieciowa na hex + `/dev/tcp`/`/dev/udp` zamiast literałów bajtowych)
- **bph** — kontenerowe laboratorium pentestowe (Kali/BlackArch) + `own-tools`; konsolidacja dawnego backendu Odin + CLI Crystal + TUI Go + skryptu Python w jeden plik H#
- **hashkit** — hashe, HMAC, weryfikacja plików, entropia, identyfikacja hashy
- **rip** — kalkulator IPv4/CIDR i pomocnik DNS
- **hct** — menedżer narzędzi w kontenerach (`hct install metasploit`, `hct run nmap ...`, `hct shim`) — koncepcja „narzędzie jak natywne, silnik w kontenerze” z Podman/Docker
- **portwatch** — skaner portów TCP z porównaniem do zapisanej bazowej linii
- **tlscheck** — audyt certyfikatu i protokołów TLS
- **hdrcheck** — audyt nagłówków bezpieczeństwa HTTP i ciasteczek
- **fim** — monitor integralności plików (manifesty SHA-256)
- **logsift** — analiza logów SSH (brute-force) i logów dostępu web
- **sshaudit** — audyt hardeningu `sshd`
- **secretscan** — skaner wyciekniętych danych uwierzytelniających (wynik maskowany)
- **sysharden** — audyt hardeningu jądra/sieci/kont Linuksa
- **jam** — DETEKTOR zalewu deauth Wi-Fi (defensywny, nie atakujący)
- **netwatch** — podgląd połączeń i nasłuchujących gniazd na żywo
- **wificheck** — sanity-check konfiguracji Wi-Fi/AP
- **phishcheck** — heurystyczny checker URL-i i nagłówków e-mail pod kątem phishingu
- **cybersecurity-cli** (`csec`) — centralny launcher listujący i uruchamiający całą paczkę

### HackerScript (`source-code/<tool>/cmd/main.hcs`, budowane przez `hackerc build` → Rust/Cargo)
`passforge`, `walldesign`, `cryptolab`, `netmap`, `dnsshield`, `backupaudit`,
`licwatch`, `ratrace`, `robotsaudit`, `cveradar`, `dockerlint`, `cronaudit`,
`jwtinspect`, `typosquat`

### Hacker Lang (`source-code/<tool>/main.hl`, uruchamiane bezpośrednio: `hl run main.hl`)
`pcapstat`, `zipbomb-check`, `hashverify`

## Budowanie

```sh
bit build            # cały workspace H# (patrz Bit.hk)
```

Dla narzędzi HackerScript, w katalogu danego narzędzia:

```sh
hackerc build cmd/main.hcs -o build/
cd build && cargo build --release
```

Dla narzędzi Hacker Lang:

```sh
hl run source-code/pcapstat/main.hl
```
