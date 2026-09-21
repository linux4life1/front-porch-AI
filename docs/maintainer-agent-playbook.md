# Maintainer playbook — driving AI agents without reading Dart

You keep the product running. You do **not** need to learn Dart. You **do**
need a short language for what “done” means, and a habit of forcing agents
to cover paths they skip.

This file is **for you**. Agents read it when linked from CLAUDE.md. The
rules themselves live in [CLAUDE.md](../CLAUDE.md) — if a prompt here
disagrees with that file, CLAUDE.md wins.

---

## What agents are good / bad at

| Good at | Bad at (unless forced) |
|---------|-------------------------|
| Fixing a named bug with tests | Finding the sibling path of that bug |
| Passing `flutter analyze` | Knowing Continue ≠ Regen |
| Deep local refactors | Desktop **and** web in one go without being told |
| Overnight “fix the Highs” | Security threat models (stolen session, LAN setup) |
| Writing unit tests | Writing the *right* interaction test |

Green CI is necessary. It is **not** “the app is safe.” The chat-switch
crash and several audit Highs shipped through full green suites.

---

## How to ask (copy-paste)

### Fix a user-visible bug

```
Bug: [what you saw, exact clicks]

Rules:
1. Read docs/design/path-complete-chat-work.md and fill the path-complete
   checklist in your summary.
2. Fix EVERY sibling path (Continue, regen, swipe, delete, 1:1 AND group)
   or mark N/A with a one-line why.
3. Add a test that was red before the fix and green after. Say so.
4. Ship web_ui parity in the same work, or stop and ask me to defer.
5. End with a 3-step poke script I can do in 30 seconds without reading code.
6. Do not claim done without flutter analyze clean on touched files.
```

### Build a new feature

```
Feature: [user benefit, not implementation]

Rules:
1. Path-complete checklist for any chat/realism/memory state.
2. Desktop + web_ui + settings toggles same PR, or ask me to defer web.
3. No new parallel 1:1 vs group logic — extend shared code.
4. Smoke script for me at the end.
5. If this makes an old feature useless, offer to remove it.
```

### Overnight / autonomous work

```
Work the P0 list from the last audit report only.
After each item: path-complete checklist + proven-red test + push Rawhide.
Do NOT expand scope into “while I’m here” refactors.
Stop and report if you need a product decision (not a code decision).
```

### After a big agent dump

```
Audit origin/Rawhide. I want a NO-GO/GO in plain English and a P0/P1
list only — no Dart.
```

### Security-ish change (web login, tunnels, 2FA)

```
Threat model first (stolen cookie, LAN bind, public tunnel), then code.
Session-only must not enable tunnels or replace 2FA without password/TOTP.
Add tests or an explicit “I cannot test X — poke this” step for me.
```

---

## What you should always demand in the answer

1. **Poke script** — 2–5 clicks, plain English.
2. **Path-complete checklist** — filled, not “n/a everything.”
3. **“I did not launch the app”** if they didn’t.
4. **Web: shipped or deferred by you** — not “later.”
5. **What could still be wrong** — one short residual-risk paragraph.

If the answer is only “analyze clean and tests pass,” **push back**.

---

## Your smoke role

You are the integration test CI cannot be. After agent work that touches
chat:

| # | Click | What “good” looks like |
|---|--------|-------------------------|
| 1 | Long reply → **Continue** → Continue again → reload chat | Full text still there, not only the last fragment |
| 2 | Group, two characters, hand/set-down item → **regen** that line | Kit stays on the right person |
| 3 | Light theme → Main Settings menu + Chat Settings | Labels readable (not white-on-cream or black-on-dark) |
| 4 | If web: Journal / review / 2FA enroll | Can finish or cancel; not stuck; 2FA needs password |
| 5 | After a “memory” fix: regen a beat that planted a Growth ring | Discarded plot does not keep steering the character |

Ten minutes of this catches more than another thousand unit tests.

---

## Cadence

| When | What to run / say |
|------|-------------------|
| Every feature / bugfix | Path-complete rules + poke script |
| After a large Rawhide landing | Ask an agent to audit origin/Rawhide: NO-GO/GO + P0/P1 only |
| Before any stable cut | That audit **and** you run the 5-click smoke |
| After “we fixed think-strip / history / pockets” | Explicitly: “audit Continue + group + Growth twins” |

There is no checked-in `/workflow full-codebase-audit` file. Ask for the
audit in those words.

---

## What not to optimize for

- **Reading Dart** — never required.
- **Trusting “the agent said it’s done”** — require poke script + checklist.
- **One mega-prompt that does everything** — short P0 list, one item, push, next.
- **Letting agents expand scope overnight** — that is how twins get half-fixed.

---

## One sentence when you’re lost

```
I cannot read Dart. Treat yourself as the only reviewer. Use
docs/design/path-complete-chat-work.md. Ship desktop+web or ask me to defer.
End with a poke script. Prove one new test red then green.
```

---

## Mapping audit Highs → how to ask next time

| Audit theme | Ask like this |
|-------------|----------------|
| Continue wiped text / re-fed think | “Fix Continue the same way we fixed history — all finalize paths, sanitizer on/off, proven-red test.” |
| Group pockets wrong owner | “Group restore must key by message speaker, not active character — test swipe after focus change.” |
| Growth keeps discarded plot | “Growth must match Journal rewrite invalidation + cursor rollback.” |
| Web missing Journal review | “Web parity for review-first or disable/auto-discard for web-only — product choice, ask me.” |
| Session can set 2FA / tunnels | “Threat model stolen session; password step-up; no public setup without token.” |

---

## If an agent argues with you

You are allowed to say:

- “I don’t care that unit tests pass. Give me the poke script.”
- “Sibling paths or it’s not done.”
- “Web or explicit deferral from me in this chat.”
- “Stop coding. Summarize residual risk in five bullets.”

That is not being difficult. That is the QA layer this project has outside
CI.
