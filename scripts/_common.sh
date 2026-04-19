#!/usr/bin/env bash
# Shared helpers for vercel-breach-best-practices scripts.
# source'd by every script; never executed directly.
#
# Based on patterns from Vercel's official vercel-cli-with-tokens skill:
# never pass VERCEL_TOKEN as a --token flag (leaks to shell history),
# always export it as an env var; check env → .env → alt var names → ask.

set -euo pipefail

# -- preflight: required CLI tools ------------------------------------------
require_tools() {
  local missing=()
  for t in "$@"; do
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  if [ ${#missing[@]} -gt 0 ]; then
    echo "missing tools: ${missing[*]}" >&2
    echo "install: brew install ${missing[*]}  (macOS)" >&2
    echo "         apt install ${missing[*]}   (Debian/Ubuntu)" >&2
    exit 1
  fi
}

# -- token discovery --------------------------------------------------------
# Sets VERCEL_TOKEN in the environment if it can find one. Order:
#   1. already exported
#   2. .env in cwd with VERCEL_TOKEN=...
#   3. .env in cwd with any var whose value starts with vca_
#   4. ~/.vercel/auth.json (if logged in via `vercel login`)
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
    # any var whose value starts with vca_ (Vercel token prefix)
    local alt
    alt=$(grep -E '^[A-Z_]+=vca_' .env 2>/dev/null | head -1 | cut -d= -f1 || true)
    if [ -n "$alt" ]; then
      VERCEL_TOKEN=$(grep "^$alt=" .env | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
      export VERCEL_TOKEN
      echo "[token] loaded VERCEL_TOKEN from .env var: $alt" >&2
      return 0
    fi
  fi
  # Vercel CLI auth locations vary by platform:
  #   macOS:   ~/Library/Application Support/com.vercel.cli/auth.json
  #   Linux:   ~/.config/com.vercel.cli/auth.json  (or ~/.local/share/com.vercel.cli/auth.json)
  #   legacy:  ~/.vercel/auth.json
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

Note: never pass the token as a --token flag — it leaks to shell history.
      Always export it as an environment variable.
EOF
  return 1
}

# -- authed curl wrapper ----------------------------------------------------
# Usage: vcurl <curl args>
vcurl() {
  curl -fsS \
    -H "Authorization: Bearer $VERCEL_TOKEN" \
    -H "Content-Type: application/json" \
    "$@"
}

# -- incident folder --------------------------------------------------------
incident_dir() {
  local d="$HOME/incident-$(date +%Y%m%d)"
  mkdir -p "$d"
  chmod 700 "$d"
  echo "$d"
}
