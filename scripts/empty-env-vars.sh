#!/usr/bin/env bash
# Set every env var on one Vercel project to "" (empty). Does not delete —
# keeps keys so values can be re-set after upstream rotation.
#
# Usage:
#   VERCEL_TOKEN=... ./empty-env-vars.sh <project_id> <team_id>            # dry-run (default, safe)
#   VERCEL_TOKEN=... ./empty-env-vars.sh <project_id> <team_id> --execute  # actually mutate
#
# Pass team_id="" (empty string) for personal-account projects.
# Skips VERCEL_* system vars. Logs per-var results to stdout.

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=_common.sh
. "$SCRIPT_DIR/_common.sh"

require_tools jq curl
discover_vercel_token

PID="${1:?project_id required}"
TID="${2:-}"   # may be empty for personal scope
parse_execute_flag "$@"

API="https://api.vercel.com"
qs=""
[ -n "$TID" ] && qs="?teamId=$TID"

envs=$(vcurl "$API/v9/projects/$PID/env$qs" | jq -c '.envs[]')

count=$(echo "$envs" | wc -l | tr -d ' ')
echo "[scope] $count env vars on project $PID (team: ${TID:-personal})" >&2

ok=0; skip=0; fail=0
while IFS= read -r env; do
  [ -z "$env" ] && continue
  id=$(echo "$env" | jq -r '.id')
  key=$(echo "$env" | jq -r '.key')
  if [[ "$key" == VERCEL_* ]]; then
    echo "SKIP  $key (system var)"
    skip=$((skip+1))
    continue
  fi
  if [ "$DRY_RUN" = "1" ]; then
    echo "DRY   $key ($id)"
    continue
  fi
  patch_qs=""
  [ -n "$TID" ] && patch_qs="?teamId=$TID"
  if vcurl -X PATCH -d '{"value":""}' \
       "$API/v9/projects/$PID/env/$id$patch_qs" >/dev/null 2>&1; then
    echo "OK    $key"
    ok=$((ok+1))
  else
    echo "FAIL  $key (likely integration-managed — disconnect integration instead)"
    fail=$((fail+1))
  fi
done <<< "$envs"

echo ""
if [ "$DRY_RUN" = "1" ]; then
  echo "Dry-run summary: would empty $((count - skip)) vars, $skip would be skipped. Re-run with --execute to mutate."
else
  echo "Summary: $ok emptied, $skip skipped, $fail failed"
fi
