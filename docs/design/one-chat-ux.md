# One chat UX: group chats work and look like 1:1, web looks like desktop

Status: rulings final (2026-11-07), build not started. The maintainer holds
the approved sketch (desktop 1:1 and group windows, both sidebars scrolled
out, wide web and phone boards, and a "where every control goes" table).
CLAUDE.md "Parity" carries the short form of rules 1 to 3.

## Rulings (binding; do not re-litigate)

1. **1:1 is the baseline.** The 1:1 chat screen does not move. A group chat
   shows every control in the same spot, with the same function, scoped to
   the tapped cast member.
2. **One UX everywhere.** Wide web is the desktop chat window: same
   controls, same places, same order. Phone adapts the layout (the sidebar
   opens full screen) but keeps every control and its order.
3. **Group-only pieces are exactly two:** a read-only **Group Dynamics**
   section (how the tapped member feels about each other member) and
   turn-taking (the Next button, tap a sender's name to speak next, turn
   order and auto-advance in the group editor). Cast chips and the Director
   panel are shared with 1:1-with-guests, not group-only.
4. **Per character.** In a group, the Realism, Needs, Afterglow and Pockets
   switches sit where 1:1 has them (Character State header; Needs row;
   Afterglow line under Trust with Lust under it; Pockets line) and act on
   the tapped member only, for this chat.
5. **Defaults vs now.** Per-member defaults for future chats live only in
   the group editor and never switch anything in the current chat.
6. **Removed:** the pinned Group Settings button (it opens from Main
   Settings → Group Settings…), the group-wide Afterglow switch, member
   cards in the sidebar, every "Reset ALL".
7. **Message buttons do not move.** Speak / inspect / other words / edit /
   fork / delete stay in the bubble's top row; regenerate / continue /
   swipe / pick version stay under the newest reply. Web adopts this.
8. **Group memory (RAG) is per member.** A character recalls only what they
   were there for, never a scene they were Away for.
9. **Voice call is desktop only, forever** (the web round trip is too slow).
   Not a parity gap. In a desktop group it shows greyed with a "1:1 only"
   tooltip.

## What the code does today (checked at ee8ce2d94)

- Group Realism switch: Group Settings window, Realism tab
  (`dialogs/group_settings/realism_needs_tab/master_toggle_cards.dart`);
  the Character State header switch is null for groups
  (`character_state_group.dart` `trailing`).
- Character State in a group shows member cards instead of the 1:1 leaves
  (`character_state_group.dart` `visible` list: `!isGroup` on bond_bars,
  fixation, needs, ambitions, pockets). The 1:1 leaves read
  `chat.activeCharacter`, not the focused participant.
- Hidden in groups: Objectives section (`sidebar_body.dart`), AFK leaf
  (`story_tools_group.dart`), Memory leaf (`journal_memory_group.dart`),
  voice call (`chat_page.input_actions.dart`).
- Member-to-member feelings are tracked (`cast_feelings_judge.dart`, the
  hidden `relationships` map) and deliberately never shown
  (`group_member_reads.dart`: "the UI never exposes inter-char data").
- Afterglow per member is a flag on the member's group copy
  (`group_member_settings.dart` `setMemberAfterglowEnabled` →
  `persistGroupMemberExtensions`), so it spans every chat of that group.
  Pockets already has the target shape: a live per-chat switch per member
  plus a member-copy default for new chats (`setMemberPocketsDefault`).
- Group memory: every window is embedded under one id, `group_<id>`
  (`session_state.dart` `ragCharacterId`); every member's turn searches that
  pile plus members' Data Bank and memory sources (`rag_sources.dart`).
- Bug: in a group, the web memory switch reads and writes the global 1:1
  setting (`chat_tools_snapshot.dart` `memory.ragEnabled`,
  `chat_tools_facade.dart`) while group retrieval gates on
  `groupRagEnabled` (`turn_rag.dart`).
- Likely dead: per-character RAG importance is keyed by
  `groupMemberStoreId` (`group_member_settings.dart`), but retrieval
  multiplies by the row's `characterId` (`group_<id>` for chat memory, the
  origin portrait id for Data Bank; `memory_retriever.dart`). Prove with a
  test before deleting.
- Web chat today: left nav rail, header with model chip / Persona / Theme /
  Conversations, cast pills under the header, a flat insight column with
  Realism and Needs checkboxes, message buttons in one hover-only row under
  the bubble, a one-line composer with a "Send" text button.

## Build order

Web layout goes first: every later PR must ship its web twin (CLAUDE.md
Parity), and building those twins on the old web layout would be thrown
away. Each PR is one draft PR on Rawhide with its own `## Hand-check`
lines, screenshots on the PR page, and a live run on the Linux media server
for anything that changes behaviour.

### PR 1 — Web chat becomes the desktop chat (layout only)

No behaviour change; controls move to their desktop homes.

- Chat route hides the nav rail; header = back, avatar(s), title (+ "N
  characters • turn order" in groups), sidebar button.
- Header items move: model → Main Settings → Model Settings; Persona → the
  persona avatar left of the composer; Theme / chat settings → Main Settings
  → Chat Settings / UI Settings; Conversations → the folder (Chat
  Management) button in the composer.
- Bubbles: name + icon row at the top, regenerate / continue / swipe / pick
  version under the newest reply, always visible (no hover).
- Composer: text box above an icon row (persona, folder, Image Studio,
  attach | impersonate, mic, send icon). No voice call on web.
- Insight column → the desktop sidebar sections in desktop order (portrait,
  Main Settings, layout pills, cast chips, Director, One-Shot Eval, Tool
  calling, Author's Note, Wiki, Character State with the Realism switch in
  its header and Needs as a row, Journal & Memory, Objectives, Story Tools
  holding Places and Lorebook). Phone: the same, full screen.
- Director strip and cast pills move into the sidebar; the Next button sits
  in the composer before Send.
- Every item of today's Chat Tools gets a mapped home in the PR body
  (Context budget, Our story, Promises, Belongings, Where we are, Scene &
  time) — map from the desktop code, not from memory.
- Tests: update `web_ui/e2e/journeys.spec.ts` selectors for moved controls
  (existing tests: `approved-test-change` with the reason "controls moved to
  their desktop homes"); add one journey that walks the sidebar sections in
  order on wide and phone; sweep routes unchanged.
- Risk: largest PR. Split 1a (wide) and 1b (phone) if review gets heavy.

### PR 2 — Group sidebar matches 1:1 (no new storage)

Desktop and web together.

- Character State in groups renders the 1:1 leaves for the tapped member
  (bond bars, fixation, Needs grid as full rows, ambition, Pockets line,
  time). Leaves take a member-scoped source instead of
  `chat.activeCharacter`. New read: ambitions for a group member.
- Member cards leave Character State. Their ✕ (remove member) moves to the
  group editor (PR 5); their objectives "Manage" is covered by the
  Objectives section; speak-next stays on the sender name and Next.
- New read-only **Group Dynamics** section below Character State: the
  tapped member's feelings toward each other member. This deliberately
  reverses "the UI never exposes inter-char data"; update that comment.
- Objectives section and AFK leaf show in groups (focused member).
- Pinned Group Settings button removed; Main Settings popup gains "Group
  Settings…" (groups only). "Group Author's Note" is titled "Author's Note".
- Voice call greyed with the "1:1 only" tooltip in groups (desktop).
- Fix the stale member-card hint "Realism off — enable in sidebar…".
- New code goes in new files: `chat_page.sidebar_widgets.dart` (498 lines)
  and `chat_page.sidebar.dart` (455) are at the cap.
- Tests (must fail with the change reverted): tapping a cast chip swaps the
  Character State leaves to that member's values; Group Dynamics lists the
  other members; Objectives is visible in a group. Sidebar goldens change →
  `approved-test-change`.

### PR 3 — Per-character switches in groups

Desktop and web together. Chat-state work: load the `path-complete-chat`
skill and fill the matrix in the PR.

- Realism, Needs, Afterglow, Pockets: a live per-chat switch per member,
  following the Pockets shape (live switch in the member's per-chat state +
  member-copy default for new chats). The Character State header switch
  mounts in groups and drives the tapped member.
- Afterglow splits into the live per-chat switch (Character State) and the
  new-chat default (member copy, group editor). The group-wide switch goes.
- Gates read the speaking member's switch: Realism evals, the Needs one
  gate (`NeedsPass.active`), Objectives' live AND, posture / climax /
  pockets post-gen passes, One-shot. 1:1 is unchanged (one character = one
  chat).
- The Needs and Objectives rows of CLAUDE.md "Chat contracts" change from
  "chat switch" to "this member's switch" in groups — needs the maintainer's
  OK in the PR conversation before merge.
- Path matrix: send, Continue (no clock tick, `newPart` only), regen and
  swipe (restore by message speaker id), delete, edit, Director auto-chat,
  member Away, guest promotion, group restore
  (`realism_restores.dart`), desktop and web.
- Tests: a member with Realism off is not scored while another member is;
  turning Needs off for one member leaves the others ticking; regen restores
  the right member's switch state. `needs_gate_ratchet_test` and friends
  change → `approved-test-change` with the reason.

### PR 4 — Per-member memory

Desktop and web together. Path-complete matrix required.

- Write: after a reply, file the window under each member who was present
  (not Away), keyed by the member's library identity (`stableGroupId`, per
  CLAUDE.md "Database"), scoped to this chat. Import backfill
  (`import_rag_backfill.dart`) uses the same rule.
- Read: the speaking member retrieves their own windows in this chat, plus
  their Data Bank and memory sources. No `group_<id>` for new windows.
- Old `group_<id>` rows: decide in the PR (proposed: read-only fallback for
  all members, so existing chats keep their memories; no re-filing pass).
- Memory leaf shows in groups for the tapped member. The web memory switch
  controls the group's memory, not the global 1:1 setting (bug above).
- RAG importance: prove the key mismatch with a test, then fix the key or
  drop the sliders.
- Open: 1:1's memory switch is global (all 1:1 chats); decide whether the
  group's stays per group or becomes per member.
- Built (decisions, change in one place each): a message is stamped with who
  was in the scene (`memory_present`, memory keys; not Away, not At work, the
  speaker always); the one writer (`WindowFiler`) files each member's copy of
  the lines they were there for under their key and this chat. Old
  `group_<id>` windows are a read-only fallback for every member
  (`legacyGroupMemoryBuckets`), never re-filed. The group's memory switch
  stays per group, and a group's memory runs only while the global Memory
  setting AND the group's switch are on (the embed, retrieval and
  `isOperational` read both; the group's switch greys out while the global one
  is off); the 1:1 one stays global. Importance sliders are translated to
  memory keys at retrieval. A memory source that is another member of the
  group keeps its other-chat windows; their windows in THIS chat are never
  read by someone else. The PWA's Memory section has the Sources picker and
  Data Bank for the focused member (`/api/chat/tools/memory/sources`,
  `/databank`).
- Tests: a window from a member's Away stretch is not retrieved for that
  member but is for one who was present; the web switch in a group flips
  the group gate.

### PR 5 — Group Settings window becomes the group editor page

Locked design: [group-editor.md](group-editor.md). It supersedes the earlier
sketch that stood here. Desktop and web together.

### PR 5b — Chaos Mode per character

Each member gets the 1:1 Chaos controls: the editor toggle is that member's
new-chat default, the chat sidebar has that member's live switch, 18+ events
toggle, pressure gauge and Spin, and a Chance Time event only reaches that
member. Existing groups seed every member from the group's switch. Sketch
the sidebar before building.

### PR 6 — Helper model reaches the web model sheet

The desktop Model Settings dialog embeds the whole Realism-evals
(`WorkerBackendSection`) group in-chat; the web chat sheet
(`ChatModelSwitcher`) offers provider + chat model only. Mount the existing
`WorkerBackendCard` inside the sheet (the `/api` worker facade already reads
and saves it); the GGUF control stays the served `localModels` dropdown —
no file browser on web. Ledger #1.

### PR 7 — Settings page rebuild + drift closure (priority 1: the settings page)

Bumped from PR 8 on 2026-11-13. The earlier PR 7 (gather the group-only
Realism settings) was done by PR 5, the Edit group page
([group-editor.md](group-editor.md)), and was retired with nothing left.

The web Settings is folded into six flat sections and never got the
desktop's Appearance tab: no theme gallery, accent, UI font or corners.
Rebuild Settings so every desktop tab maps to a web section one-for-one,
then close the rest of the drift ledger in its ranked order
(`dev-notes/drift-ledger-726.md`, tabled 2026-11-12 — full inventories of
both UIs are already in that audit; do not sweep again).

Priority order inside the PR, maintainer-ruled 2026-11-12:

1. Settings structure + Appearance controls (ledger #5) — this PR's namesake.
2. Voice & Media controls the web never got (ledger #13).
3. Small fills: slash catalog `/afk` `/image` (ledger #14), folder-tile
   avatars and shape (ledger #4).
4. Verify-and-close the suspects (ledger #15).

Four chunks, one draft PR each (the PR 1a/1b precedent). Verified
inventories with file:line evidence, the prep checklist and the open
rulings live in [settings-rebuild-scope.md](settings-rebuild-scope.md):

- **7a — structure.** Web Settings becomes seven sections in desktop tab
  order; Appearance folds out of general (the chat-appearance group
  moves with it). Layout only, no new controls. The parity manifest's
  section list is rebuilt in the same PR. Prep lands first: the four
  open settings-redesign PRs (#716–#719) get disposed of, and
  `dev-notes/web-parity.md`'s "Theme … No-go" row is reversed by
  maintainer ruling (scope doc §3–§4).
- **7b — host theme controls.** Theme gallery (the eight `AppThemeId`
  themes), accent picker, UI font, corners, and "Reset accent, font and
  corners". Host work: `themeId`/`accent`/`uiFont`/`corners` through the
  settings snapshot, writer and the `settings_changed` relay — none of
  those keys are in the web API today. The web paints the host-resolved
  token maps, never its own theme math. Changes are host-wide: a browser
  tab changes the desktop (that is the poke script).
- **7c — Voice & Media.** Expression controls (classification, display
  mode, re-roll, emoji burst + size, fallback, ONNX download), Whisper
  model choice + download with progress, auto-send transcription, the
  photo-understanding card, the image-gen toggle. The voice facade
  writes only `ttsEnabled`/`sttEnabled` today; new keys and download
  progress are the cost. Mic device list is `⚙️` desktop-only unless the
  maintainer rules otherwise (scope doc §5). Voice-call settings stay
  desktop (ruling 9).
- **7d — small fills + suspects.** `/afk` and `/image` into the web
  slash sheet — preferred: serve the catalog from `/api` so it cannot
  drift again. Home folder tiles become portrait tiles with the 2×2
  member montage (`/api/folders` must gain preview members; it ships
  counts only). Then verify-and-close ledger #15: each suspect lands as
  a fix or a pinned ◑/❌ row in `dev-notes/web-parity.md`.

Not this PR: Waifu Coder (ruled desktop-only, permanent), per-character
Chaos (PR 5b), helper model (PR 6), the web voice call and Stoop upload
wizard (ledger #10, #11 — next SOW's candidates), the creator Realism
step (ledger #12, same next SOW), local `.gguf`/`.kcpps` pickers (⏳ by
design).

### Later, not yet sketched for approval

- A small desktop window (under ~700 px): the sidebar as a slide-over like
  the phone drawer. CLAUDE.md asks for 400 px and 1440 px on new screens;
  sketch it before building.
- Dead-code sweep (queued at PR 5 handoff).

## Poke scripts (maintainer)

- PR 1: open any chat in the browser on the PC and on the phone; the screen
  should match the desktop app's chat, button for button.
- PR 2: open a group, tap each cast chip; Character State should change to
  that character and look like a 1:1 chat. Group Dynamics should list the
  others.
- PR 3: in a group, switch Realism off for one character only, chat a few
  turns; only the others' bars move.
- PR 4: in a group, mark one character Away, chat, bring them back, ask
  them about what happened while they were gone; they should not know.
- PR 5: Main Settings → Group Settings…; every old tab's item is there, and
  changing a default does not change the chat you are in.
- PR 7: open Settings in the browser and the app side by side; every app
  tab is a web section with the same controls, and changing theme or
  accent on the web changes the desktop too (and every other open
  session follows within a second).
- PR 7 (Voice chunk): set the expression classification mode and burst
  size in the browser; the app's Voice & Media tab shows the same
  values.
- PR 7 (fills chunk): type `/` in the web composer and compare with the
  app's list — same commands, `/afk` and `/image` included; and a home
  folder tile shows member faces like the app's montage tile.
