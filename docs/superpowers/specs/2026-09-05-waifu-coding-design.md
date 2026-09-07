# Waifu Coder (waifu coding) — design

**Date:** 2026-09-05
**Status:** Signed for PR #233. Target is **OpenCode-class power + a real V2-card personality**, not a toy slice or a bland agent with a portrait.
**Branch intent:** `Rawhide` via a dedicated feature branch (not bolted onto RP chat)
**Audience:** implementing agents. The maintainer cannot read Dart.
**Web:** **deferred in this conversation** — desktop only. Quote: “no web, defer that.”

---

## 0. Honest go / no-go (read this first)

### Will it actually work?

**The coworker part will work.** Taking a V2 card’s name, description, personality, and how she talks, and using that as the system prompt of a coding session, is a small, well-understood job. A tsundere reviewing a patch is not a research problem.

**The harness is the product, and it is only as good as the model.** OpenCode and Claude Code feel “real” because people point them at Claude / GPT-class (or similarly tool-fluent) models and let them **loop**: read, edit, run, read the failure, edit again. Front Porch already has `generateWithTools`. A Dart loop around that is not magic and not a 50,000-line rewrite. It is also not Claude Code.

| Backend | What you should expect |
|---|---|
| Remote, tool-fluent (OpenRouter Claude / GPT / large GLM, etc.) | Genuinely useful: she works a ticket, patches, verifies, and speaks as the card while doing it. Both work and voice are required. |
| Local Kobold, small/medium GGUF | Often a **mess**: skipped tools, half-edits, confident lies. Front Porch already knows local models struggle with long fused tool prompts. Do not ship Waifu Coder as “it works on Tiny-Porch-GGUF.” |
| Tools unsupported (XML-only / probe miss) | Mode is **inert**. Plain message: this model cannot do Waifu Coder. No fake file edits. |

If the bar is “OpenCode quality on every local install,” **do not build this.** You will get a buggy mess and you will be blamed for the model.

**Maintainer bar (2026-09-05):** a usable *optional fun* feature that might actually get work done. OpenCode is loved; the missing piece is personality — not a blank “I asked you to do a thing and you did it,” but the card’s voice *while she does it* (“Well well, you want me to do that for you? why not do it yourself?” — and then she still writes the patch). That bar is **worth building.** It is not Claude Code. It is Waifu Coder.

### What would make it a buggy mess (and how v1 refuses)

- **One tool per send** (the old harness sketch). That is RP with a file API. Out.
- **No diffs.** If you only hear her voice, you cannot trust what she did to disk. v1 has a file/diff strip.
- **No honest path-scope choice.** Folder jail is the safer default; Whole-disk access is available only after the Sit-down gate plainly says the chosen folder is a starting porch, not a fence.
- **Silent writes.** Every write is a receipt; git is the undo if the folder is a repo.
- **Pretending Porch Life is off while ChatService still ticks Needs.** Waifu Coder is a **separate pipeline**. It must not construct a chat session.

### Verdict

**Build it, sliced, as close to OpenCode as Front Porch law allows.** Do not spawn OpenCode. Do not enable web. Gate on tools support. Honesty gate on Sit down. Personality + real patches. Each slice in §15 must be testable alone.

---

## 0.1 What we cannot accomplish (do not bury this)

Say this in the room, not only in a doc. Waifu Coder copies OpenCode’s *job*. It cannot become OpenCode.

### Never

| OpenCode / industry thing | Why Waifu Coder cannot |
|---|---|
| The `opencode` binary, Bun server, TUI, VS Code / ACP, their desktop app | Sidecar retirement. Flutter is the UI. |
| Silent auto-download of an LSP **zoo** (every language, no ask) | Same class as surprise sidecars. **Opt-in one language after a prompt is allowed** — see §6.5. |
| stdio MCP (`npx` playwright, etc.) | Process spawn. HTTP/SSE MCP we already have is the only MCP door. |
| OpenCode Zen, hosted Exa/Parallel `websearch` with no key | Their SaaS. Waifu Coder uses Front Porch’s model + existing web search if we wire it. |
| Share transcript to opencode.ai | Cloud share. Out. |
| JS plugins / custom tools that run arbitrary JavaScript | No JS runtime in the Dart app. |
| Waifu Coder on web/phone | Maintainer deferred this conversation. |
| Claude Code / Grok Build reliability | Honesty gate. Especially local small GGUF. |
| Critical / production / this-app codebases | Product law. Fun throwaway folders only. |

### Deliberate v1 boundaries

| Thing | Later slice? |
|---|---|
| Bounded nested tasks | Included: parent → child → grandchild, then stop. No separate Scout product and no infinite tree. |
| Opt-in LSP catalog: many languages, **user opens each door** (detect → ask, or a list of toggles). Custom “run this binary” for anything not in the catalog | Yes, slice I. Never silent-download the set. |
| Formatter plugin registry | No. Run the project’s formatter via `bash` after edits. |
| Independent model picker inside Waifu Coder | No. Settings backend is the model. |
| Whole-disk paths | Included as an explicit Sit-down choice; Folder jail remains the default. |
| Parallel workflow steps | Included within the existing bounded workflow budget. |

### Close enough (this is the actual target)

OpenCode built-ins we **do** take, in Dart, over slices: `bash`, `edit`, `write`, `read`, `grep`, `glob`, `apply_patch`, `todowrite` / `todoread`, `webfetch`, `question`, `skill` (project `SKILL.md`), Plan / Build / Yolo (`--auto`), ask / allow / deny (once / always / reject), doom-loop guard, `.env` deny, AGENTS.md `/init`, undo/redo of her file writes, `@file` mentions, context compaction, session resume, abort, HTTP/SSE MCP (existing client).

---

## 1. Product

**Waifu Coder** is a third home mode, sibling of **Chats** and **Porch Stories**.

You pick a folder on disk (in-app walker, not the OS file picker), pick a character from the library, and sit down. She is a coding agent whose personality is that V2 card. You talk in a chat-shaped UI. She **loops** tools against that folder until the task is done or you stop her.

This is **not** a chat with extra tools. Opening Waifu Coder does not create a `sessions` row, does not run Realism, Journal, Needs, weather, clock, Chaos, Pockets, Growth, Objectives, RAG, or web search. Those stay in Chats.

Pitch (maintainer, 2026-09-05): *OpenCode but with characters and personalities driven by the character cards, so you can do work with your tsundere anime characters.*

**Why this exists (same conversation):** OpenCode (and most coding agents, Grok included) will do the work and have **no personality**. Waifu Coder is the same *kind* of work, with the V2 card as the coworker: sass, warmth, tsundere — *and* the file still gets written. Personality is not a wrapper after the fact and not an excuse to skip the tools.

Two failure modes, both ship-blockers:

| Failure | What it looks like |
|---|---|
| OpenCode with a portrait | She does the work in bland assistant-voice. The card was wasted. |
| RP with a file API | She sasses and never calls tools. Cute, useless, maybe dangerous if she *claims* she edited. |

Success is **both**: the test file exists on disk, **and** the bubble sounds like her.

### Why a separate tab

Porch Stories already proved the pattern: a different job gets a different home mode, not a toggle inside chat. Mixing a tool loop with hunger decay and diary passes is how the feature becomes a joke that fights the work.

---

## 2. Non-goals (v1)

- **Web / phone.** Deferred by maintainer in this conversation. Desktop only. A Waifu Coder button in `web_ui/` is a parity violation unless a later conversation re-opens it.
- **Spawning OpenCode, Bun, Node, or LSP servers.** Sidecar retirement still holds. We copy OpenCode’s *loop shape*, not the process.
- **FP as an MCP server.**
- **Stdio MCP spawn.** The existing HTTP/SSE MCP client is included as an opt-in; stdio remains out.
- **JS custom tools, OpenCode plugins, Zen, cloud share, LSP auto-install, stdio MCP.** See §0.1.
- **Unbounded or separately branded Scout trees.** Bounded Explore/General task delegation is included; the deepest worker cannot spawn again.
- **Sandbox / container isolation.** Folder jail is path/realpath enforcement, not a VM. Whole-disk is explicit. Neither mode may bypass secret and wipe hard stops.
- **Native Windows shell translation.** The v1 command tool is bash-only. On
  Windows it needs Git Bash or another `bash` on PATH; otherwise the existing
  failed-to-start result is returned and read/edit/apply_patch/write still
  work. PowerShell/cmd rewriting is deliberately out.
- **Destructive git** (`checkout --`, `restore` that discards uncommitted work) — same law as the rest of the app.
- **Using scenario, lorebook-as-world, example messages, or Front Porch realism extensions as the coworker.** Card identity only (see §5).
- **One-shot tool round** as in search/MCP chat.

---

## 3. Entry: home mode + wizard

Home toolbar today: **Chats | Porch Stories**. Add **Waifu Coder**.

Same Create Character chrome: AppBar step dots + labels + connecting lines, `AnimatedSwitcher` on a `_currentStep` int, nav buttons at the bottom. Linear. No side menu.

| Step | Name | What happens |
|---|---|---|
| 0 | **Project** | In-app disk browser. Start at a remembered last folder (or home / documents). List directories (and a parent `..`). Tap a folder to enter it. **Use this folder** confirms. Show a hint when `pubspec.yaml` / `.git` / `package.json` / `Cargo.toml` is visible — those are likely projects, not a requirement. **Not** `FilePicker.getDirectoryPath`. |
| 1 | **Coworker** | Library grid of characters (same cards as home, no Porch Life badges required). One tap selects. Preview: name + portrait + a one-line personality clip. |
| 2 | **Sit down** | Recap: folder, coworker, backend/model, starting mode (**Build**), and path scope: **Folder jail** (safer default) or **Whole-disk access**. If tools are unsupported, **cannot continue**. The required honesty copy branches with scope; changing scope clears the checkbox. Confirm is dead until the current copy is accepted. |

**Honesty gate copy (Sit down — do not soften):**

> Waifu Coder gives the selected coworker real read/search/patch/write/bash/test tools and visible receipts while they speak as the card. Folder jail is the safer default and keeps paths on the project porch. Whole-disk makes that porch a starting point, not a fence: absolute paths, `~`, `..`, and `cd` can reach anything the account can.
> Both modes retain secret, destructive-Git, force-push, and machine-wipe hard stops. This is its own powerful harness, not a promise that every model matches Claude Code, Grok Build, OpenCode, or Cursor. Models can still be confidently wrong. Never use it on a critical codebase; guardrails are not a backup.

Checkbox (must be on to continue) repeats the selected scope. Whole-disk explicitly acknowledges that Waifu Coder can read or change files elsewhere.

Starting mode on this step: Plan / Build / Yolo, default **Build**. Yolo copy branches: Folder jail says the jail still holds; Whole-disk says she can roam and never claims a jail.

Cancel / back to home at any step. No Waifu Coder session is created until Sit down confirms.

Recent porches (folder + character id) appear on the home grid for “sit down again.”

---

## 4. Session UI

**Chat chrome, work guts.**

Reuse the *look* of chat: her portrait, bubbles, composer, porch amber. Do **not** reuse `ChatService`, `ChatPage` orchestration, or message tables.

Required surfaces:

- **Transcript** — her lines and yours. Tool calls are chips on **her** bubble (file written, command run, ok/error), not a dump of JSON or a stack trace in the bubble body. She may talk about the work in character.
- **Work strip** (right or bottom, desktop-width): current folder name, list of files touched this turn, a simple before/after or patch view for the last write. Without this, Waifu Coder is untrustworthy.
- **Mode** — Plan / Build / Yolo, always visible. Default Build. Changing mode applies to the **next** tool, not a tool already running.
- **Abort** — visible while a loop is running. Kills active bash across nested workers and stops further tools; it does not roll back completed writes.
- **Confirm** — in Build (and never in Plan; skipped in Yolo): a modal *before* a mutating tool runs. Plain: what she wants to do, the path or command, **Allow once** / **Deny**. Deny returns a tool error she can narrate (“you wouldn’t let me”). The loop may continue or she may stop.
- **No** Character State, Journal, Needs, weather chip, Chaos, MCP chat toggles, Continue-as-RP.

Composer: you type a task (“fix the empty-email test”). Send starts a loop, not a single generate.

### 4.1 Plan / Build / Yolo

Same idea as OpenCode. One session, three permission gears — not three personalities. The card does not change.

| Mode | She can | She cannot | Asks “are you sure?” |
|---|---|---|---|
| **Plan** | `read`, `glob`, `grep`, `todoread` | `edit` / `write` / `apply_patch`, `bash`, `todowrite` | N/A (nothing mutates) |
| **Build** (default) | Full catalog inside the selected path scope | Hard-deny list (see §6.3) | **Yes** on mutate: Allow once / Always this session / Deny |
| **Yolo** | Same as Build | Same hard-deny list | **No** (OpenCode `--auto`). Selected scope + hard-deny still apply |

Yolo is “stop asking,” not “no safety.” Switching into Yolo from the session chrome repeats a one-line warning; it does not re-tick the wizard checkbox.

Plan is how you let a chaotic local model *look* without letting it save. Build is how a human stays in the loop. Yolo is for throwaway folders when the clicking is the annoying part.

---

## 5. Personality (the card)

The card block sits above the short coding constitution, in this order:

1. `Name`
2. `Persona`: non-empty `personality`
3. `Vibe`: `description` even when Persona exists, clipped to 400 characters
4. non-empty `systemPrompt` inside an author-voice fence: voice/values only, never tool, safety, path-scope, or task control; never an RP scene to continue
5. one or two clipped `mesExample` diction slices
6. today’s date

**Do not inject:** `scenario`, lorebook, worlds, `firstMessage` as an RP greeting, Front Porch extensions (bond, needs, occupation, pockets, …), Journal, RAG.

Add a short charm-first coding constitution (not the card):

> Stay in the card’s voice while doing real work. Sass is welcome; refusing the task is not. Read first, put changes on disk with tools, tell the truth about results, and keep the visible bubble to one in-character spoken line — no source dump and no make-believe scene.

Lookup/current-version instructions, bounded task delegation, built-in-before-MCP preference, and selected path scope live in the loop user prompt, not duplicated in the system constitution.

That is the whole “waifu” layer. If the harness is solid, this is enough. If the harness is weak, more prompt poetry will not save it.

**Poke that proves the product:** sit down with a tsundere card, ask for a small file change, and you get both (1) the file actually changed and (2) a line in her voice, not a generic “I’ve updated the test for you.” If you only get (1), Waifu Coder is OpenCode with a portrait. If you only get (2), ship is blocked.

---

## 6. Harness (the loop)

### 6.1 Shape (stolen from OpenCode, implemented in Dart)

1. User sends a task.
2. Build a catalog matching OpenCode’s practical core: `read`, `edit`, `apply_patch`, `write`, `glob`, `grep`, `bash`, todos, web fetch/search, question, skill, bounded task/workflow, and opt-in HTTP/SSE MCP. Git rides bash with destructive operations denied.
3. `generateWithTools` with that catalog (`tool_choice: auto`).
4. If no tool call + text → that text is her reply. Loop ends.
5. If tool call → enforce Plan/Build/Yolo, MCP mutation classification, secret/wipe hard stops, and the selected path scope. Built-in file tools win MCP name collisions. `apply_patch` performs an exact one-file structured edit and records before/after bytes.
6. Stop when: she produces final text, user hits Abort, the 80-step runaway fuse trips, or a repeated identical failing command is denied. Abort kills every active bash process, including nested/parallel workers.

**Work + voice completion contract:** a request that clearly asks for a code/file
change is not complete until a write/edit/apply_patch receipt lands. Character
sass without a mutation is retried, then shown as a red failed turn rather than
a false success. After successful tools, empty or generic “Done” text gets a
tool-free voice retry. Character speech emitted beside a tool call is retained
as the fallback, so one assistant bubble always finishes with a spoken line.

This is the opposite of search/MCP v1’s “one round then stream.” Waifu Coder **is** the loop.

Regen in Waifu Coder: abort in-flight loop; do not re-apply the last patch automatically. Delete: session transcript only, disk unchanged.

### 6.2 Model

Same `LLMProvider` as the rest of the app (whatever is launched in Settings). No second model picker in v1 unless Sit down needs to show the name.

**Hard gate:** if `ToolTransportProbe` / tools unsupported, Sit down cannot start a loop. Same honesty as search: no tools → feature inert.

### 6.3 Execution and permission layers

Three layers. They stack. Yolo only turns off layer 3.

1. **Path scope (always).** Folder jail confines lexical paths, realpaths/symlinks, and bash path arguments/cd to the selected root. Whole-disk permits absolute, `~`, `..`, and cd-out. The default is Folder jail and the session persists the choice.
2. **Hard deny (always, including Whole-disk + Yolo).** Block `.env`, `.ssh`, `.aws`, parent environment dumps, destructive Git/force-push, recursive root/home/system/ancestor deletes (with or without `-f`, quotes, or nested `bash -c`), `find … -delete` on broad roots, format/wipe/device commands, permission bombs, and obvious recursive Python wipes. Normal project reads, patches, writes, tests, and scoped cleanup remain available.
3. **Ask (Build only).** Mutating tools pause for Allow / Deny. Reads never ask. Plan never reaches this layer because those tools are not in her catalog.

- `write_file` / patch: record before-bytes for the work strip. Prefer patches over whole-file overwrite when the model emits a patch; whole-file allowed for new files.
- Git tools only if `.git` exists under root. Commit is allowed in Build (after ask) and Yolo; rewrite/history destroy is not, ever.

No `Process` for an OpenCode/Bun **agent** binary. `Process.start` for the user’s command is “run tests,” not a sidecar. It receives an explicit development-path environment allowlist, never the Front Porch parent environment.

### 6.5 Language servers: many doors, user opens them

**Audience (maintainer, 2026-09-05):** Waifu Coder is an **advanced** feature. Not every user will touch it; do **not** design it for first-run noobs. Dense UI, long language list, PATH, checksums, custom command — fine. Do not hide power behind a wizard that talks down. The honesty gate (not Claude Code, not critical repos) stays blunt because it is **safety**, not onboarding.

**Policy (same conversation):** do not restrict the user’s language. The GitHub app zip still ships **zero** LSPs (RAG-shaped). A **catalog** lists as many languages as we can pin. Sitting down never downloads the set. Each language is a **door the user opens**.

**Catalog** (in-app metadata only — names, extensions, project markers, per-OS download URL + checksum, or `PATH` command). Aim at OpenCode’s built-in coverage and then some, for example: Dart/Flutter, GDScript/Godot, Python, TypeScript/JavaScript, TSX, Vue/Svelte/Astro, JSON, HTML/CSS, Rust, Go, C/C++ (clangd), C#, Java, Kotlin, Swift, Ruby, PHP, Lua, Bash, Zig, Nim, Haskell, Elixir, Erlang, Scala, OCaml, F#, PowerShell, YAML/TOML, Markdown, SQL, Protobuf, Terraform, Nix, Solidity, Gdshader, WGSL, etc. Growing the catalog is additive and cheap; **fetching** is not. A language with no trustworthy pin stays in the list as **“bring your own binary.”**

**Detection (shortcut, not a tutorial):** after Sit down, peek at extensions + markers. Matching catalog rows can be **pre-highlighted** on the Language help list (still off until they toggle). No cartoon “it looks like you might be writing Godot!!” interstitial. Power users who already know can open **Language help** and flip whatever they want, including languages the detector missed.

**Language help:** the full catalog as toggles, searchable. Off = not downloaded. On = download that one (or use PATH if present). Enable Rust on a Godot folder if you want. Enable nothing. Show install path, checksum, and binary name — this audience can read that.

**Custom door:** “Command to run” + args + file extensions. For Holy C, brainfuck, or a fork we don’t pin: they point at a binary they already trust. We do **not** search GitHub for an unofficial Holy C LSP and fetch it. Unknown + no custom command → “No language server on file. You can add one below or just edit.”

**PATH first:** if `rust-analyzer` / `godot` / `dart language-server` is already on the machine, the toggle says **Use installed** and does not download.

**Runtime:** only **enabled** servers spawn, and only for the current Waifu Coder session. Disable = kill process, keep the bits on disk (like an unused RAG model). Uninstall = delete the bits. Yolo does **not** auto-open language doors.

**Never:** download the catalog’s artifacts on install, on first Waifu Coder open, or because one `.md` file exists; spawn a server the user did not enable; treat a failed download as “try a random npm package.”

### 6.4 Failure

Command non-zero, file missing, or path-scope miss → tool result tells the model the truth. She should retry or admit it. Empty/broken tool round → she says she could not work; **no invented patch**.

---

## 7. Architecture (where it lives)

New island. Do not grow `ChatService`.

| Piece | Role |
|---|---|
| Home mode + wizard | UI only; Create Character step pattern |
| In-app folder walker | `dart:io` `Directory.list`; remember last path in prefs |
| `WaifuSession` | folder root, character id, transcript, last patches, step count |
| `WaifuHarness` | loop, catalog, dispatch, selected path scope, abort ownership |
| `WaifuLlm` | thin over existing `LLMService.generateWithTools` |
| Persistence | own table or JSON under the data dir — **not** `messages` / `sessions`. Deleting a character does not have to delete Waifu Coder history in v1 (document that). |

500-line cap, barrel under `lib/services/waifu/` and `lib/ui/waifu/`. AppColors / porch amber. No `Colors.blueAccent`.

Reuse: `generateWithTools`, character library grid, theme. Do **not** reuse chat send/Continue/realism post-gen.

MCP is double-gated and defaults off. Waifu Coder's checkbox can only expose
servers already present in the active character chat's
`mcpEnabledServerIds`; a global server switch alone is not consent. Front
Porch file tools win name collisions. Plan blocks inferred MCP mutation, Build
asks, and legacy SSE endpoint events must remain on the configured origin
before credentials can be reused.

---

## 8. Path-complete (Waifu Coder-specific)

Chat turn-event matrix is **N/A** (no ChatService). Waifu Coder events:

| Event | Behaviour |
|---|---|
| Send task | Start loop; chips + work strip update live |
| Abort | Kill in-flight bash across nested workers; no further tools; disk remains at the last completed write |
| Regen | Not RP regen. v1: disabled or “abort + same prompt as a new loop” — pick one in implementation plan, do not silently reuse chat regen |
| Continue | **Off.** There is no Continue control. A new send is a new loop (with transcript as context). |
| Delete last turn | Transcript only |
| Leave Waifu Coder | Loop aborts; folder unchanged except what she already wrote |
| Tools unsupported | Cannot sit down |
| Plan + write/run | Tool error; nothing on disk |
| Build + mutate | Modal; Deny = tool error, disk unchanged |
| Yolo + mutate | Runs if selected path scope + hard-deny pass |
| Yolo + `git checkout --` | Still refused |

Twins: none on web (deferred). MCP chat catalog is a sibling, not this pipeline.

---

## 9. Tests (prove red, then green)

- Folder jail: parent/absolute/symlink escapes and bash cd-out fail. Whole-disk: ordinary parent/absolute/symlink paths work. Secret realpaths fail in both.
- Deny-list: `git checkout -- .` is not executed.
- Loop: scripted LLM that calls `read_file` then final text → two `generateWithTools` calls, one read, then stop.
- Max steps: 20 identical tool calls then stop; no infinite loop.
- Tools unsupported: Sit down blocked.
- Card: prompt contains personality; does **not** contain scenario / needs / journal.
- Wizard: step indicator is the Create Character pattern (dots + linear nav); folder step does not call `FilePicker`.
- Honesty gate: Sit down Confirm is disabled until the checkbox is ticked; copy names Claude Code / Grok Build / OpenCode and “never on a critical codebase.”
- Home: Waifu Coder is a sibling of Porch Stories, not a chat sidebar switch.
- Plan: a scripted `write_file` does not touch disk.
- Build: a scripted `write_file` does not touch disk until Allow; Deny leaves the file absent.
- Yolo: a scripted write inside scope runs with no modal; `git checkout -- .` still does not run.
- `apply_patch`: exact hunk succeeds atomically; ambiguous context and out-of-scope paths fail.
- MCP: Plan blocks inferred mutation, Build asks, read-only lookup remains useful, built-in FS wins collisions, and SSE endpoint events cannot pivot credentials off-origin.
- Photos: PNG/JPEG/WebP only; compressed bytes and decoded dimensions are bounded before decode/inbox write.

The signed dual-scope decision makes the old single-jail assertions false; those existing tests are deliberately rewritten and require the protected-test approval already attached to #233.

---

## 10. Web

**Not in this body of work.** Maintainer deferral, this conversation: “no web, defer that.”

Desktop-only is incomplete vs the standing parity law; the deferral is the exception. Implementing agents must not add a Waifu Coder page in `web_ui/` “while they are here.”

---

## 11. OpenCode

We do **not** vendor, spawn, or HTTP-attach OpenCode.

We **do** copy the user-visible coding agent: loop, tools in §0.1 “close enough”, Plan/Build/Yolo, permissions (ask/allow/deny, once/always/reject), undo/redo, AGENTS.md, skills, todos, question, compaction, @files, abort, diffs.

We **do not** copy: their process, JS plugins, Zen, share, TUI, ACP, stdio MCP, or an unbounded agent tree. Plan/Build/Yolo are permission gears on one card-driven coworker. Bounded task delegation ships now.

Yolo = OpenCode `--auto`: skip asks, never skip hard denies or the selected path scope.

---

## 12. Ship bar (v1)

Waifu Coder is shippable when:

1. Wizard (folder walker + character + sit down) works on macOS, Windows, Linux. Sit down cannot proceed without the honesty checkbox. The copy says this is not Claude Code / Grok Build / OpenCode and must not be used on critical code.
2. A tool-fluent remote model can complete a small real task (e.g. add a test, run it, fix fail) inside a throwaway folder, with diffs visible. Plan cannot write; Build asks; Yolo writes without asking and still cannot `git checkout --`.
3. The same session, with a card that has a strong personality, **sounds like the card** in the bubbles — not a generic coding assistant. Sass + a real patch is the win. Sass with no patch, or a patch without their voice, is not.
4. Both path modes, structured patching, abort-kill, and ruthless hard-denies are red-then-green.
5. Local/XML-only backends cannot silently wreck a folder.
6. Hostile self-review written. No ChatService ticks. No web. Optional **advanced** fun: Waifu Coder is not the default home mode, does not nag, and does not talk down. Honesty gate stays; kindergarten copy does not.

It is **not** shippable because “the tsundere talks.” Talk without a trustworthy loop is the old harness sketch. It is also **not** shippable as silent OpenCode.

---

## 13. Spec self-review

- Placeholders: none material. Recent-waifus is optional.
- Consistency: separate pipeline vs chat, no OpenCode process, web deferred, loop not one-shot — agreed throughout.
- Scope: all A–I core capabilities plus two-level task delegation land in #233; silent LSP-zoo install remains out.
- Ambiguity closed: Continue/regen are not RP controls. Folder jail defaults; Whole-disk is explicit and persisted. Hard-deny always applies; ask is Build-only. Success = work **and** voice. Honesty gate required. Yolo never lies about scope.

---

## 14. Approval gate

CoS signed the full Waifu Coder #233 scope on 2026-09-07. The feature ships in one squash after every MUST and hostile review pass; no core capability is deferred post-merge.

---

## 15. Sliced bodies of work

Each slice is its own PR-sized job. **Do not start slice N until N−1 is green** (automated tests + the poke). No slice includes `web_ui/`. No slice spawns OpenCode. Slice I is the only slice that may download/spawn an LSP, and only after an explicit Yes.

### Slice A — Home + wizard + honesty (no tools yet)

**Done when:** Chats | Porch Stories | **Waifu Coder**. Wizard: Project (in-app walker, not FilePicker) → Coworker → Sit down. Confirm dead until honesty checkbox. Tools-unsupported blocks Sit down. Opens an empty session chrome (portrait, composer, no loop).

**Automated:** wizard steps; FilePicker not called; checkbox gate; card fields in a stub prompt (no scenario/needs); home toggle.

**Manual poke:** open Waifu Coder, walk to a throwaway folder, pick a card, cannot continue until the box, then land in an empty Waifu Coder that does not tick Needs.

### Slice B — Jail + harness loop + core files

**Done when:** Send runs a loop with `read`, `edit`, `apply_patch`, `write`, `glob`, and `grep`. Folder jail rejects parent/absolute/realpath escape; Whole-disk allows ordinary roaming. The 80-step fuse and user Abort stop work; Abort kills active bash. Work strip shows the last structured edit.

**Automated:** jail red/green; loop read-then-stop; max-steps stop; write records before-bytes; prompt has personality, not scenario.

**Manual poke:** throwaway folder, remote tool-fluent model, “add a hello.txt”. File exists **and** she sounds like the card.

### Slice C — Plan / Build / Yolo + confirms

**Done when:** Mode control on session. Plan cannot mutate local or MCP state. Build asks Allow once / Always / Deny. Yolo skips ask. Both path scopes hard-deny protected secrets, environment dumps, destructive Git, force-push, and broad wipe/disk/permission commands. Doom-loop: identical tool 3× → ask even in Yolo.

**Automated:** Plan write does not touch disk; Build write waits; Deny = no file; Yolo write no modal; Yolo still refuses `git checkout --`; doom-loop trips.

**Manual poke:** Build, watch the modal; Deny; switch Yolo, watch no modal; try a denied git command, she complains, disk ok.

### Slice D — bash + undo/redo

**Done when:** `bash` starts at project root, follows the selected path scope, receives a scrubbed environment, times out, clips output, and is killed by user Abort. Undo restores Waifu Coder writes (not git reset of user work); Redo reapplies.

**Automated:** Folder-jail bash cannot cd out; Whole-disk bash can; timeout and parent/nested Abort kill; parent API keys never appear; undo restores file bytes.

**Manual poke:** “run ls”; then “write foo”; Undo, foo gone; Redo, foo back.

### Slice E — todos, question, @files, AGENTS.md, skills

**Done when:** `todowrite`/`todoread` visible as a list. `question` shows choices. `@` fuzzy-picks project files into the prompt. `/init` writes `AGENTS.md` (after ask in Build). `skill` loads `.waifu/skills/**/SKILL.md` or `.opencode/skills` / `SKILL.md` if present.

**Automated:** question pauses loop until answered; @path appears in next generate; skill file contents injected; init does not write without ask in Build.

**Manual poke:** “what should we name the helper?” she asks; you pick; she continues. Drop a SKILL.md, she can load it.

### Slice F — webfetch, FP web search, HTTP MCP

**Done when:** `webfetch` is no-redirect/clipped/untrusted. Optional web search reuses Front Porch. Existing HTTP/SSE MCP tools join only after per-session opt-in. Folder-jail copy says MCP servers are beyond its boundary; Whole-disk copy says access is already open. Cross-origin SSE endpoint pivots are rejected before an authenticated POST.

**Automated:** webfetch refuses redirect; search uses FP service; MCP tool not advertised unless opted in.

**Manual poke:** look up a doc URL; if an MCP server is connected, one harmless tool.

### Slice G — compaction, session resume, polish

**Done when:** long session summaries instead of dying at context. Resume last Waifu Coder (folder + card + transcript). Compaction does not invent files. Title on the session.

**Automated:** over-budget transcript is compacted; resume restores folder+card.

**Manual poke:** leave Waifu Coder, come back, same folder and her, history there.

### Slice H — subagents (only after A–G)

**Done when:** Explore (read-only) and General inherit the selected path scope. A child may spawn one additional Explore/General task; the grandchild cannot spawn again. Parent Abort recursively stops children and all active bash processes. There is no separate Scout-branded product.

**Automated:** nested Explore cannot write; Folder-jail children cannot escape; Whole-disk children can read an ordinary sibling; task exists at depth one and disappears at depth two; parent Abort kills nested bash.

**Manual poke:** “have explore find the auth entrypoint” then she uses that to edit, still in character.

### Slice I — language doors (after D; does not block A–G)

**Done when:**
- In-app **catalog** of many languages (metadata only in the app). Waifu Coder → Language help: every entry is a toggle. Off = nothing fetched.
- Detect-on-sit-down suggests **matching** doors (checkboxes, none pre-ticked). User opens zero, one, or several.
- Yes on a pinned entry downloads **that** artifact (URL + checksum) into the data dir. PATH-installed offered first.
- Custom door: command + args + extensions; no GitHub scrape.
- Holy C / uncatalogued: no download; custom door or skip. Edit/bash still work.
- Only enabled servers spawn; session end kills them; Yolo does not auto-enable.

**Automated:** no toggle → zero HTTP on Sit down; Godot marker → suggestion copy includes Godot, not Rust; enabling one entry does not fetch others; checksum fail → do not spawn; custom command is what we exec (no rewrite); disable stops the process.

**Manual poke:** Language help shows a long list, all off. Open a Godot folder → suggest GDScript, skip, still edit `.gd`. Enable Python only → one download. Add a custom command for something weird. Confirm Rust did not download.

### Out of all slices

Silent fetch of an LSP zoo, stdio MCP, OpenCode binary, web/phone Waifu Coder, JS plugins, Zen, share, critical-repo blessing, unbounded task trees, or fetching an unpinned “Holy C LSP” from a random repo.

---

**#233 ship rule:** every core slice above, focused security tests, hostile review, and the manual poke checklist must exist before the single squash. No core item moves to a post-merge follow-up.
