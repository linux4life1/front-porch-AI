# Web UI ⇄ Desktop Parity Checklist (W8 sign-off)

This is the parity sign-off for the React/TypeScript web UI (`web_ui/`, served by
`lib/services/web/`) against the native Flutter desktop app. It is the authoritative
"desktop feature → web status" map called for by **W8** of the web-rewrite roadmap.

**Scope of "parity":** desktop/tablet ≈ 1:1 with the desktop app; phone = same
capabilities, adapted (drawers/sheets/overflow), never silently dropped. The web
layer is a thin API over `ChatService`, the `chat/` leaves, and the repositories —
so the Realism/Needs 1:1↔group behavior is identical by construction (it is never
recomputed in the web layer).

## Legend

| Mark | Meaning |
|------|---------|
| ✅ | Full parity on the web (desktop/tablet); adapted on phone |
| ◑ | Present and usable, intentionally simplified vs desktop |
| ⚙️ | Works on the web, but first-time *engine/hardware setup* stays on desktop (by design) |
| ❌ | Out of scope — confirmed no-go (see bottom) |
| ⏳ | Decision pending (not built yet) |

## Chat

| Feature | Status | Notes |
|--------|:--:|------|
| Send / stream replies (WebSocket) | ✅ | Tokens stream over the single multiplexed `/api/ws`. |
| Stop / regenerate / continue | ✅ | |
| Swipes (alt generations) | ✅ | |
| Edit / delete message | ✅ | |
| Thinking (`<think>`) blocks | ✅ | Collapsible per message. |
| Author's note | ✅ | |
| Slash commands (`/join`, `/create`, `/promote`, `/speak`, `/exit`, `/turnorder`, `/scan`, `/expression`) | ✅ | Routed through `sendMessage`, identical to desktop; `/`-cheat-sheet popup included. |
| Inline images in messages (`![](url)`) | ✅ | `MessageContent` renders them (parity with desktop `ExternalImageWidget`). |
| Insert a generated image into chat | ✅ | "Insert into chat" in the image panel → appends to the latest message. |
| Sessions / conversations drawer | ✅ | List, resume, new. |
| Macros (`{{char}}`, `{{user}}`, …) | ✅ | Expanded server-side in `ChatService`, so web inherits them. |

## Realism & Needs

| Feature | Status | Notes |
|--------|:--:|------|
| Bond / Trust / Emotion / Arousal / Fixation / Spatial / Time display | ✅ | Read from session getters; focus-scoped per cast member. |
| 7 Needs bars | ✅ | |
| Per-message Realism + Needs chips | ✅ | From `metadata['needs_deltas']` etc. — never recomputed on the client. |
| Realism value edits | ✅ | Via the sidebar tools. |
| Chaos Mode pressure + Chance Time | ✅ | |
| NSFW toggle + cooldown | ✅ | |
| Objectives (view / generate / set) | ✅ | Focus-scoped to the selected participant. |
| Memory / RAG per-chat toggle | ✅ | The toggle is present; embedding-sidecar *setup* is desktop-only (no-go). |
| Scene / time set | ✅ | |
| 1:1 ↔ group behavioral parity | ✅ | Guaranteed: web never reimplements the simulation. |

## Characters

| Feature | Status | Notes |
|--------|:--:|------|
| Library grid (search / sort / folders) | ✅ | |
| Open / start chat | ✅ | |
| Manual creation wizard | ✅ | Step-indicator wizard mirroring `create_character_page`. |
| **AI character creator** | ✅ | `/create-ai`: describe → generate (live steps over WS) → editor. Thin driver over the existing headless `CharacterGenService`. |
| Edit character (all fields) | ✅ | |
| Per-character lorebook editor | ✅ | |
| Multi-avatar management + set prime | ✅ | Upload / remove / set prime. |
| Expression portrait (mood-driven) | ✅ | Swaps on `chat_updated`. |
| Import character card (PNG / .byaf) | ✅ | Upload → desktop import path. |
| Delete character | ✅ | |
| Avatar **crop** UI | ◑ | Upload replaces the avatar; in-browser cropping is not yet a dedicated tool. |
| Export character card | ⏳ | Not yet surfaced on the web. |

## Groups / Cast (unified model)

| Feature | Status | Notes |
|--------|:--:|------|
| Unified cast roster (host + guests/members) | ✅ | `CastBar`; one chat, changing cast. |
| Add character to scene (`/join`, `/join --full`) | ✅ | `CharacterPicker`. |
| Promote scene → group (`/promote`) | ✅ | |
| Per-speaker labels, focus-to-scope sidebar | ✅ | |
| Turn order, director mode, group system prompt / scenario / first message, per-member prompts | ✅ | Gated on `isGroupMode`; settings-only save (the old create-wizard was retired in WU3 in favor of the in-chat flow). |

## Worlds / Lorebooks · Personas

| Feature | Status | Notes |
|--------|:--:|------|
| Worlds list / detail / save (rename) / delete | ✅ | |
| Shared lorebook entry CRUD | ✅ | |
| Persona switch | ✅ | |
| Persona create / edit / delete | ✅ | |

## Image generation

| Feature | Status | Notes |
|--------|:--:|------|
| Backend choose (remote API / A1111 / Draw Things) + config | ✅ | |
| Generate + download | ✅ | |
| Insert into chat | ✅ | See Chat. |
| Prompt workspace / style presets / history / variations | ◑ | Web has a focused prompt + generate panel; the desktop Image Studio's richer workspace (style preview grid, history, variations) is not fully ported. |

## Voice

| Feature | Status | Notes |
|--------|:--:|------|
| TTS playback (🔊 per reply) | ✅ | Synthesized on host, played on the **client** device. |
| STT dictation (🎤) | ✅ | Recorded on-device, uploaded; **gated on a secure context** (Tailscale/ngrok/localhost) — browsers block the mic over plain-LAN http. |
| TTS/STT **engine + voice setup** | ⚙️ | Voice uses whatever engine you configured on desktop; choosing engines / downloading voices stays in the desktop settings. |

## Models / Backends

| Feature | Status | Notes |
|--------|:--:|------|
| LLM Local ↔ API choose + edit + flip | ✅ | |
| Switch local model (restart Kobold) | ✅ | Confirm dialog (interrupts generation). |
| HuggingFace browser + downloader (progress) | ✅ | Polled progress. |
| Backend start / stop / restart + status | ✅ | |

## Settings · Account · Remote access

| Feature | Status | Notes |
|--------|:--:|------|
| Backend / model selection, samplers, generation params | ✅ | |
| Account: username + Argon2id password + TOTP 2FA | ✅ | First-run setup, recovery codes. |
| Sessions: per-device, "log out everywhere" | ✅ | |
| Remote access: Tailscale / ngrok guided setup | ✅ | |
| PWA install (Add to Home Screen) | ✅ | `InstallHint`: `beforeinstallprompt` button + iOS manual steps; auto-hides once installed. |
| Theme, hardware/GPU flags, KCPPS presets, cloud sync, backups, data-dir | ❌ | No-go (see below). |

## Accessibility / PWA (code-level — done here)

- Icon-only buttons carry `title` + (for the new emoji voice controls) `aria-label` / `aria-pressed`.
- Streaming reply region is an `aria-live="polite"` so screen readers announce incoming text.
- Esc closes drawers / cancels edits; Enter sends (Shift+Enter newline).
- Service worker + manifest via `vite-plugin-pwa`; install only offered in a secure context (the browser refuses SW/`beforeinstallprompt` on insecure origins).

## ⚠️ Needs YOU — manual sign-off (cannot be done in CI / headless)

These require a real browser/device and are the only remaining W8 items:

- [ ] **Safari (macOS)** — chat streaming, wizards, Realism/Needs panel.
- [ ] **Safari (iPadOS)** — tablet master/detail layout; touch.
- [ ] **Firefox (Windows)** — full pass.
- [ ] **iOS Safari + Android Chrome** — phone layout (single-pane, drawers), the Realism/Needs sheet.
- [ ] **PWA install** on a secure context (Tailscale MagicDNS / ngrok) — install, relaunch, confirm the session cookie persists.
- [ ] **Mic (STT)** in a secure context; **TTS playback** over Tailscale on the client device.
- [ ] Keyboard-only + screen-reader spot check.

## Out of scope (confirmed no-go)

Cloud sync (deprecated), backups / DB cleanup / vacuum, hardware/GPU/accel flags +
ROCm/CUDA wizard, data-dir / root-path settings, the app updater, process/log
viewers, raw `.kcpps` launch-flag authoring, and RAG/embedding-sidecar *setup*
(the per-chat "use memory" toggle stays). The app updater and these are
desktop-only by design.

## Porch Stories (novel generator)

| Feature | Status | Notes |
|--------|:--:|------|
| Project list (create / open / delete) | ✅ | `/stories`. |
| Setup wizard (concept, style, AI config, chat-history seed) | ✅ | 3-step StepIndicator wizard. |
| Story-bible dashboard (concept/cast/threads/lore/acts) | ✅ | Generate via architect / act-structure / autopilot; live progress over WS. |
| Act → scene → beat structure tree | ✅ | Generate scenes/beats/full-act; per-scene auto-write. |
| Beat-by-beat prose writer | ✅ | Per-beat (re)generate; auto-write scene; per-beat 🔊. |
| Reader | ✅ | Assembled prose in reading order, per-scene read-aloud (reuses voice). |
| Export (.txt / .md) | ✅ | |
| Export (.epub / audiobook) | ⏳ | Desktop has dedicated generators; not yet exposed as web download routes. |

The whole pipeline is driven by the headless `StoryPipelineService` over the web
facade — no desktop code changed.
