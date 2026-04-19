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
AUTH=(-H "Authorization: Bearer $VERCEL_TOKEN")
OUT=$(incident_dir)
chmod 700 "$OUT"

echo "[evidence] writing to $OUT" >&2

# Personal account identity (useful cross-check for audit log)
curl -fsS "${AUTH[@]}" "$API/v2/user" > "$OUT/user.json" 2>/dev/null || {
  echo "[evidence] failed to fetch user — token may be invalid" >&2
  exit 1
}

# Teams
curl -fsS "${AUTH[@]}" "$API/v2/teams" > "$OUT/teams.json"
TEAM_IDS=$(jq -r '.teams[].id' "$OUT/teams.json")

# If a team_id arg was provided, filter to just that one
if [ $# -ge 1 ]; then
  TEAM_IDS="$1"
fi

for TID in $TEAM_IDS; do
  SLUG=$(jq -r --arg id "$TID" '.teams[] | select(.id==$id) | .slug' "$OUT/teams.json" 2>/dev/null || echo "$TID")
  echo "[evidence] team $SLUG ($TID)" >&2

  # Audit log — paginate up to 500 events
  : > "$OUT/audit-log-$SLUG.json"
  local_out=$(curl -fsS "${AUTH[@]}" "$API/v1/teams/$TID/audit-logs?limit=200" 2>/dev/null || echo "{}")
  echo "$local_out" > "$OUT/audit-log-$SLUG.json"

  # Deploy history (last 100)
  curl -fsS "${AUTH[@]}" "$API/v6/deployments?teamId=$TID&limit=100" \
    > "$OUT/deployments-$SLUG.json" 2>/dev/null || echo "{}" > "$OUT/deployments-$SLUG.json"

  # Team roster
  curl -fsS "${AUTH[@]}" "$API/v2/teams/$TID/members?limit=100" \
    > "$OUT/members-$SLUG.json" 2>/dev/null || echo "{}" > "$OUT/members-$SLUG.json"

  # Integrations
  curl -fsS "${AUTH[@]}" "$API/v2/teams/$TID/integrations/configurations?limit=100" \
    > "$OUT/integrations-$SLUG.json" 2>/dev/null || echo "{}" > "$OUT/integrations-$SLUG.json"
done

# Active personal tokens (useful to cross-check against audit-log token.created events)
curl -fsS "${AUTH[@]}" "$API/v5/user/tokens" > "$OUT/active-tokens.json" 2>/dev/null || echo "{}" > "$OUT/active-tokens.json"

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
