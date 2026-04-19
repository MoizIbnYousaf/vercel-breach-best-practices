# Changelog

## v2.2 — 2026-04-19 — Critic-pass corrections

Self-audit in critic mode surfaced 8 issues. All fixed in this commit.

### Critical

- **README rewritten.** The v1 README still described the autonomous Supabase
  rotation that was removed in v2: listed the deleted `rotate-supabase.sh` in
  the repo tree, claimed "Supabase rotation is fully automated via API",
  labeled it "the reference implementation", and showed a stale file count.
  The GitHub page was contradicting `SKILL.md`. Rewrote from scratch to match
  v2.1 reality: advisor framing, removed rotator acknowledged, safety rails
  summarized, contributor guidance amended to forbid adding upstream-rotation
  scripts.

### Bugs

- **Classifier order fix** — `scripts/enumerate.sh` matched `*_API_KEY` before
  `NEXT_PUBLIC_*`, so `NEXT_PUBLIC_STRIPE_API_KEY` was misclassified as a
  secret when it's client-exposed public config. Moved `NEXT_PUBLIC_*` ahead
  of the catch-all with a comment explaining why.
- **Audit-log script name** — `audit_log()` in `_common.sh` used
  `BASH_SOURCE[2]`, which lands on `_common.sh` for every call (the actual
  user script is at depth 3). Fixed to prefer `[3]`, fall back to `[2]`.
- **Unnecessary dep** — `enumerate.sh` required `openssl` but never used it.
  Removed.

### Safer defaults

- **Step 8 "delete all tokens" softened** — the v2.1 wording could break the
  user's in-flight Vercel session if they deleted all tokens including the one
  the CLI was using. Changed to: "create the fresh team-scoped one FIRST,
  update local CLI auth, THEN revoke old tokens."
- **Step 11 no longer defaults to wipe** — the "Default yes" wording risked
  destroying the only local copy of new credentials if the user hadn't
  migrated them to a password manager yet. Changed to explicit three-option
  `AskUserQuestion` with no default: wipe both, wipe audit.log only, keep
  everything.
- **`generate-secrets.sh` handoff clarified** — SKILL.md now explicitly says:
  never read `secrets.txt` in chat. Tell the user the filename and let them
  `cat` it themselves. Prevents accidental secret exposure in the transcript.

### Unchanged (re-verified)

- Host allowlist is airtight; every network call funnels through `safe_curl`.
- Dry-run default works; `--execute` is the only opt-in.
- No upstream rotation anywhere in the codebase.
- `THREAT_MODEL.md` verification recipe still runs green.

## v2.1 — 2026-04-19 — Advisor framing + exposure interview

Tonal and structural refinement based on critic-mode review. No new scripts,
no new hosts, no new permissions. Same safety posture as v2.

### Added

- **`references/exposure-interview.md`** — optional Step 4.5. A batched markdown
  checklist the user fills in *after* inventory, covering three classes of
  exposure the Vercel API cannot see:
  1. Historical env vars deleted during the incident window
  2. Out-of-band copies (Slack, git history, screenshots)
  3. Vercel-adjacent exposures (deploy hooks, Git OAuth, past team members)
  Explicitly scoped to Vercel exposure — not a generic security questionnaire.
  Opt-in, never blocks containment.

### Changed

- **SKILL.md reframed as advisor, not director.** Each step now surfaces
  observations, trade-offs, and options — then uses `AskUserQuestion` for the
  decision. Scripts are framed as observation tools, not action dictators.
- **Added "What this skill is NOT" section** — makes scope boundary explicit.
  No autonomous rotation, no generic security audit, no decision-making on
  behalf of the user.
- **Step 5 rewritten** around trade-off thinking (blast radius, rotation cost,
  urgency, ready state) rather than a linear click-through.
- **"When uncertain, prefer dashboard"** promoted to a first-class operating
  principle. Dashboard clicks are visible, reversible, and well-understood.

### Rationale

v2 made the skill safer. v2.1 makes it a better *thinking partner*. The shift:
a skill that runs stuff during an incident is a liability; a skill that helps
the user think clearly is an asset. Default to the second.

Critic-mode review (simulated forefy / senior DFIR / HN skeptics) flagged
scope-creep risk on the exposure interview — addressed by anchoring strictly
to "exposure that passed through Vercel" and never framing the interview as a
gate or ground truth.

## v2 — 2026-04-19 — Hardening pass

Response to public security feedback on v1. Goal: reduce the skill's attack surface and make supply-chain review trivial.

### Removed

- **`scripts/rotate-supabase.sh`** — the only autonomous upstream-rotation script. Now the user rotates Supabase in their dashboard; the skill provides the link. Rationale: no autonomous writes to third-party services.

### Added

- **`ALLOWED_HOSTS` allowlist in `scripts/_common.sh`** — every network call funnels through `safe_curl`, which rejects any host outside `api.vercel.com` / `api.supabase.com`. Single point of control for reviewers.
- **`audit.log`** — every API call appends to `~/incident-YYYYMMDD/audit.log` with timestamp, method, host, path. No bodies, no tokens.
- **`parse_execute_flag`** — destructive scripts default to dry-run. Require explicit `--execute` flag to mutate. Reversed from v1.
- **`THREAT_MODEL.md`** — explicit about what the skill defends against, what it does not, and how to verify the skill itself.
- **Transparency section in `SKILL.md`** — lists exactly which hosts the skill calls, explicit no-telemetry / no-auto-upload statement.
- **Consent model section in `SKILL.md`** — requires `AskUserQuestion` before every Vercel mutation with scope + effect surfaced.

### Changed

- **`empty-env-vars.sh`** — default is dry-run. `--execute` required to mutate. Summary line distinguishes dry-run vs executed.
- **`preserve-evidence.sh`** — migrated to `vcurl` wrapper (routes through `safe_curl`). No behavior change, just consistent allowlist enforcement.
- **`SKILL.md` description** — trimmed from 1326 to under 1024 chars per skill-registry guidance.
- **`references/rotation-playbooks.md`** — replaced `$DATABASE_URL` with `<YOUR_DATABASE_URL>` placeholders throughout (scanner false-positive reduction).
- **Supabase rotation guidance** — now dashboard-only. Removed references to the deleted automation script.

### Fixed (scanner findings from v1)

- Description length (1326 → under 1024 chars)
- False-positive "secret grabbing" hits on `$DATABASE_URL` / `$API_KEY` shell-example patterns
- False-positive "external fetch" hit on `brew install jq` / `apt install jq` lines

### Philosophy

v1 offered optional API-driven rotation. v2 removes that path entirely. The skill is now an **advisor**: it preserves evidence, enumerates the surface, classifies secrets, and produces a guided checklist with direct dashboard links. The **user** rotates every credential in their own dashboard.

## v1 — 2026-04-19 — Initial release

Incident-response skill for the April 2026 Vercel security incident. Preserve + enumerate + classify + rotate + verify workflow. Included `rotate-supabase.sh` for optional automated Supabase rotation (removed in v2).
