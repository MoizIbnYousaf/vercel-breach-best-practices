# vercel-breach-best-practices

**A Claude Code skill for responding to a Vercel breach.** Enumerates every project + env var across your account, AI-triages the audit log, rotates credentials in blast-radius order, and hands you a clean checklist of what's done vs. what you need to click through yourself.

Built in the hours after the [April 2026 Vercel security incident](https://vercel.com/knowledge/vercel-april-2026-security-incident). Applicable to any Vercel compromise — platform breach, leaked `VERCEL_TOKEN`, compromised integration, or suspected env-var exposure.

> Vercel's own recommendation was: review your activity log, rotate env vars, use the sensitive-environment-variables feature. This skill does those things for you, and then goes further — across every upstream service your Vercel projects touch.

---

## What it does

In order, it runs:

1. **Scopes the incident** with a single set of questions (which team, confirmed or precautionary, what CLIs are authed).
2. **Preserves evidence** — dumps Vercel audit logs, deployment history, team roster, and active tokens to `~/incident-YYYY-MM-DD/` before anything rotates. Attackers' trails are irreplaceable.
3. **AI-triages the audit log** — you can read 200 JSON rows faster than a human clicking through them. Surfaces suspicious tokens created off-hours, env.listed bursts, new integrations, deploy-hook creation, unfamiliar IPs.
4. **Inventories every team + project + env var**, classifying each variable by upstream service (Supabase, Stripe, AWS, OpenAI…) so rotation can be prioritized by blast radius.
5. **Rotates upstream** in the order that matters most:
   `AWS → DBs → auth → Stripe → email → AI APIs → observability → Git hosts → webhooks`. Automates what can be automated (Supabase JWT + DB password, local auth secrets); hands you a [MANUAL] checklist with direct dashboard links for the rest.
6. **Empties Vercel env vars** (keys preserved, values cleared) so in-flight builds fail loudly until fresh values are set.
7. **Disconnects compromised integrations** so they don't re-inject old credentials.
8. **Hardens the Vercel account** — rotates your Vercel access token, enables 2FA, regenerates deploy hooks, re-auths the GitHub OAuth app.
9. **Scans build logs** for accidentally-logged secrets (`console.log(process.env)`-style leaks persist in Vercel's log storage even after env-var rotation).
10. **Guides redeploy + enables sensitive env vars** — both per-var and team-wide `Enforce Sensitive Environment Variables` policy.
11. **Delivers a single markdown checklist** split into `[DONE]` / `[MANUAL]` / `[BLOCKED]`, ordered by what you should do first.

---

## Quick start

**1. Install Claude Code** if you don't have it: `npm install -g @anthropic-ai/claude-code`

**2. Install the skill:**

```bash
git clone https://github.com/moizibnyousaf/vercel-breach-best-practices.git \
  ~/.claude/skills/vercel-breach-best-practices
chmod +x ~/.claude/skills/vercel-breach-best-practices/scripts/*.sh
```

**3. Get authed into Vercel:**

```bash
# Option A — the CLI way
vercel login

# Option B — a scoped token
export VERCEL_TOKEN=vca_...
```

Tokens live at https://vercel.com/account/tokens. Generate one scoped to the affected team(s). The skill will also auto-discover `VERCEL_TOKEN` from `~/.vercel/auth.json` or a `.env` file if present.

**4. In a project directory, run Claude Code and invoke the skill:**

```
> /vercel-breach-best-practices
```

Or just tell Claude: "vercel got breached, help me rotate everything." The skill will trigger automatically.

---

## Requirements

Hard dependencies:
- `curl`, `jq`, `openssl` — standard tooling, preinstalled on macOS
- `VERCEL_TOKEN` — either via `vercel login` or exported manually
- Claude Code (the skill lives inside it)

Soft dependencies (used opportunistically by specific rotations):
- `SUPABASE_ACCESS_TOKEN` — for `rotate-supabase.sh` (get at https://supabase.com/dashboard/account/tokens)
- `aws` CLI — for AWS IAM rotation
- `gh` CLI — for GitHub audit
- `neon`, `turso`, `pscale` CLIs — for each database provider's rotation

Anything missing is flagged in the final `[MANUAL]` section of the checklist.

---

## Repository layout

```
vercel-breach-best-practices/
├── SKILL.md                              # the skill itself (Claude reads this)
├── README.md                             # you are here
├── LICENSE
├── scripts/
│   ├── _common.sh                        # shared: token discovery, preflight, auth'd curl
│   ├── preserve-evidence.sh              # dump audit log, deploys, roster, active tokens
│   ├── enumerate.sh                      # list + classify every env var, output JSON
│   ├── empty-env-vars.sh                 # set all env vars on a project to ""
│   ├── generate-secrets.sh               # generate AUTH_SECRET / JWT_SECRET / etc. locally
│   ├── rotate-supabase.sh                # fully-automated Supabase rotation (JWT + DB pw)
│   └── scan-build-logs.sh                # grep recent build logs for leaked secret patterns
└── references/
    ├── rotation-playbooks.md             # per-service rotation recipes (tier 1–9)
    ├── classifier.md                     # env-var-name → service name patterns
    ├── audit-triage.md                   # what to look for in a Vercel audit log
    └── checklist-template.md             # format of the final deliverable
```

`SKILL.md` and the files under `references/` are the knowledge layer — Claude reads them. `scripts/` are runnable; Claude invokes them on your behalf, or you can run them directly.

---

## Non-negotiable ordering

The skill runs in a specific order because the ordering itself is the defense:

**Evidence → Inventory → Upstream rotation → Empty Vercel env vars → Redeploy**

Reversing any step makes the response worse:

- **Rotate upstream before emptying Vercel** — emptying Vercel env vars does **not** invalidate leaked secrets. The upstream service (Supabase, Stripe, etc.) still accepts the old key. Upstream rotation is what kills leaked values. Emptying Vercel is hygiene.
- **Preserve evidence before rotating** — once keys rotate, some providers stop surfacing the old key's activity. The attacker's trail is irreplaceable.
- **Highest blast radius first** — AWS + Stripe before analytics + Sentry. Money and cloud-account takeover are worth more to an attacker than dashboard access.

---

## What Claude does vs. what you do

The skill automates what's automatable and gets out of your way on what isn't:

| Category | Automation |
|---|---|
| Enumeration, classification, checklist | 100% automated |
| Audit-log triage | AI reads the log and summarizes anomalies |
| Supabase rotation (JWT + DB password) | 100% automated via API |
| Local auth secrets (`AUTH_SECRET`, etc.) | 100% automated locally |
| Vercel env-var emptying | 100% automated via API |
| Evidence preservation | 100% automated |
| Build-log secret scanning | 100% automated |
| Stripe, Clerk, OpenAI, Anthropic, GitHub, AWS, etc. | Guided dashboard links with exact steps |
| Sensitive-env-var migration | Guided (Vercel requires remove + re-add) |

For the dashboard-only services, the skill gives you a clean ordered checklist with deep links so you can click through fast.

---

## Integrations with other Claude skills

This skill focuses on rotation. Vercel publishes a complementary skill, [`vercel-cli-with-tokens`](https://vercel.com/docs/claude-code), for deploying via the CLI with token-based auth. The two interlock:

- **This skill** handles the rotation loop and the post-incident checklist.
- **`vercel-cli-with-tokens`** handles the redeploy (step 9) — setting new env vars, triggering fresh deploys, verifying builds.

Both follow the same ground rules: never pass `VERCEL_TOKEN` as a `--token` flag (it leaks to shell history); export it as an env var and let the CLI read it natively.

---

## FAQ

**Is this safe to run on my production Vercel account?**
Yes. The destructive actions are (a) emptying env vars (keys preserved, values cleared — no data loss) and (b) upstream credential rotation (which is the point). Every batched destructive action confirms with you first and shows the scope.

**Does this leak secrets into the Claude conversation?**
No — new secrets are written to `~/incident-YYYY-MM-DD/secrets.txt` with `chmod 600`. Only destinations are mentioned in chat, never values.

**What if my Vercel account has multiple teams?**
The skill enumerates every team your token can see, plus personal scope. A team's 403 (viewer-only token) is noted in the checklist and skipped gracefully.

**What if I want to stop halfway?**
Fine. The skill hands you a partial checklist with an `[INCOMPLETE]` section listing what wasn't rotated yet. Half a rotation is still better than none.

**Why not one giant script?**
Because incident response isn't linear. The skill orchestrates conversationally — you can pause, redirect, skip a tier, or ask questions mid-flight. Scripts cover the deterministic parts.

**Is there a "precautionary mode"?**
Yes — just tell the skill "I haven't confirmed a breach, just being cautious." It adjusts urgency (fewer session-invalidating rotations, softer on integration disconnects) while still doing the structural hardening.

---

## Contributing

Pull requests welcome. Most valuable additions:

- **New service rotation playbooks** in `references/rotation-playbooks.md` (bonus if scripted in `scripts/`).
- **Classifier patterns** for env-var names the current regex misses — add to `scripts/enumerate.sh`'s `classify()` and to `references/classifier.md`.
- **Audit-log heuristics** in `references/audit-triage.md`.

Keep SKILL.md under 500 lines; push detail into `references/` with clear pointers.

---

## License

MIT — see [LICENSE](LICENSE).

---

## Credits

- The [April 2026 Vercel security bulletin](https://vercel.com/knowledge/vercel-april-2026-security-incident) for the initial prompt.
- Vercel's own [`vercel-cli-with-tokens`](https://vercel.com/docs/claude-code) skill for the token-discovery pattern and shell-safety rules.
- The Claude Code [skill-creator](https://docs.claude.com/claude-code/skills) framework for the SKILL.md structure.

Built with Claude Code.
