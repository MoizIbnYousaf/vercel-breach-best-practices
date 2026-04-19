# Changelog

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
