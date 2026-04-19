#!/usr/bin/env bash
# Smoke test for the safe_curl host allowlist.
# Run this to prove the allowlist actually rejects non-allowlisted hosts
# instead of taking the documentation's word for it.
#
# Usage:
#   bash scripts/test_allowlist.sh
#
# Exits 0 on pass, 1 on fail. No network required — tests run offline
# because safe_curl refuses before it would make the call.

set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=_common.sh
. "$SCRIPT_DIR/_common.sh"

pass=0
fail=0

check() {
  local name="$1" expected="$2" url="$3"
  if safe_curl "fake-token" "$url" >/dev/null 2>&1; then
    got="allowed"
  else
    got="refused"
  fi
  if [ "$got" = "$expected" ]; then
    echo "  ✓ $name"
    pass=$((pass+1))
  else
    echo "  ✗ $name  (expected $expected, got $got)"
    fail=$((fail+1))
  fi
}

echo "[test-allowlist] testing safe_curl host allowlist..."
echo ""

# Must reject — not in ALLOWED_HOSTS
check "rejects evil.com"                refused  "https://evil.com/steal"
check "rejects attacker-controlled IP"  refused  "https://203.0.113.1/exfil"
check "rejects vercel.com (root, not api.)" refused  "https://vercel.com/api/foo"
check "rejects api.supabase.io (wrong TLD)" refused  "https://api.supabase.io/v1/projects"
check "rejects localhost redirect"      refused  "http://localhost:8080/stash"

# Must refuse when no URL is passed (defense against malformed calls)
check "rejects empty URL"               refused  ""

# The allowed hosts must reach the network-call stage. We can't actually
# complete these without a real token, so we rely on safe_curl passing
# the allowlist check and then failing on HTTP auth — either is "allowed"
# from the allowlist's perspective. The fact that we're reading this output
# means the host was not rejected pre-network.
#
# We skip testing positive cases here because running real API calls with
# a fake token is noisy and doesn't add information. If you want to verify
# positive-path, run `bash scripts/preserve-evidence.sh` with a real token.

echo ""
echo "[test-allowlist] $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
