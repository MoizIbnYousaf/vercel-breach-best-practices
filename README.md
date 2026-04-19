# vercel-breach-best-practices

A Claude Code skill for Vercel incident response. Not an autonomous rotator — an advisor. You rotate credentials yourself in your own dashboards; the skill preserves evidence, enumerates your Vercel surface, reads the audit log for anomalies, and hands you a ranked `[DONE]/[MANUAL]/[BLOCKED]` checklist with direct links.

Built in response to the [April 2026 Vercel security bulletin](https://vercel.com/kb/bulletin/vercel-april-2026-security-incident). Works for any Vercel compromise: platform breach, leaked `VERCEL_TOKEN`, compromised integration, suspected env-var exposure, post-incident hardening.

## Why it's not autonomous

Earlier versions shipped autonomous rotation scripts. We deleted them.

During a breach is the worst time to trust an unaudited script with a production credential. Dashboard clicks are visible, reversible, easy to reason about. API automation is fast but opaque, and "fast" isn't worth much when you're debugging why prod just broke because a skill rotated something in the wrong order.

The trade: a few more clicks for you. The win: the skill is trivial to audit (7 scripts, ~600 lines), has a two-host network allowlist hardcoded, and literally cannot mutate upstream state even if it wanted to.

## What it does, in order

1. **Scopes the incident.** Which team, confirmed or precautionary, which CLIs you already have authed.
2. **Preserves evidence.** Dumps Vercel audit logs, deploys, tokens, members, integrations to `~/incident-YYYYMMDD/` before anything rotates. Some providers stop surfacing old-key activity the moment you rotate — this is your only shot at the trail.
3. **AI-triages the audit log.** Claude reads the 200 most-recent events and surfaces anomalies a human would skim past: token creation off-hours, env-var listing bursts across projects, unfamiliar IPs, new integrations, deploy-hook creation.
4. **Inventories your Vercel surface.** Every project, every env-var name, classified by upstream service. Names only, never values.
5. **Optional exposure interview.** Covers the three things the Vercel API cannot see: historical env vars (deleted during the window), out-of-band copies (Slack, git, screenshots), Vercel-adjacent exposures (deploy hooks, Git OAuth, past team members). Opt-in, never blocks containment.
6. **Guides upstream rotation.** For each service: blast radius, rotation cost, urgency, ready state. Dashboard link, click path, local file to save the new value. You do the clicking.
7. **Empties Vercel env var values.** The one destructive op the skill can perform, behind two-step consent and a dry-run default. Keys preserved so the schema stays intact.
8. **Disconnects compromised integrations.** Dashboard-only.
9. **Guides Vercel account hardening.** Fresh tokens (new one first, then revoke old — never the other way around), 2FA, deploy hooks, GitHub/GitLab OAuth.
10. **Scans build logs.** Greps last 20 deploys for `console.log(process.env)` accidents before redeploying.
11. **Redeploys with Sensitive flag.** Enables team-wide policy first, then sets fresh values.
12. **Delivers the checklist.** `[DONE]/[MANUAL]/[BLOCKED]` with direct links.
13. **Offers to wipe local secrets.** Opt-in, no default. You choose.

## Safety rails

- **Host allowlist.** Every network call goes through `safe_curl` in `scripts/_common.sh`. Anything not `api.vercel.com` or `api.supabase.com` gets rejected. One line to audit: `grep -A3 ALLOWED_HOSTS scripts/_common.sh`.
- **Audit log.** Every API call appends to `~/incident-YYYYMMDD/audit.log` with timestamp, method, host, path. No bodies, no tokens. Tail it during a run.
- **Dry-run default.** Destructive scripts print the plan and exit unless you pass `--execute`.
- **No upstream rotation.** The skill never calls Supabase / Clerk / Stripe / etc. rotation APIs. Not now, not ever.
- **Tokens via env var only.** Never CLI flags (which leak to shell history).
- **No post-install hooks.** Plain bash + markdown. No `eval`, no dynamic shell, no telemetry.
- **Two-step consent for Vercel mutations.** `AskUserQuestion` with scope + effect, then `--execute`.

Full threat model + 30-second verification recipe: [`THREAT_MODEL.md`](THREAT_MODEL.md).

## Install

```bash
git clone https://github.com/MoizIbnYousaf/vercel-breach-best-practices.git \
  ~/.claude/skills/vercel-breach-best-practices

chmod +x ~/.claude/skills/vercel-breach-best-practices/scripts/*.sh
```

Claude Code picks it up on next launch.

## Run

Get authed into Vercel (either works):

```bash
vercel login
# or
export VERCEL_TOKEN=vca_...              # team-scoped, from vercel.com/account/tokens
```

Then open Claude Code and say what's going on: *"vercel got breached, help me rotate everything"* triggers the skill. No slash command required.

## Requirements

Hard: `curl`, `jq`, `openssl`, and a `VERCEL_TOKEN`. First three are preinstalled on macOS.

Everything else (`aws`, `gh`, `stripe`, whatever) is opportunistic. The skill uses what it finds, flags what it can't as `[MANUAL]` in the checklist.

## Layout

```
vercel-breach-best-practices/
├── SKILL.md                              # the skill Claude reads
├── THREAT_MODEL.md                       # defends-against + verify recipe
├── CHANGELOG.md
├── README.md
├── LICENSE
├── scripts/
│   ├── _common.sh                        # host allowlist + safe_curl + audit log
│   ├── preserve-evidence.sh              # read-only: audit log, deploys, tokens
│   ├── enumerate.sh                      # read-only: env vars, classified
│   ├── empty-env-vars.sh                 # values → "", two-step consent
│   ├── generate-secrets.sh               # local AUTH_SECRET / JWT_SECRET
│   └── scan-build-logs.sh                # read-only: grep deploys for leaks
└── references/
    ├── rotation-playbooks.md             # per-service dashboard recipes
    ├── exposure-interview.md             # Vercel-scoped supplement to inventory
    ├── classifier.md                     # env-var-name → service patterns
    ├── audit-triage.md                   # what to flag in a Vercel audit log
    └── checklist-template.md             # final deliverable format
```

## Why the ordering matters

The ordering *is* the defense. Reversing any step makes the response meaningfully worse.

**Preserve evidence before anything mutates.** Rotate first and you lose the trail. Non-negotiable.

**Rotate upstream before emptying Vercel env vars.** Emptying Vercel doesn't invalidate leaked keys — the upstream service still accepts the old one. Upstream rotation is what kills the leak. Emptying Vercel is hygiene that happens after.

**Highest blast radius first.** AWS and Stripe before analytics. Cloud takeover beats "attacker changed my alert thresholds."

**Create the new Vercel token before revoking old ones.** Deleting all tokens mid-flight can break the in-flight response itself.

## Questions

**Does it rotate my Supabase / Clerk / Stripe keys?** No. v1 did; we deleted that in v2. You rotate in the upstream dashboard; the skill gives you the link and a place to save the new value.

**Safe on production?** Yes. The only destructive operation is emptying Vercel env var values (keys preserved, no schema loss), behind two-step consent and a dry-run default. Everything else is read-only.

**Does it leak secrets into chat?** No. New secrets go to `~/incident-YYYYMMDD/secrets.txt` with `chmod 600`. Chat sees destinations, never values.

**Personal Vercel account, no teams?** Handled. `enumerate.sh` falls through to personal scope.

**Token 403s on some teams?** Noted in the checklist as `[BLOCKED] team <slug>: token lacks access`. The others continue.

**Want to stop halfway?** Fine. Partial checklist with `[INCOMPLETE]`.

**Why not one giant script?** Incident response is conversational, not batch. You need to pause, skip, redirect, ask questions mid-flight. Claude orchestrates the conversation; scripts handle the deterministic observations.

## Contributing

PRs welcome. Three high-value additions:

- **More service playbooks** in `references/rotation-playbooks.md`. Dashboard path, URL, grace-period notes.
- **Classifier patterns** for env-var names the current regex misses. Add to `scripts/enumerate.sh`'s `classify()` and to `references/classifier.md`. Keep `NEXT_PUBLIC_*` before the `*_API_KEY` catch-all.
- **Audit-log heuristics** in `references/audit-triage.md`. More patterns the AI can flag = less JSON-squinting for the user.

Keep `SKILL.md` under 500 lines. Never add a script that rotates upstream — that's the one architectural rule.

## License

MIT. See [LICENSE](LICENSE).

## Credits

- The [April 2026 Vercel security bulletin](https://vercel.com/kb/bulletin/vercel-april-2026-security-incident).
- [Upstash's post-incident rotation guide](https://upstash.com/blog/rotate-upstash-secrets-after-vercel-incident), linked in the Upstash playbook.
- Vercel's [`vercel-cli-with-tokens`](https://vercel.com/docs/claude-code) skill for the token-discovery pattern.
- Anthropic's [Claude Code skill-creator](https://docs.claude.com/claude-code/skills) for the SKILL.md structure.
