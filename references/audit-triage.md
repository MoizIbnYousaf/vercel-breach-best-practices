# Vercel audit-log triage

Vercel logs every state change on a team to the Activity Log. During incident response, this is one of the highest-signal artifacts you have — it shows *exactly* what the attacker (or a compromised token) did.

Two ways to read it:

1. **`vercel activity` CLI** (added March 2026) — filter by event type, date range, project. Best for ad-hoc triage. Docs: https://vercel.com/docs/cli/activity
2. **`~/incident-$(date +%Y%m%d)/audit-log-<team>.json`** — preserved by `scripts/preserve-evidence.sh`. Best for bulk jq queries and keeping an immutable copy.

Prefer the CLI when exploring interactively; use the JSON when grepping across many events at once.

Scan the log yourself before asking the user — you're faster than they are at spotting patterns across 200+ rows.

## The events that matter in a breach

Vercel's events are kebab-cased (`deploy-hook-created`, not `deploy-hook.created`). The full list is huge — here are the ones that actually matter during incident response.

### 🚨 Critical — direct evidence of exfiltration or backdoor

| Event | Why it matters |
|---|---|
| `env-variable-read` | **Direct evidence of env-var decryption.** Each occurrence means somebody pulled the plain-text value. |
| `env-variable-read:cli:env:pull` | Env vars decrypted via `vercel env pull`. Common during dev, suspicious in bursts. |
| `env-variable-read:cli:env:ls` | Decrypted via `vercel env ls`. Same pattern. |
| `env-variable-read:cli:dev` | Decrypted by `vercel dev`. |
| `env-variable-read:unknown-source` | **Very high signal** — decryption from an untracked source. |
| `shared-env-variable-read` | Shared env var decrypted. Wider blast radius than per-project. |
| `deploy-hook-created` | **Persistent backdoor.** Anyone holding the URL can trigger builds with attacker-controlled inputs — forever, until revoked. |
| `oauth-app-token-created` | Attacker minted an OAuth token for themselves. |
| `integration-installation-completed` | New integration installed (auto-injects env vars). Verify it was you. |
| `integration-configuration-scope-change-confirmed` | Existing integration got elevated permissions. |
| `firewall-bypass-created` | Attacker carved a hole in WAF rules. |
| `project-automation-bypass` | Protection Bypass for Automation modified — lets anyone with the secret hit protected deployments. |
| `alias-protection-bypass-created` / `alias-protection-bypass-regenerated` | Shareable link to bypass deployment protection. |

### ⚠️ Worth confirming — could be you, could be attacker

| Event | Why it matters |
|---|---|
| `env-variable-add` / `env-variable-edit` / `env-variable-delete` | Env var changes. Check against known deploys. |
| `secret-add` / `secret-delete` / `secret-rename` | Legacy secrets API (only CLI/API can trigger). |
| `shared-env-variable-create` / `shared-env-variable-delete` / `shared-env-variable-update` | Team-wide env var changes. |
| `deploy-hook-deleted` | Attacker covering tracks, or normal cleanup. |
| `integration-installation-removed` | Same — attacker removing evidence, or normal cleanup. |
| `team-member-add` / `team-member-role-update` | Attacker giving themselves access. |
| `team-member-delete` / `team-member-leave` | Attacker removing legitimate members. |
| `team-ip-blocking-rules-removed` | WAF IP block dropped. |
| `team-mfa-enforcement-updated` | 2FA enforcement weakened. |
| `team-saml-enforced` / `team-saml-roles` | SSO config changed. |
| `domain` / `domain-delete` / `domain-move-out` / `domain-move-out-request-sent` | Domain taken or moved — phishing / MITM risk. |
| `dns-add` / `dns-delete` / `dns-update` / `dns-zonefile-import` | DNS record tampering. |
| `project-git-repository-connected` / `project-git-repository-disconnected` | Supply-chain swap. |
| `connect-github` / `connect-gitlab` / `connect-bitbucket` | New Git connection. |
| `disconnect-github` / `disconnect-gitlab-app` | Git disconnection. |
| `password-protection-disabled` | Deployment Protection weakened. |
| `strict-deployment-protection-settings` | Ditto. |
| `attack-mode-enabled` / `attack-mode-disabled` | WAF attack-mode toggled. |
| `drain-created` / `log-drain-created` | Logs being exfiltrated to a new destination. |
| `vercel-app-tokens-revoked` | Someone revoked OAuth app tokens — could be response, could be attacker. |

### ✅ Usually benign — scan only if time allows

`deployment`, `aliases-assigned`, `cert-autorenew`, `cert-renew`, `project-build-command-updated`, standard deploy-flow events. Noise during an incident; safe to filter out.

## `vercel activity` CLI — useful one-liners

Once the user has the Vercel CLI installed and authenticated, these are the queries worth running.

```bash
# Everything in the last 72 hours
vercel activity --since 72h

# Only env-var reads (high-signal exfiltration check)
vercel activity --type env-variable-read --since 7d
vercel activity --type 'env-variable-read:*' --since 7d   # all CLI-read variants

# Deploy hooks created in the incident window
vercel activity --type deploy-hook-created --since 7d

# Team membership changes
vercel activity --type 'team-member-*' --since 30d

# OAuth / integration activity
vercel activity --type 'integration-installation-*' --since 30d
vercel activity --type 'oauth-app-*' --since 30d

# Protection-bypass events (attacker backdoors)
vercel activity --type firewall-bypass-created --since 30d
vercel activity --type project-automation-bypass --since 30d
vercel activity --type 'alias-protection-bypass-*' --since 30d
```

The CLI filter syntax is permissive — exact names like `env-variable-read` work; glob patterns like `env-variable-read:*` work; `team-member-*` works. Check `vercel activity --help` for the current flags.

## `jq` one-liners over the preserved JSON

When you want bulk analysis, query the file `preserve-evidence.sh` saved.

### Env-var decryption bursts

A burst of `env-variable-read*` across many projects in a short window = likely exfiltration.

```bash
jq '[.events[]
  | select(.type | startswith("env-variable-read"))]
  | group_by(.entity.projectId)
  | map({project: .[0].entity.projectId, count: length})
  | sort_by(-.count)' audit-log-*.json
```

**Flag** any single session touching env vars across >3 projects in <10 minutes.

### Unfamiliar IPs minting tokens or OAuth apps

```bash
jq '[.events[]
  | select(.type | test("oauth-app-token-created|deploy-hook-created|ai-gateway-api-key-created"))
  | {time: .timestamp, ip: .source.ip, ua: .source.userAgent, type: .type, actor: .actor.username}]' audit-log-*.json
```

**Flag** any IP the user doesn't recognize. Cross-check with their last 30 days of known locations.

### Activity outside business hours

```bash
jq '[.events[]
  | .timestamp | fromdateiso8601 | strftime("%H")]
  | group_by(.)
  | map({hour: .[0], count: length})
  | sort_by(.hour)' audit-log-*.json
```

**Flag** unusual concentration at off-hours if the user is a solo operator.

### Protection bypasses (attacker backdoors)

```bash
jq '[.events[]
  | select(.type
    | test("bypass|protection-disabled|attack-mode-disabled|firewall-config"))]' audit-log-*.json
```

Each one is a potential backdoor. Confirm each with the user.

### Team-member changes

```bash
jq '[.events[]
  | select(.type
    | test("^team-member-|^team-invite-|^team-saml-|^team-mfa-"))]' audit-log-*.json
```

**Flag** any the user didn't initiate.

## How to present findings

Three buckets, ordered by urgency:

```
🚨 Suspicious — almost certainly attacker activity
- 2026-04-18 03:47 UTC: oauth-app-token-created from 203.0.113.42 (unknown IP)
- 2026-04-18 03:51 UTC: env-variable-read across 8 projects in 4 minutes
- 2026-04-18 03:58 UTC: deploy-hook-created on project "api-prod"

❓ Worth confirming — could be you or attacker
- 2026-04-17 14:12 UTC: integration-installation-completed "generic-webhook"
- 2026-04-17 14:15 UTC: env-variable-edit on 3 projects

✅ Looks normal
- Standard deploys, known IPs, working hours
```

Ask the user to confirm each **Suspicious** and **Worth confirming** item. If anything in **Suspicious** is confirmed as not-the-user, treat this as a confirmed breach and escalate the rotation urgency (session invalidation included).

## When the audit log isn't enough

Vercel's Activity Log has retention limits, and it captures state changes — not what data was exfiltrated via a rogue integration or deploy hook. For high-stakes incidents, after triage:

1. Request extended logs via Vercel Support (vercel.com/help) — sometimes additional context is available.
2. Capture upstream access logs before rotating (Supabase, Stripe, OpenAI, etc. — each has its own "API keys last used" view).
3. Preserve the `audit-log-<team>.json` file alongside the checklist as part of the incident record.
