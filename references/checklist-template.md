# Final checklist template

The deliverable at the end of an incident. Save to `~/incident-$(date +%Y%m%d)/checklist.md` and hand the copy-pasteable markdown back to the user.

## Principles

- **Three buckets**: `[DONE]` (what the skill observed or executed with consent), `[MANUAL]` (what the user rotates in their own dashboards), `[BLOCKED]` (unknowns and failures).
- **Order by what to do first.** Money and cloud go at the top. Analytics and observability go last.
- **One link per action** — deep links into dashboards, not home pages.
- **Count things.** "emptied 47 env vars across 6 projects" is more useful than "emptied all env vars".
- **Note what was skipped and why.** Paused Supabase projects, 403s on foreign teams, etc.
- **Never write secret values into this file.** Reference them by name; actual values live in `secrets.txt` (chmod 600).

## Template

```markdown
# Vercel Incident Response — <team slug> — <YYYY-MM-DD>

Scope: <N teams, M projects, K env vars, Z services>.
Confirmed breach: <yes | no — precautionary>.
Evidence preserved to: ~/incident-YYYY-MM-DD/

---

## [DONE] What the skill completed this session

### Evidence + inventory (read-only)
- [x] Evidence preserved — Activity Log (via API + `vercel activity`), deploys, tokens, members, integrations at ~/incident-YYYY-MM-DD/
- [x] Inventory: 47 env vars across 6 projects in team `acme`, classified by upstream service (see inventory.json)
- [x] Build logs scanned across last 20 deploys per project — 0 leaked-secret patterns found (see build-log-scan-*.txt)

### Activity Log triage
- [x] No unexpected `oauth-app-token-created` or `deploy-hook-created` events in the last 60 days
- [x] No unfamiliar IPs on recent sessions
- [x] One `env-variable-read:cli:env:pull` burst on 2026-04-18 03:47 UTC across 8 projects — **user confirmed** this was their CI run
- [x] No protection-bypass events (`project-automation-bypass`, `firewall-bypass-created`, `alias-protection-bypass-*`)

### Vercel mutations (two-step consent, executed with --execute)
- [x] Emptied 47 env var values on project `api-prod` in team `acme` (keys preserved for repopulation)
- [x] Skipped 3 VERCEL_* system vars
- [x] 2 integration-managed vars failed to empty — will be handled by disconnecting integration in Step 7

### Local-only generation
- [x] Generated fresh AUTH_SECRET, NEXTAUTH_SECRET, JWT_SECRET, SESSION_SECRET → secrets.txt (chmod 600)

---

## [MANUAL] Your turn — in priority order

### Money / cloud (do first, within the hour)
- [ ] AWS IAM — rotate access keys for user `app-production` → https://console.aws.amazon.com/iam/home#/security_credentials
- [ ] Stripe — roll secret key → https://dashboard.stripe.com/apikeys
- [ ] Stripe — roll 5 webhook signing secrets → https://dashboard.stripe.com/webhooks
- [ ] Stripe (test mode) — roll test secret key → https://dashboard.stripe.com/test/apikeys

### Databases
- [ ] Supabase project `prod-xyz` — rotate ES256 JWT signing key + DB password → https://supabase.com/dashboard/project/prod-xyz/settings/jwt-signing-keys
- [ ] Supabase project `staging-abc` — same → https://supabase.com/dashboard/project/staging-abc/settings/jwt-signing-keys
- [ ] Neon project `prod` — reset password for role `app_user` → `neon roles reset-password app_user --project-id prod`
- [ ] Upstash Redis — reset password → https://console.upstash.com/redis/<db-id>
- [ ] Upstash QStash — regenerate token + both signing keys → https://console.upstash.com/qstash
  - Reference: https://upstash.com/blog/rotate-upstash-secrets-after-vercel-incident

### Auth / identity
- [ ] Clerk — roll secret key → https://dashboard.clerk.com/last-active → API Keys
  - ⚠ Invalidates all active sessions. Expected during breach response.
- [ ] GitHub — revoke Vercel OAuth app + reinstall → https://github.com/settings/applications
- [ ] GitHub — review + rotate PATs → https://github.com/settings/tokens

### AI / APIs (cost-risk if attacker used)
- [ ] OpenAI — revoke + recreate → https://platform.openai.com/api-keys (also check usage dashboard for unusual spend)
- [ ] Anthropic — revoke + recreate → https://console.anthropic.com/settings/keys

### Email / communications
- [ ] Resend → https://resend.com/api-keys
- [ ] Twilio — rotate Auth Token → https://www.twilio.com/console

### Observability
- [ ] Sentry auth token → https://sentry.io/settings/auth-tokens

### Webhooks
- [ ] Slack incoming webhook for #alerts → admin → Apps → Incoming Webhooks (regenerate)
- [ ] Discord webhook for #deploys → Channel Settings → Integrations → Webhooks (delete + recreate)

### Vercel account hardening
- [ ] **Create a fresh team-scoped token FIRST** — https://vercel.com/account/tokens
- [ ] Update local CLI auth with the new token
- [ ] **Then revoke old tokens** (delete anything you don't recognize)
- [ ] Verify 2FA → https://vercel.com/account/security
- [ ] Review team members, remove anyone suspicious → https://vercel.com/<team>/~/settings/members
- [ ] Regenerate deploy hooks per project (Settings → Git → Deploy Hooks)
- [ ] Enable team-wide "Enforce Sensitive Environment Variables" policy → https://vercel.com/<team>/~/settings/security
- [ ] Reconnect integrations (only after upstream rotations done) → https://vercel.com/<team>/~/integrations

### Redeploy (last)
- [ ] Set new env-var values in Vercel — each should default to **Sensitive** if the team-wide policy is enabled
- [ ] Trigger fresh deploys: `vercel --prod` or Git push
- [ ] Smoke-test each production service end-to-end

### Cleanup (optional)
- [ ] Wipe `~/incident-YYYY-MM-DD/secrets.txt` once values are in your password manager
- [ ] Keep `audit.log` and evidence files for post-mortem; remove when you're ready

---

## [BLOCKED] Needs your input

- [ ] Env var `CUSTOM_FOO_KEY` on project `internal-tools` — classifier returned `unknown`. Which service owns this?
- [ ] Integration `super-custom-thing` — no documented rotation path found. Contact vendor?
- [ ] Team `legacy-org` — token lacks access (403). Generate a token with access to this team, or skip?
- [ ] Supabase project `archive-2024` — paused (INACTIVE). Leaked creds are inert while paused; **must rotate JWT + DB password BEFORE resuming**.

---

## Evidence preserved

All in `~/incident-YYYY-MM-DD/`:
- `audit-log-<team>.json` — Activity Log snapshot via API
- `vercel-activity-30d.json` — 30-day dump via `vercel activity` CLI (if CLI was installed)
- `deployments-<team>.json` — recent deployment metadata per team
- `members-<team>.json` — team roster
- `integrations-<team>.json` — installed integrations
- `active-tokens.json` — Vercel access tokens at time of snapshot
- `inventory.json` — every project and env-var name with service classification
- `secrets.txt` — newly generated local secrets (🔒 chmod 600, do not share)
- `audit.log` — every API call this session made (timestamp, method, host, path)
- `exposure-map.md` — user-reported exposure supplement (if Step 4.5 was done)
- `checklist.md` — this file
```

## Things to verify before handing off

- [ ] Did you mark every re-populated secret as Sensitive, or is the team-wide policy enabled?
- [ ] Is `~/incident-YYYY-MM-DD/secrets.txt` locked down (`chmod 600`)?
- [ ] Any `[BLOCKED]` items the user can resolve now vs. later?
- [ ] Did you test at least one prod endpoint end-to-end after redeploying?
- [ ] Does `audit.log` show only calls to `api.vercel.com` and `api.supabase.com` — no unexpected hosts?
