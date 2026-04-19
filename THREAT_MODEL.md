# Threat model

This skill runs during incident response, when the user is most likely to accept risky actions without reviewing. That makes the skill itself a supply-chain surface. This document is explicit about what the skill defends against, what it does not, and how to verify the skill itself hasn't been tampered with.

## What this skill defends against

- Leaked Vercel env vars: emptied (with user consent) so stale values can't be reused at deploy time.
- Leaked Vercel access tokens: guided revocation via dashboard.
- Leaked upstream credentials (Supabase, Clerk, Stripe, etc.): guided rotation via dashboard. The skill never calls these providers' rotation APIs.
- Missing evidence: audit log, deploy history, token list, team roster preserved before any mutation.

## What this skill does NOT defend against

- **Compromised local machine.** If the user's shell, browser, or keychain is already compromised, this skill can't help.
- **Compromised Vercel token in memory.** Any script that runs with `VERCEL_TOKEN` has token access for the duration of the run. Mitigation: use team-scoped tokens, rotate after the incident.
- **Upstream service compromise.** If Supabase/Clerk/etc. is itself breached, rotating the API key only helps if the upstream has also closed its hole.
- **Zero-day in curl, jq, openssl, bash.** Standard tools are trusted.
- **Build logs that were already scraped.** If logs with secrets were pulled before rotation, those secrets are gone — rotation kills future use but can't revoke past copies.

## Known limitations — be honest about these

The host allowlist, audit log, and consent gates are real controls, but they have limits. Don't let the README sell these as stronger than they are:

- **Claude (the model) can bypass `safe_curl`.** The allowlist binds the bash scripts in this repo. Claude also has its own Bash tool and could in principle run `curl https://evil.com` directly without going through `safe_curl`. The mitigation is **human observability**: every Bash tool call appears in the transcript and the SKILL.md instructs Claude to only use the bundled scripts. That's a soft control, not hard enforcement. If you notice Claude running a `curl` that isn't in one of the bundled scripts, stop and review.
- **The audit log is honor-system.** `audit.log` is written *by* the skill being audited. A malicious fork could log nothing, or log fake entries. The real defense is reading the source code before you trust it — `audit.log` is for your own recordkeeping, not third-party verification.
- **"Never read `secrets.txt` in chat" is a soft prompt.** SKILL.md tells Claude not to read that file aloud. There is no technical barrier; an adversarial prompt could cause it to be read. The only enforcement is: Claude's behavior is observable in the transcript, and you can `chmod 000` the file if you're paranoid.
- **No code signing.** Tags and commits are not GPG-signed. A compromised maintainer account could publish a malicious tag. Pin to a reviewed commit SHA if that concerns you.

## Skill-as-supply-chain

Because skills are user-installed and run with the user's privileges, a malicious skill could:
- Read local files, env vars, SSH keys
- Make network calls with the user's tokens
- Persist via shell rc files, cron, or system services
- Exfiltrate to attacker-controlled hosts

### How this skill mitigates those risks

1. **Host allowlist.** Every network call funnels through `safe_curl` in `scripts/_common.sh`. The allowlist is `api.vercel.com`, `api.supabase.com`. No other host. Verify: `grep -A3 ALLOWED_HOSTS scripts/_common.sh`.

2. **Audit log.** Every API call appends to `~/incident-YYYYMMDD/audit.log` with timestamp, method, host, path. Bodies and tokens are never logged. Verify during a run: `tail -f ~/incident-*/audit.log`.

3. **Dry-run default on destructive scripts.** `empty-env-vars.sh` requires `--execute`. Without it, the script prints the plan and exits.

4. **Tokens only via env var.** Never accepted as CLI flag. Prevents shell-history leak.

5. **No post-install hooks.** The skill is plain bash scripts + markdown. No `eval`, no dynamic shell, no package-manager post-install.

6. **Explicit consent for every Vercel mutation.** The SKILL.md workflow requires Claude to use `AskUserQuestion` before any mutation, with scope (project, count) and effect (builds will fail) surfaced.

7. **No upstream rotations by this skill.** User rotates Supabase, Clerk, Stripe, etc. in their own dashboards. Skill provides links and checklist slots for the new values.

## Verifying this skill hasn't been tampered with

Before running in an incident, run:

```bash
# 1. Inspect every shell script in under a minute
wc -l ~/.claude/skills/vercel-breach-best-practices/scripts/*.sh
cat ~/.claude/skills/vercel-breach-best-practices/scripts/_common.sh

# 2. Confirm the host allowlist is just two hosts
grep -A3 'ALLOWED_HOSTS=' ~/.claude/skills/vercel-breach-best-practices/scripts/_common.sh

# 3. Confirm no script makes a call outside the allowlist
grep -rE 'curl |wget |nc ' ~/.claude/skills/vercel-breach-best-practices/scripts/ \
  | grep -v '_common\|vcurl\|sbcurl\|safe_curl'
# Expected: no results. Any curl/wget/nc invocation outside _common.sh is a red flag.

# 4. Confirm dry-run is the default for destructive scripts
grep -B1 -A2 'parse_execute_flag' ~/.claude/skills/vercel-breach-best-practices/scripts/empty-env-vars.sh
```

If any of these checks surface something unexpected, **stop and review** before running anything.

## What a malicious fork might look like

If you're evaluating a fork or an older pinned version of this skill, these are the red flags:

- `ALLOWED_HOSTS` includes anything beyond `api.vercel.com` and `api.supabase.com`
- Scripts that call `curl` / `wget` / `nc` / `ssh` directly instead of through `safe_curl`
- `rotate-*.sh` scripts that call upstream rotation APIs (this skill removed those on purpose)
- Default execution without `--execute` flag
- `eval`, `source <(curl ...)`, or dynamic bash anywhere
- `.sh` files writing to `~/.ssh/`, `~/.bashrc`, `~/.zshrc`, or anywhere outside `~/incident-YYYYMMDD/`
- Telemetry, `User-Agent: tracking`, or "phone home" logic
- SHA256 sums that don't match the upstream repository
