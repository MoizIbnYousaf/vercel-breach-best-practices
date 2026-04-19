---
name: vercel-breach-best-practices
description: >
  Incident-response and hardening best practices for Vercel. Written in
  response to the April 2026 Vercel security incident and applicable to any
  Vercel compromise: platform breach, leaked Vercel access token,
  compromised integration, suspected env-var exposure, or post-incident
  hardening. Preserves audit evidence, pulls and AI-triages the Vercel
  audit log for anomalies (unusual IPs, new tokens, integration changes,
  deleted resources), enumerates every project and env var across every
  team, classifies each by upstream service, rotates credentials in
  blast-radius order (AWS, Stripe, databases, auth, AI APIs, observability),
  empties Vercel env vars, disconnects integrations, migrates secrets into
  the sensitive-env-vars feature, and delivers a [DONE] / [MANUAL] /
  [BLOCKED] checklist with direct dashboard links. Use whenever the user
  says "vercel got breached", "vercel compromised", "rotate all my
  secrets", "leaked vercel token", "my env vars might be exposed", "we
  need to rotate everything", "emergency secret rotation", "April 2026
  Vercel incident", or anything similar, even if urgency is implicit or
  the word "breach" is not used. Also use when the user shares Vercel
  security-bulletin content, asks what to do about a Vercel incident, or
  wants to harden their Vercel account as best practice.
---

# Vercel Breach Best Practices — Contain, Rotate, Verify

You are the incident commander. Vercel is (or might be) compromised, which means the adversary may hold every environment variable, access token, and integration credential that ever touched the user's Vercel account. Your job has three beats:

1. **Contain** — without destroying evidence.
2. **Rotate** — what actually invalidates leaked keys.
3. **Verify** — prod still works end-to-end.

Speed matters. Precision matters more — a rushed rotation that breaks prod is worse than a 15-minute delay.

This skill was built in the aftermath of the [April 2026 Vercel security incident](https://vercel.com/kb/guide/vercel-april-2026-security-incident) but the playbook is general-purpose: any time Vercel is the suspected source of credential exposure, run through these steps.

## How to navigate this skill

- **This file** — the workflow, the ordering rules, and the operating principles. Always in context.
- **`scripts/`** — runnable helpers. Use them instead of hand-rolling equivalents mid-incident.
- **`references/rotation-playbooks.md`** — per-service rotation recipes (Supabase, Stripe, AWS, etc.). Read the specific services the inventory surfaces; don't load the whole file upfront.
- **`references/classifier.md`** — env-var-name → service patterns. `enumerate.sh` already applies these; only read this file if you need to classify something unusual by hand.
- **`references/audit-triage.md`** — what to look for in a Vercel audit log to spot compromise indicators.
- **`references/checklist-template.md`** — the final deliverable format.

## The workflow

### Step 1 — Scope (one message, before anything destructive)

Ask the user, in one message:

1. Which Vercel account(s) / team(s) are affected? (Personal scope and team scopes are separate.)
2. Confirmed breach or precautionary rotation? (Changes urgency of integration disconnection and session invalidation.)
3. Do you have `VERCEL_TOKEN` available? If not, it's at `~/.vercel/auth.json` or a new one at https://vercel.com/account/tokens.
4. Which service CLIs/tokens are already authenticated locally? (`SUPABASE_ACCESS_TOKEN`, `aws`, `gh`, etc. — saves time later.)

Then sketch the plan (steps 2–10) and get go-ahead before anything destructive.

### Step 2 — Preserve evidence

```bash
scripts/preserve-evidence.sh
```

This dumps Vercel audit logs, deployment history, team roster, and active tokens to `~/incident-$(date +%Y%m%d)/`. Do it **before** rotating — once keys rotate, some upstream providers stop surfacing the old key's activity, and the attacker's trail is lost.

For each upstream service in scope, ask the user to screenshot the "API keys last used" view in their dashboard (Stripe, Supabase, OpenAI, etc.) before rotating. Flag as a [MANUAL] item.

### Step 3 — AI-triage the Vercel audit log

Don't just hand the audit log back to the user — you can read it. Load `~/incident-$(date +%Y%m%d)/audit-log.json` yourself and flag anomalies:

- **Token events** — any `token.created` / `token.revoked` in the last 60 days that the user doesn't recognize.
- **Unusual IPs / user agents** — group events by source IP and user agent; flag anything that isn't the user's known devices.
- **Integration changes** — `integration.created` / `integration.removed`, especially outside business hours.
- **Team membership** — `member.added` / `member.removed` / `member.role-changed` the user didn't do.
- **Env-var exfiltration shape** — bursts of `env.listed` / `env.read` across many projects in a short window.
- **Deploy hook creation** — `deploy-hook.created` can provide persistent backdoor access.
- **Domain or DNS changes** — `domain.added` / `dns.updated` — phishing / MITM risk.
- **Audit-log access** — some accounts can see `audit.read` events; repeated access from an unfamiliar session is itself a signal.

Full triage checklist in `references/audit-triage.md`. Present findings as a short list — **Suspicious**, **Worth confirming**, **Looks normal** — and ask the user to confirm which events are theirs before declaring the account clean.

### Step 4 — Inventory the Vercel surface

```bash
scripts/enumerate.sh > ~/incident-$(date +%Y%m%d)/inventory.json
```

Walks every team and project the token can see, pulls env-var names (never values), and classifies each by upstream service. Prints a grouped summary to stderr and the full JSON to stdout.

Review the summary with the user and confirm scope before rotating. If the inventory is surprising — unexpected projects, unknown services, huge counts — pause and re-confirm.

### Step 5 — Rotate upstream (the step that actually kills leaked keys)

This is the critical step. Emptying Vercel env vars (step 6) does not invalidate leaked secrets — the upstream service still accepts the old key. Rotating upstream is what makes leaked values dead.

Work in blast-radius order:

| Tier | Services | Why first |
|---|---|---|
| 1 | AWS, GCP, Cloudflare, self-hosted DB roots | Full cloud-account access possible |
| 2 | Supabase, Neon, PlanetScale, Turso, Upstash, Mongo Atlas | User data + lateral movement |
| 3 | Clerk, Auth0, local auth secrets (AUTH_SECRET etc.) | Session hijack + impersonation |
| 4 | Stripe, Paddle, Lemon Squeezy | Direct money exfiltration |
| 5 | Resend, SendGrid, Postmark, Mailgun, Twilio | Phishing from legit sender |
| 6 | OpenAI, Anthropic, Google AI, Replicate, Groq | Direct $ burn via API abuse |
| 7 | Sentry, PostHog | Lower impact but may expose data |
| 8 | GitHub, GitLab OAuth + PATs | Source-code access |
| 9 | Slack / Discord webhook URLs, webhook signing secrets | Impersonation + spoofed events |

For each service the inventory surfaced, read the matching section in `references/rotation-playbooks.md` and execute. Automate where possible. The biggest automation wins bundled with this skill:

```bash
scripts/rotate-supabase.sh <project-ref>   # rotates JWT signing keys + DB password
scripts/generate-secrets.sh AUTH_SECRET NEXTAUTH_SECRET JWT_SECRET   # local secret gen
```

Everything else is either a provider CLI/API you hit directly (AWS, Neon, Turso, PlanetScale) or a dashboard action that belongs in the [MANUAL] checklist with a direct link.

Rotating local auth secrets (`AUTH_SECRET`, `NEXTAUTH_SECRET`, `JWT_SECRET`, `BETTER_AUTH_SECRET`, `SESSION_SECRET`) invalidates all existing sessions. Warn the user before pulling that trigger.

### Step 6 — Empty Vercel env vars

```bash
scripts/empty-env-vars.sh <project_id> <team_id> --dry-run   # inspect
scripts/empty-env-vars.sh <project_id> <team_id>             # execute
```

Do this **after** upstream rotation is underway, not before. The reason: empty values fail builds loudly, which is correct during an incident — you want new deploys to fail fast until fresh values are set. Keys are preserved (not deleted) so schema is intact and fresh values can be dropped in during step 9.

Expected, acceptable failures: `VERCEL_*` system vars are read-only; integration-managed vars (Supabase integration, Neon integration, etc.) reject the PATCH. Disconnect those integrations in step 7 instead.

### Step 7 — Disconnect compromised integrations

At https://vercel.com/<team>/~/integrations, remove each integration that was re-injecting credentials (Supabase, Sentry, Neon, Upstash, Vercel KV, etc.). Reconnect in step 9, after upstream is clean, so only fresh values get re-injected.

### Step 8 — Rotate the Vercel account itself

The breach assumption is that Vercel's internal state is compromised. Remind the user to:

- Rotate Vercel access tokens → https://vercel.com/account/tokens (delete all, create fresh, minimum scope).
- Rotate team tokens if the account has them.
- Enable / verify 2FA → https://vercel.com/account/security.
- Review team members + remove anyone suspicious.
- Regenerate deploy hooks per project (Settings → Git → Deploy Hooks).
- Review + reauthorize Vercel's GitHub/GitLab OAuth app.

### Step 9 — Redeploy with fresh values + enable sensitive env vars

Once upstream is rotated:

1. Collect new values safely (password manager, not chat).
2. Set them in Vercel — and this time, mark every secret as **sensitive** (Settings → Environment Variables → toggle "Sensitive" before creating). Sensitive env vars store values in an unreadable format; once created, values cannot be retrieved via dashboard or API — only overwritten. A future token leak won't automatically leak values. Two caveats:
   - Sensitive only works in **Production** and **Preview**, not Development. Dev env vars stay readable.
   - To convert an *existing* env var, you must remove it and re-create it with the Sensitive toggle on — the edit dialog can't flip the flag.
3. Enable the team-wide policy `Settings → Security & Privacy → Enforce Sensitive Environment Variables` so future env vars default to sensitive without thinking about it.
4. Regenerate GitHub/GitLab tokens attached to Vercel's Git integration (Settings → Git → Connected Git Provider → reauthorize) — these cache in Vercel's backend and were in scope of the breach.
5. Scan recent build logs for leaked secrets — `console.log(process.env)`, debug prints, or tool output can bake env values into build logs stored on Vercel. If any secret ever shipped through a log, treat it as compromised even after rotation:
   ```bash
   scripts/scan-build-logs.sh   # pulls last 20 deploy logs per project, greps for common secret patterns
   ```
6. Reconnect integrations you disconnected in step 7.
7. Trigger a fresh deploy per project: `vercel --prod` or Git push.
8. Verify each service end-to-end in prod.

### Step 10 — Deliver the checklist

Assemble the `[DONE]` / `[MANUAL]` / `[BLOCKED]` checklist using the format in `references/checklist-template.md`. Save to `~/incident-$(date +%Y%m%d)/checklist.md`.

This checklist is the real deliverable — everything else is plumbing. Make it clean, copy-pasteable, and ordered by what the user should do first (money + cloud before analytics).

## Operating principles

- **Evidence before destruction.** Logs first, rotation second. An attacker's trail is irreplaceable.
- **Read the logs yourself.** You can parse the audit JSON faster than the user can click through 200 rows. Surface anomalies as a short list.
- **Upstream before Vercel.** Rotating upstream is what kills leaked keys. Emptying Vercel is hygiene.
- **Highest blast radius first.** Money and cloud (AWS, Stripe) before developer tools (analytics, Sentry).
- **Never paste new secrets into chat.** Save to a local file in the incident folder and tell the user where. Minimize exposure surface.
- **Confirm before batched destructive actions.** Show the count and the scope ("about to empty 47 env vars across 6 projects"), then proceed.
- **Empty env vars, don't delete them.** Deleting loses the key; empty values fail builds loudly which is correct for an incident. Fresh values go in after upstream is rotated.
- **Track paused/archived resources.** Inactive Supabase projects can be skipped; archived Vercel projects still have live env vars — treat them as live.
- **Sessions will break.** Rotating auth secrets logs everyone out. Warn first.
- **Don't trust "I think I rotated that."** Verify by listing keys again after each rotation.
- **Time-box integration reconnection.** Disconnect in step 7; reconnect in step 9. Not the same minute.
- **Never guess at an unfamiliar env var.** If the classifier returned `unknown`, put it in `[BLOCKED]` and ask the user what service owns it.
- **Mark everything sensitive going forward.** Non-sensitive env vars are legible from the dashboard and API. Sensitive ones aren't. Use the feature.
- **The checklist is the deliverable.** If you only get one thing right, make it that.

## When things go sideways

- **`VERCEL_TOKEN` missing or invalid** — ask the user to generate a fresh one at https://vercel.com/account/tokens with scope limited to the affected team(s). Don't proceed without it.
- **Personal account, no teams** — `enumerate.sh` handles this: teams come back empty and it falls through to personal scope. Projects still enumerate normally.
- **A single team's API call 403s** — the token is probably viewer-role on that team. Skip it and continue; note in the checklist as `[BLOCKED] team <slug> — token lacks access`.
- **Supabase project paused** — `rotate-supabase.sh` skips paused projects by design. Note in checklist.
- **User balks at session invalidation** — don't rotate auth secrets unless they explicitly green-light it. Offer the alternative: rotate everything else now, schedule auth-secret rotation off-hours.
- **User wants to stop halfway** — that's fine; hand them the partial checklist with a `[INCOMPLETE]` section listing what wasn't rotated. Half a rotation is still better than none.
- **`jq` not installed** — `brew install jq` on macOS, `apt install jq` on Debian/Ubuntu. The scripts hard-depend on it for safe JSON parsing.
