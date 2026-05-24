# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## Recent improvements

- ☀️ **Light mode is now fully usable and comfortable** — The "blinding" experience (harsh cool grays + invisible white text/icons on the sidebar, home, forms, dialogs, and model lists) is gone. Warmer paper tones (`#F8F4ED` family), proper adaptive surfaces/borders/text/icons across the main screen, settings, Realism/Needs/Chaos panel, **character creator (all steps, mode cards, identity/avatar forms, progress indicators)**, chat sidebar (Realism, Objectives, Lorebook, Evolution badges, Summary, RAG, Author's Note), character & group dialogs, model manager, and download UI. Theme now driven by a single reliable source of truth (`StorageService.isDark`) so your preference sticks on restart and toggles are instant. 100% feature parity with dark mode — every slider, dropdown, button, text field, and workflow works identically; only the palette changes. Many dead dark-only constants and helpers were deleted in the process.

- 🖥️ **Pseudo-Remote backend fully delivered** (PR #36) — Run KoboldCPP locally on your machine but talk to it through a clean OpenAI-compatible `/v1` endpoint. Choose your `.kcpps` preset, hit Start, and get full support for chat, Realism, Needs, and reasoning. The entire settings UI, model switching, process logs, autostart, and connection status now work consistently for managed Kobold instances.

- 🧠 **Major Realism & Needs upgrade** — Per-character group Realism is now first-class. Every character in a group chat maintains their own independent bond, trust, emotion, arousal, fixation, and full Needs state. Much richer proactive pre-response Needs pressure with natural OOC guidance. The strong "Enjoys low hygiene" personality inversion is fully supported — filthy characters are properly rewarded for enjoying it. Characters in groups finally feel like distinct individuals instead of sharing one blob of state.

- 🧼 **Enjoys low hygiene toggle** — Characters who love being musky and gross now get proper mechanical and narrative rewards. The inversion is strong and intentional, exactly as requested.

- 📖 **Story & stability fixes** — LLMs returning doubles instead of ints in Story projects no longer break things. Narrative weekday progression is now stable across app restarts. AUR nightly automation continues to work as before.

(The Pseudo-Remote backend code was left 100% untouched except for one small authorized addition to display per-character fixation in group member panels.)

- 📖 **Porch Stories now fully light-mode compatible** — Cards, export pop-up sub-menus, delete confirmation dialogs, main dashboard, act & cast expandable sub-menus (with editable title/desc fields), thread/lore boxes, and voice dropdowns all switched from hard-coded dark surfaces + white70/38/24 text to `AppColors.cardOf`/`surfaceOf`/`textPrimary`/`textSecondary` + `resolve`. The "Porch Stories" boxes and sub-menus are finally readable and consistent with the rest of the app in both themes.

- 🏷️ **World card tags no longer overflow** — Long character names linked to a world now truncate with ellipsis instead of spilling past the card edge in the Worlds grid.

- 🖼️ **Lockable avatar size in chat sidebar** — New per-character toggle in UI Settings → "Lock Avatar Size". When on, the character avatar stays capped at the default sidebar width and won't stretch when you drag the sidebar wider. It still shrinks normally when the sidebar is narrow, and stays anchored to the top-right corner. Saves per-character in the card file.

- 📐 **Grid scale slider now has breathing room** — Added horizontal padding around the card size slider so it's no longer jammed against the sort dropdown.

- 💾 **Grid scale & sort mode now persist between launches** — Fixed a startup race condition: `StorageService._init()` runs async, and `HomePage.initState()` was reading settings before they loaded from disk. Both sort mode and grid scale now correctly restore on restart.

- 🔗 **Memory sources now survive restarts and cloud sync** — The cross-character memory source list (the "selected memory" picker in the chat sidebar's Memory section) was previously stored only in the in-memory card object. It is now persisted in the database alongside the character, so your selections stick across app restarts, hot reloads, cloud sync imports, and DB replacements. Works with group chats too.

- 🏷️ **Memory section shows full character names** — The Memory source toggle chips now display the full selected character names instead of being truncated/ellipsed.

- 🖼️ **Chat bubble avatar opacity flicker fixed** — The on-hover opacity effect on chat message avatars no longer flickers continuously.

- 🧩 **Triplicated character creator UI extracted into reusable widgets** — The Greeting Tone selector (FilterChips), Alternate Greetings slider, Avatar Art Style picker, and NSFW toggle were each copy-pasted across the Quick, Guided, and Full creation modes. Extracted into `GreetingToneSelector`, `AlternateGreetingsSlider`, `AvatarArtStyleSelector`, and `NsfwToggle` — stateless widgets used by all three modes.

- 🧩 **Second wave of character creator extractions** — Styled dropdown wrapper (`StyledDropdown<T>`), persona selector, first message length dropdown, description detail chip row, character name field (with randomize button), and age/gender side-by-side fields all extracted into dedicated widgets. The private `_buildBackButton` helper eliminated 5 near-identical OutlinedButton blocks. Roughly 350 lines of duplication removed, including dead `_greetingLengths` constant. Also fixed `create_character_page.dart` hardcoded white label text that was invisible in light mode.
- 🖥️ **Pseudo-Remote backend now available in Character Creator** — The setup step (Step 0) now has a dedicated "Pseudo-Remote" backend chip alongside KoboldCpp (Local) and API (Remote). Select a `.kcpps` preset, optionally override the model, and start/stop the backend directly from the creator with a live status indicator (Stopped → Starting... → Ready).

