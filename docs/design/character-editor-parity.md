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

Realism off: desktop hides rows 19 to 22 except Afterglow-free Chaos; web does
the same (the engine switch gates the same rows). Time & Day, Chaos and
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

## Controls the web editor has that the desktop editor does not

Not decided here; listed for the maintainer.

| Web control | Where desktop offers it, if anywhere |
|---|---|
| Auto passage of time (Realism block) | Not in the character editor. Porch Life settings has the passage-of-time switch. |
| Avatars & expressions (Upload look, Expressions) | Not in the editor, which shows a read-only avatar. The Avatar Gallery opens from the home grid and the chat sidebar. |
| Delete character | Not in the editor. The home grid offers delete. |
