#!/usr/bin/env bash
# Rotate a Supabase project's ES256 JWT signing keys and database password.
# Skips paused projects. Writes new DB password to the incident folder.
#
# Usage:
#   SUPABASE_ACCESS_TOKEN=sbp_... ./rotate-supabase.sh <project-ref>

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=_common.sh
. "$SCRIPT_DIR/_common.sh"

require_tools jq curl openssl
: "${SUPABASE_ACCESS_TOKEN:?Set SUPABASE_ACCESS_TOKEN first (supabase.com/dashboard/account/tokens)}"

REF="${1:?Supabase project-ref required (the identifier in the project URL)}"
API="https://api.supabase.com"
SB_AUTH=(-H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json")
OUT=$(incident_dir)

echo "[supabase] checking project $REF" >&2
proj=$(curl -fsS "${SB_AUTH[@]}" "$API/v1/projects/$REF" 2>/dev/null || echo "{}")
status=$(echo "$proj" | jq -r '.status // "unknown"')
if [ "$status" != "ACTIVE_HEALTHY" ] && [ "$status" != "ACTIVE" ]; then
  echo "[supabase] project status: $status — skipping (only active projects are rotated)" >&2
  echo "$REF: skipped — status $status" >> "$OUT/rotation-log.md"
  exit 0
fi

# 1. Create new ES256 signing key, status in_use
echo "[supabase] creating new ES256 signing key..." >&2
new_key=$(curl -fsS -X POST "${SB_AUTH[@]}" \
  -d '{"algorithm":"ES256","status":"in_use"}' \
  "$API/v1/projects/$REF/config/auth/signing-keys")
new_key_id=$(echo "$new_key" | jq -r '.id')
echo "[supabase]   new key id: $new_key_id" >&2

# 2. List, find old keys that are not the new one, revoke them
echo "[supabase] listing existing signing keys..." >&2
keys=$(curl -fsS "${SB_AUTH[@]}" "$API/v1/projects/$REF/config/auth/signing-keys")
to_revoke=$(echo "$keys" | jq -r --arg new "$new_key_id" '.[] | select(.id != $new) | .id')

for kid in $to_revoke; do
  echo "[supabase]   revoking old key $kid" >&2
  curl -fsS -X DELETE "${SB_AUTH[@]}" "$API/v1/projects/$REF/config/auth/signing-keys/$kid" >/dev/null
done

# 3. Rotate DB password
NEW_PW=$(openssl rand -hex 32)
echo "[supabase] rotating DB password..." >&2
curl -fsS -X PATCH "${SB_AUTH[@]}" \
  -d "$(jq -n --arg pw "$NEW_PW" '{db_password: $pw}')" \
  "$API/v1/projects/$REF" >/dev/null

{
  echo ""
  echo "# Supabase $REF — rotated $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "SUPABASE_DB_PASSWORD_${REF}=$NEW_PW"
} >> "$OUT/secrets.txt"
chmod 600 "$OUT/secrets.txt"

{
  echo ""
  echo "## $REF — $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "- Rotated ES256 signing key. New key id: $new_key_id"
  echo "- Revoked: $(echo "$to_revoke" | wc -l | tr -d ' ') old key(s)"
  echo "- Rotated DB password. New value in secrets.txt."
} >> "$OUT/rotation-log.md"

echo "" >&2
echo "[supabase] done. secrets.txt updated. log updated." >&2
echo "[supabase] NOTE: update DATABASE_URL / DIRECT_URL in Vercel + anywhere else" >&2
echo "[supabase] NOTE: existing JWT tokens issued by the old key will be rejected" >&2
