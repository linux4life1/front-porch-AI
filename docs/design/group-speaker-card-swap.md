# Group speaker card swap (anti-jumble)

One room: the **group generation prompt**. Swap the speaker’s costume.
Keep the shared labeled script. Do not build a new group engine.

---

## 1. For Sosuke

A group chat is one play with several actors.

- The **script** is the transcript. Everyone reads the same pages:
  `Zinna: …` / `Senjumaru: …` / `you: …`. That does not change.
- A **costume** is that actor’s personality and example lines — how they
  sound when it is their turn.
- **Nametags** are the names on those lines, plus a one-line roll call so
  the speaker knows who else is in the room.

**Today the app dresses every actor in every costume at once.** Before
Senjumaru speaks, the model is also handed Zinna’s personality and Zinna’s
example dialogue. SillyTavern calls that **Join character cards**. Their
own docs warn it merges personalities. Front Porch is doing that Join
today, without a setting.

**After this change, only the speaker wears a costume.** When it is
Senjumaru’s turn she gets Senjumaru’s personality and Senjumaru’s examples,
plus a short slap: you are Senjumaru, you are not Zinna, you are not the
user. Zinna’s examples stay off that prompt. The script is still the same
shared log.

**What you will notice in chat**

- Group replies should sound like the person whose name is on the bubble,
  not a blend.
- The room does not jump to a newcomer’s solo scene just because they
  `/join`. The group keeps the group’s scene (or the host’s original scene
  when the group has none).
- 1:1 chats do not change. Scene Guests (the lite drop-ins) do not change.
- Continue and regen still continue/reroll **that bubble’s speaker**.

**What you will not notice**

- No new toggle. No new group mode. No rewrite of old messages.
- Opening greetings (`first_mes`) still do not get pasted in as an entrance.
- Context Viewer after a group send: **Persona** is a short roll call;
  the speaker’s costume sits in a **Speaker Card** row after the chat
  history, not mixed into everyone else’s.

**What this does not fix (later rooms)**

- A card that writes “right now she is on the riverside” in *her own*
  description still says that about herself. Swap only stops *other*
  people’s pages being stuffed into her turn.
- Remembered lines from RAG currently drop the `Name:` tag, so a nameless
  “I never want to see you again” can glue to whoever is speaking. That is
  Room 2.
- `/join` still does not scrub a newcomer’s present-tense solo scene out of
  *their* lore/examples. That is Room 3.

---

## 2. Current vs SillyTavern

ST group docs ([Group Chats](https://docs.sillytavern.app/usage/core-concepts/groupchats/)):

| Mode | What it does | Cache | Identity |
|------|----------------|-------|----------|
| **Swap** (ST default) | Before Char2 speaks, only Char2’s card fields are in context. History stays the shared labeled script. `{{char}}` is the speaker. | Prefix changes every speaker. | Clean. |
| **Join** | All members’ description, scenario (unless chat-overridden), personality, examples, and character notes concatenated in list order. | Built so llama.cpp can keep a stable prefix. | ST warns: identity confusion, merged personalities. |

Front Porch today is **Join of personality + examples**, with a **shared
scenario**, without ST’s Join/Swap setting.

Verified on this tree:

| Piece | What Front Porch does now | Path |
|-------|---------------------------|------|
| **Join personas** | `personaBlock` maps **every** `_groupCharacters` to `"{name}'s Persona: …"` and joins with newlines. | `lib/services/chat/chat_service_generation_blocks.dart` 115–125 |
| **Join examples** | `mesExampleBlock` concatenates **every** member’s `mesExample` (non-empty). | same file, 171–185 |
| **1:1 (unchanged target)** | One speaker’s persona; one `mesExample`. | same file, 126–132 and 186–188 |
| **Shared scenario** | `_activeGroup.scenario` if non-empty, else **first member’s** `scenario` (the host/anchor original). Not the speaker’s solo scenario. | same file, 138–148 |
| **`/join --full` group scenario** | `forkToGroupChat` sets `scenario: scenario ?? ''`. Empty → fallback to first member (host). Senjumaru’s riverside is **not** the Scenario block on that path. | `lib/services/chat/chat_service_group_membership.dart` 91–96 |
| **Guest scenario** | Scene Guest turns blank `t.scenario`. Factory also clears the guest card’s scenario. Keep. | `chat_service_generation_blocks.dart` 153–158; `scene_guest_factory.dart` 98–103 |
| **History labels** | `ChatMessage.toPromptHistoryLine()` → `$sender: $promptText` (think-stripped). | `lib/models/chat_message.dart` 141–154 |
| **Suffix** | Normal mode: `"\n${speakingCharacter.name}:"`. | `chat_service_generation_blocks.dart` 162–164 |
| **Group system head** | `defaultGroupSystemPrompt` — generic “character whose turn it is”, **no speaker name**. Observer uses `observerModeSystemPrompt`. | `lib/services/chat/chat_service_defaults.dart` 39–49 |
| **Per-speaker overlay (already swapped, but in the system head)** | Appends group-specific instructions or the card `systemPrompt` onto `t.systemPrompt`. That **churns the prefix every speaker**. | `chat_service_generation_blocks.dart` 53–65 |
| **Per-speaker author’s note** | Already speaker-scoped, already after history. Keep. | same file, 201–222 |
| **Guest identity slap** | `buildGuestTurnNote` in the author’s-note seat: “You are now X, NOT host, NOT user.” 1:1 Scene Guest only. | `lib/services/chat/scene_guest_prompt.dart` 48–77; wired at `chat_service_generation_blocks.dart` 256–262 |
| **Full-member slap** | **Missing.** Full members only get the generic group rules. | — |
| **Journal / realism / needs** | Already keyed on the speaking member (`_turnSpeakerIdForRealism`, journal `characterId`). Keep. | `chat_service_generation.dart` 320–326; journal build 347–374 |
| **`{{char}}` / `{{description}}`** | `_buildChatMacroContext(speaking)` already binds macros to **this turn’s speaker**. No dedicated description **section** exists on the wire. Do not invent one. | `chat_service_wiring_injection.dart` 288–322; `macro_resolver.dart` 336–337 |
| **Persona vs description on the wire** | Generation persona is `_getEffectivePersonality` (Growth-aware personality). Card `description` is **not** a PromptPlan section. It only appears if a card/system prompt contains `{{description}}`, or in the Context Viewer **Refresh estimate** (see below). | `chat_service_growth.dart` 239–244 |
| **Entrance** | `_generateMemberEntrance` is a hidden stage direction + `_generateResponse`. Does **not** paste `first_mes`. Still runs the full prompt, so today’s Join still leaks other members’ examples into the entrance turn. Swap on the generation path covers entrance for free. | `chat_service_guest_flow.dart` 265–292 |
| **Stops** | Other member names rotated so the next speakers survive a capped stop list. Keep. | `chat_service_generation_request.dart` 88–106 |
| **Continue / regen speaker** | Continue infers `forceSpeaker` via `resolveGroupSpeakerForMessage` (id first, refuse on duplicates). Regen already passes it. Assembly then uses `t.speakingCharacter`. Swap follows that automatically. | `chat_service_generation.dart` 210–286; `group_speaker_resolution.dart` |
| **Impersonate twin** | Group impersonate still **joins all personas** (examples already omitted). Same Join leak on the “write as the user” path. | `chat_service_impersonate.dart` 99–110 |
| **Context Viewer Refresh estimate** | Concatenates **every** member `description` + `personality` into `identityBlock`. Last-send snapshot comes from PromptPlan and will follow Swap; Refresh will still look like Join until this is updated. | `chat_service_context_budget.dart` 30–37 |
| **Lore inherit (not this room)** | Default `inheritCharacterLorebooks == true` injects **all** members’ lorebooks. Senjumaru’s “Present scene: riverside” can still fire on Zinna’s turn. | `chat_service_wiring_injection.dart` 27–31, 266–281 |
| **RAG nametags (Room 2)** | Group embeds under `group_<id>`. `rememberedLineFromWindow` strips `Name:` prefixes. | `rag_injection.dart` 265–286; `chat_service_generation_rag.dart` 347–351 |

ST Join also concatenates **description** and **scenario**. Front Porch
does **not** concatenate description on the generation wire, and already
shares one scenario. The jumble Sosuke hit is the **joined personality +
joined examples**, plus a missing named slap for full members.

---

## 3. Target prompt shape (one group turn)

### 3.1 System head (must stay byte-stable across speakers)

Prefix cache: anything that **changes with the speaker** and sits **before**
the transcript forces a full re-prefill of the script. Already measured in
`chat_service_generation_plan.dart` 21–56 (gemma-4-31B, 5.4k-token prompt):

- state zone **after** the transcript: ~508 of 5.5k tokens re-prefilled / turn
- the same zone **in the system message**: ~5020 of 5.5k / turn (**9.3×**)

ST Join exists so llama.cpp can keep that prefix. Front Porch already paid
the other side of that lesson with Journal: volatile speaker-shaped text
belongs **after** history.

**Keep in system (group):**

1. Group rules — `defaultGroupSystemPrompt` / `observerModeSystemPrompt`,
   or the group’s own `systemPrompt` when set. **Do not** rewrite this head
   to insert the speaker’s name.
2. Short **roster** (names only), same bytes every speaker:
   `Also present: Zinna, Senjumaru, {{user}}.`
   List **every** member plus the user. **Do not** drop the current speaker
   — that would churn the prefix every turn. Observer: members only, no user.
3. User persona block (already stable).
4. Shared Scenario block (group override, else host/first-member original),
   still wrapped by `ScenarioFade.wrapForChat`.
5. Lore buckets that already live in system (trigger volatility is
   pre-existing; out of scope).

**Empty in system (group):**

- `examples` (`mesExampleBlock = ''`)
- per-character group overlay / card `systemPrompt` append (move off this
  head; see 3.2)

**Persona section in system (group):** the roster line only. Not
`Zinna's Persona: …` + `Senjumaru's Persona: …`.

### 3.2 After the labeled transcript (author-note / state-zone seat)

New PromptPlan section, **not** `inSystem`, **not** in
`kStateZoneSectionIds` (Continue must **keep** it, same as today’s persona):

- **id:** `speaker_card`
- **label:** `Speaker Card` (Context Viewer + web budget modal)

Contents, in order:

1. **Identity slap** (full members, not Scene Guests — guests keep
   `buildGuestTurnNote`):

   ```
   [GROUP TURN. You are Senjumaru. You are not Zinna. You are not Alex.
   Reply ONLY as Senjumaru: their own dialogue, actions, and thoughts.
   Do NOT write, speak, or narrate anything for Zinna or Alex.]
   ```

   Sanitize names the same way as `clipGuestCite` / impersonate `_safeName`
   (strip `[]` / newlines). List every other member, then the user
   (observer: other members only).

2. Speaker costume:
   - `{speaker}'s Persona: {effective personality}`
   - speaker `mesExample` only (macro-resolved with **that** character’s
     name, as today’s per-member loop already does)

3. Per-character group system overlay / card `systemPrompt` fallback —
   the block currently appended at `chat_service_generation_blocks.dart`
   53–65, moved here so it stops busting the prefix.

Keep where they already are: per-character author’s note, entrance
directive, journal, realism, needs, suffix `\n{speaker}:`.

**Do not inject from the joining card:** `first_mes` / greetings, the
newcomer’s solo scenario as the room, other members’ personality or
examples.

**Description:** no new section. If a card’s system prompt or personality
contains `{{description}}`, macros already resolve to the speaker.

### 3.3 1:1 and Scene Guest

- 1:1: persona + examples stay in the system head, as now.
- Scene Guest: still 1:1 (`_activeGroup == null`), still speaker-only
  guest card, still blank scenario, still `buildGuestTurnNote`. Do not
  run the full-member slap on a guest turn.

### 3.4 Walk-through: Zinna + `/join --full` Senjumaru

Start: 1:1 with Zinna on the porch. `/join --full Senjumaru`.

1. `joinFull` → `forkToGroupChat` with `scenario: ''`.
2. Members: Zinna first, Senjumaru second. Scenario fallback = **Zinna’s
   original** porch, not Senjumaru’s riverside. That is already true.
3. Entrance generation calls `_generateResponse` for Senjumaru. **After
   Swap**, that prompt has Senjumaru’s persona/examples and the named slap,
   **not** Zinna’s `mesExample` / personality blob. The Scenario block is
   still the porch (or empty-if-faded), **not**
   `SENJUMARU_SCENARIO_MARKER` riverside.
4. Later Senjumaru turn, same costume rule. Later Zinna turn, Zinna’s
   costume only; Senjumaru’s examples are absent.
5. Senjumaru’s **own** card may still say “right now she is closing a
   fault” in description/examples/lore. Swap does not rewrite cards. That
   leftover is Room 3, not a Swap bug.

---

## 4. File list and function-level changes

New leaf (pure, testable, same shape as `scene_guest_prompt.dart`):

**Create `lib/services/chat/group_speaker_prompt.dart`**

Export from `lib/services/chat/chat.dart`.

```dart
/// Full-cast roll call for the system head. Same bytes every speaker.
String buildGroupRosterLine({
  required List<String> memberNames,
  required String userName,
  bool observerMode = false,
});

/// Named identity slap for a full group member (not a Scene Guest).
String buildSpeakerTurnNote({
  required String speakerName,
  required List<String> otherMemberNames,
  required String userName,
  bool observerMode = false,
});

/// `{name}'s Persona: {personality}` — speaker only.
String buildSpeakerPersonaLine({
  required String name,
  required String personality,
});
```

Do not grow `lib/services/chat_service.dart` (483). Do not add a new
`part` unless a 500-line split is required (below).

### 4.1 `chat_service_generation_blocks.dart` (376 — replace Join, do not grow)

`ChatServiceGenerationBlocks._assembleGenerationBlocks`:

- **Group `personaBlock`:** `buildGroupRosterLine(...)` only. Stop mapping
  all `_groupCharacters`.
- **Group `mesExampleBlock`:** `''`.
- **New `t.speakerCardBlock`:** slap + `buildSpeakerPersonaLine` for
  `t.speakingCharacter` + that speaker’s macro-resolved `mesExample` + the
  overlay currently glued onto `t.systemPrompt` (lines 53–65). Skip the
  overlay append on `t.systemPrompt`.
- 1:1 persona/examples: no behaviour change.
- Guest branch: no full-member slap; keep `buildGuestTurnNote`.
- Macro-resolve speaker persona/examples with
  `MacroContext(userName:, characterName: speaker.name)` as today.

### 4.2 `_GenTurn` field

Add `String speakerCardBlock = ''` on `_GenTurn` in
`lib/services/chat/chat_service_generation.dart` (**489 lines — one field
only**, no new comments). If any other edit is needed in that file, extract
`_GenTurn` first to a part `lib/services/chat/chat_service_gen_turn.dart`
so the file stays under 500.

### 4.3 `chat_service_generation_plan_register.dart` (230)

In `_registerGenerationPlanSections`, after `author_note` (before
`lore.an_bottom` is fine; keep insertion order documented):

```dart
plan.add(
  id: 'speaker_card',
  label: 'Speaker Card',
  text: t.speakerCardBlock,
);
```

`inSystem` defaults false. **Do not** add `speaker_card` to
`kStateZoneSectionIds`. **Do not** clear it in `_stripContinuePlanSections`.
Continue of Senjumaru must still be Senjumaru.

1:1: `speakerCardBlock` is empty → section omitted from Context Viewer
(`sectionTexts` already skips empty).

### 4.4 Impersonate (required twin, one-line hook)

`chat_service_impersonate.dart` 99–110 still joins all personas. Point
group impersonate at `buildGroupRosterLine` (no speaker slap, no examples —
examples already `''`). 1:1 impersonate unchanged. Do not dump every
member’s personality into “write as the user.”

### 4.5 Context Viewer Refresh

`chat_service_context_budget.dart` 30–37: stop concatenating every member’s
description+personality. Group estimate should match the new shape: roster
in Persona, speaker costume for **whoever would speak next**
(`_pickPresentGroupSpeaker` / current next pointer) as Speaker Card, shared
scenario. Last-send already follows PromptPlan once 4.1–4.3 land.

### 4.6 Context Viewer colours (tiny web/desktop parity)

New labeled section needs a distinct hue, same contract as the existing
comment (“shared verbatim with the web ContextBudgetModal”):

- `lib/ui/dialogs/context_viewer_dialog.dart` `sectionColors`
- `web_ui/src/components/ContextBudgetModal.tsx` `SECTION_COLORS`

Pick one unused data-viz colour (not a new chrome accent). Fallback grey
would work, but the two maps are supposed to match. No other web UI. No
new setting.

### 4.7 Line-count splits (only if an edit would cross 500)

| File | Now | Rule |
|------|-----|------|
| `chat_service.dart` | 483 | Do not touch. |
| `chat_service_generation.dart` | 489 | One field; else extract `_GenTurn`. |
| `chat_service_generation_blocks.dart` | 376 | Join→helpers should shrink. If overlay move pushes toward 500, the new leaf already holds the strings. |
| `chat_service_impersonate.dart` | 345 | Helper call only. |
| `context_viewer_dialog.dart` | 463 | One colour entry. |
| New `group_speaker_prompt.dart` | new | Stay small; one concern. |

`kGodFileBar` is 500. Do not add `god_files.json` leftovers.

### 4.8 Do not edit

- `defaultGroupSystemPrompt` wording (generic rules stay; names live in
  the slap).
- `first_mes` / greeting seed / entrance stage-direction text.
- RAG `rememberedLineFromWindow` (Room 2).
- Lore inherit (later room).
- Existing tests, goldens, `analysis_options.yaml`.

---

## 5. Cache / prefix decision (explicit)

**Decision: Swap the costume after the transcript. Do not Swap it in the
system head. Do not Join to save cache.**

| Choice | Prefix across round-robin | Identity | Verdict |
|--------|---------------------------|----------|---------|
| A. Speaker persona+examples in system (ST Swap literal) | Misses **every** turn (two-person round-robin never repeats a prefix) | Clean | Reject. We already measured this class of move at 9.3×. |
| B. Join all personas+examples in system (today) | Hits | Jumble | Reject. Product verdict. |
| C. Stable system (rules + name roster + shared scene) + speaker costume **after** history | Hits on the script; costume rides the ~500-token tail with Journal | Clean | **Ship this.** |

**Named cost of C:** speaker examples are no longer in the cached prefix.
They re-prefill as part of the post-history tail, like Journal. That is
the same bill we accepted for mood-ordered cards. It is not free, and it
is much cheaper than re-prefilling the transcript.

**Quality:** the slap and the costume sit nearer the `Name:` suffix, which
is the seat local models actually obey (guest slap, idle cue, and Journal
already live there). Putting the costume in system is not required for
quality; putting it there **is** required to burn the prefix.

**If a later poke shows weak in-character group replies:** try moving
**only** `mesExample` back to the system `examples` section (cache miss
every speaker, smaller than a full persona Swap). Do **not** re-Join. Do
not pretend that miss is free. That fallback is **not** this room.

**Already-volatile system bits (out of scope):** lore triggers, search /
user-tool lines, call-mode overlay. Do not “fix” them here.

**Continue:** stripping `speaker_card` would undress the speaker mid-line.
Leave it. Continue still must not re-open the state zone
(`kStateZoneSectionIds`).

---

## 6. Tests

New files only. Do not edit existing tests (test-integrity). No stub LLM
as the **pin**. Inspect the **prompt on the wire**.

Harness for the wiring test: `FakeBackendServer` + `lastChatBody`, same
pattern as `test/services/chat/state_zone_placement_test.dart` (real
listening OpenAI-compatible server, assertions on `messages[0].content`
and `messages[1].content`, not on the canned reply). Group boot like
`test/services/chat/posture_regen_rewind_test.dart` (insert group + two
members, `setActiveGroup`). Unique markers so Join cannot hide:

- Zinna personality: `ZINNA_PERSONA_MARKER`
- Zinna mesExample: `ZINNA_EXAMPLE_MARKER`
- Zinna scenario: `ZINNA_SCENARIO_MARKER` (porch)
- Senjumaru personality: `SENJUMARU_PERSONA_MARKER`
- Senjumaru mesExample: `SENJUMARU_EXAMPLE_MARKER`
- Senjumaru scenario: `SENJUMARU_SCENARIO_MARKER` (riverside)

Force the speaker with public `ChatService.setNextCharacter`.

### 6.1 `test/services/chat/group_speaker_prompt_test.dart`

Pure unit of the new leaf (same style as `scene_guest_prompt_test.dart`).

| Test | Red if… | Green |
|------|---------|--------|
| `roster is names only` | Line contains a personality blob | `Also present:` + names; no `Persona:` |
| `roster is stable across speakers` | Helper takes a speaker and drops them | Same string for Zinna-turn and Senjumaru-turn inputs |
| `observer roster omits the user` | User name present | Members only |
| `slap names the speaker and bans the rest` | Generic “whose turn it is” only | Contains `You are Senjumaru`, `You are not Zinna`, `You are not {user}`, bans dialogue/actions/thoughts |
| `slap sanitizes brackets in names` | Raw `[` survives | Same clip as guest note |

**Proven red:** implement the helper as “join every persona” and the roster
test fails.

### 6.2 `test/services/chat/group_speaker_card_swap_test.dart`

Wiring. **This is the load-bearing pin.** Deleting the product call site
in `_assembleGenerationBlocks` (restore the `map` over `_groupCharacters`)
must turn it red.

| Test | Assert |
|------|--------|
| `Senjumaru's turn does not wear Zinna's costume` | `setNextCharacter(Senjumaru)`; `sendMessage`; **user** message contains `SENJUMARU_PERSONA_MARKER` and `SENJUMARU_EXAMPLE_MARKER`; **neither** system nor user contains `ZINNA_PERSONA_MARKER` or `ZINNA_EXAMPLE_MARKER` |
| `costume sits after the transcript, not in system` | System does **not** contain `SENJUMARU_PERSONA_MARKER` / `SENJUMARU_EXAMPLE_MARKER`; user **does**; `user.indexOf('<START>')` < `user.indexOf('SENJUMARU_PERSONA_MARKER')`; slap is in user |
| `riverside is not the Scenario block` | Neither system nor user Scenario contains `SENJUMARU_SCENARIO_MARKER`. Host/group scene may still show `ZINNA_SCENARIO_MARKER` |
| `Zinna's turn does not wear Senjumaru's costume` | Mirror of the first test |
| `1:1 still puts persona in system` | Single character with `SOLO_PERSONA_MARKER`; system contains it (parity with `state_zone_placement_test`’s `Malumbra's Persona`) |
| `Continue of Senjumaru keeps Senjumaru's costume` | After her reply, `continueLastMessage` (or the production Continue entry the suite already uses); last chat body still has her markers, still lacks Zinna’s; no state-zone re-open required beyond existing Continue contract |
| `regen of Senjumaru still resolves Senjumaru` | `regenerateLastMessage`; speaker on the bubble stays Senjumaru; prompt still her costume |

Do **not** assert Scene Guest by rewriting `scene_guest_prompt_test.dart`.
Guest path is `_activeGroup == null`; Swap branches on group. If a guest
regression is cheap: one extra test in the **new** file that a 1:1 + guest
turn still contains `SCENE GUEST TURN` and still blanks scenario — only if
the harness is already there. Do not expand into director/observer beyond
roster-omits-user in 6.1.

**Impersonate:** one test in the new wiring file **or** a tiny extra case:
group impersonate prompt contains the roster and does **not** contain
`ZINNA_PERSONA_MARKER`. Required twin, not a new product.

### 6.3 What must stay green without editing those files

- `test/services/chat/scene_guest_prompt_test.dart`
- `test/services/chat/state_zone_placement_test.dart` (1:1 persona in system)
- `test/services/chat/group_speaker_resolution_test.dart` (who said it)
- `test/services/chat/prompt_plan_test.dart` — **do not edit**. It builds
  its own fixture plan; production adding `speaker_card` does not break it.

### 6.4 Analyze later, not now

When implementing: `flutter analyze` on touched Dart; `dart format` those
paths only; `flutter test` of the two new files plus
`test/hygiene/god_file_ratchet_test.dart`; `wc -l` on every edited Dart
file. Do not `dart format .`.

---

## 7. Non-goals / later rooms

**This room (must ship):** group generation prompt = speaker-only costume +
named slap + stable roster + stop concatenating all examples/personas.

| Later | Why not now |
|-------|-------------|
| **Room 2 — RAG nametags** | `rememberedLineFromWindow` strips `Name:`. Nameless remembered lines glue to the current speaker. Separate pin, separate product copy. |
| **Room 3 — `/join` present-tense scene** | Entrance + inherit lore still feed the newcomer’s “right now / riverside” from **her own** card. Neutralize on join, or don’t treat present-tense description as the room. Explodes into lore + card fields. |
| **Card craft** | Senjumaru’s description “Right now she is in the World of the Living…” is not an app bug. |
| **Lore inherit default-on** | All members’ lore still injects. Related leak, not costume Join. |
| **Director / observer / Scene Guest lite** | Guest already has a slap. Observer only needs roster-without-user (6.1). No director rewrite. |
| **Group `postHistoryInstructions`** | Currently omitted in group (`chat_service_generation_blocks.dart` 190–194). Do not start injecting it. |
| **Dedicated description section** | Not on the wire today. Do not invent one. |
| **Join/Swap user setting** | Product verdict is Swap. No toggle. |
| **Whole-tree 500-LOC cleanup** | Split only files this room would push over 500. |
| **Web settings / new chat chrome** | Prompt assembly is Dart. Maintainer deferred extra UI; colour maps in §4.6 are the only web touch. |

---

## 8. Done means

Observable without reading Dart:

1. Open a group (or `/join --full` a second card into a 1:1).
2. Send a line that lets B speak (`setNextCharacter` / wait for their
   turn).
3. Open **Context Viewer** (desktop) or **Context Budget** (phone/PWA).
4. **Last send → Persona** is a short “Also present: …” name list — not
   two personality essays.
5. **Speaker Card** (after Chat History) names **B**, quotes **B**’s
   persona/examples, and says B is not A and not you.
6. A’s unique example line is **absent**.
7. Scenario is still the group/host room, not B’s solo riverside.
8. 1:1 Context Viewer still shows `{Name}'s Persona` under Persona in the
   system half, as today.
9. Continue on B’s bubble still reads as B; regen still rerolls B.

**Poke script (Sosuke)**

1. 1:1 with Zinna. Talk once so there is a porch scene.
2. `/join --full` Senjumaru (or the library card that jumble-leaked).
3. When Senjumaru’s entrance / turn lands, open Context Viewer → Last send.
4. Confirm her examples, not Zinna’s; confirm Scenario is not the riverside
   seam.
5. Send another line for Zinna’s turn; confirm the reverse.

**Path-complete (implementer paste)**

```
### Path-complete checklist
- Turn events:
  - 1:1 send: unchanged (persona still in system)
  - group send: speaker-only costume + slap + roster
  - Continue: same speaker (forceSpeaker); speaker_card kept; state zone still stripped
  - Regen / swipe: same speaker id; same costume rule
  - Delete / edit: n/a (prompt assembly only)
- Twins grepped: impersonate group personas; Context Viewer estimate; guest slap left alone; journal/realism already speaker-scoped
- New test: test/services/chat/group_speaker_card_swap_test.dart (wire) + group_speaker_prompt_test.dart (leaf); proven red by restoring the Join map
- Web: no new UI; Speaker Card colour in ContextBudgetModal + desktop dialog (parity of existing maps). Other web deferred: prompt assembly is Dart.
- I cannot launch the app: [fill at implement time] → poke script: five steps above
```

**Release note (human prose, when this ships — not a commit dump)**

Group chats still share one script. They no longer dress every character
in every costume at once. On each turn the speaker wears only their own
personality and examples, and they are told who they are (and who they
are not). 1:1 and Scene Guests stay as they were.

---

## Key decisions

1. **Swap, not Join, not a new engine.** Product verdict.
2. **Costume after history, roster+rules in system.** Cache is the Journal
   lesson; named slap is the Scene Guest lesson.
3. **Roster lists the full cast every turn** so the system prefix does not
   change with the speaker.
4. **No description section.** Macros already speaker-bind `{{description}}`.
5. **Shared scenario stays shared.** Empty group.scenario → host/first
   member original, never the speaker’s solo scene.
6. **New leaf + new tests; no existing-test edits; no `chat_service.dart`
   growth.**

---

## Also in this commit (Rooms B and C)

Swap's design above is unchanged. Same worktree also ships the ensemble
mic and the convert path Sosuke actually typed:

- **Room B — `/speak` is the porch mic.** A 1:1 with a Scene Guest is an
  ensemble. `/speak <host>` generates the host (`_generateResponse`
  without `guestSpeaker`). Bare `/speak` is still the last guest. Unknown
  / ambiguous names list **host + present guests**. Full-group `/speak
  <member>` is a force (`forceSpeaker:`) so Away skip cannot swallow it,
  and busy shows the same banner as guest speak instead of a silent
  return.
- **Room C — `/join --full` converts.** The parser already routed to
  `joinFull`. The 1:1 call site now banners when there is no scene to
  copy, when the turn is busy, or when group support is missing — never a
  silent no-op. Named unique match (substring `senju` → Senjumaru) still
  calls `joinFull` (fork + present lite guests). Bare / ambiguous `--full`
  still parks `pendingPickerFull`; desktop and web pickers call `joinFull`,
  not lite join.
