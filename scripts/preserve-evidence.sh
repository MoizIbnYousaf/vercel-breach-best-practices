#!/usr/bin/env bash
# Preserve Vercel audit logs, deployment history, team roster, and active tokens
# before any rotation begins. Writes to ~/incident-$(date +%Y%m%d)/.
#
# Usage:
#   VERCEL_TOKEN=... ./preserve-evidence.sh [team_id]
#
# If team_id is omitted, preserves across every team the token can see, plus
# personal scope.

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=_common.sh
. "$SCRIPT_DIR/_common.sh"

require_tools jq curl
discover_vercel_token

API="https://api.vercel.com"
OUT=$(incident_dir)
chmod 700 "$OUT"

echo "[evidence] writing to $OUT (read-only API calls — no mutations)" >&2

# Personal account identity (useful cross-check for audit log)
vcurl "$API/v2/user" > "$OUT/user.json" 2>/dev/null || {
  echo "[evidence] failed to fetch user — token may be invalid" >&2
  exit 1
}

# Teams
vcurl "$API/v2/teams" > "$OUT/teams.json"
TEAM_IDS=$(jq -r '.teams[].id' "$OUT/teams.json")

# If a team_id arg was provided, filter to just that one
if [ $# -ge 1 ]; then
  TEAM_IDS="$1"
fi

for TID in $TEAM_IDS; do
  SLUG=$(jq -r --arg id "$TID" '.teams[] | select(.id==$id) | .slug' "$OUT/teams.json" 2>/dev/null || echo "$TID")
  echo "[evidence] team $SLUG ($TID)" >&2

  : > "$OUT/audit-log-$SLUG.json"
  local_out=$(vcurl "$API/v1/teams/$TID/audit-logs?limit=200" 2>/dev/null || echo "{}")
  echo "$local_out" > "$OUT/audit-log-$SLUG.json"

  vcurl "$API/v6/deployments?teamId=$TID&limit=100" \
    > "$OUT/deployments-$SLUG.json" 2>/dev/null || echo "{}" > "$OUT/deployments-$SLUG.json"

  vcurl "$API/v2/teams/$TID/members?limit=100" \
    > "$OUT/members-$SLUG.json" 2>/dev/null || echo "{}" > "$OUT/members-$SLUG.json"

  vcurl "$API/v2/teams/$TID/integrations/configurations?limit=100" \
    > "$OUT/integrations-$SLUG.json" 2>/dev/null || echo "{}" > "$OUT/integrations-$SLUG.json"
done

vcurl "$API/v5/user/tokens" > "$OUT/active-tokens.json" 2>/dev/null || echo "{}" > "$OUT/active-tokens.json"

# Optional: use `vercel activity` CLI for a richer dump if the CLI is installed.
# This supplements the API audit-log pull above with the CLI's filtering / pagination.
if command -v vercel >/dev/null 2>&1; then
  echo "[evidence] vercel CLI detected — pulling activity log via 'vercel activity'" >&2
  # Last 30 days, JSON output. --all-events is the richest scope.
  vercel activity --since 30d --output json > "$OUT/vercel-activity-30d.json" 2>/dev/null \
    || echo "[evidence] vercel activity call failed — check CLI auth" >&2
fi

# Quick summary
echo "" >&2
echo "[evidence] summary:" >&2
for f in "$OUT"/audit-log-*.json; do
  [ -f "$f" ] || continue
  slug=$(basename "$f" .json | sed 's/audit-log-//')
  count=$(jq '.events | length // 0' "$f" 2>/dev/null || echo "?")
  echo "  $slug: $count audit events" >&2
done

active_tokens=$(jq '.tokens | length // 0' "$OUT/active-tokens.json" 2>/dev/null || echo "?")
echo "  active tokens on this account: $active_tokens" >&2

echo "" >&2
echo "[evidence] done. review with:" >&2
echo "  ls -la $OUT" >&2
echo "  jq '.events[0:5]' $OUT/audit-log-*.json" >&2
