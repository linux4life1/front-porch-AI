# Waifu Coder = managed OpenCode + card (UI kept)

**Branch:** `feat/waifu-opencode-managed`  
**Worktree:** `/Users/linux4life/dev/fpai-waifu-opencode`  
**Base:** Rawhide `a41628ec` (Belt B tip — keep the chrome, kill the Dart gym)  
**Status:** Implement this. No Belt C. No Dart verify-theater.

Maintainer cannot read Dart. Talk in product terms in comments/changelog.

## Goal

Porch **owns** OpenCode the way it owns Kobold: download on first use, not in the app bin, start/stop/upgrade, HTTP to the engine. The existing Waifu **UI** stays. The Dart tool loop dies.

Success: sit-down with a V2 card → she tools through OpenCode → files land → bubbles sound like her.

## Non-goals

- Do not ship OpenCode inside the Flutter binary / dmg.
- Do not use the user's Homebrew OpenCode, `~/.config/opencode`, or oh-my-opencode as the product copy (Sisyphus landmine).
- Do not keep a Dart fallback loop “just in case.”
- Do not mix Chats realism/Needs/lorebook into the coder prompt.
- Do not spawn OpenCode for normal chat.
- Web/phone Waifu still deferred.

## Architecture (pictures)

- **Stage:** `lib/ui/waifu/**` — keep. Composer, photos, sit-down, Jail/Disk, chips, plan chrome, abort.
- **Gym:** OpenCode binary in app-support closet, `opencode serve` on 127.0.0.1.
- **Remote:** thin Dart **client** (health, session, prompt, SSE/events, abort, permissions). Not a second agent.
- **Costume:** at sit-down, create/select a primary OpenCode agent whose system prompt is card name + personality + speech. Tools still allowed. One line: if joke vs write, write.

## Closet (Kobold-shaped)

Mirror `BackendManager` + `KoboldService` patterns, new types, don't stuff Kobold files.

- Path: same family as Kobold bin — app support / `FrontPorchAI/opencode-bin/` (use existing storage roots; do not invent a second Documents tree).
- First sit-down: if missing, download GitHub release asset for this OS/arch (`opencode-darwin-arm64.zip` etc.), show progress, unpack, chmod +x.
- Pin a **known-good version** in one constant (start with a current stable tag, e.g. 1.18.x). Record version file next to binary.
- Upgrade: Settings or Waifu honesty line — “OpenCode a → b, ~44MB.” User taps. Swap binary. Never auto-latest on launch.
- Start: `opencode serve --hostname 127.0.0.1 --port <free>` with `OPENCODE_CONFIG` / `--print-logs` as needed so config is **only** our directory (isolated from `~/.config/opencode`).
- Health: `GET /global/health` before any session.
- Stop: leave Waifu / app quit → kill **our** PID. Never kill brew `opencode`.
- Optional later: “attach to already-running serve.” Not v1.

## OpenCode config we generate (isolated)

On start, write a config **in our closet**:

- Model = Porch's current backend (OpenAI-compatible URL + key the app already has — oMLX / OpenRouter). One picker: Settings. No second model UI.
- Default agent = `waifu` (primary).
- `waifu` agent prompt = coworker card fields only (name, description, personality, speaking style). Plus: you are a coding agent; use tools; do not roleplay skipping edits; no lorebook/Needs/weather.
- Permissions: Folder jail → restrict to sit-down cwd. Disk → broader, still honor secret/wipe hard stops if OpenCode exposes equivalent; if not, document the gap in honesty chrome, don't fake Dart deny.
- Plan/Build: map existing mode bar to OpenCode plan vs build agents if that's the native switch; don't reimplement Plan YAML in Dart.

## UI wiring

- `WaifuHarness.send` (and friends) become a client that:
  1. Ensures binary + process + health
  2. Ensures session for this porch folder
  3. Forwards user text + queued photos if the OpenCode API accepts image parts; if not, honesty: “photos not in this OpenCode version” — don't lie
  4. Streams assistant text + tool events into existing transcript/tool-log/todo widgets
  5. Maps permission asks to existing ask dialogs
  6. Abort → session abort
- Keep session store/sidebar if it's UI state. Don't persist a fake Dart ledger of “tested=”.
- Sit-down wizard stays. After confirm, handshake as above.

## Rip the slop

Delete or stub-to-gone (no silent reimport):

- Verify theater / maven / families / compact ledger as **policy**
- Turn contract “tested=” gym
- Bash/fs/deny/patch/tools/workflow as the **engine** (OpenCode has these)

Keep only:

- UI
- Session list / store that's chrome
- Coworker prompt **builder** (card → agent prompt string)
- Brand/honesty copy that we rewrite to “OpenCode is the gym”
- Image/composer helpers that are UI

Tests: delete belt A/B mole farms that pin theater. Replace with:

- Client unit tests against a fake HTTP OpenCode (health, session, prompt stream)
- Binary manager tests (version pin, path, don't touch brew)
- One widget test: send still paints user line then awaits (existing CoS)

`flutter analyze` on touched paths. Do not `dart format .`. Do not touch pubspec version.

## Law / CLAUDE.md

Add a short note: Waifu Coder may manage an OpenCode binary like Kobold (download, start, stop). It is not a chat sidecar. Do not reintroduce a Dart coding loop.

Changelog: human prose — Waifu Coder now uses OpenCode as a managed engine; Dart harness retired.

## Order of work (do not skip)

1. Isolated OpenCode manager (download/start/health/stop) + fake-server tests. No UI yet.
2. Thin HTTP client: session + prompt stream into a dumb sink.
3. Card → agent prompt; sit-down handshake.
4. Wire existing UI to client; rip harness call sites.
5. Delete dead gym files + belt tests that no longer compile.
6. Analyze + unit tests green on touched/remaining waifu tests.
7. Changelog + honesty strings.

If OpenCode HTTP field names differ from docs, **read live `/doc` from a running serve** — do not invent.

## Out of this PR

- Bundling Node
- OMO/Sisyphus
- Web Waifu
- Dependabot
- Belt C flags
