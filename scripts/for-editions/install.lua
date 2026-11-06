#!/usr/bin/env lua
-- ─────────────────────────────────────────────────────────────────────────────
-- HackerOS cybersecurity-tools — installer for editions (live-build hooks)
--
--   lua install.lua              full install:
--                                  download pack.tar.gz, unpack it, chmod a+x on
--                                  everything, copy the contents to /usr/local/bin/
--
--   lua install.lua --default    minimal install:
--                                  only `hct` and `cybersec` are taken from the
--                                  archive (chmod a+x) and put in /usr/bin/ —
--                                  everything else in the archive is ignored
--
--   lua install.lua --version X  use release X instead of the VERSION below
--   lua install.lua --help
--
-- Written for a live-build chroot hook: no tty, no sudo, a bare PATH, root user.
-- Works on Lua 5.1 – 5.4 / LuaJIT. Only needs: tar, gzip and curl (or wget).
-- Exit code 0 = installed, non-zero = failed (so the hook fails the build).
--
-- Environment overrides (mostly for testing):
--   CYBERSEC_VERSION   release tag            (default: VERSION below)
--   CYBERSEC_URL       full URL of the pack   (default: the GitHub release URL)
--   CYBERSEC_BIN_DIR   full-install target    (default: /usr/local/bin)
--   CYBERSEC_USR_DIR   --default target       (default: /usr/bin)
-- ─────────────────────────────────────────────────────────────────────────────

-- Release of HackerOS-Linux-System/cybersecurity-tools to install.
-- It is used verbatim as the tag in the URL, so write it exactly as the tag is
-- named on GitHub (e.g. "0.2" or "v0.2").
local VERSION = "0.2"

local REPO_URL    = "https://github.com/HackerOS-Linux-System/cybersecurity-tools"
local PACK_NAME   = "pack.tar.gz"
local FULL_DIR    = "/usr/local/bin"
local DEFAULT_DIR = "/usr/bin"

-- Files kept by `--default` (matched by file name, wherever they sit in the archive).
local DEFAULT_FILES = { "hct", "cybersec" }

-- ── helpers ──────────────────────────────────────────────────────────────────

local function log(msg)  io.stdout:write("[cybersec-install] " .. msg .. "\n") end
local function warn(msg) io.stderr:write("[cybersec-install] warning: " .. msg .. "\n") end
local function die(msg, code)
  io.stderr:write("[cybersec-install] ERROR: " .. msg .. "\n")
  os.exit(code or 1)
end

-- Quote a string for /bin/sh.
local function sq(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Runs a shell command. Returns true on exit code 0.
-- (os.execute returns a number in Lua 5.1 and true/nil,"exit",code in 5.2+.)
local function sh(cmd)
  local a, _, c = os.execute(cmd)
  if type(a) == "number" then return a == 0 end
  if a == true then return true end
  return c == 0
end

-- stdout of a command, trimmed.
local function capture(cmd)
  local p = io.popen(cmd .. " 2>/dev/null")
  if not p then return "" end
  local out = p:read("*a") or ""
  p:close()
  return (out:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function have(tool)
  return sh("command -v " .. sq(tool) .. " >/dev/null 2>&1")
end

local function getenv_or(name, default)
  local v = os.getenv(name)
  if v == nil or v == "" then return default end
  return v
end

-- ── arguments ────────────────────────────────────────────────────────────────

local function usage()
  io.stdout:write([[
Usage: lua install.lua [--default] [--version X] [--help]

  (no flags)     unpack the whole pack to /usr/local/bin/ (everything chmod a+x)
  --default      take only hct and cybersec from the pack -> /usr/bin/ (chmod a+x)
  --version X    install release X instead of the built-in VERSION (]] .. VERSION .. [[)
  -h, --help     this text
]])
end

local default_mode = false
local version      = getenv_or("CYBERSEC_VERSION", VERSION)

do
  local a = arg or {}
  local i = 1
  while i <= #a do
    local v = a[i]
    if v == "--default" then
      default_mode = true
    elseif v == "--version" then
      i = i + 1
      if not a[i] or a[i] == "" then die("--version needs a value", 2) end
      version = a[i]
    elseif v:match("^%-%-version=") then
      version = v:gsub("^%-%-version=", "")
      if version == "" then die("--version needs a value", 2) end
    elseif v == "-h" or v == "--help" then
      usage()
      os.exit(0)
    else
      io.stderr:write("[cybersec-install] unknown argument: " .. v .. "\n")
      usage()
      os.exit(2)
    end
    i = i + 1
  end
end

local url = getenv_or("CYBERSEC_URL", REPO_URL .. "/releases/download/" .. version .. "/" .. PACK_NAME)
local target_dir
if default_mode then
  target_dir = getenv_or("CYBERSEC_USR_DIR", DEFAULT_DIR)
else
  target_dir = getenv_or("CYBERSEC_BIN_DIR", FULL_DIR)
end

-- ── temporary workspace (always cleaned up) ──────────────────────────────────

local tmp = capture("mktemp -d /tmp/cybersec-install.XXXXXX")
if tmp == "" then tmp = capture("mktemp -d /var/tmp/cybersec-install.XXXXXX") end
if tmp == "" then die("cannot create a temporary directory (is /tmp writable?)") end

local function cleanup()
  sh("rm -rf " .. sq(tmp))
end

-- Fail path that still removes the temp dir.
local function fail(msg)
  cleanup()
  die(msg)
end

-- ── 1. download ──────────────────────────────────────────────────────────────

local pack    = tmp .. "/" .. PACK_NAME
local staging = tmp .. "/unpacked"

log("release " .. version .. (default_mode and "  (--default: hct + cybersec only)" or ""))
log("downloading " .. url)

local downloaded = false
if have("curl") then
  downloaded = sh("curl -fsSL --retry 5 --retry-delay 3 --retry-connrefused " ..
                  "--connect-timeout 30 -o " .. sq(pack) .. " " .. sq(url))
elseif have("wget") then
  downloaded = sh("wget -q --tries=5 --waitretry=3 --timeout=30 -O " .. sq(pack) .. " " .. sq(url))
else
  fail("neither curl nor wget is available in this environment")
end
if not downloaded then
  fail("download failed: " .. url .. " (no network / DNS in the chroot, or release " ..
       version .. " has no " .. PACK_NAME .. ")")
end

-- ── 2. unpack to a staging directory ─────────────────────────────────────────

if not sh("tar -tzf " .. sq(pack) .. " >/dev/null 2>&1") then
  fail(PACK_NAME .. " is not a valid gzip tarball")
end
if not sh("mkdir -p " .. sq(staging)) then fail("cannot create " .. staging) end
if not sh("tar -xzf " .. sq(pack) .. " -C " .. sq(staging) .. " --no-same-owner") then
  fail("cannot unpack " .. PACK_NAME)
end

-- ── 3a. --default: only hct and cybersec -> /usr/bin ─────────────────────────

if default_mode then
  if not sh("mkdir -p " .. sq(target_dir)) then fail("cannot create " .. target_dir) end

  local installed = 0
  for _, name in ipairs(DEFAULT_FILES) do
    -- the first regular file with that name, wherever it is in the archive
    local found = capture("find " .. sq(staging) .. " -type f -name " .. sq(name) .. " | head -n 1")
    if found == "" then
      warn("'" .. name .. "' is not in " .. PACK_NAME)
    else
      if not sh("chmod a+x " .. sq(found)) then fail("chmod a+x failed for " .. name) end
      -- `cp` onto a running binary fails with "Text file busy": copy beside it, then rename.
      local dest = target_dir .. "/" .. name
      local ok = sh("cp -f " .. sq(found) .. " " .. sq(dest .. ".new")) and
                 sh("chmod a+x " .. sq(dest .. ".new")) and
                 sh("mv -f " .. sq(dest .. ".new") .. " " .. sq(dest))
      if not ok then
        sh("rm -f " .. sq(dest .. ".new"))
        fail("cannot install " .. name .. " to " .. target_dir)
      end
      log("installed " .. dest)
      installed = installed + 1
    end
  end

  cleanup()
  if installed == 0 then
    die("none of: " .. table.concat(DEFAULT_FILES, ", ") .. " found in the archive")
  end
  log("done (" .. installed .. "/" .. #DEFAULT_FILES .. ")")
  os.exit(0)
end

-- ── 3b. full install: everything -> /usr/local/bin ───────────────────────────

-- chmod a+x on every unpacked file BEFORE it is placed in the target directory
if not sh("chmod -R a+x " .. sq(staging)) then fail("chmod a+x failed") end

-- an archive packed as `pack/…` (one wrapper directory) is flattened one level
local root = staging
do
  local n_top = tonumber(capture("ls -A " .. sq(staging) .. " | wc -l")) or 0
  if n_top == 1 then
    local only = capture("ls -A " .. sq(staging))
    if sh("test -d " .. sq(staging .. "/" .. only) .. " && test ! -L " .. sq(staging .. "/" .. only)) then
      root = staging .. "/" .. only
    end
  end
end

if (tonumber(capture("ls -A " .. sq(root) .. " | wc -l")) or 0) == 0 then
  fail(PACK_NAME .. " is empty")
end

if not sh("mkdir -p " .. sq(target_dir)) then fail("cannot create " .. target_dir) end
-- "/." copies the content (dotfiles included); -f overwrites an older version of a tool
if not sh("cp -rf " .. sq(root) .. "/. " .. sq(target_dir) .. "/") then
  fail("cannot copy files to " .. target_dir)
end

log("installed into " .. target_dir .. ":")
local listing = capture("cd " .. sq(root) .. " && find . -type f | sed 's|^\\./||' | sort")
for line in listing:gmatch("[^\n]+") do log("  " .. line) end

cleanup()
log("done")
os.exit(0)
