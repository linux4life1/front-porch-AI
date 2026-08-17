// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/ambition_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/plan_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/behavioral_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/emotion_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/needs_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/nsfw_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/inventory_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/preferences_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/promise_debt_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/relationship_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/time_injection.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/weather_injection.dart';

/// The words-only state block composer (docs/design/prompt-state-injection.md
/// §3): the ONE place the model receives the speaker's live internal state.
///
/// Thin by contract — this class only GATES, ORDERS, and WRAPS the fragments
/// the leaf builders produce; all ladder/stepped prose lives in the leaves
/// (file-size rule + single source per fact). No simulation scalar ever
/// appears here: every number was translated to banded language upstream, so
/// stat-bleed ("my hunger at 41…") is structurally impossible rather than
/// merely discouraged. Salience-gated fragments return '' and vanish. (In
/// practice the bond+tension line renders whenever realism is on — a
/// deliberate anti-drift anchor — so the block only fully disappears when
/// realism is off or every builder is inactive; "quiet" means ~130 tokens,
/// not zero.)
///
/// Output shape (macro-resolved by the assembly call site — fragments may
/// carry {{user}}):
///
/// ```
/// [How NAME is right now:
/// time line
/// bond+tension (+voice note)
/// trust calibration
/// mood line
/// 0-3 need lines
/// body/arousal line
/// fixation / position lines
/// private group feelings
/// Express all of this only through NAME's behavior, body language, and
/// voice — never quote meters, scores, percentages, turn counts, or system
/// terms.]
/// ```
///
/// Replaces the old "Current Metrics" sheet + 8 restating sub-blocks + three
/// collation paragraphs (~700-1200 tokens, every fact 2-3×, and a literal
/// "use these numbers directly" instruction that CAUSED the reported
/// stat-bleed). 1:1↔group parity rides the leaves' per-speaker dispatch,
/// exactly as before; one-shot parity holds because both eval paths share
/// this single assembly-time block.
class RealismStateInjection {
  final RelationshipInjection relationshipInjection;
  final EmotionInjection emotionInjection;
  final TimeInjection timeInjection;
  final WeatherInjection weatherInjection;
  final AmbitionInjection ambitionInjection;
  final PlanInjection? planInjection;
  final PreferencesInjection preferencesInjection;
  final InventoryInjection inventoryInjection;
  final PromiseDebtInjection promiseDebtInjection;
  final BehavioralInjection behavioralInjection;
  final NsfwInjection nsfwInjection;
  final NeedsInjection needsInjection;

  final bool Function() getRealismEnabled;

  /// Whether the story clock is actually advancing — under the engine, or on
  /// the standalone scene-time eval. Gates the scene-facts fragments (see
  /// [_sceneFactsEnabled]).
  ///
  /// Optional for the same reason as the two below: existing callers and the
  /// protected prompt_injection_test keep compiling. Absent falls back to
  /// [getRealismEnabled], which is byte-for-byte the behaviour those callers
  /// had before the standalone clock existed.
  final bool Function()? getClockRunningOverride;

  bool getClockRunning() =>
      (getClockRunningOverride ?? getRealismEnabled).call();

  /// Long-term goals. Independent of realism: card-authored, never stale.
  ///
  /// Optional so existing callers (and the protected prompt_injection_test)
  /// keep compiling; absent means "on", which matches how these behaved
  /// whenever realism was enabled.
  final bool Function()? getAmbitionsEnabled;

  /// The one-shot real-absence note (living-time-features.md §2), lifted out
  /// of the time fragment on 2026-08-07. It answers to its OWN gate — the
  /// closure returns null unless the opt-in is on and a note is pending — and
  /// deliberately NOT to [_sceneFactsEnabled]: the note is computed from your
  /// last message's wall-clock timestamp, not from story time, so a frozen
  /// story clock has no bearing on whether it is true. Riding the time
  /// fragment is exactly why it was silently dead with the clock stopped.
  /// Optional for the same reason as the others: the protected
  /// prompt_injection_test keeps compiling.
  final String? Function()? getAbsenceNote;

  /// Standing Mood — what the character walked in carrying, before the user
  /// said anything. Ungated in the fragment list below for the same reason
  /// preferences and pockets are: it answers to its own switch and nothing
  /// else, and it self-gates to '' on an unremarkable day.
  final String? Function()? getStandingMood;

  /// The promise ledger. Independent of realism, but stored as Journal cards,
  /// so the caller's predicate must also require the Journal. Optional for the
  /// same reason as above.
  final bool Function()? getPromisesEnabled;
  final bool Function() getIsGroupNonObserverMode;
  final String Function() getCurrentSpeakerIdForRealism;
  final List<CharacterCard> Function() getGroupCharacters;
  final CharacterCard? Function() getActiveCharacter;
  final String Function(CharacterCard) getCharacterIdFromCard;

  RealismStateInjection({
    required this.relationshipInjection,
    required this.emotionInjection,
    required this.timeInjection,
    required this.weatherInjection,
    this.getAmbitionsEnabled,
    this.getPromisesEnabled,
    required this.ambitionInjection,
    this.planInjection,
    required this.preferencesInjection,
    required this.inventoryInjection,
    required this.promiseDebtInjection,
    required this.behavioralInjection,
    required this.nsfwInjection,
    required this.needsInjection,
    required this.getRealismEnabled,
    this.getClockRunningOverride,
    this.getAbsenceNote,
    this.getStandingMood,
    required this.getIsGroupNonObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getGroupCharacters,
    required this.getActiveCharacter,
    required this.getCharacterIdFromCard,
  });

  String _speakerName() {
    if (getIsGroupNonObserverMode()) {
      final id = getCurrentSpeakerIdForRealism();
      final card = getGroupCharacters()
          .where((c) => getCharacterIdFromCard(c) == id)
          .firstOrNull;
      // Never fall back to getActiveCharacter() in group mode — it points at
      // the PREVIOUS speaker after the realism dance, and heading the block
      // with their name over this speaker's data is worse than a generic
      // label (review finding).
      return card?.name ?? 'the character';
    }
    return getActiveCharacter()?.name ?? 'the character';
  }

  /// SCENE FACTS: where and when the scene is, what this character is working
  /// toward, and what they owe. Four of the fragments below are these, and not
  /// one of them contains a realism check of its own — time_injection has no
  /// gate at all, weather gates on the weather being null, and ambitions and
  /// promises gate on having any.
  ///
  /// This getter covers only TIME and WEATHER now — ambitions and promises
  /// each answer to their own user-facing switch (getAmbitionsEnabled /
  /// getPromisesEnabled), because neither needs the engine: ambitions are
  /// card-authored text, promises are Journal cards detected from dialogue.
  ///
  /// And time and weather do not need the engine either. They need a clock
  /// that MOVES, which is what [getClockRunning] reports (updated 2026-08-06,
  /// superseding the 2026-08-02 "must stay gated on realism" note here).
  ///
  /// The old reasoning was sound for its facts: with the clock frozen, this
  /// fragment would inject the SAME timestamp every turn while the story
  /// visibly moved — a lie told once per turn. That is still true, and it is
  /// still what this gate prevents. The change is only in what unfreezes the
  /// clock: the engine used to be the sole driver, and now the standalone
  /// scene-time eval is a second one. When neither is running, this is false
  /// and the fragment is suppressed exactly as before. Weather follows for
  /// free — currentWeather is null unless the clock is moving.
  ///
  /// Do NOT weaken this to "passage of time is enabled". That flag defaults
  /// on and is inert without a driver, so it would resurrect precisely the
  /// frozen-timestamp lie this gate exists to stop.
  bool get _sceneFactsEnabled => getClockRunning();

  /// CHARACTER STATE: how this character is right now. Genuinely realism, and
  /// correctly gated.
  bool get _characterStateEnabled => getRealismEnabled();

  /// The one sentence that lets a character use what she is already carrying.
  ///
  /// Emitted ONLY when the needs fragment and the inventory fragment are both
  /// present — which means Needs is on (so the Realism Engine is too), Pockets
  /// is on, something is actually biting, and she actually has something. Any
  /// of those missing and this is absent, because it would have nothing to
  /// point at.
  ///
  /// WHY IT EXISTS. Both facts already reached the model — "thoughts keep
  /// returning to when the next meal might come" a few lines above "carrying a
  /// candy bar" — and nothing joined them. A frontier model usually noticed; a
  /// smaller local one narrated the hunger and walked past the food in her own
  /// pocket, or went off to cook something. A person eats what is in their
  /// pocket before they go to the kitchen.
  ///
  /// WHY IT IS PHRASED THIS LOOSELY. It names no need and no item on purpose.
  /// A food-word list here would be the wrong shape twice over: it would put a
  /// pantry vocabulary in a prompt composer, and it would only ever cover
  /// hunger, when the same instinct governs a coat in the cold, a bottle when
  /// thirsty and a painkiller for a headache. Letting the model judge relevance
  /// costs nothing and generalises; "if" and "would" leave it free to decide
  /// that nothing she has helps, which is the common answer.
  ///
  /// It does NOT suppress the feeling — she still shows the hunger. It only
  /// stops her from overlooking what is already in her hand.
  static const _useWhatSheHasLine =
      'If something they are already carrying or wearing would ease any of '
      'that, they would reach for it before looking elsewhere.';

  String buildRealismStateInjection() {
    // Hoisted out of the list below so the join-line can ask whether BOTH
    // actually said anything. Each still self-gates exactly as before, so the
    // emitted fragments are unchanged.
    final needsLine = _characterStateEnabled
        ? needsInjection.buildNeedsInjection()
        : '';
    final inventoryLine = inventoryInjection.buildInventoryInjection();

    // No blanket early return. One gate used to sit here and silently delete
    // all eleven fragments — including the four that are not realism features —
    // which made the coupling invisible to anyone reading a single builder.
    // Each fragment declares the gate it answers to, and the GATES ARE
    // UNCHANGED by the ordering pass below: every `if` here is the same one
    // that fragment always had.
    //
    // ── WHY THIS ORDER ──────────────────────────────────────────────────────
    // The fragments accumulated one at a time over months, each appended where
    // it happened to be written, and nobody had read the result end to end. It
    // showed. The block told a character she was starving four lines before
    // telling her what was in her pocket; it staged her physical position dead
    // last, after everything she might do from it; it said "she came in not at
    // her best" before any of the weather or needs that explain why; and it
    // split how-she-feels-about-people across the very top and the very bottom
    // with everything else in between.
    //
    // A model reads this top to bottom and every line is conditioned by what
    // came before. So the order is now the order a person would think it:
    //
    //   1. the scene   — when, where, and where everyone is standing
    //   2. her people  — who she is with and how she feels about them
    //   3. her word    — what she owes them
    //   4. who she is  — the standing facts that do not change with the hour
    //   5. how she is  — the volatile state, last, right next to the
    //                    instruction to express it
    //
    // A fact that explains another fact comes first. A directive comes after
    // everything it refers to. Nothing here is cosmetic: it matters least for
    // frontier models, which read the whole block regardless, and most for
    // small local ones — which are exactly the models these fragments exist to
    // prop up.
    final fragments = <String>[
      // ── 1. THE SCENE ────────────────────────────────────────────────────
      if (_sceneFactsEnabled) timeInjection.buildTimeInjection(),
      // Out-of-story note about the real-world gap since the last exchange.
      // Kept beside the time line because it is also about elapsed time.
      getAbsenceNote?.call() ?? '',
      // MOVED UP, from below the standing-mood line. Weather is a scene fact
      // like the clock, and it is one of the things the mood line is derived
      // FROM — stating the conclusion before the evidence read backwards.
      if (_sceneFactsEnabled) weatherInjection.buildWeatherInjection(),
      // MOVED UP from dead last, and split out of the behavioural fragment.
      // "Position: … — ground actions in this" is staging: the model has to
      // know where everyone is standing BEFORE it decides what happens, not
      // after it has already written the scene.
      if (_characterStateEnabled) behavioralInjection.buildPositionInjection(),

      // ── 2. HER PEOPLE ───────────────────────────────────────────────────
      if (_characterStateEnabled)
        relationshipInjection.buildRelationshipInjection(),
      if (_characterStateEnabled)
        relationshipInjection.buildTrustBehaviorInjection(),
      // MOVED UP from dead last, to sit with the other two relationship lines.
      // How she feels about the people in the room is one subject and was
      // being told in two places with nine fragments in between.
      if (_characterStateEnabled)
        relationshipInjection.buildInterCharacterFeelingsInjection(),

      // ── 3. HER WORD ─────────────────────────────────────────────────────
      // Directly after the people, because a commitment is owed TO one of them.
      if (getPromisesEnabled?.call() ?? true)
        promiseDebtInjection.buildPromiseDebtInjection(),

      // ── 4. WHO SHE IS ───────────────────────────────────────────────────
      // Standing facts, ahead of the volatile state they colour.
      if (getAmbitionsEnabled?.call() ?? true)
        ambitionInjection.buildAmbitionInjection(),
      planInjection?.buildPlanInjection() ?? '',
      // Likes & Dislikes. UNGATED on purpose — see the class doc on
      // PreferencesInjection: acting on a taste is characterisation, not
      // scoring, so it must survive the Realism Engine being off. It
      // self-gates on the card carrying any.
      preferencesInjection.buildPreferencesInjection(),

      // ── 5. HOW SHE IS RIGHT NOW ─────────────────────────────────────────
      // Last, so the volatile state sits against the closing instruction to
      // express it. Her head first, then her body and what she has for it.
      //
      // MOVED DOWN from third overall. The line opens "Before this
      // conversation started, …", so it is the baseline the current mood sits
      // on top of — and it is derived from the weather and needs elsewhere in
      // this block, which now both precede it or explain it in order.
      getStandingMood?.call() ?? '',
      if (_characterStateEnabled) emotionInjection.buildEmotionInjection(),
      // MOVED UP from dead last, split out of the behavioural fragment. It
      // describes itself as "a background thought that colors mood and
      // reactions", and it was sitting nine lines below the mood it colours.
      if (_characterStateEnabled) behavioralInjection.buildFixationInjection(),
      // Pockets & Wardrobe, immediately ABOVE the needs line.
      //
      // Placed by function rather than by category: what she carries is
      // standing knowledge and would otherwise belong in §4, but nobody
      // discovers the contents of their own pocket at the moment they get
      // hungry. They already knew, and that prior knowledge is what makes
      // reaching for it obvious rather than a realisation. Told the other way
      // round, the model met a vivid directive line ("thoughts drifting
      // uncontrollably to food") and learned about the candy bar afterwards,
      // by which point a small model had already sent her to the kitchen.
      //
      // Ungated here for the same reason preferences are (it answers to its own
      // switch and nothing else); the leaf self-gates on the record being
      // non-empty, which it is only when the feature is on.
      inventoryLine,
      needsLine,
      if (_characterStateEnabled) nsfwInjection.buildNsfwCooldownInjection(),
      // The join closes the block. It reads backwards over what she has, what
      // she needs and how her body is, so it must follow all three — and it
      // lands immediately before "Express all of this…", the strongest position
      // a directive gets. The ONLY place Pockets and Needs meet, and it costs
      // no LLM call: neither engine reads the other's state, the composer just
      // says the sentence that was always implied by having both.
      if (needsLine.trim().isNotEmpty && inventoryLine.trim().isNotEmpty)
        _useWhatSheHasLine,
    ].where((f) => f.trim().isNotEmpty).map((f) => f.trim()).toList();

    if (fragments.isEmpty) return '';

    final name = _speakerName();
    return '[How $name is right now:\n'
        '${fragments.join('\n')}\n'
        'Express all of this only through $name\'s behavior, body language, '
        'and voice — never quote meters, scores, percentages, turn counts, '
        'or system terms.]\n';
  }
}
