#!/usr/bin/env bash
# Shared helpers for vercel-breach-best-practices scripts.
# source'd by every script; never executed directly.
#
# Hardening model (v2):
#   1. Host allowlist — every network call funneled through safe_curl, which
#      rejects any URL outside ALLOWED_HOSTS. Single point of control.
#   2. Audit log — every API call appends to ~/incident-YYYYMMDD/audit.log
#      with timestamp, method, host, path (no bodies, no secrets).
#   3. Fail-safe defaults — destructive scripts require --execute. No silent
#      mutations.
#   4. Token hygiene — tokens only via env var, never CLI flags (no shell
#      history leak). All outbound requests use Authorization header.

set -euo pipefail

# -- allowed hosts ----------------------------------------------------------
# This is the authoritative list. If you need to call a new host, add it here
# and only here. Any drift from this list is a red flag for reviewers.
ALLOWED_HOSTS=(
  "api.vercel.com"
  "api.supabase.com"
)

# -- preflight: required CLI tools ------------------------------------------
require_tools() {
  local missing=()
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "missing tools: ${missing[*]}" >&2
    echo "use your system package manager to install them, then retry." >&2
    exit 1
  fi
}

# -- incident folder --------------------------------------------------------
incident_dir() {
  local d="$HOME/incident-$(date +%Y%m%d)"
  mkdir -p "$d"
  chmod 700 "$d"
  echo "$d"
}

# -- audit log --------------------------------------------------------------
# Appends a single line per API call. Never records bodies, headers, or tokens.
# Format: ISO8601_timestamp | METHOD | host | path | script_name
audit_log() {
  local method="$1" url="$2"
  local host path ts script
  host=$(echo "$url" | sed -E 's|^https?://([^/]+).*|\1|')
  path=$(echo "$url" | sed -E 's|^https?://[^/]+||' | sed 's|?.*||')
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  script=$(basename "${BASH_SOURCE[2]:-unknown}")
  local log
  log="$(incident_dir)/audit.log"
  echo "$ts | $method | $host | $path | $script" >> "$log"
  chmod 600 "$log" 2>/dev/null || true
}

# -- host allowlist check ---------------------------------------------------
is_allowed_host() {
  local url="$1"
  local host
  host=$(echo "$url" | sed -E 's|^https?://([^/]+).*|\1|')
  for allowed in "${ALLOWED_HOSTS[@]}"; do
    if [ "$host" = "$allowed" ]; then
      return 0
    fi
  done
  return 1
}

# -- safe_curl: gated network call wrapper ----------------------------------
# Usage:
#   safe_curl <auth_header_value> <curl args including URL>
#
# Rejects any URL whose host is not in ALLOWED_HOSTS. Logs to audit.log.
# Prints the destination to stderr so the user sees every call in real time.
safe_curl() {
  local auth="$1"
  shift
  # Extract URL (last non-flag argument, or the one after -X METHOD)
  local url="" method="GET"
  local args=("$@")
  local i=0
  while [ $i -lt ${#args[@]} ]; do
    case "${args[$i]}" in
      -X) method="${args[$((i+1))]}"; i=$((i+2));;
      http://*|https://*) url="${args[$i]}"; i=$((i+1));;
      *) i=$((i+1));;
    esac
  done
  if [ -z "$url" ]; then
    echo "[safe_curl] refusing: no URL in args" >&2
    return 1
  fi
  if ! is_allowed_host "$url"; then
    local host
    host=$(echo "$url" | sed -E 's|^https?://([^/]+).*|\1|')
    echo "[safe_curl] REFUSED host '$host' — not in allowlist (${ALLOWED_HOSTS[*]})" >&2
    return 1
  fi
  echo "[net] $method $(echo "$url" | sed -E 's|^https?://([^/]+)([^?]*).*|\1\2|')" >&2
  audit_log "$method" "$url"
  curl -fsS \
    -H "Authorization: Bearer $auth" \
    -H "Content-Type: application/json" \
    "$@"
}

# -- token discovery (Vercel) -----------------------------------------------
# Sets VERCEL_TOKEN in the environment if it can find one. Order:
#   1. already exported
#   2. .env in cwd with VERCEL_TOKEN=...
#   3. .env in cwd with any var whose value starts with vca_
#   4. Vercel CLI auth.json (platform-specific paths)
#   5. error out with guidance
discover_vercel_token() {
  if [ -n "${VERCEL_TOKEN:-}" ]; then
    return 0
  fi
  if [ -f .env ] && grep -q '^VERCEL_TOKEN=' .env 2>/dev/null; then
    VERCEL_TOKEN=$(grep '^VERCEL_TOKEN=' .env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
    export VERCEL_TOKEN
    echo "[token] loaded VERCEL_TOKEN from .env" >&2
    return 0
  fi
  if [ -f .env ]; then
    local alt
    alt=$(grep -E '^[A-Z_]+=vca_' .env 2>/dev/null | head -1 | cut -d= -f1 || true)
    if [ -n "$alt" ]; then
      VERCEL_TOKEN=$(grep "^$alt=" .env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
      export VERCEL_TOKEN
      echo "[token] loaded VERCEL_TOKEN from .env var: $alt" >&2
      return 0
    fi
  fi
  for candidate in \
    "$HOME/Library/Application Support/com.vercel.cli/auth.json" \
    "$HOME/.config/com.vercel.cli/auth.json" \
    "$HOME/.local/share/com.vercel.cli/auth.json" \
    "$HOME/.vercel/auth.json"
  do
    if [ -f "$candidate" ] && command -v jq >/dev/null 2>&1; then
      local t
      t=$(jq -r '.token // empty' "$candidate" 2>/dev/null || true)
      if [ -n "$t" ]; then
        VERCEL_TOKEN="$t"
        export VERCEL_TOKEN
        echo "[token] loaded VERCEL_TOKEN from $candidate" >&2
        return 0
      fi
    fi
  done
  cat >&2 <<EOF
error: VERCEL_TOKEN not set.

To fix:
  1. Run 'vercel login' (if vercel CLI is installed), or
  2. Generate a token at https://vercel.com/account/tokens, scope it to the
     affected team(s), then:
       export VERCEL_TOKEN=vca_xxxxx...
  3. Re-run this script.

Never pass the token as a --token CLI flag — that leaks to shell history.
EOF
  return 1
}

# -- vcurl: Vercel-authed safe_curl -----------------------------------------
vcurl() {
  safe_curl "$VERCEL_TOKEN" "$@"
}

# -- sbcurl: Supabase-authed safe_curl --------------------------------------
sbcurl() {
  safe_curl "${SUPABASE_ACCESS_TOKEN:?SUPABASE_ACCESS_TOKEN not set}" "$@"
}

# -- --execute gate ---------------------------------------------------------
# Destructive scripts MUST call this. Default behavior is dry-run.
# If --execute is in "$@", the caller sets DRY_RUN=0; otherwise DRY_RUN=1.
#
# Usage in a script:
#   parse_execute_flag "$@"
#   if [ "$DRY_RUN" = "1" ]; then echo "DRY: would do X"; else actually_do_X; fi
parse_execute_flag() {
  DRY_RUN=1
  for arg in "$@"; do
    if [ "$arg" = "--execute" ]; then
      DRY_RUN=0
      return
    fi
  done
  echo "[dry-run] no --execute flag — this run will not mutate anything." >&2
  echo "          add --execute to perform the actual operation." >&2
}
