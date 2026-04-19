#!/usr/bin/env bash
# Scan recent Vercel build logs for leaked secrets. During a breach, secrets
# that were ever logged via console.log(process.env), debug prints, or tool
# output are persisted on Vercel — rotation of those specific values is
# mandatory even if the rotation playbook already rotated the rest.
#
# Usage:
#   VERCEL_TOKEN=... ./scan-build-logs.sh <project_id> [team_id]
#
# Writes a per-project findings report to the incident folder.

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=_common.sh
. "$SCRIPT_DIR/_common.sh"

require_tools jq curl grep
discover_vercel_token

PID="${1:?project_id required}"
TID="${2:-}"
LIMIT="${LIMIT:-20}"

API="https://api.vercel.com"
OUT=$(incident_dir)
REPORT="$OUT/build-log-scan-$PID.txt"

qs=""
[ -n "$TID" ] && qs="&teamId=$TID"

echo "[scan-logs] fetching last $LIMIT deployments for project $PID..." >&2
deploys=$(vcurl "$API/v6/deployments?projectId=$PID&limit=$LIMIT$qs" | jq -r '.deployments[].uid')

: > "$REPORT"
echo "# Build-log secret scan for project $PID" >> "$REPORT"
echo "# scanned $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$REPORT"
echo "" >> "$REPORT"

# Secret-ish patterns. Err on the side of more matches — a human (or Claude)
# will triage the report.
patterns='(sk_live_|sk_test_|rk_live_|pk_live_|whsec_|eyJ[A-Za-z0-9_=-]{20,}\.[A-Za-z0-9_=-]{20,}\.[A-Za-z0-9_=-]{20,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]+|github_pat_[A-Za-z0-9_]{50,}|ghp_[A-Za-z0-9]{36}|sbp_[a-f0-9]{40,}|vca_[A-Za-z0-9]{20,}|postgres(ql)?://[^ \t\n"]+:[^ \t\n"]+@|mongodb\+srv://[^ \t\n"]+:[^ \t\n"]+@)'

hits=0
for DID in $deploys; do
  [ -z "$DID" ] && continue
  # Build events endpoint; stream as NDJSON where supported
  events=$(vcurl "$API/v3/deployments/$DID/events?limit=1000$qs" 2>/dev/null || echo "[]")
  text=$(echo "$events" | jq -r '.[]?.payload.text // empty' 2>/dev/null || true)
  matches=$(echo "$text" | grep -Eo "$patterns" 2>/dev/null | sort -u || true)
  if [ -n "$matches" ]; then
    hits=$((hits+1))
    {
      echo "## deployment $DID"
      echo "  url: https://vercel.com/_/$DID"
      echo "  matches:"
      echo "$matches" | sed 's/^/    - /'
      echo ""
    } >> "$REPORT"
  fi
done

if [ "$hits" -eq 0 ]; then
  echo "[scan-logs] no obvious secret-pattern matches across $LIMIT deployments" >&2
  echo "  (absence of match doesn't prove absence of leak — review manually if in doubt)" >> "$REPORT"
else
  echo "[scan-logs] ⚠ $hits deployment(s) had potential secret leaks — see $REPORT" >&2
fi

echo "$REPORT"
