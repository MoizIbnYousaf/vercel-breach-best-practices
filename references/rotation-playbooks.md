# Per-service rotation playbooks

Tier-by-tier rotation recipes. Read only the sections matching services the inventory surfaced.

Every command assumes `~/incident-$(date +%Y%m%d)/` is the working directory and that new values get written to `secrets.txt` there, not pasted into chat.

---

## Tier 1 — Cloud / infra (highest blast radius, do first)

### AWS IAM

Full cloud-account access possible. Rotate access keys per user:

```bash
# List existing keys
aws iam list-access-keys --user-name "$USER_NAME"

# Create the new key
aws iam create-access-key --user-name "$USER_NAME" \
  > ~/incident-$(date +%Y%m%d)/aws-newkey-$USER_NAME.json

# Deactivate (don't delete yet) the old key
aws iam update-access-key \
  --access-key-id "$OLD_ACCESS_KEY_ID" \
  --status Inactive \
  --user-name "$USER_NAME"

# Once prod is verified with the new key:
aws iam delete-access-key --access-key-id "$OLD_ACCESS_KEY_ID" --user-name "$USER_NAME"
```

Also check: `aws iam list-users`, `aws iam list-roles` — look for accounts/roles you didn't create. CloudTrail: `aws cloudtrail lookup-events --max-results 100` for the last 24h of API activity.

### GCP service accounts

```bash
gcloud iam service-accounts keys list --iam-account="$SA_EMAIL"
gcloud iam service-accounts keys create new-key.json --iam-account="$SA_EMAIL"
gcloud iam service-accounts keys delete "$OLD_KEY_ID" --iam-account="$SA_EMAIL"
```

### Cloudflare API tokens

Dashboard only: https://dash.cloudflare.com/profile/api-tokens — delete each token, recreate with scoped permissions. Don't use Global API Key; always use scoped tokens.

### Self-hosted Postgres / MySQL

```bash
# Postgres
psql "<YOUR_DATABASE_URL>" -c "ALTER USER <app_user> WITH PASSWORD '$(openssl rand -hex 32)';"

# MySQL
mysql -e "ALTER USER '<app_user>'@'%' IDENTIFIED BY '$(openssl rand -hex 32)';"
```

Save new DSN to `secrets.txt`.

---

## Tier 2 — Managed data services

### Supabase (dashboard-only)

This skill does not automate Supabase rotation. Dashboard path:

1. https://supabase.com/dashboard/project/<ref>/settings/jwt-signing-keys → rotate the ES256 signing key (this invalidates all signed-in user sessions — expected).
2. https://supabase.com/dashboard/project/<ref>/settings/database → Reset database password.
3. https://supabase.com/dashboard/project/<ref>/settings/api → regenerate the service-role key if you see an option (some projects tie this to the signing key rotation above).
4. Update `<YOUR_DATABASE_URL>`, `<YOUR_DIRECT_URL>`, and `SUPABASE_SERVICE_ROLE_KEY` in Vercel env with the new values.

### Neon

```bash
# Reset password for a role; prints the new connection string
neon roles reset-password <role-name> --project-id <project-id>
```

Save new connection string to `secrets.txt`. Test before continuing.

### PlanetScale

```bash
# Create a new password
pscale password create <database> <branch> --name "rotated-$(date +%s)"

# List to find the old password name
pscale password list <database> <branch>

# Delete the old password
pscale password delete <database> <branch> <old-password-name>
```

PlanetScale passwords are per-connection-string, so you must update every consumer before deleting.

### Turso

```bash
# Create new token
turso db tokens create <db-name> --expiration 1w > /dev/null  # save this

# Once deployed with new token:
turso db tokens invalidate <db-name>
```

Turso has `--expiration none` for service tokens, but prefer short expirations where possible.

### Upstash Redis + QStash

Upstash published an official post-incident rotation guide during the April 2026 Vercel event — **follow that as the canonical reference**:

- [Rotate Upstash Secrets After Vercel Incident](https://upstash.com/blog/rotate-upstash-secrets-after-vercel-incident) (Upstash blog)

Summary of what to rotate per database:
- **Redis**: dashboard → database → Details → **Reset Password** (regenerates `UPSTASH_REDIS_REST_TOKEN` and refreshes connection URLs).
- **QStash**: console → QStash → **Regenerate** `QSTASH_TOKEN`. Also rotate `QSTASH_CURRENT_SIGNING_KEY` and `QSTASH_NEXT_SIGNING_KEY`.
- **Vector / Kafka / Workflow**: each has a "Reset" or "Regenerate" action in the database settings.

After rotating, update Vercel env vars with the new values. If the database is connected via the Upstash Vercel integration, disconnect + reconnect to let Vercel re-inject fresh credentials.

### Vercel KV

Vercel KV is Upstash under the hood, managed via a Vercel integration. Cleanest path: disconnect the integration (step 7), reconnect (step 9). Vercel injects fresh credentials.

### MongoDB Atlas

Dashboard-only: Database Access → each user → Edit → Edit Password. No public API for password rotation as of writing.

---

## Tier 3 — Auth / identity

### Clerk

Dashboard: https://dashboard.clerk.com → API Keys. Roll the secret key. Clerk supports a grace-period rotation (two keys valid at once) — use it.

### Auth0

Dashboard: Applications → your app → Credentials → Rotate client secret. If you use a Machine-to-Machine app, rotate its client secret separately.

### Local auth secrets (NextAuth, Better Auth, custom JWT)

```bash
scripts/generate-secrets.sh AUTH_SECRET NEXTAUTH_SECRET JWT_SECRET SESSION_SECRET BETTER_AUTH_SECRET
```

Writes to `secrets.txt`. **Warns the user** that rotating invalidates all existing sessions.

---

## Tier 4 — Payments

### Stripe

Dashboard-only. Do all three:

1. https://dashboard.stripe.com/apikeys → roll secret key, roll every restricted key (they have a 12-hour grace period — don't panic).
2. https://dashboard.stripe.com/webhooks → per endpoint → roll signing secret.
3. If you use test mode: repeat the above in Test Mode.

Stripe CLI:
```bash
# Rolling via CLI is not supported for secret keys — dashboard only.
# But you can audit recent events:
stripe events list --limit 50
```

### Paddle / Lemon Squeezy

Dashboard-only rotation. Add to [MANUAL] with a direct link.

---

## Tier 5 — Communication

### Resend

https://resend.com/api-keys — delete old, create new. Note: Resend API keys grant full send permissions; scope by domain if you can.

### SendGrid

https://app.sendgrid.com/settings/api_keys — delete + recreate. SendGrid supports scoped API keys; prefer minimum scope.

### Postmark

https://account.postmarkapp.com/ → Servers → Server → API Tokens → regenerate.

### Mailgun

Dashboard → Sending → Domain settings → API security → regenerate.

### Loops / Customer.io

Dashboard → Settings → API. Both provide rotation.

### Twilio

https://www.twilio.com/console → Account → API keys & tokens. Rotate:
1. Auth Token (requires confirming you've updated everywhere).
2. Any API Keys + Secrets.

---

## Tier 6 — AI providers

All dashboard-only, all similar pattern: revoke old key, create new.

- OpenAI → https://platform.openai.com/api-keys
- Anthropic → https://console.anthropic.com/settings/keys
- Google AI Studio → https://aistudio.google.com/apikey
- Google Vertex → Cloud Console → APIs & Services → Credentials
- Replicate → https://replicate.com/account/api-tokens
- Groq → https://console.groq.com/keys
- Mistral → https://console.mistral.ai/api-keys
- OpenRouter → https://openrouter.ai/keys

These are especially urgent because they burn money fast if the attacker uses them.

---

## Tier 7 — Observability

### Sentry

https://sentry.io/settings/auth-tokens — delete + recreate.

The DSN (`SENTRY_DSN`, `NEXT_PUBLIC_SENTRY_DSN`) is not a secret per se — it's included in client bundles. You don't need to rotate unless the auth-token scope could modify alerts/projects, in which case the token rotation already covers it.

### PostHog

https://us.posthog.com/settings/user-api-keys — personal API keys (server-side usage). Project API keys are public and don't need rotation.

### Datadog

https://app.datadoghq.com/organization-settings/api-keys — rotate API keys and Application keys separately.

---

## Tier 8 — Git hosts

### GitHub

1. Review authorized OAuth apps: https://github.com/settings/applications → revoke Vercel's OAuth app, then reinstall via Vercel.
2. Rotate Personal Access Tokens used by Vercel: https://github.com/settings/tokens.
3. Check SSH keys: https://github.com/settings/keys — remove any you don't recognize.
4. Audit repo access: Organization settings → Third-party access.

### GitLab

1. User Settings → Applications → revoke Vercel, reinstall.
2. User Settings → Access Tokens → delete + recreate any PATs.
3. Audit: Admin → Monitoring → Audit Events (if self-managed).

---

## Tier 9 — Webhooks

Any `*_WEBHOOK_URL` env var is a **secret** — the URL itself grants posting rights to anyone holding it.

### Slack incoming webhooks

Slack admin → Apps → Incoming Webhooks → remove old webhook, create new one with same channel binding. The URL is the secret.

### Discord webhooks

Channel settings → Integrations → Webhooks → Delete old, create new.

### Generic webhook signing secrets

Anything ending in `_WEBHOOK_SECRET` or `_SIGNING_SECRET` — rotate at the source service (Stripe, GitHub App, custom provider) and update the Vercel env var after.

---

## Tier 10 — Everything else

For env vars your classifier flagged as `unknown` or `generic-secret`:

1. Ask the user to identify the owning service.
2. If the answer is "I don't know, that's from before my time" — treat as highest priority. Unknown secrets can't be verified as rotated.
3. Add to `[BLOCKED]` in the checklist if no clear owner emerges.

For `analytics-public`, `stripe-public`, `sentry-dsn-public`, `public-config` — these are client-exposed by design. No rotation needed; note in checklist and move on.

---

## When a rotation fails

- **API rate-limited** — back off, retry. Most providers rate-limit at 1-5 rotations per minute per token.
- **Token doesn't have permission to rotate** — fall back to dashboard, add to [MANUAL].
- **Service is paused/inactive** — skip it, note in checklist.
- **Service has no rotation path** (rare, mostly very old self-hosted tools) — add to [BLOCKED] and escalate.

Record each failure in `rotation-log.md` alongside the incident folder so nothing gets lost.
