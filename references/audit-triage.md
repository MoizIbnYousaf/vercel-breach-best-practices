# Vercel audit-log triage

When the user runs `scripts/preserve-evidence.sh`, the Vercel audit log lands at `~/incident-$(date +%Y%m%d)/audit-log.json`. Load it yourself and walk it before asking the user what's suspicious — you're faster than a human clicking through 200 rows.

This reference lists the event types worth flagging and the patterns that should raise eyebrows.

## Event types worth reading closely

Vercel's audit-log event names follow a `<resource>.<action>` shape. The ones that matter most during incident response:

| Event | Why it matters |
|---|---|
| `token.created` | Attacker-minted tokens persist across password resets |
| `token.revoked` | Attacker covering tracks (or the user rotating — check against the user's known actions) |
| `integration.created` / `integration.removed` | Integrations re-inject env vars; a new one can backdoor secrets |
| `integration.configuration.updated` | Changed scopes on an existing integration |
| `env.created` / `env.updated` / `env.removed` | Attacker adding their own env vars (e.g., a rogue webhook URL) |
| `env.read` / `env.listed` | Bursts across many projects suggest exfiltration |
| `deploy-hook.created` | Persistent backdoor — a webhook URL that triggers builds forever |
| `deploy-hook.removed` | Track against user's recent activity |
| `member.added` / `member.removed` / `member.role-changed` | Attacker giving themselves team access |
| `team.transfer.initiated` | Catastrophic — team handoff to an attacker-controlled account |
| `domain.added` / `domain.moved` | Phishing or traffic interception |
| `dns.record.created` / `dns.record.updated` | Same |
| `project.transferred` | Project moved to another account |
| `git-integration.disconnected` / `git-integration.connected` | Supply-chain risk |
| `sso.connection.updated` | SSO takeover |
| `audit-log.viewed` | Repeated access from unfamiliar IP = attacker scoping the trail |

Any event not in this list is usually benign for incident scoping, but worth a quick scan if time allows.

## Patterns to flag

These are heuristics — they suggest compromise but don't prove it. Present to the user as *Suspicious* and let them confirm.

### Burst of `env.read` / `env.listed` across many projects

Attackers dumping env vars tend to sweep — list env-vars on every project in a short window. Normal user behavior is one project at a time.

```bash
jq '[.events[] | select(.type | startswith("env."))] | group_by(.entity.projectId) | map({project: .[0].entity.projectId, count: length, span_ms: ((.[-1].timestamp | fromdateiso8601) - (.[0].timestamp | fromdateiso8601)) * 1000}) | sort_by(-.count)' audit-log.json
```

**Flag** if a single session touched env vars across >3 projects in <10 minutes.

### Tokens created from unfamiliar IPs

```bash
jq '[.events[] | select(.type == "token.created") | {time: .timestamp, ip: .source.ip, ua: .source.userAgent, name: .entity.name}]' audit-log.json
```

**Flag** any IP the user doesn't recognize. Cross-check with their last 30 days of known locations.

### Activity outside business hours

Group events by hour-of-day in the user's timezone. Attacker activity often clusters outside the user's normal working hours.

```bash
jq '[.events[] | .timestamp | fromdateiso8601 | strftime("%H")] | group_by(.) | map({hour: .[0], count: length}) | sort_by(.hour)' audit-log.json
```

**Flag** unusual concentration at off-hours if the user is a solo operator.

### New integrations in the last 30 days

```bash
jq '[.events[] | select(.type == "integration.created")] | map({time: .timestamp, integration: .entity.slug, actor: .actor.username})' audit-log.json
```

**Flag** any the user doesn't recognize. Especially dangerous: integrations that request `env-vars:write`.

### Deploy hooks created without matching project activity

Deploy hooks are URL-triggered builds — an attacker can create one, save the URL, and trigger builds later to exfiltrate via a modified build output.

```bash
jq '[.events[] | select(.type == "deploy-hook.created")] | map({time: .timestamp, project: .entity.projectId, name: .entity.name, actor: .actor.username})' audit-log.json
```

**Flag** any hook the user didn't create.

### Team membership changes

```bash
jq '[.events[] | select(.type | startswith("member.") or startswith("team.transfer"))]' audit-log.json
```

**Flag** any that weren't user-initiated.

## How to present findings

Structure the output as three buckets:

```
🚨 Suspicious — likely attacker activity
- 2026-04-18 03:47 UTC: token.created from 203.0.113.42 (unknown IP, off-hours)
- 2026-04-18 03:51 UTC: env.listed across 8 projects in 4 minutes
- 2026-04-18 03:58 UTC: deploy-hook.created on project "api-prod"

❓ Worth confirming — could be you or could be attacker
- 2026-04-17 14:12 UTC: integration.created "generic-webhook"
- 2026-04-17 14:15 UTC: env.updated on 3 projects

✅ Looks normal
- Standard deploys, your IPs, within working hours
```

Ask the user to confirm each **Suspicious** and **Worth confirming** item before declaring the account clean. If anything in **Suspicious** is confirmed as not-the-user, treat this as a confirmed breach and escalate the rotation urgency (session invalidation included).

## When the audit log isn't enough

Vercel's audit log has retention limits and doesn't capture everything (e.g., what data was exfiltrated via a rogue integration). For high-stakes incidents, after triage:

1. Request extended logs via Vercel Support (vercel.com/help) — they can sometimes provide additional context.
2. Capture upstream access logs before rotating (Supabase, Stripe, etc. — each has its own "API keys last used" view).
3. Preserve the audit-log.json file alongside the checklist as part of the incident record.
