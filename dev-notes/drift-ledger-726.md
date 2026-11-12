# Dart ⇄ PWA drift ledger (PR 726 audit, started 2026-11-11)

**Status: TABLED 2026-11-12.** Both UI inventories are complete; no further
sweep needed. Closure happens in **PR 8 of `docs/design/one-chat-ux.md`**,
settings page (ledger #5) first, then the ranked list below.

Maintainer-confirmed items get a ✅ in *Found by*; code evidence is verified in
this worktree's `web_ui/src` and `lib/`. Full inventories from the two audit
passes land as "suspects" until verified.

| # | Drift | Evidence | Found by | Status |
|---|-------|----------|----------|--------|
| 1 | Chat **Model Settings** sheet: desktop dialog embeds the full helper/worker section (helper host, Realism-evals GGUF picker, `.kcpps` preset, helper URL/key/model); the PWA chat sheet (`ChatModelSwitcher`) has provider+chat model only. Worker card exists on the PWA Settings page but is never reachable from chat. | `lib/ui/dialogs/model_settings_dialog.dart:288` (embeds `WorkerBackendSection`) vs `web_ui/src/pages/chat/ChatModelSwitcher.tsx` (no worker/helper code) ; web Settings mount: `pages/SettingsPage.tsx:627` | maintainer + code | open |
| 2 | In-chat **Director card** (roster + "Step out to direct") absent from PWA Main Settings; `web_ui` only has `StoryDirectorPage` for stories | `lib` DirectorSection vs PWA | maintainer + code | **fixed in 3bfa3b17** — `web_ui/src/components/DirectorStrip.tsx` (desktop header, status pill, blurb, step button) + `DirectorStrip.test.tsx` |
| 3 | PWA Main Settings header shows a single **initials placeholder** tile where desktop shows the **cast strip with live expression portraits** | `web_ui/src/components/ChatSidebar.tsx` (expression-avatar), `CastBar.tsx:59-78` (faces ringed when focused, Away/Back, GUEST/Promote) | maintainer + code | **fixed in 3bfa3b17** — pinned by `ChatSidebar.groupState.test.tsx` |
| 4 | Home grid **folder tile**: desktop renders a portrait tile (`childAspectRatio: 0.7`) with a **2×2 avatar montage** (up to 4 member previews) + "N characters"; PWA renders a short **landscape row with a 📁 glyph and no member avatars** | `lib/ui/pages/home/cards/folder_grid_card.dart:32,152` (`_folderPreviewImages(..., 4)`, Stack montage) vs `web_ui/src/components/library/LibraryCards.tsx:97` + `web_ui/src/styles/library-cards.css:51` (`flex-direction: row`, `.folder-glyph` text only) | maintainer + code | open |
| 5 | **Settings structure (corrected after full inventory)**: desktop = 7 tabs; PWA folds Appearance into "general". Web DOES carry: dark mode + per-device theme, ambient scene/effects, pause-while-generating, scene sound + volume, mood-on-character, reading size, bubble opacity, chat colours, spell-check language. STILL MISSING: the app **theme gallery** (`ThemeCardGrid`), **accent colour** picker, **UI font**, **corners** style, and the "Reset accent, font and corners" action. | `lib/ui/settings/tabs/appearance_tab/theme_card_grid.dart`, `accent_picker_row.dart`, `appearance_tab.dart` vs `web_ui/src/components/AppearanceSettings.tsx` (grep Accent/ThemeCard → 0) | maintainer + inventories | open |
| 6 | Home toolbar has **three modes on desktop** (`enum HomeMode { chats, stories, waifu }`); PWA `HomeModeToggle` is two-mode (`'chats' \| 'stories'`). No Waifu Coder on web **at all**: no facade in `lib/services/web/` (grep waifu → 0) and no UI in `web_ui/src` | `lib/ui/pages/home/widgets/home_mode_toggle.dart:26` + `lib/ui/waifu/` (~5,900 lines, 20+ widgets) vs `web_ui/src/components/HomeModeToggle.tsx:10` | handoff + code | **ruled desktop-only, permanent** (maintainer ruling 2026-11-12; not queued) |
| 7 | Per-character Chaos (queued pre-handoff; scope not yet analyzed) | — | handoff | queued |
| 8 | Group-only settings in one place (queued pre-handoff) | — | handoff | queued |
| 9 | Dead-code sweep (queued pre-handoff) | — | handoff | queued |

## Closure order

Fix order = maintainer's call; each fix ships desktop + web in one change per
One UI rule.

| 10 | **Voice call absent from web entirely**: desktop 1:1 has `Start voice call`, `CallOverlay` (mute/send/end, Listening→Speaking status), and its settings (Voice Call Model dropdown, Voice Buffer, Call System Prompt, Auto-send); PWA composer has mic-STT and per-message Speak only | grep of `web_ui/src/components`+`pages` for voicecall/CallOverlay → 0; `lib/ui/chat_components/widgets/call_overlay/` | inventory diff + code | open |
| 11 | **Stoop upload wizard is a web stub**: desktop has the 4-step wizard (Pick/Details/Content/Review); PWA Share tab renders a "coming soon" placeholder (wide-only, phone redirects) | `web_ui/src/pages/stoop/StoopSection.tsx:102-113` vs `lib/ui/pages/repository/stoop_upload_page.dart:78` | inventory diff + code | open |
| 12 | **AI Character Creator drops the Realism step on web**: desktop `Setup → Mode → Configure → Generate → Profile → Greetings → Realism → Review`; PWA has Mode→Details→Output→Generate→Profile→Greetings — no Realism (needs/relationships/starting emotion/optional features) at generation time | grep Realism/Porch Life in `web_ui/src/pages/CreateAiCharacterPage.tsx` → 0; `lib/ui/character_creator/steps/realism_step.dart` | inventory diff + code | open |
| 13 | **Voice & Media settings thin on web beyond design**: beyond the documented ⚙️ engine-setup split, missing are Expression controls (classification LLM/ONNX/Manual, Display mode, Re-roll, Emoji Burst + size, Fallback), Whisper model download, Microphone device list, Auto-send transcription, Photo-understanding card | `lib/ui/settings/tabs/voice_media_tab/expression_section.dart:145-166,406-447` vs grep ONNX/classification/burst in `web_ui/src/components/VoiceMediaSettings.tsx` → 0 | inventory diff + code | open |
| 14 | Slash cheat-sheet omits `/afk` and `/image` (desktop catalog has 17 commands, web sheet lists 15) | `lib/services/chat/chat_command_handler/slash_command_catalog.dart:37-123` vs `web_ui/src/components/ChatComposer.tsx` | inventory diff + code | open |
| 15 | Suspects pending deep verify: (a) group per-speaker "Regenerate main character (removes the NPC's reply)" variant; (b) persona JSON import/export app-bar actions; (c) Models-folder ops (Change folder / Open in File Manager) on /models | desktop: `message_bubble.actions.dart:177`, `user_persona_page.dart` AppBar, `model_manager_page.dart` | inventory diff | suspect |

## Waifu Coder ruling (#6), 2026-11-12 — DESKTOP-ONLY, permanent

Maintainer ruling: **Waifu Coder remains Dart-app only.** It is not queued for
a web port and must not be counted as drift in future parity audits; the web
two-mode toggle is the intended shipped behaviour. Decision also unblocks this
PR (it never gated it): Rationale:

1. It is not a control gap — it is a missing **feature**: no web facade at all
   (`lib/services/web/` has zero waifu endpoints) plus ~5,900 lines of UI in
   `lib/ui/waifu/`. Porting it is an SOW of its own, like the AI Character
   Creator and Porch Stories were.
2. It is a local-process feature (private `opencode serve` on loopback,
   filesystem drops, skill folders). The web story is "remote-control the
   host's coder", which needs its own design pass, not a parity patch.
3. The web degrades honestly today: `HomeModeToggle` is a clean two-mode
   control; nothing is broken or half-drawn. This fits the ⏳/❌ legend of
   dev-notes/web-parity.md, so the parity guard's silence is acceptable here.

Action: add a `❌ Waifu Coder` row to `dev-notes/web-parity.md` ("out of
scope — confirmed no-go, desktop-only by rulings").

