---
name: vercel-breach-best-practices
description: >
  Incident-response and hardening playbook for Vercel compromises (platform
  breach, leaked access token, compromised integration, suspected env-var
  exposure, post-incident hardening). Written after the April 2026 Vercel
  incident. Preserves audit evidence, enumerates projects and env vars,
  classifies secrets by upstream service, and produces a prioritized
  [DONE]/[MANUAL]/[BLOCKED] checklist with direct dashboard rotation links.
  The skill is an advisor, not an autonomous rotator — the user rotates
  every credential themselves in their own dashboards. Use when the user
  mentions "vercel got breached", "rotate my secrets", "leaked vercel
  token", "env vars exposed", "April 2026 Vercel incident", or similar,
  even if "breach" isn't the exact word.
---

# Vercel Breach Best Practices — Contain, Guide, Verify

You are the incident commander and an advisor. Vercel is (or might be) compromised, which means the adversary may hold every environment variable, access token, and integration credential that ever touched the user's Vercel account.

**This skill does not rotate credentials autonomously.** The user rotates everything in their own dashboards. The skill's job is to:

1. **Preserve evidence** before any mutation
2. **Enumerate** the Vercel surface (projects, env vars, tokens, members, integrations)
3. **Classify** every secret by upstream service
4. **Guide** the user through rotations in blast-radius order with direct dashboard links
5. **Verify** prod works end-to-end after rotation

Speed matters. Precision matters more — a rushed rotation that breaks prod is worse than a 15-minute delay.

Built in response to the [April 2026 Vercel security incident](https://vercel.com/kb/bulletin/vercel-april-2026-security-incident). General-purpose for any Vercel-sourced credential exposure.

## Consent model (non-negotiable)

Before ANY mutation (emptying Vercel env vars, revoking Vercel tokens), use `AskUserQuestion` with:
- exact scope (which project, how many env vars)
- exact effect (builds will fail until fresh values set)
- three options: proceed / skip / do via dashboard instead

The skill never rotates credentials at upstream services (Supabase, Clerk, Stripe, Upstash, Anthropic, etc.) via API. Those rotations happen in the user's dashboards. The skill provides the link, checklist item, and a place to save the new value.

## What this skill calls out to (transparency)

Every network call from this skill goes to **exactly one of two hosts**:

- `api.vercel.com` — read inventory, audit logs, deploy history, team roster, tokens. Optionally (with `--execute` flag + user consent): empty Vercel env var values, revoke Vercel tokens.
- `api.supabase.com` — only if user opts in to pulling Supabase audit data via their own PAT. No automated rotations.

**No third-party endpoints. No telemetry. No auto-upload. No data leaves the user's machine except direct API calls to the two hosts above using the user's own tokens.**

Enforced in code: `scripts/_common.sh` has a hardcoded `ALLOWED_HOSTS` list. Every outbound request funnels through `safe_curl` which rejects any host outside that list. Grep it: `grep -A3 ALLOWED_HOSTS scripts/_common.sh`.

Every API call is logged to `~/incident-YYYYMMDD/audit.log` (timestamp, method, host, path — never bodies or tokens). Tail it during a run: `tail -f ~/incident-*/audit.log`.

## Scripts in this skill

- `preserve-evidence.sh` — **read-only**. Pulls Vercel audit log, deploys, teams, members, integrations, active tokens.
- `enumerate.sh` — **read-only**. Lists every project + env var key across every team, classified by upstream service. Values are never read.
- `scan-build-logs.sh` — **read-only**. Scans last N deploys for leaked-secret patterns (e.g., accidentally logged `console.log(process.env)` output).
- `empty-env-vars.sh` — **destructive, `--execute` required, dry-run default**. PATCHes every env var value on one project to `""`. Keeps keys so schema is intact. No upstream rotation.
- `generate-secrets.sh` — **local-only**. `openssl rand` for local auth secrets (`AUTH_SECRET`, `JWT_SECRET`). No network.

Gone from prior versions: `rotate-supabase.sh`. Removed to enforce user-does-rotation. If you need automated Supabase rotation, run their official API yourself after explicit review — we won't ship that path in this skill.

## The workflow

### Step 1 — Scope (one message, before anything destructive)

Ask the user in one message:

1. Which Vercel account(s) / team(s) are affected?
2. Confirmed breach or precautionary?
3. Do you have `VERCEL_TOKEN` available? (`~/.vercel/auth.json` or new at https://vercel.com/account/tokens — team-scoped, not account-wide)
4. Which service CLIs/tokens are authenticated locally?

Then sketch the plan and get go-ahead.

### Step 2 — Preserve evidence (read-only, no consent needed)

```bash
bash scripts/preserve-evidence.sh
```

Dumps Vercel audit logs, deploys, tokens, members, integrations to `~/incident-YYYYMMDD/`. Read-only.

Also ask the user to screenshot "API keys last used" in each upstream dashboard (Stripe, Supabase, OpenAI, Anthropic) before rotating. Flag as [MANUAL].

### Step 3 — Triage the audit log (you read it, not the user)

Load `~/incident-YYYYMMDD/audit-log-<team>.json` and flag anomalies:
- Unexpected `token.created` / `token.revoked` events
- Unfamiliar IPs or user agents
- `integration.created` / `integration.removed` outside business hours
- Unexpected `member.added` / `member.role-changed`
- Bursts of `env.listed` / `env.read` across many projects
- `deploy-hook.created` (persistent backdoor risk)
- DNS / domain changes

Present findings as **Suspicious / Confirm / Normal**. Have the user confirm which events are theirs.

Full triage checklist: `references/audit-triage.md`.

### Step 4 — Inventory the Vercel surface

```bash
bash scripts/enumerate.sh > ~/incident-YYYYMMDD/inventory.json
```

Lists every project + env-var *name* (never values), classified by upstream service.

Review with the user. Confirm scope. If surprising — unexpected projects, unknown services — pause and re-confirm.

### Step 5 — Guide upstream rotations (user does every one)

**The skill does NOT rotate upstream services.** For each service in the inventory, you:

1. Use `AskUserQuestion` to confirm intent to rotate that service now.
2. Show the direct dashboard link.
3. Tell them the exact clicks.
4. Ask them to confirm when done.
5. Offer to save the new value to `~/incident-YYYYMMDD/secrets.txt` (chmod 600) — never to chat.

Blast-radius order:

| Tier | Services | Why |
|---|---|---|
| 1 | AWS, GCP, Cloudflare, self-hosted DB roots | Full cloud access |
| 2 | Supabase, Neon, PlanetScale, Turso, Upstash, Mongo Atlas | User data |
| 3 | Clerk, Auth0, local auth secrets | Session hijack |
| 4 | Stripe, Paddle, Lemon Squeezy | Money |
| 5 | Resend, SendGrid, Postmark, Twilio | Phishing from legit sender |
| 6 | OpenAI, Anthropic, Google AI, Groq | $ burn |
| 7 | Sentry, PostHog | Lower impact |
| 8 | GitHub, GitLab OAuth + PATs | Source access |
| 9 | Slack/Discord webhooks | Impersonation |

Per-service guidance (dashboard links, click paths, grace periods) lives in `references/rotation-playbooks.md`. Read only the sections you need.

### Step 6 — Empty Vercel env vars (after upstream is rotated)

After the user has rotated upstream credentials, empty the Vercel-side values so builds can't deploy with stale references.

`AskUserQuestion` confirm the project + count (e.g., "empty 20 env vars across skillcreator-ai?"). On YES:

```bash
bash scripts/empty-env-vars.sh <project_id> <team_id>              # dry-run first (default)
bash scripts/empty-env-vars.sh <project_id> <team_id> --execute    # mutate after reviewing dry-run
```

Expected failures on integration-managed vars (Supabase integration, etc.) — disconnect those integrations instead (step 7).

### Step 7 — Disconnect compromised integrations

Dashboard-only: https://vercel.com/<team>/~/integrations → remove each. Reconnect in step 9 after upstream is clean.

### Step 8 — Rotate the Vercel account itself (user does this)

Via dashboard:
- https://vercel.com/account/tokens — delete all, create fresh team-scoped
- https://vercel.com/account/security — verify 2FA
- Review team members, remove suspicious
- Regenerate deploy hooks per project
- Review + reauthorize Vercel's GitHub/GitLab OAuth app

### Step 9 — Redeploy with fresh values + Sensitive flag

1. User collects new values (password manager, not chat).
2. **Enable team-wide policy first**: https://vercel.com/teams/<slug>/settings/security → "Enforce Sensitive Environment Variables". Do this BEFORE re-populating.
3. Set new values in Vercel (they'll be Sensitive by default thanks to policy).
4. Regenerate Git provider OAuth.
5. Scan build logs for leaked secrets:
   ```bash
   bash scripts/scan-build-logs.sh <project_id> <team_id>
   ```
6. Reconnect integrations disconnected in step 7.
7. `vercel --prod` or Git push.
8. Verify each service end-to-end.

### Step 10 — Deliver checklist

Assemble the `[DONE] / [MANUAL] / [BLOCKED]` checklist using `references/checklist-template.md`. Save to `~/incident-YYYYMMDD/checklist.md`.

### Step 11 — Offer to wipe secrets

Once the user confirms new values are in a password manager, `AskUserQuestion`: "incident response complete — wipe `~/incident-YYYYMMDD/secrets.txt` and `audit.log` now?"

## Operating principles

- **Evidence before destruction.** Always.
- **User rotates upstream.** Skill never calls a third-party rotation API.
- **Two-step consent for Vercel mutations.** `AskUserQuestion` with scope + effect, then again at execute.
- **Dry-run default.** `--execute` required for any mutation.
- **Read logs yourself.** You parse audit JSON faster than the user clicks through rows.
- **Never paste new secrets into chat.** Save to local file in the incident folder.
- **Empty env vars, don't delete them.** Deleting loses keys; empty values fail builds loudly — correct for incident.
- **Rotating auth secrets invalidates sessions.** Warn before pulling that trigger.
- **Don't trust "I think I rotated that."** Verify by listing keys again after each rotation.
- **When uncertain, prefer dashboard.** Faster, visible, and no automation risk.
- **The checklist is the deliverable.** If one thing is right, make it that.

## When things go sideways

- **`VERCEL_TOKEN` missing** — ask the user to generate a team-scoped one at https://vercel.com/account/tokens. Don't proceed without it.
- **A team's API call 403s** — viewer-role token. Skip and note `[BLOCKED] team <slug> — token lacks access`.
- **Supabase project paused** — script handles it. Note in checklist.
- **User balks at session invalidation** — don't rotate auth secrets without explicit green-light.
- **User wants to stop halfway** — fine. Give them the partial checklist with `[INCOMPLETE]` section.
- **`jq` not installed** — use your system package manager to install it. The scripts hard-depend on jq for safe JSON parsing.
