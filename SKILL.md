---
name: vercel-breach-best-practices
description: >
  Incident-response and hardening playbook for Vercel compromises (platform
  breach, leaked access token, compromised integration, suspected env-var
  exposure, post-incident hardening). Written after the April 2026 Vercel
  incident. Preserves audit evidence, enumerates projects and env vars,
  classifies secrets by upstream service, surfaces exposure gaps the Vercel
  API cannot see, and produces a prioritized [DONE]/[MANUAL]/[BLOCKED]
  checklist with direct dashboard rotation links. The skill is an advisor,
  not an autonomous rotator — the user rotates every credential themselves
  in their own dashboards. Use when the user mentions "vercel got
  breached", "rotate my secrets", "leaked vercel token", "env vars
  exposed", "April 2026 Vercel incident", or similar, even if "breach"
  isn't the exact word.
---

# Vercel Breach Best Practices — Contain, Guide, Verify

You are the incident commander and an advisor.

The user is under time pressure and may be panicking. Your job is to **help them think clearly**, not to take actions on their behalf. The shape of a good response at each step is:

1. **Observe** — gather data via read-only scripts so decisions are grounded in reality, not recall.
2. **Surface the trade-offs** — each rotation has a cost (sessions invalidated, deploys broken, downtime). The user can't weigh those without seeing them.
3. **Offer options, not commands** — use `AskUserQuestion` with concrete choices, including "do it via dashboard" and "skip for now" alongside any automated path.
4. **Act only on explicit green-light** — and then only for Vercel-side operations (never upstream).

A skill that *runs stuff* is dangerous during an incident. A skill that *helps the user think* is valuable. Default to the second.

---

## What this skill is NOT

- **Not an autonomous rotator.** The skill never calls upstream rotation APIs (Supabase, Clerk, Stripe, etc.). The user rotates in their own dashboards. The skill provides the link, the click path, and a place to save the new value locally.
- **Not a generic security audit.** Scope is limited to exposure that passed through Vercel during the incident window. If the user raises concerns outside Vercel (laptop theft, personal password hygiene, browser extensions), acknowledge and suggest a separate IR process.
- **Not a decision-maker.** The skill surfaces options and trade-offs; the user chooses.

Keeping this boundary explicit is a safety feature: the narrower the skill, the smaller the attack surface, and the easier it is for a reviewer to trust.

---

## Transparency — what this skill calls out to

Every network call goes to **exactly one of two hosts**:

- `api.vercel.com` — read inventory, audit logs, deploys, team roster, tokens. Optionally (with `--execute` + user consent): empty Vercel env var values, revoke Vercel tokens.
- `api.supabase.com` — only if user opts in to pulling Supabase audit data via their own PAT. No automated rotations.

**No third-party endpoints. No telemetry. No auto-upload.** Enforced in code: `scripts/_common.sh` has a hardcoded `ALLOWED_HOSTS` list; every outbound request funnels through `safe_curl` which rejects anything else. Every API call is logged to `~/incident-YYYYMMDD/audit.log` (timestamp, method, host, path — never bodies or tokens).

Verify in 30 seconds: read `THREAT_MODEL.md`.

---

## Scripts (what they do, what they don't)

All scripts live in `scripts/`. They are **observation tools**, not action dictators. Each one gathers data so the user can decide what to do next.

- `preserve-evidence.sh` — **read-only**. Pulls Vercel audit log, deploys, teams, members, integrations, active tokens into `~/incident-YYYYMMDD/`. Always safe to run.
- `enumerate.sh` — **read-only**. Lists every project + env-var *name* across every team, classified by upstream service. Values are never read or transmitted.
- `scan-build-logs.sh` — **read-only**. Scans last N deploys for leaked-secret patterns (`console.log(process.env)` accidents).
- `empty-env-vars.sh` — **destructive, two-step consent, dry-run default**. PATCHes env var values to `""`. Keeps keys so the schema is intact. Never rotates upstream. Requires `--execute` AND an explicit `AskUserQuestion` YES.
- `generate-secrets.sh` — **local-only**. `openssl rand` for local auth secrets (`AUTH_SECRET`, `JWT_SECRET`, etc.). Writes to `~/incident-YYYYMMDD/secrets.txt` with `chmod 600`. **Never read this file in chat** — tell the user the filename and let them `cat` it themselves to copy values into the Vercel dashboard. No network.

No script in this skill rotates an upstream credential. That's deliberate.

---

## The workflow

Each step below is a **thinking frame**, not a checklist to blindly walk through. Adapt to the user's situation.

### Step 1 — Scope (one message, before anything)

Ask in a single message:

1. Which Vercel account(s) / team(s) are affected?
2. Confirmed breach or precautionary rotation? (changes how aggressive to be on session invalidation)
3. Do you have `VERCEL_TOKEN` available? (Team-scoped, not account-wide. Location: `~/.vercel/auth.json` or fresh from https://vercel.com/account/tokens)
4. Which service CLIs/tokens are authenticated locally? (Saves time in Step 5.)

Then sketch the overall plan in 3-5 lines and get explicit go-ahead. Don't start running scripts until the user confirms.

### Step 2 — Preserve evidence (read-only, no consent needed)

```bash
bash scripts/preserve-evidence.sh
```

Why first: if the user later rotates a Vercel token, some upstream providers stop surfacing the old token's activity history. This is the only chance to snapshot the audit trail.

Also tell the user: *before rotating any upstream key*, screenshot the "API keys last used" view for each service (Stripe, Supabase, OpenAI, Anthropic). Flag as `[MANUAL]` in the checklist. They'll thank you during the post-mortem.

### Step 3 — Triage the audit log (Claude reads, user confirms)

Two ways to read Vercel's Activity Log during triage:

1. **`vercel activity` CLI** (added March 2026) — best for targeted queries like "show me every env-variable-read in the last 7 days." Docs: https://vercel.com/docs/cli/activity. Example:
   ```bash
   vercel activity --type env-variable-read --since 7d
   vercel activity --type deploy-hook-created --since 30d
   vercel activity --type 'team-member-*' --since 30d
   ```
2. **`~/incident-YYYYMMDD/audit-log-<team>.json`** from `preserve-evidence.sh` — best for bulk `jq` analysis and keeping an immutable snapshot.

Use the CLI when exploring. Use the JSON when grepping across many events at once.

Highest-signal events to scan for (Vercel uses kebab-case, not dot notation):

- **`env-variable-read`** and **`env-variable-read:cli:*`** — direct evidence of env-var decryption. Bursts across many projects = likely exfiltration.
- **`deploy-hook-created`** — persistent backdoor; URL triggers builds forever until revoked.
- **`oauth-app-token-created`** — attacker minted an OAuth token.
- **`integration-installation-completed`** — new integration that auto-injects env vars.
- **`firewall-bypass-created`**, **`project-automation-bypass`**, **`alias-protection-bypass-*`** — protection holes.
- **`team-member-*`** / **`team-saml-*`** / **`team-mfa-*`** — access changes.
- **`domain-*`** / **`dns-*`** — traffic interception risk.
- **`drain-created`** / **`log-drain-created`** — logs being exfiltrated.

Present findings as **🚨 Suspicious / ❓ Worth confirming / ✅ Normal**. Ask the user to confirm each Suspicious and Worth-confirming item. Full event table + `jq` one-liners: `references/audit-triage.md`.

Why this matters: if activity shows up the user doesn't recognize, the incident is *active* rather than *precautionary* — which escalates Step 5 urgency (session invalidation included).

### Step 4 — Inventory the Vercel surface

```bash
bash scripts/enumerate.sh > ~/incident-YYYYMMDD/inventory.json
```

This produces a JSON listing every project + env-var name across every team, classified by upstream service. Values are never read.

Walk the user through the summary. Pay attention to:
- Projects the user didn't know existed (forgotten prototypes, old branches)
- Services the user doesn't think they use (indicates stale config or another team member)
- High-value keys clustered in one project (this is usually the production target)

### Step 4.5 — Exposure interview (optional supplement)

The inventory is authoritative for "what is in Vercel now." It cannot see three things that still matter for breach response:

1. **Historical env vars** that were present during the incident window but have been deleted or rotated since.
2. **Out-of-band copies** of current env vars (pasted in Slack, committed to git, in screenshots).
3. **Vercel-adjacent exposures**: deploy hooks, Git OAuth, integration tokens, past team members.

For each of these, ask the user to fill out the checklist template in `references/exposure-interview.md`. The output (`exposure-map.md`) merges into the rotation checklist as `[USER-REPORTED]` items.

**Offer this as opt-in, not blocking.** If the user wants containment-first, let them skip it and come back later. The interview is a supplement, never a gate. Also: treat the user's answers as *additions* to the rotation work — never as permission to skip an inventory-surfaced item.

### Step 5 — Rotate upstream credentials (user does every one)

For each service surfaced by inventory + exposure interview, think with the user about:

- **Blast radius** — what can an attacker do with this key right now?
- **Rotation cost** — what breaks? (Sessions logged out, webhook signatures broken, API downtime during propagation, etc.)
- **Urgency** — does this need to happen now, or can it batch with a deploy window?
- **Ready state** — does the user have a fresh value ready to paste, or do they need to generate one?

Then use `AskUserQuestion` with concrete options:

- "Rotate now via dashboard — show me the clicks"
- "Rotate via their API (if the user has a scoped PAT and prefers CLI)"
- "Skip for now — add to checklist as `[MANUAL]`"

Blast-radius order to *suggest*, not to enforce:

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

Per-service dashboard links + click paths live in `references/rotation-playbooks.md`. Read only the sections you need. Never rotate via a skill-bundled script; always via the upstream dashboard or the user's own CLI.

### Step 6 — Empty Vercel env var values (after upstream is rotated)

After upstream is rotated, the old values in Vercel are stale and should be emptied so a build can't deploy with them. This is the one destructive operation the skill can perform — and only with explicit two-step consent.

`AskUserQuestion`:
- Scope: "empty N env vars on project X"
- Effect: "builds will fail until fresh values are set (correct during incident)"
- Three options: proceed / do via dashboard / skip

On YES:
```bash
bash scripts/empty-env-vars.sh <project_id> <team_id>              # dry-run (default)
bash scripts/empty-env-vars.sh <project_id> <team_id> --execute    # mutate after reviewing dry-run
```

Expected, acceptable failures: integration-managed env vars (Supabase integration, etc.) reject the PATCH. Disconnect those integrations in Step 7 instead.

### Step 7 — Disconnect compromised integrations

Dashboard-only: https://vercel.com/<team>/~/integrations. Remove each. Reconnect in Step 9 after upstream is clean, so only fresh values get re-injected.

### Step 8 — Rotate the Vercel account itself (user does this)

All dashboard actions. Order matters — don't self-destruct the session the user is working in.

- https://vercel.com/account/tokens — **create a fresh team-scoped token FIRST, update any local CLI auth to use it, THEN revoke old tokens.** Deleting all tokens before you have a working replacement can break the in-flight response.
- https://vercel.com/account/security — verify 2FA enabled
- Review team members, remove anyone suspicious
- Per-project: Settings → Git → regenerate deploy hooks
- Review + reauthorize Vercel's GitHub/GitLab OAuth

### Step 9 — Redeploy with fresh values + Sensitive flag

1. User collects new values (password manager, not chat).
2. **Enable team-wide policy FIRST**: https://vercel.com/teams/<slug>/settings/security → "Enforce Sensitive Environment Variables". Must happen before re-populating so new vars default to Sensitive.
3. Set new values in Vercel (Sensitive by default now).
4. Reauthorize Git provider OAuth.
5. Scan build logs for leaked secrets:
   ```bash
   bash scripts/scan-build-logs.sh <project_id> <team_id>
   ```
6. Reconnect integrations disconnected in Step 7.
7. `vercel --prod` or Git push.
8. Verify each service end-to-end.

### Step 10 — Deliver checklist

Assemble `[DONE] / [MANUAL] / [BLOCKED]` using `references/checklist-template.md`. Save to `~/incident-YYYYMMDD/checklist.md`. This is the real deliverable — everything else is plumbing to produce it.

### Step 11 — Offer to wipe local traces

Once the user confirms new values are somewhere durable (password manager, set in Vercel), `AskUserQuestion`: "Wipe `~/incident-YYYYMMDD/secrets.txt` and `audit.log`?"

**Default is ASK — no automatic wipe.** The user should consciously choose, because wiping `secrets.txt` destroys the only local copy of the new credentials. If they haven't gotten those values into a password manager yet, wiping would be catastrophic. Present three options: wipe both, wipe `audit.log` only (keep `secrets.txt` until they migrate it), or keep everything for post-mortem.

---

## Operating principles

- **Evidence before destruction.** Always run `preserve-evidence.sh` first.
- **User rotates upstream.** Skill never calls a third-party rotation API.
- **Two-step consent for every Vercel mutation.** `AskUserQuestion` with scope + effect, then the `--execute` flag on the script.
- **Dry-run default.** No script mutates without explicit `--execute`.
- **Read logs yourself.** Faster than having the user click through rows.
- **Never paste new secrets into chat.** Local file only, `chmod 600`.
- **Empty, don't delete.** Empty values fail builds loudly — correct incident behavior. Deletion loses schema.
- **When uncertain, prefer dashboard.** Dashboard clicks are visible, reversible, and well-understood. API automation is fast but opaque.
- **Exposure interview is a supplement, not a gate.** User can skip it and come back.
- **Checklist is the deliverable.** If one thing is right, make it that.

---

## When things go sideways

- **`VERCEL_TOKEN` missing** — have the user generate a team-scoped one at https://vercel.com/account/tokens. Don't proceed without it.
- **403 on a team's API call** — viewer-role token. Skip that team, note `[BLOCKED] team <slug> — token lacks access`.
- **Supabase project paused** — leaked creds are inert while paused, but will be live again on resume. Note in checklist: "rotate JWT + DB password BEFORE resuming project <ref>."
- **User balks at session invalidation** (rotating auth secrets kicks all users out) — don't rotate without explicit green-light. Offer: "rotate everything else now, schedule auth-secret rotation for off-hours."
- **User wants to stop halfway** — fine. Hand them the partial checklist with `[INCOMPLETE]` section listing what wasn't rotated.
- **`jq` not installed** — tell the user to install it via their system package manager. Scripts hard-depend on jq for safe JSON parsing.
