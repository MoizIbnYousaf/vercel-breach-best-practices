# Env-var → service classifier

`scripts/enumerate.sh` already classifies every env var it finds using these patterns. Read this file only if you need to classify something manually — e.g., the script returned `unknown` and you're trying to figure out what service owns a var.

## How classification works

Each env var name is tested against these patterns in order. First match wins. The script emits `service: <label>` alongside every env var in `inventory.json`.

| Pattern | Service | Tier | Notes |
|---|---|---|---|
| `SUPABASE_*`, `NEXT_PUBLIC_SUPABASE_*`, `*SERVICE_ROLE*` | `supabase` | 2 | Rotate JWT + DB password |
| `BLOB_READ_WRITE_TOKEN` | `vercel-blob` | 2 | Vercel-managed; rotate via dashboard |
| `KV_*`, `UPSTASH_*`, `REDIS_URL` | `upstash-kv` | 2 | Vercel KV = Upstash under the hood |
| `DATABASE_URL`, `POSTGRES_*`, `DIRECT_URL`, `SHADOW_*` | `database-url` | 2 | Inspect the host to sub-classify |
| `NEON_*` | `neon` | 2 | Rotate via Neon CLI |
| `TURSO_*` | `turso` | 2 | Rotate via Turso CLI |
| `PLANETSCALE_*` | `planetscale` | 2 | Per-branch password |
| `MONGODB_*`, `MONGO_URI` | `mongodb` | 2 | Dashboard rotation |
| `RESEND_API_KEY` | `resend` | 5 | Dashboard |
| `SENDGRID_*` | `sendgrid` | 5 | Dashboard |
| `POSTMARK_*` | `postmark` | 5 | Dashboard |
| `MAILGUN_*` | `mailgun` | 5 | Dashboard |
| `LOOPS_*` | `loops` | 5 | Dashboard |
| `SENTRY_AUTH_TOKEN` | `sentry` | 7 | Dashboard |
| `SENTRY_DSN`, `NEXT_PUBLIC_SENTRY_DSN` | `sentry-dsn-public` | — | Not secret; client-exposed |
| `STRIPE_SECRET_KEY`, `STRIPE_RESTRICTED_*`, `STRIPE_WEBHOOK_SECRET` | `stripe` | 4 | Dashboard; don't forget test mode |
| `STRIPE_PUBLISHABLE_KEY`, `NEXT_PUBLIC_STRIPE_*` | `stripe-public` | — | Not secret; client-exposed |
| `OPENAI_API_KEY` | `openai` | 6 | Dashboard |
| `ANTHROPIC_API_KEY` | `anthropic` | 6 | Dashboard |
| `GOOGLE_*API_KEY`, `GEMINI_API_KEY` | `google-ai` | 6 | Cloud Console |
| `MISTRAL_*`, `GROQ_*`, `REPLICATE_*`, `OPENROUTER_*` | `ai-provider` | 6 | Each provider's dashboard |
| `CLERK_SECRET_KEY`, `CLERK_*KEY` | `clerk` | 3 | Dashboard |
| `AUTH0_*` | `auth0` | 3 | Dashboard |
| `NEXTAUTH_SECRET`, `AUTH_SECRET`, `BETTER_AUTH_SECRET`, `JWT_SECRET`, `SESSION_SECRET` | `local-auth-secret` | 3 | Local gen; invalidates sessions |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` | `aws` | 1 | Highest priority |
| `CLOUDFLARE_*`, `CF_API_TOKEN`, `CF_ACCOUNT_ID` | `cloudflare` | 1 | Dashboard |
| `GITHUB_TOKEN`, `GH_TOKEN`, `GITLAB_TOKEN` | `git-host` | 8 | Revoke OAuth + PATs |
| `TWILIO_*`, `VONAGE_*` | `sms` | 5 | Dashboard |
| `PUSHER_*`, `ABLY_*` | `realtime` | — | Dashboard |
| `ALGOLIA_*API_KEY`, `MEILISEARCH_*MASTER_*`, `TYPESENSE_*API_KEY` | `search` | — | Admin keys only |
| `POSTHOG_API_KEY`, `MIXPANEL_SECRET`, `AMPLITUDE_API_KEY` | `analytics-server` | 7 | Dashboard |
| `NEXT_PUBLIC_POSTHOG_*`, `NEXT_PUBLIC_UMAMI_*`, `NEXT_PUBLIC_GA_*` | `analytics-public` | — | Client-exposed; don't rotate |
| `*_WEBHOOK_URL`, `SLACK_WEBHOOK_URL`, `DISCORD_WEBHOOK_URL` | `webhook-url` | 9 | URL itself is the secret |
| `*_WEBHOOK_SECRET`, `*_SIGNING_SECRET` | `webhook-signing` | 9 | Rotate at source service |
| `NOTION_TOKEN`, `LINEAR_API_KEY`, `FIGMA_TOKEN` | `tool-api` | — | Dashboard |
| `CRON_SECRET`, `VERCEL_CRON_SECRET` | `cron-secret` | — | Generate with openssl |
| `VERCEL_*` | `vercel-system` | — | System-managed; skip |
| `*_API_KEY`, `*_SECRET`, `*_TOKEN`, `*_PASSWORD` | `generic-secret` | ? | Ask user which service |
| `NEXT_PUBLIC_*` | `public-config` | — | Likely non-secret, verify |
| *otherwise* | `unknown` | ? | Ask user |

## When classification is ambiguous

`DATABASE_URL` is the big one — it's just a Postgres DSN, but the host tells you where to rotate. Inspect:

```bash
# Pull the host out of a DSN without echoing the password
echo "$DATABASE_URL" | sed -E 's|^[^@]+@([^:/]+).*|\1|'
```

- `*.supabase.co` → rotate via Supabase playbook
- `*.neon.tech` → rotate via Neon playbook
- `*.turso.io` → rotate via Turso playbook
- `aws-*.*.rds.amazonaws.com` → rotate via AWS (see self-hosted Postgres in rotation-playbooks.md)
- Everything else → ask the user

For `generic-secret` or `unknown`, always ask the user before rotating — you can't safely guess which upstream to rotate against.

## Adding a new pattern

If you hit a recurring unknown, update `scripts/enumerate.sh`'s `classify()` function and add a row to this table. Keep the pattern specific; overly broad patterns eat legitimately-different services (`*_KEY` would catch `STRIPE_KEY` but also `ALGOLIA_KEY` which belong in different tiers).
