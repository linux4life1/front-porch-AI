# Mood with bite — statement of work

Version 1, approved and built 2026-10-13 (branch feat/mood-with-bite). Status at the end.

Mood becomes a feeling the character carries: it has a cause, it holds from turn to turn, it eases on a schedule instead of vanishing, and it changes how the character acts. Bond and trust are not touched by any of this (ruling 2026-10-13: a character's own goals and moods say nothing about how they feel toward the user). This is the channel the objectives work will use next for a landed or dropped quest.

## What the engine does today (read from the code, not from the docs)

- The emotional judge runs every turn on the last four messages and names a feeling and an intensity (mild, moderate, strong). The previous mood reaches it as one clause in the standing line ("current mood: X (strong)") with no instruction to keep it. `docs/realism-engine.md` promises inertia and a fade over several turns; nothing in the code holds or fades the mood.
- The model gets one sentence: `Mood: Desire, strong — let it subtly color tone, body language, and word choice.` The same sentence for mild and for strong.
- Nothing else reads the mood. Needs, time and pockets have bands with consequences. Mood has none. Its only other readers are the expression portrait, the journal's hot-card sort and the memory query.
- Across the maintainer's library the judged mood looks like this:

| Measure | Across 1,392 stamped replies |
| --- | --- |
| Label changes from one reply to the next | 57% of turns |
| Intensity judged "strong" | 67% |
| Intensity judged "mild" | 4% |
| Labels from the negative family (anger, sadness, fear, disappointment, …) | 7% |

A mood that flips more often than not, is nearly always "strong", and is told to stay subtle cannot drive anything.

## What changes and what stays

Five things change. The mood gains a cause and a hold count. The judge is told the standing mood with its cause and asked to keep it unless the turn moves it. The app eases intensity on a fixed schedule when the feeling holds, and on every story day that passes. The prompt line scales with intensity, names the cause, and is followed by a mood-effects line in words. Other features (the planner today, objectives next) move the mood through one small door that regen can rewind.

Everything else stands: the label vocabulary (a free nuanced word; the expression label set when portraits are on), the judge's four-message window, one judge call per turn (no new model call anywhere in this work), bond, trust, desire and fixation untouched, Standing Mood (the pre-chat baseline) untouched, Realism off means none of this runs, regen, swipe and delete rewind the mood exactly as they rewind it today, and 1:1 and group behave the same for the character.

## The mood state

| Field | What it is |
| --- | --- |
| label | the feeling, one word, as today |
| intensity | mild, moderate or strong, as today |
| cause | why, in at most twelve words, in the character's own terms ("he lied to me about the money"); empty when neutral (the judge writes "none", the app stores nothing) |
| held | how many judge passes in a row have kept this feeling; 0 when it just changed |

Stored on the chat for a 1:1 and per member for a group, stamped on every reply beside bond and trust, carried in chat-package export and import, shown in the sidebar on desktop and on the phone.

## The judge

The standing line the judge reads becomes, in substance:

> Mood going in: furious (strong), because he lied about the money, and it has held for the last few exchanges. Keep it unless this turn genuinely moves it. A strong feeling eases over several exchanges; it does not vanish in one.

The judge answers four fields instead of two: `emotion`, `emotion_intensity`, `emotion_cause` (why, at most twelve words, "none" for neutral) and `emotion_change`, one of `held` (the same feeling, carrying on), `stoked` (the same feeling, freshly fed by this turn) or `moved` (a different feeling now). Both transports carry them: the tool schema (where `emotion_change` is a required field, because tool-calling models skip optional ones) and the JSON text floor. The Director's correction pass carries the two new keys through unchanged, the way it carries the others. The one-shot path applies them exactly as the multi-call path does.

How the app applies the answer:

| Judge says | The app does |
| --- | --- |
| moved | takes the judge's label, intensity and cause; held resets to 0 |
| held | keeps the stored label and cause; held goes up by one; intensity is the lower of the judge's and the eased value below, so an apology can ease anger faster than the schedule, but a lazily repeated "strong" cannot stop it easing |
| stoked | keeps the label, takes the judge's intensity and a fresh cause if it gives one; held resets to 0, so a feeling that keeps being fed stays strong for as long as the story feeds it |
| missing (an older model, a confused reply) | treated as held when the new label maps to the same canonical feeling as the stored one, else moved |

## Easing: the schedule

Easing is pure Dart. No model call, no setting.

| Held passes in a row | Intensity |
| --- | --- |
| 0–2 | as judged |
| 3–5 | one step down (strong becomes moderate) |
| 6 and up | two steps down (moderate becomes mild); mild stays until the judge moves it |

Every story day that passes eases one more step, and a mild mood that crosses a day clears to neutral with no cause. A character who skips ahead a month arrives neutral. "Next morning" takes a strong feeling to moderate: they slept on it. The day roll eases every group member, not only the one about to speak.

## The voice in the prompt

The mood line scales with intensity and names the cause. The hold is said in words, never as a count (the state block never quotes numbers): nothing for a fresh feeling, "still" after two or more held passes, "for a while now" after five.

| Intensity | Line (cause and hold words filled in) |
| --- | --- |
| mild | `Mood: Wistful, mild, since <cause> — it colours tone and word choice.` |
| moderate | `Mood: Wistful, moderate, because <cause> — it shapes what they say and do this turn.` |
| strong | `Mood: Furious, strong, because <cause>, still — it leads this reply: they act on it before anything else.` |

The prefix `Mood: <Label>, <intensity>` is the one the existing prompt pins already check, so it stays. The cause clause is omitted when the cause is empty. Version 1 writes they/them for the character; the app has no pronoun field on the card yet.

Then, at moderate and strong only, one effects line: the pull the feeling has on what the character does, in the same stepped-text style the Needs bands use, always framed as inclination in their own manner, never as an instruction. A mild mood gets no effects line; the cause does the work. The family comes from the label through the existing nuanced-word map (the one the portraits use): sour (anger, annoyance, disgust, disapproval), low (sadness, grief, disappointment, remorse), anxious (fear, nervousness, confusion, embarrassment), lifted (joy, amusement, excitement, optimism, pride, relief, gratitude, admiration, approval), warm (love, affection, caring), charged (desire, anticipation, curiosity, surprise, realization). Neutral and unmapped words get no effects line. The line opens with "In their own way:" so a stoic and a hothead carry the same pull differently; the cause and the card's personality decide how it shows.

| Family | moderate | strong |
| --- | --- | --- |
| sour | less patience, no warmth offered; a favour is a harder sell | the grievance comes first: they may refuse, argue, withdraw or leave before anything else |
| low | little initiative, shorter replies, easily discouraged | withdrawn: may not engage, answers in fragments, nothing lands as good news |
| anxious | hedges, seeks reassurance, avoids commitments and risk | fixed on the threat, cannot settle into the scene, may bolt or freeze |
| lifted | takes initiative, says yes more readily, playful | carried away: bold, generous, starts things, laughs off small slights |
| warm | attentive, reaches out, small acts of care | openly tender: closeness before anything else, quick to forgive |
| charged | leans in, pushes the scene toward what they want | single-minded: everything bends toward it and patience is thin |

The two lines stay one fragment of the state block, in the slot the mood line holds today.

**Self-determination (ruling 2026-10-13).** The mood never forces cooperation. A character in a strong sour or low mood may refuse, argue, withdraw or walk out, and no line here or anywhere in the state block tells the model to comply with the user. A character who must cooperate is a puppet; the effects lines describe inclinations, never obligations.

## Other features moving the mood

One door: set a mood with a label, an intensity and a cause, held 0. It is stamped on the turn that moved it, so regen, swipe and delete rewind it with everything else. A change made outside a turn (the today line's X in the sidebar) patches the visible reply's stamp and saves, so a swipe back still finds it. The planner's today line is the first user of the door: a finished line sets content (moderate) with the line as the cause; an abandoned line or a day that ate it sets annoyed (moderate). Today the planner sets a bare label with no cause and no stamp. The objectives work will use the same door for a landed quest and a dropped one.

## Groups

Per member, as today: the two new fields ride the member's realism record and are loaded into the live registers when that member is about to speak and saved back after. The day roll eases every member's stored mood, not only the loaded one.

## Rewinds

The two new fields are captured in the reply's realism stamp wherever label and intensity are captured, and restored at every door that restores them: regen revert, swipe, delete, fork, import, the greeting re-seed, a cast change. Easing that happens after the reply (the day roll) lands on the reply's stamp through the post-reply restamp, so a swipe back shows the eased mood, not the one from before the clock moved. The file-by-file list is in Files below.

## Desktop and web

No new screen. The mood row in the sidebar's Character State card and the group member card gains the cause and the hold word: `Furious (strong) · because he lied about the money · still`. The phone's chat insight shows the same line. Chat-package export carries the cause. Before this is called done, the desktop card and the phone card are rendered side by side.

## Tests

- The easing rules and the family map are a pure leaf with their own test file (the feature has none today). Each rule is proven red by breaking it.
- The judge apply rules get new cases appended to the one-shot parity test, so both transports stay identical by construction.
- Stamp and rewind get a case appended to the existing regen and swipe tests: a mood with a cause and a hold survives regen and comes back on swipe.
- The prompt voice gets cases appended to the prompt-injection and state-block-order tests: the three intensities, the hold words, the effects line, and that the mood stays one fragment in its slot.
- The web line gets a vitest case beside the chat-insight tests.
- The sidebar golden may drift when the row grows; that is a reviewed change with the maintainer's label.

## Live check on the media server

Five turns in a scene where the character is lied to: the mood line names the lie as the cause, holds across the next turns, eases from strong to moderate on the fourth, and the reply visibly refuses or withdraws while it is strong. Then a two-day skip: the mood clears. Desktop and phone screenshots and the log lines go in the pull request.

## Files

Verified against the tree on 2026-10-13. Several ChatService parts sit within ten lines of the 500-line cap, so the mood state lives in one new leaf and every existing two-line read or write of label and intensity becomes a single call into it; the near-cap parts shrink or stay flat. No new part files.

| Stage | New | Changed |
| --- | --- | --- |
| Pure leaf | `lib/services/chat/mood_physics.dart` (state, judge rules, easing, cause cleaning, hold words, tone family), `lib/services/chat/mood_effects.dart` (the copy tables), `lib/services/chat/mood_registers.dart` (the one door: set, reset, seed, apply, ease, stamp, restore, group load/save, display line) | `lib/services/chat/chat.dart` barrel |
| State | — | `chat_service_fields.dart` (two fields), `chat_service.dart` (three class-pinned getters), `database.tables.core.dart`, `database.migrations.late.dart` (v57, additive), `database.dart` (57), `database.repair.dart`, regenerated `database.g.dart`, `chat_service_session_hydrate.dart`, `chat_service_session_state_save.dart`, `group_member_realism.dart` (two keys), `realism_dance.dart` (speaker load/save), `chat_service_import_seed.dart` + `fpchat_format.dart` (chat package head keys; stamp version stays 2) |
| Judge | — | `realism_prompt_builder.dart` (standing line; the two new args at all four call sites so the shared judge prefix stays byte-identical), `realism_prompt_fragments.dart` (emotion section), `realism_tool_schemas.dart` (two fields, `emotion_change` required), `realism_evals.dart` (optional getters/setters), `realism_eval_support.dart` (the ONE apply), `realism_eval_one_shot.dart` (drops its own emotion regex and calls the same apply), `realism_director_rules.dart` (carry the keys through), the two eval wiring parts |
| Stamps and rewinds | — | `realism_snapshot.dart` (capture + post-reply restamp of the four keys), `chat_service_regen_revert.dart`, `chat_service_send_handoff.dart` (two sites), `chat_service_speaker_objectives.dart` (the shared restore used by swipe, delete, fork, import and the greeting re-seed), `chat_service_cast_shrink.dart` (two sites), `chat_service_reprocess_choice.dart` (judged registers), seeds in `chat_service_chat_entry.dart`, `chat_service_group_entry.dart`, `chat_service_session_manage.dart`, `chat_service_import_walk.dart`, `chat_service_greeting_seed.dart`, `long_skip_settle.dart`; day roll via a new optional `onStoryDaysCrossed` on `time_service.dart` wired in `chat_service_wiring_realism.dart` (eases the live registers and every group member's record); `chat_service_planner_resolve.dart` uses the door |
| Prompt | — | `prompt_injection/emotion_injection.dart` (optional cause/hold getters; one fragment, same slot), `chat_service_wiring_injection_leaves.dart` |
| Desktop and web | `web_ui/src/components/ChatInsight.mood.test.tsx` | `character_state_group.dart` (mood row), `group_member_card.dart` + `chat_service_group_read.dart` (member cause/hold), `services/web/facade/chat_realism_read.dart` (host and member: cause, hold, mood line), `web_ui/src/components/chatTypes.ts`, `ChatInsight.tsx`; then `npm run build` |
| Tests | `test/services/chat/mood_physics_test.dart`, `test/services/chat/mood_with_bite_test.dart` (the one ChatService journey: stamp, regen revert, day roll restamp, two-day skip to neutral, non-loaded group member fades) | New cases appended to: `one_shot_parity_test`, `realism_prompt_builder_test`, `judge_tools_wire_test`, `director_rules_reachable_test`, `prompt_injection_test`, `group_member_realism_wire_format_test`, `session_scalar_parity_test`, `planner_today_fate_test`, `repair_story_clock_columns_test`, `session_rename_preserves_engine_test`. `fpchat_stamp_keys_test` goes red on its own until the head keys are listed. Needs the maintainer's label: `v14_to_current_upgrade_test` (schema 56 to 57) and the golden fake, which gains two defaulted fields so the sidebar golden's pixels do not move. |

Left alone on purpose: the card's authored starting mood and the group baseline seed carry no cause (the first judge pass supplies one); `moodLabel` stays verbatim for the portrait swiper and older web clients; the call strip is unchanged.

## Status
- 2026-10-13, reviewed: the independent review found one real bug and one gap, both fixed. The day-roll patch of the visible reply fired on an OOC skip too (the skip is applied before any busy flag), so the clock applier now says which rolls are made by hand (`manual`, from the chevrons and the calendar dialog) and only those patch stamps; in a group that patch covers every member's latest reply. A dead door was removed and two missing test cases added. Rewinds: a reply's own clock pass is restamped afterwards; a skip on the way to a reply belongs to that reply's capture; a manual roll patches the latest replies.

- 2026-10-13: draft written from the diagnosis; mechanics, schedule and prompt copy above are proposals awaiting the maintainer's word.
- 2026-10-13, ruling: a strong sour mood may refuse the user outright; the copy keeps that bite and must never force cooperation (self-determination, not a puppet).
- 2026-10-13, held against the north star (simulate real feelings, bring the characters to life): the judge's hold field became three-way (held / stoked / moved) so a feeling the story keeps feeding stays strong and an apology can ease anger faster than the schedule; the effects line now speaks only at moderate and strong and opens "In her own way:" so personality, not the table, decides how the pull shows.
- 2026-10-13, built: every stage above is in on the branch, each guard proven red then green (schedule, day easing, effects line, regen restore, post-reply restamp, day-roll easing). Three things the build taught: the mood door must treat the pre-reply quest check as inside a turn (the generating flag rises only afterwards), or it patches the previous reply's stamp and a delete restores the new mood; the text-reply salvage demands every required tool field and a non-empty string for every string field, so the judge writes "none" for a neutral cause and the one protected salvage fixture gained the change field; the eval engine leaf has its own emotion callbacks and does not take the mood ones.
- 2026-10-13: file-by-file survey done (Files above). Adjustments from it: the mood line keeps the pinned `Mood: <Label>, <intensity>` prefix; they/them in version 1; `emotion_change` is required in the tool schema; a mood change outside a turn patches the visible reply's stamp.
- Going with as proposed unless the maintainer objects: the easing speed (three passes per step, one step per story day) and the cause wording (the character's own terms, never a quote of the user).
