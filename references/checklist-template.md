# Final checklist template

The deliverable at the end of an incident. Save to `~/incident-$(date +%Y%m%d)/checklist.md` and hand the copy-pasteable markdown back to the user.

## Principles

- **Split into three buckets**: `[DONE]` (what the skill did automatically), `[MANUAL]` (what the user needs to click through), and `[BLOCKED]` (unknowns and failures).
- **Order by what to do first.** Money and cloud rotations go at the top. Analytics + observability go last.
- **One link per action** — deep links into dashboards, not home pages.
- **Count things.** "emptied 47 env vars across 6 projects" is more useful than "emptied all env vars".
- **Note what was skipped and why.** Paused Supabase projects, 403s on foreign teams, etc.

## Template

```markdown
# Vercel Incident Response — <team slug> — <YYYY-MM-DD>

Scope: <N teams, M projects, K env vars, Z services>.
Confirmed breach: <yes | no — precautionary>.
Evidence preserved to: ~/incident-YYYY-MM-DD/

---

## [DONE] Rotated automatically

### Vercel
- [x] Emptied 47 env vars across 6 projects in team `acme` (see rotation-log.md)
- [x] Dumped audit log (200 most-recent events) + deployment history to ~/incident-YYYY-MM-DD/

### Upstream services
- [x] Supabase project `prod-xyz`: rotated ES256 signing key, rotated DB password
- [x] Supabase project `staging-abc`: rotated (paused project `archive-2024` skipped — note below)
- [x] Neon project `prod`: rotated role password for `app_user` (new DSN in secrets.txt)
- [x] Generated AUTH_SECRET, NEXTAUTH_SECRET, JWT_SECRET (values in secrets.txt)

### Audit-log triage (what we found)
- [x] No suspicious token creations in the last 60 days
- [x] No unfamiliar IPs on recent sessions
- [x] One env.listed burst on 2026-04-18 03:47 UTC across 8 projects — **user confirmed** this was their CI run

---

## [MANUAL] Your turn — in priority order

### Money / cloud (do now, within the hour)
- [ ] AWS IAM — rotate access keys for user `app-production` → https://console.aws.amazon.com/iam/home#/security_credentials
- [ ] Stripe — roll secret key → https://dashboard.stripe.com/apikeys
- [ ] Stripe — roll 5 webhook signing secrets → https://dashboard.stripe.com/webhooks
- [ ] Stripe (test mode) — roll test secret key → https://dashboard.stripe.com/test/apikeys

### Auth / identity
- [ ] Clerk — roll secret key → https://dashboard.clerk.com
- [ ] GitHub — revoke Vercel OAuth app + reinstall → https://github.com/settings/applications
- [ ] GitHub — rotate PATs → https://github.com/settings/tokens

### AI / APIs (cost-risk if attacker used)
- [ ] OpenAI — revoke + recreate → https://platform.openai.com/api-keys
- [ ] Anthropic — revoke + recreate → https://console.anthropic.com/settings/keys

### Email / communications
- [ ] Resend → https://resend.com/api-keys
- [ ] Twilio — rotate Auth Token → https://www.twilio.com/console

### Observability
- [ ] Sentry auth token → https://sentry.io/settings/auth-tokens

### Webhooks
- [ ] Slack incoming webhook for #alerts → admin → Apps → Incoming Webhooks
- [ ] Discord webhook for #deploys → Channel Settings → Integrations

### Vercel account hardening
- [ ] Rotate Vercel access tokens → https://vercel.com/account/tokens
- [ ] Rotate Supabase access tokens → https://supabase.com/dashboard/account/tokens
- [ ] Enable / verify 2FA → https://vercel.com/account/security
- [ ] Review team members → https://vercel.com/<team>/~/settings/members
- [ ] Reconnect integrations (only after upstream is clean) → https://vercel.com/<team>/~/integrations
- [ ] Enable team-wide "Enforce Sensitive Environment Variables" policy → https://vercel.com/<team>/~/settings/security

### Redeploy (last)
- [ ] Set new env-var values in Vercel — mark every secret as **Sensitive** before saving
- [ ] Regenerate deploy hooks (Settings → Git → Deploy Hooks for each project)
- [ ] Trigger fresh deploys: `vercel --prod` or Git push
- [ ] Smoke-test each production service end-to-end

---

## [BLOCKED] Needs your input

- [ ] Env var `CUSTOM_FOO_KEY` on project `internal-tools` — classifier returned `unknown`. Which service owns this?
- [ ] Integration `super-custom-thing` — no documented rotation path found. Contact vendor?
- [ ] Team `legacy-org` — token lacks access (403). Can you generate a token with access to this team, or should we skip?

---

## Evidence preserved

All in `~/incident-YYYY-MM-DD/`:
- `audit-log.json` — first 200 audit events
- `deployments.json` — recent deployment metadata per project
- `team-roster.json` — who has access to what team
- `inventory.json` — every project and env-var name with service classification
- `secrets.txt` — newly generated secrets (🔒 local only, do not share)
- `rotation-log.md` — per-rotation success/fail log
- `checklist.md` — this file
```

## Things to verify before handing off

- [ ] Did you mark every secret in step 9 as Sensitive?
- [ ] Is `~/incident-YYYY-MM-DD/secrets.txt` locked down (`chmod 600`)?
- [ ] Are there any `[BLOCKED]` items the user can resolve now vs. later?
- [ ] Did you enable the team-wide Enforce Sensitive Environment Variables policy?
- [ ] Did you test at least one prod endpoint end-to-end after redeploying?
