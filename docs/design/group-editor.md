# Group editor (One Chat UX PR 5): locked design

Status: **locked by the maintainer, 2026-11-11.** This file is the spec for
PR 5 of [one-chat-ux.md](one-chat-ux.md). Build exactly this. Anything this
file does not cover follows the 1:1 character editor as it is today. If the
code makes something here impossible, stop and ask; do not improvise a
variant.

Pictures (on this branch, open them before writing code):

| File | What it is |
|------|------------|
| `docs/screenshots/pr5-design/baseline-1to1-editor-top.png`, `…-bottom.png` | The real 1:1 "Edit character" page today (Rawhide, Porch theme, Realism off). **This is the look.** |
| `docs/screenshots/pr5-design/edit-member-in-group.png` | Editing a member from a group: the baseline page plus the additions in this file, outlined in dashed green. |
| `docs/screenshots/pr5-design/edit-group-page.png` | The Edit group page: section **order and content**. It is a sketch: its cards, fonts and spacing are NOT the look. Build every section from the widgets the 1:1 editor uses (section cards, headers with icons, fields, switches, sliders). |

Live mockup (maintainer's canvas): https://claude.ai/artifact/Lue9ZeKBoeP6c7cnWm4iBv

## The two rules behind everything here

1. **One editor.** Editing a group member opens the *same* character editor a
   1:1 chat opens (`EditCharacterPage` on desktop, `CharacterEditPage` on
   web), with the same tabs, sections, controls, order and wording. Member
   mode may only *add* the pieces listed in section A and *grey out* the
   pieces listed there. It never swaps, hides, reorders or rewords a 1:1
   control. There is one implementation, not a member twin.
2. **The group keeps its own copy.** A member's edits save to the group's
   copy of that character (`saveGroupMemberCard`, the `group_members` row).
   They never write to the library character, and library edits never reach
   the group. The UI says so in both directions (A1, C).

## A. Editing a member from a group

Opened from: Edit group > Cast > "Edit Ana's card"; the chat sidebar's edit
action on a member. Desktop and web.

Exactly these differences from the 1:1 editor, nothing else:

**A1. Notice at the top of the Details tab**, above the avatar, full width of
the content column, accent border, people icon:

> **You're editing Ana in The Porch Trio only.**
> This group keeps its own copy of Ana. Changes here don't affect your solo
> chats with Ana, and edits to Ana's own card don't reach this group.

Names are the member's and the group's, never `{{char}}`. The page title
stays "Edit Ana", as in 1:1.

**A2. Time & Day greyed out, not removed.** The Time & Day card (Time of
Day, Day Number) and the row under it (Story begins / Opens at) render in
place, disabled, at reduced opacity. Hover (desktop, web pointer) and
long-press (touch) show the tooltip:

> Time & Day is set per group, not per character.

They show the group's values, read-only. They are set on the Edit group page
(B, Realism Engine).

**A3. Worlds tab greyed out, not removed.** The Worlds tab stays in the tab
bar at its 1:1 position, disabled (cannot be selected), with the tooltip:

> Worlds are set per group, not per character.

A group's worlds are set on the Edit group page's Worlds tab (B). One world
per group so the cast is always in the same place.

**A4. Group-only section at the end of the Details tab**, after the last 1:1
section (Optional Features), heading "In The Porch Trio" with a people icon,
built from the 1:1 section widgets:

- *System prompt in this group* (single field; helper: "Blank uses the
  System Prompt under Advanced Prompts.") = today's per-character group
  system prompt (`characterSystemPrompts`).
- *Author's note when Ana speaks* + *Strength* slider = today's
  per-character author's note and strength.
- *How Ana starts out feeling about the others*: one slider per other
  member ("Toward Bea · Warm"), helper "New chats only. Same values the Edit
  group page shows for Ana." = today's starting feelings between members.

These are the same stored values the Edit group page shows. Either place
edits them; there is one store.

**A5. Save target.** Unchanged from today: the group's member copy, never
the library. The start values (bond, trust, emotion, Needs, Afterglow,
Pockets) are the member copy's own new-chat defaults, edited with the 1:1
controls in their 1:1 places, as in 1:1. Remove the separate group "start"
path (`MemberGroupView.start` / `saveStart`) if the 1:1 controls can carry
the values on the member copy; if a stored shape must stay for old data,
read it as a fallback and write only the member copy.

**A6. Lite members** keep today's behaviour: Realism, Needs and Afterglow
hidden behind the existing note until promoted.

**A7. Chaos Mode** in member mode, in this PR: greyed out like A2, tooltip
"Chaos Mode is set per group for now." Per-character Chaos (each member's
own switch, 18+ events, pressure and Spin, the member editor toggle as the
new-chat default exactly as in 1:1) is the **next PR**, not this one.

**A8. Realism Verification greyed out** (switch, Max reprocess passes,
Strictness, Director authority): in a group it is a group setting, on the Edit
group page (B, Realism Engine). Same grey-out as A2, tooltip:

> Realism Verification is set per group, not per character.

**Delete** from member mode, desktop and web: the "These are Ana's own
settings in this group" banner, `memberGroupRows`, `memberGroupNeedsLine`,
the read-only "Realism Engine · On / Time & Day / Chaos Mode / Afterglow /
Needs" lines and their "Group Settings" links, and any member-only code
path in `edit_character_page/member_group_view*.dart` that A1 to A7 do not
need. The avatar stays locked in member mode (`allowAvatarChange: false`;
the member's avatar path is its storage key).

## B. The Edit group page

Replaces the Group Settings dialog (desktop `GroupSettingsDialog` and its
tab files; web `GroupSettings.tsx`). Everything that opened the dialog opens
this page. Same four tabs, same order, same icons as the 1:1 editor:
**Details · Dialogue · Lorebook · Worlds** (today's "Lore & Worlds" and
"Realism & Dynamics" tabs go away).

### Details tab, in this order

1. **Identity**: Group name. Cast: one row per member with avatar, name,
   "Edit Ana's card" (opens A), "Remove…". Then "+ Add a character" and
   "Bring back a removed member" (today's recovery).
2. **Turns** (group-only, ruling 3): Turn order (Round Robin / Random),
   Auto-advance, Start this group in Director Mode.
3. **Voice**: one line, no control: "Each member speaks in their own
   text-to-speech voice, set in their card: Ana · …, Bea · …".
4. **Personality & World**: Personality (new group field), Scenario.
5. **Advanced Prompts** (collapsed by default, as in 1:1): System Prompt,
   Post-History Instructions (new group field), then "Per-character, in
   this group only (optional)": for each member the group system prompt,
   author's note and strength (same store as A4).
6. **Tags** (new group field), the 1:1 tag control.
7. **Realism Engine**, header note "these settings only affect new chats
   with this group", intro line "Each member's Realism, starting
   relationship and emotion, Needs, Afterglow and Pockets are in their card,
   exactly where a 1:1 character keeps them. The shared scene is set here:"
   - Time of Day, Day Number; The story begins on…, The story opens at…
     (new for groups, the 1:1 controls).
   - Chaos Mode switch (stays here until the next PR moves it per member).
   - Realism Verification with Strictness, Max reprocess passes, Director
     authority (new for groups, the 1:1 controls).
   - Starting feelings between members: a slider per ordered pair (same
     store as A4).
8. **Your chats together** (new for groups): the 1:1 stats card (chats,
   your messages, their messages, first chat) over this group's chats.

### Dialogue tab

The 1:1 Dialogue tab minus Example Dialogue: First Message, Alternate
Greetings (with today's greeting seeds). A group has no Example Dialogue: one
text would be handed to every speaker as their own voice, and cannot be an
exchange between two characters. Each member's examples live in their card
(Edit Ana's card). The stored `mes_example` column and Group Card field stay
for old data and are no longer read into prompts.

### Lorebook tab

The 1:1 Lorebook tab over the group lorebook (entries, Add, Import file,
Export file, From character), plus "Inherit character & world lorebooks"
(group-only, kept).

### Worlds tab

The 1:1 Worlds tab (`GroupWorldsSection`, the picker both already share):
Setting world and "Also read lore from". Applies to the whole cast.

### Removed from groups, desktop and web

- Member Reset (Realism, Needs) and Reset ALL (ruling 6).
- Memory settings on this page (switch, memories per turn, budget %). They
  stay in the chat sidebar's Memory section, as in 1:1.
- Per-character memory importance sliders, their "Reset to defaults", and
  the retrieval weighting they fed.
- The group-wide Needs master switch. Each member's own Needs switch, as in
  1:1.

New group fields (Personality, Post-History Instructions, Tags, Example
Dialogue, story start date/time, Realism Verification settings) are
additive Drift columns on `groups` in the onUpgrade ladder, honest
`database.g.dart` diff, wired into prompt building exactly where the 1:1
fields are, and into Group Card export/import. Removing the importance
weighting must not drop stored data (leave the column, stop reading it).

## C. The 1:1 editor, when the character is in groups

One line at the top of the Details tab, same style as A1:

> Ana is also in The Porch Trio. Groups keep their own copy; changes here
> don't reach them.

Several groups: list them ("in The Porch Trio and Book Club"). No group:
no line. Desktop and web.

## D. Web

The PWA gets the same page, tabs, sections, order, notice, greyed controls
with tooltips (long-press on touch), and removals. Phone width: the same
sections in the same order, collapsible; the tab bar fits four tabs. The
PWA paints only `var(--…)` tokens.

## E. Proof the build must ship (CI)

- `one_ui_parity_test`: the member editor's section and leaf order equals
  the 1:1 editor's plus exactly A1, A4; A2, A3, A7, A8 present and disabled.
  Edit group page leaf order, desktop vs web.
- Goldens: Edit group Details tab; member editor top (A1) and Realism
  bottom (A2, A4, A7). Porch and one non-Porch theme, light and dark.
- Widget tests: member save writes the group copy and leaves the library
  row untouched (`doubleTapNoFrame`, exactly one write); Time & Day and
  Worlds cannot be changed in member mode and show the tooltip; removed
  controls are absent; C shows only when the character is in a group.
- Web: unit tests for the same, a sweep route for the Edit group page, a
  journey: open group > Edit Ana > change a field > save > the library
  character is unchanged.
- Deleted dialog tests and goldens: `approved-test-change`, with the reason
  "the Group Settings dialog is replaced by the Edit group page (PR 5)".
