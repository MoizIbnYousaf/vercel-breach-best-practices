#!/usr/bin/env bash
# Enumerate every Vercel project + env var across every team the token can see,
# classify each env var by upstream service. Writes JSON inventory to stdout,
# prints a human summary to stderr.
#
# Handles: personal-account scope (no teams), paginated projects (>100),
# paginated env vars, 403 on foreign teams (skipped with note).
#
# Usage:
#   VERCEL_TOKEN=... ./enumerate.sh > inventory.json

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=_common.sh
. "$SCRIPT_DIR/_common.sh"

require_tools jq curl openssl
discover_vercel_token

API="https://api.vercel.com"

classify() {
  local k="$1"
  case "$k" in
    SUPABASE_*|NEXT_PUBLIC_SUPABASE_*|SUPABASE_SERVICE_ROLE_KEY) echo supabase;;
    *SERVICE_ROLE*) echo supabase;;
    BLOB_READ_WRITE_TOKEN) echo vercel-blob;;
    KV_*|UPSTASH_*|REDIS_URL) echo upstash-kv;;
    DATABASE_URL|POSTGRES_*|DIRECT_URL|SHADOW_*) echo database-url;;
    NEON_*) echo neon;;
    TURSO_*) echo turso;;
    PLANETSCALE_*) echo planetscale;;
    MONGODB_*|MONGO_URI) echo mongodb;;
    RESEND_API_KEY) echo resend;;
    SENDGRID_*) echo sendgrid;;
    POSTMARK_*) echo postmark;;
    MAILGUN_*) echo mailgun;;
    LOOPS_*) echo loops;;
    SENTRY_AUTH_TOKEN) echo sentry;;
    SENTRY_DSN|NEXT_PUBLIC_SENTRY_DSN) echo sentry-dsn-public;;
    STRIPE_SECRET_KEY|STRIPE_RESTRICTED_*|STRIPE_WEBHOOK_SECRET) echo stripe;;
    STRIPE_PUBLISHABLE_KEY|NEXT_PUBLIC_STRIPE_*) echo stripe-public;;
    OPENAI_API_KEY) echo openai;;
    ANTHROPIC_API_KEY) echo anthropic;;
    GOOGLE_*API_KEY|GEMINI_API_KEY) echo google-ai;;
    MISTRAL_*|GROQ_*|REPLICATE_*|OPENROUTER_*) echo ai-provider;;
    CLERK_SECRET_KEY|CLERK_*KEY) echo clerk;;
    AUTH0_*) echo auth0;;
    NEXTAUTH_SECRET|AUTH_SECRET|BETTER_AUTH_SECRET|JWT_SECRET|SESSION_SECRET) echo local-auth-secret;;
    AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN) echo aws;;
    CLOUDFLARE_*|CF_API_TOKEN|CF_ACCOUNT_ID) echo cloudflare;;
    GITHUB_TOKEN|GH_TOKEN|GITLAB_TOKEN) echo git-host;;
    TWILIO_*|VONAGE_*) echo sms;;
    PUSHER_*|ABLY_*) echo realtime;;
    ALGOLIA_*API_KEY|MEILISEARCH_*MASTER_*|TYPESENSE_*API_KEY) echo search;;
    POSTHOG_API_KEY|MIXPANEL_SECRET|AMPLITUDE_API_KEY) echo analytics-server;;
    NEXT_PUBLIC_POSTHOG_*|NEXT_PUBLIC_UMAMI_*|NEXT_PUBLIC_GA_*) echo analytics-public;;
    *_WEBHOOK_URL|SLACK_WEBHOOK_URL|DISCORD_WEBHOOK_URL) echo webhook-url;;
    *_WEBHOOK_SECRET|*_SIGNING_SECRET) echo webhook-signing;;
    NOTION_TOKEN|LINEAR_API_KEY|FIGMA_TOKEN) echo tool-api;;
    CRON_SECRET|VERCEL_CRON_SECRET) echo cron-secret;;
    VERCEL_*) echo vercel-system;;
    *_API_KEY|*_SECRET|*_TOKEN|*_PASSWORD) echo generic-secret;;
    NEXT_PUBLIC_*) echo public-config;;
    *) echo unknown;;
  esac
}

echo "[enumerate] discovering scope..." >&2

teams_resp=$(vcurl "$API/v2/teams" 2>/dev/null || echo '{"teams":[]}')
teams=$(echo "$teams_resp" | jq -c '[.teams[]? | {id, slug, name}]' 2>/dev/null || echo '[]')
team_count=$(echo "$teams" | jq 'length')
echo "[enumerate] found $team_count team(s), plus personal scope" >&2

# Every team, plus the personal scope (team_id=null).
scopes=$(jq -n --argjson teams "$teams" '$teams + [{"id":null,"slug":"personal","name":"Personal Account"}]')

result=$(jq -n --argjson teams "$teams" \
  '{scanned_at: now|todate, teams: $teams, inventory: [], skipped_teams: []}')

for row in $(echo "$scopes" | jq -r '.[] | @base64'); do
  t=$(echo "$row" | base64 --decode)
  team_id=$(echo "$t" | jq -r '.id // empty')
  team_slug=$(echo "$t" | jq -r '.slug')
  echo "[enumerate] scope: $team_slug${team_id:+ ($team_id)}" >&2

  proj_url="$API/v9/projects?limit=100"
  [ -n "$team_id" ] && proj_url="${proj_url}&teamId=${team_id}"

  if ! first_page=$(vcurl "$proj_url" 2>/dev/null); then
    echo "[enumerate]   403 or error — skipping" >&2
    result=$(echo "$result" | jq --arg slug "$team_slug" \
      '.skipped_teams += [{slug: $slug, reason: "api-403-or-error"}]')
    continue
  fi

  projects=$(echo "$first_page" | jq -c '.projects | map({id,name})')
  cursor=$(echo "$first_page" | jq -r '.pagination.next // empty')
  while [ -n "$cursor" ]; do
    more=$(vcurl "${proj_url}&until=${cursor}" 2>/dev/null || echo '{"projects":[]}')
    projects=$(jq -c -n --argjson a "$projects" --argjson b "$(echo "$more" | jq -c '.projects | map({id,name})')" '$a + $b')
    cursor=$(echo "$more" | jq -r '.pagination.next // empty')
  done

  proj_count=$(echo "$projects" | jq 'length')
  echo "[enumerate]   $proj_count project(s)" >&2

  for prow in $(echo "$projects" | jq -r '.[] | @base64'); do
    p=$(echo "$prow" | base64 --decode)
    pid=$(echo "$p" | jq -r '.id')
    pname=$(echo "$p" | jq -r '.name')

    env_url="$API/v9/projects/$pid/env"
    [ -n "$team_id" ] && env_url="${env_url}?teamId=${team_id}"

    envs_raw=$(vcurl "$env_url" 2>/dev/null || echo '{"envs":[]}')
    envs=$(echo "$envs_raw" | jq -c '[.envs[] | {id,key,target,type}]')

    classified_tmp=$(mktemp)
    echo "$envs" | jq -c '.[]' 2>/dev/null | while IFS= read -r env; do
      [ -z "$env" ] && continue
      k=$(echo "$env" | jq -r '.key')
      svc=$(classify "$k")
      echo "$env" | jq --arg svc "$svc" '. + {service: $svc}'
    done | jq -s '.' > "$classified_tmp"

    entry=$(jq -n \
      --arg team_id "${team_id:-personal}" \
      --arg team_slug "$team_slug" \
      --arg project_id "$pid" \
      --arg project_name "$pname" \
      --slurpfile envs "$classified_tmp" \
      '{team_id: $team_id, team_slug: $team_slug, project_id: $project_id, project_name: $project_name, envs: $envs[0]}')
    rm "$classified_tmp"
    result=$(echo "$result" | jq --argjson e "$entry" '.inventory += [$e]')
  done
done

echo "" >&2
echo "[enumerate] service summary:" >&2
echo "$result" | jq -r '.inventory
  | map(.envs[] | .service)
  | group_by(.)
  | map({service: .[0], count: length})
  | sort_by(-.count)
  | .[]
  | "  \(.count)  \(.service)"' >&2

skipped=$(echo "$result" | jq -r '.skipped_teams | length')
if [ "$skipped" -gt 0 ]; then
  echo "" >&2
  echo "[enumerate] skipped $skipped team(s) due to access errors:" >&2
  echo "$result" | jq -r '.skipped_teams[] | "  - \(.slug): \(.reason)"' >&2
fi

echo "$result"
