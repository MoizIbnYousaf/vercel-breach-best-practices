# vercel-breach-best-practices

> A Claude Code skill for Vercel incident response. **Advisor, not autonomous rotator.** You rotate credentials yourself in your own dashboards; the skill preserves evidence, enumerates your Vercel surface, reads the Activity Log for anomalies, and hands you a ranked `[DONE]/[MANUAL]/[BLOCKED]` checklist with direct links.

Built in response to the [April 2026 Vercel security bulletin](https://vercel.com/kb/bulletin/vercel-april-2026-security-incident). Works for any Vercel compromise: platform breach, leaked `VERCEL_TOKEN`, compromised integration, suspected env-var exposure, post-incident hardening.

**TL;DR** — install, say "vercel got breached", answer four scoping questions, get a complete rotation checklist with dashboard links by the end of the session. No credentials leave your machine; no autonomous upstream rotation; every network call funneled through a hardcoded two-host allowlist.

---

## Why you can trust this skill during an incident

Incident response is when you're *least* equipped to audit unfamiliar code. This skill takes that seriously:

- **No autonomous upstream rotation.** Zero scripts call Supabase / Clerk / Stripe / etc. rotation APIs. You rotate in the provider dashboard; the skill gives you the link and a local file to save the new value.
- **Hardcoded two-host allowlist.** Every network call funnels through `safe_curl` in `scripts/_common.sh`, which rejects anything that isn't `api.vercel.com` or `api.supabase.com`. One grep to verify: `grep -A3 ALLOWED_HOSTS scripts/_common.sh`.
- **Audit log of every API call** at `~/incident-YYYYMMDD/audit.log` (timestamp, method, host, path — no bodies, no tokens). Tail it during a run.
- **Dry-run default on destructive ops.** The one mutation the skill can perform (emptying Vercel env var values) requires `--execute` AND an explicit `AskUserQuestion` confirmation.
- **Auditable in 10 minutes.** Six scripts, ~600 lines of bash, no `eval`, no dynamic shell, no post-install hooks, no telemetry.

Full threat model + 30-second verification recipe: [`THREAT_MODEL.md`](THREAT_MODEL.md).

---

## The deliverable

What you get at the end, saved to `~/incident-YYYYMMDD/checklist.md`:

```markdown
# SkillCreator Vercel Breach Response — 2026-04-19

## [DONE] — automated this session
- [x] Evidence preserved (audit log, deploys, tokens, members, integrations)
- [x] Activity Log triaged — 3 suspicious events flagged, user confirmed all were theirs
- [x] Inventory: 20 env vars across skillcreator-ai project
- [x] Vercel env var values emptied (20/20)
- [x] Build logs scanned — no leaked secrets detected

## [MANUAL] — dashboard actions, ordered by urgency
1. Clerk → rotate CLERK_SECRET_KEY — https://dashboard.clerk.com/...
2. Anthropic → rotate ANTHROPIC_API_KEY — https://console.anthropic.com/...
3. Upstash → rotate UPSTASH_REDIS_REST_TOKEN — https://console.upstash.com/...
4. Stripe → roll secret key + webhook signing secrets — https://dashboard.stripe.com/...
5. Enable "Enforce Sensitive Environment Variables" — https://vercel.com/teams/.../security
6. Re-populate fresh values in Vercel (Sensitive toggle ON), redeploy, verify

## [BLOCKED] — waiting on another condition
- Supabase rotation — project paused. MUST rotate JWT + DB password BEFORE resuming.
```

Every `[MANUAL]` item has a direct dashboard link. Every `[BLOCKED]` item has a specific unblock condition. Nothing is hand-wavy.

---

## How it works, in order

1. **Scope the incident** — one set of questions: which team, confirmed or precautionary, which CLIs you have authed.
2. **Preserve evidence** — dumps Vercel Activity Log, deploys, tokens, team, integrations to `~/incident-YYYYMMDD/` before anything rotates. Some providers stop surfacing old-key activity the moment you rotate — this is your only shot at the trail.
3. **Triage the Activity Log** — Claude reads the log via `vercel activity` CLI and flags anomalies by real event name: `env-variable-read` bursts, `deploy-hook-created`, `oauth-app-token-created`, `project-automation-bypass`, and so on. Faster than you clicking through rows.
4. **Inventory your Vercel surface** — every project, every env-var name, classified by upstream service. Names only, never values.
5. **Optional exposure interview** — covers what the API can't see: historical env vars, out-of-band copies (Slack, git, screenshots), Vercel-adjacent exposures (deploy hooks, Git OAuth, past members). Opt-in, never blocks containment.
6. **Guide upstream rotation** — for each service: blast radius, rotation cost, urgency, ready state. Dashboard link, click path, local file to save the new value. You do the clicking.
7. **Empty Vercel env var values** — the one destructive op, behind two-step consent and a dry-run default. Keys preserved so the schema stays intact.
8. **Disconnect compromised integrations** — dashboard-only.
9. **Guide Vercel account hardening** — fresh tokens (create the new one first, *then* revoke old), 2FA, deploy hooks, GitHub/GitLab OAuth.
10. **Scan build logs** — greps last 20 deploys for `console.log(process.env)` accidents before redeploying.
11. **Redeploy with Sensitive flag** — enables team-wide policy first, then sets fresh values.
12. **Deliver the checklist** — `[DONE]/[MANUAL]/[BLOCKED]` with direct links.
13. **Offer to wipe local secrets** — opt-in, no default. You choose.

---

## Install

```bash
git clone https://github.com/MoizIbnYousaf/vercel-breach-best-practices.git \
  ~/.claude/skills/vercel-breach-best-practices

chmod +x ~/.claude/skills/vercel-breach-best-practices/scripts/*.sh
```

Pin to a specific version:

```bash
cd ~/.claude/skills/vercel-breach-best-practices
git checkout v2.3     # see tags: https://github.com/MoizIbnYousaf/vercel-breach-best-practices/tags
```

Claude Code picks up the skill on next launch.

## Run

Auth into Vercel (either works):

```bash
vercel login
# or
export VERCEL_TOKEN=vca_...              # team-scoped, generated at vercel.com/account/tokens
```

Open Claude Code and say what's going on: *"vercel got breached, help me rotate everything"* triggers the skill. No slash command needed.

## Requirements

Hard: `curl`, `jq`, `openssl`, and a `VERCEL_TOKEN`. First three are preinstalled on macOS.

Recommended: the `vercel` CLI. If present, `preserve-evidence.sh` also pulls a 30-day `vercel activity` dump and Step 3 uses the CLI for targeted triage (`vercel activity --type env-variable-read --since 7d`).

Everything else (`aws`, `gh`, `stripe`, etc.) is opportunistic. The skill uses what's there, flags what it can't as `[MANUAL]`.

---

## Ordering — why it matters

The sequence *is* the defense. Reversing any step makes the response meaningfully worse.

- **Preserve evidence before anything mutates.** Rotate first and you lose the trail. Non-negotiable.
- **Rotate upstream before emptying Vercel env vars.** Emptying Vercel doesn't invalidate leaked keys — the upstream service still accepts the old one. Upstream rotation kills the leak. Emptying Vercel is hygiene that happens after.
- **Highest blast radius first.** AWS and Stripe before analytics and Sentry.
- **Create the new Vercel token before revoking old ones.** Deleting all tokens mid-flight can break the in-flight response itself.

---

## What's automated vs. what's your clicks

**Automated observation (read-only):** evidence preservation, env-var enumeration, classification, Activity Log triage, build-log secret scanning.

**Automated generation (local-only):** fresh local auth secrets (`AUTH_SECRET`, `JWT_SECRET`) to a `chmod 600` file. Nothing leaves the machine.

**Automated mutation (destructive, two-step consent):** Vercel env-var emptying — the *only* mutation the skill can perform.

**Your dashboard clicks:** every upstream rotation (Supabase, Clerk, Stripe, Upstash, Anthropic, OpenAI, SendGrid, Twilio, etc.), Vercel token revocation, deploy-hook regeneration, Sensitive-env-var policy toggle, integration disconnect/reconnect.

The split is deliberate. Observation gets scripted so it's fast. Destructive actions get surfaced as options so you choose. Dashboard beats API every time during an incident because the action is visible and reversible.

---

## Layout

```
vercel-breach-best-practices/
├── SKILL.md                              # the skill Claude reads
├── THREAT_MODEL.md                       # defends-against + 30s verify recipe
├── CHANGELOG.md                          # v1 → current
├── README.md
├── LICENSE
├── scripts/
│   ├── _common.sh                        # host allowlist + safe_curl + audit log
│   ├── preserve-evidence.sh              # read-only: Activity Log, deploys, tokens
│   ├── enumerate.sh                      # read-only: env vars, classified
│   ├── empty-env-vars.sh                 # values → "", two-step consent
│   ├── generate-secrets.sh               # local AUTH_SECRET / JWT_SECRET
│   └── scan-build-logs.sh                # read-only: grep deploys for leaks
└── references/
    ├── rotation-playbooks.md             # per-service dashboard recipes (tier 1–9)
    ├── exposure-interview.md             # Vercel-scoped supplement to inventory
    ├── audit-triage.md                   # real Activity Log event names + jq/CLI queries
    ├── classifier.md                     # env-var-name → service patterns
    └── checklist-template.md             # final deliverable format
```

---

## FAQ

**Does it rotate my Supabase / Clerk / Stripe keys?** No. v1 did; deleted in v2. You rotate in the upstream dashboard.

**Safe on production?** Yes. The only destructive op is emptying Vercel env var values (keys preserved, no schema loss), behind two-step consent + dry-run default. Everything else is read-only.

**Secrets leaked into chat?** No. New values go to `~/incident-YYYYMMDD/secrets.txt` (`chmod 600`). Chat sees destinations, never values.

**Personal Vercel account, no teams?** Handled. `enumerate.sh` falls through to personal scope.

**Token 403s on some teams?** Noted as `[BLOCKED] team <slug>: token lacks access`. The others continue.

**Stop halfway?** Fine. Partial checklist with `[INCOMPLETE]` section.

**Why not one giant script?** Incident response is conversational. You need to pause, skip a tier, ask questions mid-flight. Claude orchestrates; scripts handle the deterministic observations.

**How do I verify the skill hasn't been tampered with?** Three commands in [`THREAT_MODEL.md`](THREAT_MODEL.md). Under a minute.

---

## Contributing

PRs welcome. Three high-value additions:

- **More service playbooks** in `references/rotation-playbooks.md`. Dashboard path, URL, grace-period notes.
- **Classifier patterns** for env-var names the current regex misses. Keep `NEXT_PUBLIC_*` before the `*_API_KEY` catch-all.
- **Audit-log heuristics** in `references/audit-triage.md`. More patterns surfaced by name = less squinting for the user.

Keep `SKILL.md` under 500 lines. **Never add a script that rotates upstream credentials** — that's the one architectural rule.

Security disclosures: see [`SECURITY.md`](SECURITY.md).

---

## License

MIT. See [LICENSE](LICENSE).

## Credits

- [April 2026 Vercel security bulletin](https://vercel.com/kb/bulletin/vercel-april-2026-security-incident).
- Vercel's [Activity Log docs](https://vercel.com/docs/observability/activity-log) and [`vercel activity` CLI](https://vercel.com/docs/cli) — the high-signal event names came straight from there.
- [Upstash's post-incident rotation guide](https://upstash.com/blog/rotate-upstash-secrets-after-vercel-incident).
- Vercel's [`vercel-cli-with-tokens`](https://vercel.com/docs/claude-code) skill for the token-discovery pattern.
- Anthropic's [Claude Code skill-creator](https://docs.claude.com/claude-code/skills).
