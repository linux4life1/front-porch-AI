# Character editor parity: desktop vs web, leaf by leaf

The desktop `EditCharacterPage` is the baseline. The web `CharacterEditPage`
(1:1 and group-member mode) and the Edit group page must show the same tabs,
sections, leaf controls, labels and helper text in the same order. Only layout
may adapt to phone width. `test/hygiene/one_ui_parity_test.dart` pins the
label order of every row below marked "pinned"; it reads both sides' sources
(`ONE_UI_WEB_ROOT` points the web side at another `web_ui/src` copy).

Sources. Desktop: `lib/ui/pages/edit_character_page/`, `lib/ui/widgets/`
(`realism_form_section*`, `identity_chip_lists`, `needs_form_section`,
`work_row`, `birthday_row`, `plan_lines_editor`, `wardrobe_chip_section`,
`story_begins_row`), `lib/ui/dialogs/lorebook_entry*`. Web:
`web_ui/src/pages/CharacterEditPage.tsx`, `components/realism/*`,
`components/TagsField.tsx`, `AltGreetingsEditor.tsx`, `LoreEntriesEditor.tsx`,
`groupSetting/CharacterWorldsSection.tsx`.

## Tabs

| Desktop | Web | Status |
|---|---|---|
| Details, Dialogue, Lorebook, Worlds | same four, same order | matches |
| Worlds greyed in member mode (A3) | same | matches |

## Details (1:1; member mode adds the notice first and "In the group" last)

| # | Leaf (desktop label) | Web before | Web now | Pinned |
|---|---|---|---|---|
| 1 | Group-member notice / "In N groups" line | present | same | yes (heading test) |
| 2 | Avatar box (read-only image) | absent | present | no (visual) |
| 3 | Chats-together stats card | present | same | no |
| 4 | Identity: Name | bare text | label "Name" | yes |
| 5 | Identity: Tags (chips + "Add a tag...") | comma text input | `TagsField` chips | yes |
| 6 | Voice | present | same | yes |
| 7 | Personality & World: Description, Personality, Scenario | present | same | yes |
| 8 | Advanced Prompts: System Prompt, Post-History Instructions | present | same | yes |
| 9 | Ambitions header, "Long-term goals" chips + helper | after Realism; label "Ambitions" | moved up; desktop header and label | yes |
| 10 | Plan lines | after Realism | moved up | yes |
| 11 | Work: Occupation, What the job is, Start, End, days | after Realism | moved up | yes |
| 12 | Birthday | after Realism | moved up | yes |
| 13 | Likes & Dislikes header, Drawn to, Put off by | no header, after Realism | header, moved up | yes |
| 14 | Pockets & Wardrobe: Wearing, Carrying | after Realism | moved up | yes |
| 15 | Intimate preferences header + intro, Warms to, Not interested in | no header, intro on first chip list | header, intro paragraph, moved up | yes |
| 16 | Enable Realism Engine (+ hint) | after Time & Day | first | yes |
| 17 | Time & Day: Time of Day, Day Number | "Time of day", "Day" | desktop labels | yes |
| 18 | Story begins / Opens at | absent in 1:1 | present, saved through the relay | yes |
| 19 | Needs Simulation (+ hint), Hunger, Bladder, Energy, Social, Fun, Hygiene, Comfort, Enjoys low hygiene, Pace (+ helper), Sloth/Normal/Fast | lower-case labels, no Pace helper | desktop labels and helper text | yes |
| 20 | Relationship: Short-Term Bond, Long-Term Bond, Trust Level | "Short-term bond" etc. | desktop labels | yes |
| 21 | Starting Emotion | "Emotion" | desktop heading | yes |
| 22 | Optional Features: Afterglow (+ Recovery, 18+), Chaos Mode (Chance Time), Realism Verification (Director/Verifier), Max reprocess passes, Strictness, Director authority (needs) | Chaos and Verification first; other labels | desktop order and labels | yes |
| 23 | In the group (member mode, last) | present | same | yes |

Realism off: both sides keep Time & Day and the identity rows, drop rows 19,
20, 21 and the rest of 22, and show only Optional Features with Chaos Mode. Time & Day, Chaos and
Realism Verification grey out in member mode (A2, A7, A8) on both sides.

## Dialogue

| Leaf | Web before | Web now | Pinned |
|---|---|---|---|
| First Message / Opening Message | present | same | yes |
| Alternate Greetings header + "Add" | "Alternate greetings" + "+ Add" | desktop copy | yes |
| "No alternate greetings yet" | long hint | desktop copy | yes |
| Greeting N+2 label per row | none | present | yes |
| "Remove greeting" | "Remove" | desktop copy | yes |
| Example Dialogue / Example Conversations | present | same | yes |

## Lorebook

| Leaf | Web before | Web now | Pinned |
|---|---|---|---|
| Heading + "World lore entries inject context when keywords are detected." | heading only | both | yes |
| Import file, Export file, From character, Add Entry (in that order) | "From character…" under the list; "Import JSON" and "+ Add entry" in the list header | the four desktop actions, in order | yes |
| Empty state (two lines) | one different line | desktop copy | yes |
| Entry: Simple / Advanced tabs | one "Advanced" toggle | Simple and Advanced | yes |
| Entry basics: Name (optional), Keywords (comma separated) (disabled when Always Active), Content, Enabled, Always Active, Sticky Depth, Chance to trigger, Placement + helper lines | different labels, no helpers | desktop labels and helpers | yes |
| Advanced: Conditions, Placement & priority (Position, Depth, Speak as, Order, Ignore token budget), Timing (messages), Chain reactions, Matching overrides, Variety group, Weight, Prioritize in group, Score by matched keys | flat grid, other order and labels | desktop sections, order, labels, helpers | yes |
| Position names ("Example dialogues - top") | "Examples - top" | desktop names | no |

## Worlds

| Leaf | Status | Pinned |
|---|---|---|
| Where new chats meet, New chats, Applies to ... new chats, split banner | matches (group copy "Applies to new chats of this group.") | yes |

## Edit group (Details)

Pinned in order: Identity (Group name, Cast, Remove..., + Add a character,
Bring back a removed member), Turns, Voice, Personality & World, Advanced
Prompts (with the per-character group-only fields), Tags, Realism Engine
(Time & Day, Story begins, Chaos, Verification, Starting feelings). The web
Story begins row used "The story begins on..." and now reads like the desktop
row.

## What the test does not pin

Control kind (slider vs number box), colours, spacing, and the way a lore
entry opens (desktop: dialog; web: in the card; a layout adaptation). Those are
checked by eye and by the golden and screenshot rules.

## Controls removed from the web editor (maintainer ruling)

The desktop editor does not have these, so the web editor does not either. Each
lives where the desktop keeps it, and the parity test pins both the absence and
the new entry points.

| Was on the web editor | Now | Desktop place, and the web twin |
|---|---|---|
| Auto passage of time | removed | Settings, Porch Life, "Passage of Time" (web `PorchLifeSettings` has the same row) |
| Avatars & expressions (Upload look, Expressions) | removed | "Avatar Gallery" in the character card menu (home grid) and in the chat's Main Settings menu. Web: `AvatarGalleryModal` ("Avatar Gallery - name"), opened from the same two menus, with all the looks, expressions, favourite and portrait-swap controls the old section had |
| Delete character | removed | "Delete" in the character card menu; web grid menu has it with its confirm dialog |

The web character card menu now has the desktop's items, labels and order
(Start New Chat, Manage Chats, Edit Character, AI Enhance, Avatar Gallery,
Duplicate Character, Use as Persona, Export PNG, Export JSON, Move to Folder...,
Remove from Folder, Delete); the test compares the two lists.

## Lore entry editor

Desktop edits an entry in a dialog; the web character editor now does too:
cards with the Always Active / Depth chip, enable switch, "Edit entry" and
"Delete entry"; "Add Lorebook Entry" / "Edit Lorebook Entry" with Simple and
Advanced tabs and Cancel / Add or Save. Sticky Depth and Chance to trigger are
sliders and are hidden while the entry is Always Active, as on desktop. (The
group and chat lorebook editors keep the inline card; they are not the
character editor.)

## Control kinds

| Control | Desktop | Web |
|---|---|---|
| Bonds, Needs bars, Max reprocess, Strictness, Sticky Depth, Chance | slider | slider |
| Time of Day, Position, Speak as, Secondary logic | dropdown | select |
| Day Number, Order, Timing fields | number box | number input |
| Tags | chips with "Add a tag..." | chips with "Add a tag..." |
| Pace | segmented button | segmented buttons |
| Story begins / Opens at, Birthday, work hours | Flutter date and time pickers | the browser's own date and time inputs |

## Avatar Gallery in a group chat

Desktop opens the gallery of the library character behind the tapped member
(a member copy has one avatar file and no expression set). The web chat's Main
Settings menu does the same: it asks `GET /api/groups/<id>/members/<memberId>/library`
(`{id, name}`, 404 when the member has no resolvable origin) and opens the
gallery of that library character. The member's own avatar file under
`groups/<id>/avatars/` is never touched, so its storage key stays as it is.
Pinned by `group_cast_relay_test.dart` and `ChatSidebar.gallery.test.tsx`.

## Home menus (desktop vs web)

Same items, labels and order, pinned by label-list equality in the parity test:
the character card menu, the group card menu (Start New Chat, Manage Chats,
Edit Group, Duplicate Group, Export PNG, Extract Characters, Move to Folder,
Remove from Folder, Delete), the folder card menu (Rename Folder, New Subfolder,
Delete Folder...) and the import menu (Import Cards, Import Folder, Import
Backyard AI (.byaf), Import .porch / .porchpack). "Duplicate Group" is real on both
(`GroupDuplicator`: name "<name> (copy)", fresh group and member ids, avatars
copied under the new group, every setting, the group lorebook, worlds and the
per-member prompts, notes and feelings; no chats, memories or journals; web
route `POST /api/groups/<id>/duplicate`). The web's two "Browse ..." links were
not on the desktop and are gone.

Toolbar buttons: New Folder, Multi-select and Import carry the desktop tooltips.

## Navigation (desktop sidebar vs web nav)

The web nav lists the desktop sidebar's items in its order and wording
(`Sidebar.labels`): Home, Image Studio, The Stoop, AI Character Creator, Create
Character, Create Group Chat, Manage Models, Settings, User Persona, Worlds,
Backups & Restore, Join the Discord, Buy Me a Coffee. User Persona is its own
page on both. Chat, Stories and Remote are not nav items (maintainer ruling):
Home's Chats / Porch Stories toggle reaches the story shelf, and the web server
(Remote Access) sits in Settings > Advanced, where the desktop sets web access
up. Pinned by the nav test in `one_ui_parity_test.dart`.

## Accepted platform differences (maintainer rulings)

- The date and time fields (Story begins, Opens at, Birthday, work hours) use
  the browser's native date and time inputs where the desktop draws Flutter
  pickers. Same fields, same values.
- Account and Log out in the web nav: the web app needs a sign-in; the desktop
  has none.

## Open differences

None, except the accepted platform differences above, and the desktop Home
toggle's third mode (the Waifu Coder), which the web does not have; that is a
whole feature awaiting a maintainer ruling.

Built on the web to match the desktop: Refresh list, the Organize into folders
mode (a second picking mode; dragging a picked card carries every pick), Select
all / Select none and Cancel selection in the selection bar, Create Character /
AI Character Creator / Create Group Chat as nav items (the toolbar has none of
them), and the Delete Folder dialog with character and group counts and
"Delete Folder + Characters..." only when the folder holds characters.
