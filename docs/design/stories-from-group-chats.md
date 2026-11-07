# Stories from group chats

Status: **decided, implemented with this document.** A Porch Story could
start only from a 1:1 chat: the chat menu hid *Turn Into a Story…* in a
group, the relay refused `POST /api/chat/tools/to-story` in group mode, and
the New Story picker listed 1:1 chats only. This is the set of decisions
that lets a group chat be the source, on the desktop and in the web app.
Companion to [stories-in-worlds.md](stories-in-worlds.md) §3.4 (a chat's
Setting carries into the story) and
[porch-stories-studio.md](porch-stories-studio.md) (the engine that reads
the cast and the timeline).

## 1. The cast

**Every roster member joins the cast.** A group's members are rows of
`group_members`, not library characters: each has its own UUID, which is
also the `character_id` a message in that chat carries. The story keeps
those ids:

- `chat_history_character_ids` holds the member ids, in roster order.
- `character_card_snapshots` holds one snapshot per member, built from the
  member row (name, description, personality, scenario, first message,
  system prompt) with an `id` key, plus the persona snapshot when the user
  is in the story. On the relay the snapshot text comes from the member
  rows (`StorySnapshotBuilder` gets them as extra cards); the client never
  sends card text, as before.
- `chat_group_id` / `chat_group_name` (additive, absent for a 1:1 source)
  say where the roster came from, so a reopened draft shows the group and
  the relay knows which members to look up.

**The lead.** The first roster member is the lead (`Protagonist`) unless
the user picks otherwise. For a group promoted from a 1:1 the first member
is that chat's host, so the story leads with the character the chat began
with. The persona keeps `Protagonist` alongside the lead, exactly as the
1:1 story does (the user is a protagonist of their own chat); every other
member is `Supporting`. *Turn Into a Story…* shows a **Lead** row of the
roster plus the persona, defaulting to the first member; the web button
gets the same choice as a select. The New Story wizard's Cast step lists
the members with the same role chips library characters get, so "picks
otherwise" there is the ordinary role change.

A member removed from the cast on the Cast step still spoke in the chat:
the timeline names them, the bible is told so, and the cast is what the
user left. Removing the chat removes the whole roster, as it removes the
one character of a 1:1 source today.

## 2. The timeline names speakers

The distiller already lines up `sender: text`. For a group session it names
each line's speaker **from the message's `character_id`** through the
roster, falling back to the stored sender name only when the id resolves to
nobody (a member removed since). Never from whoever is active in the chat:
the distiller runs long after the chat and the active speaker is the last
one to have answered. The user's lines keep the persona name they were
sent under.

The distiller prompt is told who is talking: *"The conversation is a group
scene: the characters are Mira, Dov and Ash, each speaking for themselves;
the user plays Sam. Name the speaker in every event."* A 1:1 chat keeps
the one-character wording. The canon block every stage reads
(`StoryChatHistory.context`) opens with the same cast sentence, so a
timeline event that says "she" is read against the right roster.

The chat the story grew from is its **session id**. The history loader,
the preview and the distiller load the listed sessions by id (a group
session has no `character_id` of its own) and fall back to "every session
of the listed characters" only for a project with no session list, which
is the pre-Living-Time contract.

## 3. What the bibles are told

Nothing about the engines changes. Both already receive the cast as
`StoryContext.characterCards` / `StudioContext.cast` with one profile per
snapshot and the role on each, so a three-member roster reaches the
foundation as three core characters. What the group source adds is in the
canon block, where both engines read it:

- the cast sentence of §2, and
- one rule for a multi-protagonist source: *"Keep every one of these
  characters as themselves. Do not fold two of them into one, and do not
  drop one because another carries more of the story."*

The faithful directives are unchanged: "the cast is the people who appear
in the timeline" already covers a roster.

## 4. The world

A group chat keeps its Setting on the session's world slots, the same way
a 1:1 does (PR #646 keeps it through a promotion). The story reads it
through the session id in both entry points, so nothing in the world
carry-over is group-specific:

- *Turn Into a Story…* and the relay pass `chatPrimaryWorldId` /
  `chatSettingName` to the builder, as the 1:1 path does.
- The New Story Idea step fills the world card from
  `getChatWorldAttachments(sessionId)` after a chat is adopted, with the
  "from the chat" chip, and the web step asks
  `GET /api/stories/world-summary?session=` the same way.

## 5. Entry points

| Surface | Before | Now |
|---------|--------|-----|
| Chat menu *Turn Into a Story…* | hidden in a group | shown; the dialog gains a Lead row in a group |
| `POST /api/chat/tools/to-story` | `1:1 chat with a character required` | accepts a group; optional `lead` (member id or `persona`) |
| Web chat tools *Turn this chat into a story* | 1:1 only | a Lead select in a group, sent with the request |
| New Story *Choose a chat…* (desktop and web) | 1:1 chats | group chats too, titled by group name with the roster under it; search matches member names |
| `GET /api/stories/chat-sources` | 1:1 rows | rows add `group_id`, `group_name`, `members[{id,name}]` (additive) |
| Idea card | the character | the group name, the roster, "its characters join the cast" |
| Cast step | library characters | the members too, with the group avatar, role chips and Remove |

## 6. Not in this change

- **Guests in a 1:1.** A `/join`'ed scene guest is not on a 1:1 roster;
  that chat still becomes a one-character story and the guest appears in
  the timeline by name.
- **Member cards that changed since the chat.** The snapshot is the member
  row as it is when the story is made, as the 1:1 path snapshots the card
  then. No history of card edits.
- **Story-side lead switching after setup.** Roles change on the Cast
  screen, as for any cast.
