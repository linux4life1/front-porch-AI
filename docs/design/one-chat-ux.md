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
- Tests: a window from a member's Away stretch is not retrieved for that
  member but is for one who was present; the web switch in a group flips
  the group gate.

### PR 5 — Group Settings window becomes the group editor page

Desktop and web together.

- Fold the dialog into the group editor page (`EditGroupPage`; confirm at
  build): name, scenario, first message, alternate greetings, turn order,
  auto-advance, start in Director, group and per-character prompts,
  per-character author's notes, lorebook import and entries, worlds picker,
  member recovery, add / remove members, and per-member defaults for new
  chats (Realism, Needs and its sliders, Afterglow, Pockets). No Reset ALL.
- Delete `GroupSettingsDialog` and its tab files once nothing opens them;
  retarget deep links (`edit_character_page/member_group_views.dart`).
- Web `GroupSettings.tsx` becomes the same page with the same sections.
- Dialog goldens and tests go → `approved-test-change` with the reason.

### Later, not yet sketched for approval

- A small desktop window (under ~700 px): the sidebar as a slide-over like
  the phone drawer. CLAUDE.md asks for 400 px and 1440 px on new screens;
  sketch it before building.

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
