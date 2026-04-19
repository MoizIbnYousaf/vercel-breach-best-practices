# Exposure interview — Vercel scope

**This is a supplement to `inventory.json`, not a replacement.** The inventory (pulled from the Vercel API) is ground truth for "what is currently in Vercel." This interview fills the gaps the API cannot see: things that *passed through Vercel* during the incident window but may not be in Vercel right now.

**Point-in-time, user-reported.** Treat every answer as *additions* to the rotation checklist — never as permission to skip something the inventory surfaced.

**Vercel-scoped only.** This interview is not a general security audit. It only asks about credentials / state that could have been exposed *via* the Vercel incident. If something is scary but unrelated to Vercel (e.g., a leaked AWS key from a laptop theft), it belongs in a separate IR process.

---

## How Claude uses this file

Invoke the interview as an **optional Step 4.5**, *after* `enumerate.sh` produces `inventory.json`. Never before. The user should see the inventory first so their answers are grounded in real data, not recall.

Offer the interview as a batched markdown checklist — not a 20-turn AskUserQuestion sequence. Drop the template below into the conversation. Let the user paste it back with sections filled in. Save to `~/incident-YYYYMMDD/exposure-map.md`.

Sections the user skips are fine — the skill doesn't block on this. User can also skip the whole step if they're containment-first.

---

## The checklist template

Copy this block to the user, have them fill it in, and save the filled copy to `exposure-map.md`.

```markdown
# Vercel exposure map — <date>

> User-reported. Supplement to inventory.json. NOT authoritative.

## 1. Historical Vercel env vars (deleted or rotated since)

During the incident window, did you ever delete or rotate an env var in Vercel?
The *old* values may have been exposed even though they're gone from Vercel now.

- [ ] No changes — only current inventory is in scope
- [ ] Yes — list the names of vars that were present at any point during the window:

_____________________________________________

## 2. Deploy hooks

Any Vercel Deploy Hooks registered? Their URLs grant anyone who holds them the
ability to trigger builds with attacker-controlled inputs.

Location: https://vercel.com/<team>/<project>/settings/git → Deploy Hooks

- [ ] No deploy hooks exist
- [ ] Deploy hooks exist — I will regenerate them (add to checklist)
- [ ] Unsure — check the dashboard

## 3. Team access

Who had Vercel team-member access during the incident window?

- [ ] Only me
- [ ] A past collaborator who still has access (must remove)
- [ ] A past collaborator already removed (confirm their removal timestamp vs. incident window)
- [ ] Multiple current collaborators (list if any might themselves be compromised)

Notes: _____________________________________________

## 4. Vercel-managed Git provider OAuth

Vercel holds an OAuth token to your GitHub / GitLab / Bitbucket. Rotating it
re-authorizes Vercel without giving it new access the attacker already has.

- [ ] Will revoke + re-authorize
- [ ] Already did
- [ ] Not using Git integration

## 5. Out-of-band copies of current env vars

Is any value *currently* in Vercel env ALSO stored somewhere the incident could
have exposed?

- [ ] Posted in Slack / Discord / chat message
- [ ] Committed to a public or private Git repo at any point (even if later removed — git history keeps it)
- [ ] Pasted into a shared Google Doc / Notion / wiki
- [ ] Shown in a screenshot or screen recording
- [ ] Written to a `.env` / `.env.local` file on a machine that might itself be compromised
- [ ] Stored in a build log via `console.log(process.env.X)` or equivalent
- [ ] None of the above

For any box checked, list which env var names — do NOT paste values here:

_____________________________________________

## 6. Vercel access tokens created

The audit log / tokens list from `preserve-evidence.sh` shows active tokens.
Review that list yourself. Anything unfamiliar?

- [ ] All tokens are mine, I recognize them
- [ ] One or more tokens I don't recognize (critical — revoke immediately)
- [ ] Unsure (dashboard: https://vercel.com/account/tokens)

Notes: _____________________________________________

## 7. Sensitive env var policy

Vercel's "Enforce Sensitive Environment Variables" team policy makes new env vars
unreadable via dashboard/API after creation — only overwritable.

- [ ] Already enabled for my team
- [ ] Will enable before re-populating new values
- [ ] Unsure where this setting lives (https://vercel.com/teams/<slug>/settings/security)

## 8. Integrations

From `integrations-<team>.json`, list any integration that injected credentials
(Supabase, Neon, Upstash, Sentry, etc.):

_____________________________________________

For each: do you want to disconnect + reconnect after upstream rotation?

## 9. Recovery priority

Of all the exposed credentials, which matters most to contain *first*?

- [ ] Payment (Stripe / Paddle)
- [ ] Database (Supabase / Neon / etc.)
- [ ] Auth (Clerk / Auth0)
- [ ] AI API keys ($ burn risk)
- [ ] Something else: _____

## 10. Timeline

When was the last known "clean" state? When did you first notice?

- Last clean: _____________________________________________
- First noticed: _____________________________________________
- Incident window: _____________________________________________

---

**Once filled, Claude should:**
1. Merge the additions into the rotation checklist (`checklist.md`) — marked `[USER-REPORTED]`.
2. Leave inventory-based items alone; the user's answers here *add* to the work, never subtract.
3. Store this file as `exposure-map.md` in the incident folder with `chmod 600`.
```

---

## What NOT to ask

The interview is **scoped to Vercel exposure**. Do not ask about:

- Local laptop security posture (iCloud backups, Time Machine, keychain state)
- Browser extensions / browser history
- SSH keys, GPG keys, password-manager master passwords
- Personal security practices unrelated to the Vercel incident
- Anything that requires the user to recall things they likely forgot under stress and couldn't verify anyway

If the user volunteers these concerns unprompted, acknowledge and suggest a separate IR process — don't let this skill expand into generic security advising.

---

## Why this is a supplement, not a replacement

The inventory from the Vercel API is authoritative for "what is in Vercel right now." But three classes of exposure aren't in the API:

1. **Historical state** — env vars that were present during the incident window but have since been deleted or rotated.
2. **Out-of-band copies** — the same value pasted into Slack, a commit, a screenshot.
3. **Permissions-adjacent exposures** — deploy hooks, integration tokens, Git provider OAuth, team membership.

This interview asks about exactly those three classes — and only those three. Everything else is either in the inventory already or outside this skill's scope.
