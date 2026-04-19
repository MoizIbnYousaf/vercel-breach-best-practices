# vercel-breach-best-practices

A Claude Code skill that runs the Vercel incident-response playbook for you. Point it at a Vercel account, it enumerates every project and env var, reads the audit log for anomalies, rotates upstream credentials in blast-radius order, empties the Vercel env vars, and hands you a final checklist of what's done vs. what needs your hands.

Built the day the [April 2026 Vercel security bulletin](https://vercel.com/knowledge/vercel-april-2026-security-incident) landed. Works for any Vercel compromise: platform breach, leaked `VERCEL_TOKEN`, compromised integration, suspected env-var exposure, or just general post-incident hardening.

Vercel's own bulletin said: review your activity log, rotate environment variables, use the sensitive-environment-variables feature. This skill does all three for you, and then keeps going across every upstream service your Vercel projects ever touched.

---

## The one-line pitch

Your Vercel account might be compromised. You probably have 40+ env vars across 6 projects touching AWS, Stripe, Supabase, OpenAI, and a dozen others. Rotating all of them by hand is an afternoon of clicking through dashboards in the correct order, remembering what blast radius looks like, and keeping a clean log. This skill does the mechanical 80% and gives you a ranked checklist for the rest.

## What it does, in order

**1. Scopes the incident.** One set of questions: which team, confirmed or precautionary, which CLIs are authed locally. No more.

**2. Preserves evidence.** Dumps Vercel audit logs, deployment history, team roster, and active tokens to `~/incident-YYYY-MM-DD/` before anything rotates. The attacker's trail is irreplaceable. Keys rotate once; the logs that show what the keys were used for only exist now.

**3. AI-triages the audit log.** Claude reads the 200 most-recent events, groups by source IP, clusters by event type, and surfaces anomalies: tokens created off-hours, env-var listing bursts across many projects, new integrations, deploy-hook creation. Faster than clicking through the dashboard, and doesn't miss the quiet events humans skim past.

**4. Inventories the surface.** `enumerate.sh` walks every team, every project, every env var. Names only, never values. Classifies each var by upstream service using 38 name patterns so rotation can be prioritized by blast radius.

**5. Rotates upstream.** Highest blast radius first: AWS, Cloudflare, GCP, then databases (Supabase, Neon, PlanetScale, Turso, Upstash), then auth (Clerk, Auth0, local JWT secrets), then Stripe, then email (Resend, SendGrid, Postmark, Twilio), then AI providers (OpenAI, Anthropic, etc.), then observability, then Git hosts, then webhooks. Supabase rotation is fully automated via API (JWT signing keys + DB password). Local auth secrets get generated to a chmod-600 file in the incident folder. Everything dashboard-only becomes a link in the final checklist.

**6. Empties Vercel env vars.** Keys are preserved, values are set to "". Leaked values in Vercel's storage are now neutralized; new deploys fail loudly until fresh values arrive in step 9. `VERCEL_*` system vars and integration-managed vars are skipped correctly.

**7. Disconnects integrations.** Supabase, Sentry, Neon, Upstash, Vercel KV. Re-inject credentials automatically on connection, so they get disconnected here and reconnected in step 9 once upstream is clean.

**8. Hardens the Vercel account itself.** Rotates your Vercel access tokens, enables 2FA, regenerates deploy hooks, re-auths the GitHub OAuth app. This is the step that assumes Vercel's internal state is compromised.

**9. Scans build logs.** `console.log(process.env)` prints persist in Vercel's log storage. Rotation of the env vars doesn't remove them from the logs. `scan-build-logs.sh` pulls the last 20 deploys per project and greps for 15 secret patterns (Stripe keys, AWS access keys, GitHub PATs, JWT tokens, Postgres connection strings).

**10. Redeploys with sensitive env vars.** New values go in with the Sensitive toggle on, which stores them in a format Vercel can't read back through dashboard or API. The team-wide `Enforce Sensitive Environment Variables` policy gets enabled so future env vars default to sensitive without thinking about it.

**11. Delivers the checklist.** One markdown file split into `[DONE]` / `[MANUAL]` / `[BLOCKED]`. Ordered by what you should do first, with direct dashboard links for every manual step.

---

## Install

```bash
git clone https://github.com/moizibnyousaf/vercel-breach-best-practices.git \
  ~/.claude/skills/vercel-breach-best-practices

chmod +x ~/.claude/skills/vercel-breach-best-practices/scripts/*.sh
```

Claude Code picks up the skill on next launch.

## Run

Get authed into Vercel (pick one):

```bash
vercel login                             # interactive
# or
export VERCEL_TOKEN=vca_...              # generate at vercel.com/account/tokens
```

Then in any project directory, open Claude Code and invoke:

```
/vercel-breach-best-practices
```

Or just say "vercel got breached, help me rotate everything." The skill triggers on incident language without needing the slash.

## Requirements

Hard: `curl`, `jq`, `openssl`, and a `VERCEL_TOKEN`. The first three are preinstalled on macOS.

Opportunistic: `SUPABASE_ACCESS_TOKEN` for the automated Supabase rotation, and whichever service CLIs you already have installed (`aws`, `gh`, `neon`, `turso`, `pscale`). The skill uses what it finds and flags what it can't automate in the `[MANUAL]` section.

---

## Repository layout

```
vercel-breach-best-practices/
├── SKILL.md                              # the skill Claude reads
├── README.md
├── LICENSE
├── scripts/
│   ├── _common.sh                        # shared: token discovery, auth'd curl
│   ├── preserve-evidence.sh              # audit log + deploys + roster + tokens
│   ├── enumerate.sh                      # every env var, classified, paginated
│   ├── empty-env-vars.sh                 # values to "", keys preserved
│   ├── generate-secrets.sh               # AUTH_SECRET / JWT_SECRET locally
│   ├── rotate-supabase.sh                # full Supabase rotation via API
│   └── scan-build-logs.sh                # grep deploys for leaked secrets
└── references/
    ├── rotation-playbooks.md             # per-service tier 1–9 recipes
    ├── classifier.md                     # env-var-name → service patterns
    ├── audit-triage.md                   # what to flag in a Vercel audit log
    └── checklist-template.md             # final deliverable format
```

`SKILL.md` and the `references/` files are the knowledge layer Claude reads. The `scripts/` are what Claude (or you) runs. Total: 14 files, 1,559 lines.

---

## Ordering rules, and why they matter

The skill runs in a specific order because the ordering is the defense. Reversing any step makes the response meaningfully worse.

**Rotate upstream before emptying Vercel env vars.** Emptying the values in Vercel does not invalidate leaked secrets. The upstream service still accepts the old key. Upstream rotation is what kills the leak. Emptying Vercel is hygiene.

**Preserve evidence before rotating anything.** Some providers stop surfacing the old key's activity as soon as the new key is generated. If you rotate first, you lose the trail.

**Highest blast radius first.** AWS and Stripe before analytics and Sentry. Cloud-account takeover and direct money exfiltration beat "attacker changed my alert thresholds."

---

## What's automated vs. what's dashboard clicks

Automated: enumeration, classification, audit-log triage, Supabase rotation (JWT + DB password), local auth-secret generation, Vercel env-var emptying, evidence preservation, build-log secret scanning.

Dashboard with direct links: Stripe, Clerk, Auth0, OpenAI, Anthropic, SendGrid, Twilio, GitHub OAuth, most webhook URLs, the sensitive-env-var toggle.

The split is deliberate. Services that expose rotation endpoints get rotated; services that require dashboard clicks get ordered links in the checklist so the clicking is fast.

---

## Works with Vercel's official Claude skill

Vercel publishes [`vercel-cli-with-tokens`](https://vercel.com/docs/claude-code) for deploy operations through the CLI. The two skills interlock: this one handles the rotation loop, Vercel's handles the redeploy (step 10) where new env vars get set and fresh deploys get triggered.

Both skills agree on the same security rule: never pass `VERCEL_TOKEN` as a `--token` flag, because it leaks to shell history and process listings. Export it as an environment variable and let the CLI read it.

---

## Common questions

**Is this safe on production?** Yes. The destructive actions are emptying env vars (keys preserved, no schema loss) and upstream credential rotation (the point of the exercise). Every batched action confirms scope and count before executing.

**Does it leak secrets into chat?** No. New secrets go to `~/incident-YYYY-MM-DD/secrets.txt` with chmod 600. Chat sees destinations, never values.

**What about personal Vercel accounts with no teams?** Handled. `enumerate.sh` falls through to personal scope when teams come back empty.

**Token has access to 3 of 5 teams, 403s on 2?** Noted in the checklist as `[BLOCKED] team <slug>: token lacks access`. Remaining teams rotate normally.

**User wants to stop halfway?** Fine. The skill hands back a partial checklist with an `[INCOMPLETE]` section listing what wasn't touched. Half a rotation is still better than none.

**Precautionary, not confirmed breach?** Say so. The skill relaxes urgency on session-invalidating rotations (auth secrets) and integration disconnects, keeps the structural hardening.

**Why not one giant script?** Incident response is conversational, not batch. You need to pause, redirect, skip a tier, ask questions mid-flight. Claude orchestrates; scripts handle the deterministic parts.

---

## Contributing

Pull requests welcome. Three high-value additions:

New service rotation playbooks in `references/rotation-playbooks.md`, bonus if scripted into `scripts/`. The Supabase script is the reference implementation.

Classifier patterns for env-var names the current regex misses. Add to `scripts/enumerate.sh`'s `classify()` and to `references/classifier.md` so the two stay in sync.

Audit-log heuristics in `references/audit-triage.md`. The more patterns the AI can flag, the less the user has to squint at JSON.

Keep `SKILL.md` under 500 lines. Push detail into `references/` with clear pointers.

---

## License

MIT. See [LICENSE](LICENSE).

## Credits

The [April 2026 Vercel security bulletin](https://vercel.com/knowledge/vercel-april-2026-security-incident) for the initial prompt. Vercel's [`vercel-cli-with-tokens`](https://vercel.com/docs/claude-code) skill for the token-discovery pattern. Anthropic's [Claude Code skill-creator](https://docs.claude.com/claude-code/skills) for the SKILL.md structure.

Built with Claude Code in an afternoon. Shipped the same day Vercel shipped the bulletin.
