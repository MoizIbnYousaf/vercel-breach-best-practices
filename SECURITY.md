# Security policy

## Reporting a vulnerability

If you find a security issue in this skill — the bash scripts, the markdown guidance, or the workflow itself — please report it privately before opening a public issue or PR.

**Preferred**: open a [private security advisory](https://github.com/MoizIbnYousaf/vercel-breach-best-practices/security/advisories/new) on GitHub. This keeps the report visible only to the maintainer until a fix is ready.

**Alternative**: email `moizibnyousaf@gmail.com` with the subject line `[vercel-breach-best-practices security]`. Include enough detail to reproduce, and (if you have one) a suggested fix.

### What counts as a security issue

- Any path by which the skill could exfiltrate credentials or env-var values off the user's machine
- Any way to bypass the `ALLOWED_HOSTS` allowlist in `scripts/_common.sh`
- Any mutation that happens without `--execute` + explicit user consent
- Any script that calls an upstream rotation API (Supabase, Clerk, Stripe, etc.) — this skill's rule is "zero autonomous upstream rotation"
- Any `eval`, `source <(curl ...)`, or dynamic-shell pattern that evaluates attacker-controlled input
- Any write outside `~/incident-YYYYMMDD/` to a location an attacker could persist in (`~/.bashrc`, `~/.ssh/`, etc.)
- Documentation claims in `SKILL.md` / `THREAT_MODEL.md` / `README.md` that misrepresent what the skill does or does not do

### What is not a security issue

- Scanner false positives on shell examples in documentation (e.g., `$DATABASE_URL` in a code block). Feel free to open a normal issue.
- Style / wording suggestions. Open a regular PR.
- Feature requests for new provider playbooks. Open a regular PR against `references/rotation-playbooks.md`.

## Scope

This policy covers the contents of this repository at `github.com/MoizIbnYousaf/vercel-breach-best-practices`. It does not cover:

- Vercel's platform itself (report to `security@vercel.com`)
- Anthropic's Claude Code runtime (report to Anthropic)
- Any upstream service's rotation UX (report to that service)

## Response

The skill is solo-maintained, so response times are best-effort. Expectations:

- Acknowledgment within 72 hours
- Fix or detailed response within 14 days for anything genuinely exploitable
- Credit in the changelog (if you want it)

## Verification

Before trusting an unfamiliar version of this skill during an incident, run the verification recipe in [`THREAT_MODEL.md`](THREAT_MODEL.md) — it takes about 30 seconds and confirms the allowlist, dry-run defaults, and absence of upstream-rotation scripts.
