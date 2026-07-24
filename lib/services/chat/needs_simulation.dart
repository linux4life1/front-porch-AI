// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/needs_impact.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';

/// Documented decay modifier for the `tickDecay` pipeline.
/// Name for logs; condition decides applicability; factor the multiplier.
/// Applied after base decay + time-of-day.
typedef DecayModifier = ({
  String name,
  bool Function(String key, Map<String, int> vector, NeedsSimulation ctx) condition,
  double Function(String key, int current, NeedsSimulation ctx) factor,
});

/// Plain (non-ChangeNotifier) domain service owning the Needs simulation.
///
/// After buffer/afterglow/post-climax-crash/arousal-suppression removal:
/// - Straight per-turn decay ticks (needDecay + time mods + remaining cross-boost modifiers).
/// - Scene deltas from model (reviewed by optional Director) applied via applySceneImpact.
/// - Catastrophe text when needs cross critical thresholds.
/// - No erotic buffers, no afterglow damp in decay, no crash multipliers, no suppression state.
///
/// 1:1 vs group per-speaker parity preserved via cbs + god impersonation.
/// Reset hygiene: initializeFresh/clearVector/resetBuffers (now just vector + pending catas + reason) called from god at all sites + both startNew.
///
/// Stateless w.r.t. card config; owner (god) owns resets.
class NeedsSimulation {
  final VoidCallback onNotify;
  final Future<void> Function() onSaveChat;

  final String Function() getTimeOfDay;
  final bool Function() getRealismEnabled;
  final bool Function() getObserverMode;
  final String Function() getCurrentSpeakerIdForRealism;
  final bool Function() getIsGroupNonObserverMode;
  final Map<String, int> Function(String charId) getGroupNeeds;
  final void Function(String charId, Map<String, int> needs) setGroupNeeds;
  final bool Function() getEnjoysLowHygiene;
  final bool Function() getNeedsSimEnabled;
  final Map<String, int>? Function()? getCustomDecayRates;

  /// Today's story weather, or null when the feature is off. Optional so
  /// existing construction sites/tests are untouched; the weather decay
  /// modifiers below no-op on null. Per-chat shared state → both the 1:1 and
  /// group ticks see the identical value through [decayedValueFor] (parity
  /// by construction).
  final DailyWeather? Function()? getWeather;

  Map<String, int> _vector = {};
  String? _pendingCatastrophe;
  String? _lastSceneReason; // from model/Director for better chip reasons on scene deltas

  NeedsSimulation({
    required this.onNotify,
    required this.onSaveChat,
    required this.getTimeOfDay,
    required this.getRealismEnabled,
    required this.getObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getIsGroupNonObserverMode,
    required this.getGroupNeeds,
    required this.setGroupNeeds,
    required this.getEnjoysLowHygiene,
    required this.getNeedsSimEnabled,
    this.getCustomDecayRates,
    this.getWeather,
  });

  Map<String, int> get vector => Map<String, int>.unmodifiable(_vector);
  String? get pendingCatastrophe => _pendingCatastrophe;

  // Buffer state and getters completely removed.

  static const List<String> needKeys = [
    'hunger', 'bladder', 'energy', 'social', 'fun', 'hygiene', 'comfort',
  ];

  static const Map<String, int> needDefaults = {
    'hunger': 75, 'bladder': 80, 'energy': 80, 'social': 65, 'fun': 65, 'hygiene': 75, 'comfort': 70,
  };

  static const Map<String, int> needDecay = {
    'hunger': 4, 'bladder': 6, 'energy': 3, 'social': 2, 'fun': 2, 'hygiene': 1, 'comfort': 2,
  };

  static const Map<String, int> needRestore = {
    'hunger': 50, 'bladder': 70, 'energy': 40, 'social': 45, 'fun': 40, 'hygiene': 35, 'comfort': 35,
  };
  static const int needRestoreDefault = 30;

  static const int needUrgentThreshold = 35;
  static const int needCriticalThreshold = 20;

  static const List<int> needStepUpperBounds = [0, 15, 30, 45, 65];

  /// Stepped background prose per need, worst-first (index 0 = crisis → 4 =
  /// mild). PRONOUN-FREE by design (docs/design/prompt-state-injection.md §3):
  /// these lines render directly inside the composed state block right after a
  /// header that names the character ("Hunger: [line]"), so gendered or
  /// generic pronouns here would clash with the named, gendered header on
  /// small models (the "their stomach… she said" template-paste read). Keep
  /// any new lines pronoun-free participial/nominal phrases for the same
  /// reason. ({{user}} macros are fine — the block is macro-resolved.)
  static const Map<String, List<String>> needSteppedText = {
    'hunger': [
      '''Doubled over by a violent stomach cramp — genuinely starving: vision swimming, knees weak, barely able to stay upright. The hunger has become a real physical crisis.''',
      '''Sharp, gnawing hunger cramps; light-headed and shaky, thoughts drifting uncontrollably to food, focus on anything else a real struggle.''',
      '''Stomach painfully hollow and tight — a constant, distracting ache; restless, short-tempered, thoughts keep returning to when the next meal might come.''',
      '''A steady, empty feeling in the stomach; thoughts occasionally wander toward food — a bit distracted and low-energy.''',
      '''A quiet, background emptiness in the stomach — not urgent, but noticeable; a chance to eat soon would be welcome.''',
    ],
    'bladder': [
      '''Control gives out completely — a sudden hot rush, an accident happening right now in the current scene; the humiliation is immediate and overwhelming.''',
      '''Fighting with everything not to lose control — thighs pressed tight, constant shifting, voice tight with strain; an accident is very close.''',
      '''A strong, insistent pressure has built up — visibly uncomfortable, watching for a polite way to slip away soon.''',
      '''A steady, distracting pressure low in the belly; the need keeps growing — a bathroom before too long would be a relief.''',
      '''A faint but persistent urge to use the restroom sits at the back of the mind, bringing slight restlessness.''',
    ],
    'energy': [
      '''The body gives out completely — eyes flutter mid-sentence and collapse follows, slumping to the floor or into {{user}}'s arms, fully unconscious from exhaustion.''',
      '''Barely staying awake — head nodding, speech slow and heavy, eyes unfocused; sleep could take over at any moment.''',
      '''A heavy, crushing tiredness; every movement takes effort and thoughts run slow — rest is desperately wanted.''',
      '''A deep weariness — movements a little slower, noticeably less animated than usual, clearly running low on energy.''',
      '''A comfortable, heavy tiredness behind the eyes; curling up to rest would be welcome if the chance arose.''',
    ],
    'social': [
      '''Overwhelming loneliness — hollow and raw, on the edge of breaking down without real, meaningful connection soon.''',
      '''Painfully isolated; the lack of real connection is starting to hurt — unusually quiet, clingy, or emotionally fragile.''',
      '''A deep ache for genuine connection sits in the chest; casual interaction feels hollow — meaningful moments and closeness keep being sought.''',
      '''Feeling the absence of real companionship — a little more eager than usual for meaningful conversation or physical closeness.''',
      '''A quiet, gentle craving for real connection — a touch warmer and more attentive than normal.''',
    ],
    'fun': [
      '''Torturous boredom — dangerously restless, liable to do something reckless or wildly inappropriate just to feel *something* again.''',
      '''Deeply restless and thoroughly bored — constant fidgeting, ready to suggest almost anything to break the monotony.''',
      '''A heavy restlessness has settled in; everything feels dull — any excuse for something more stimulating keeps being sought.''',
      '''Noticeably bored and fidgety; the current situation feels flat — actively hoping for a change of pace.''',
      '''A mild restlessness — a little more eager than usual for something fun or different to happen.''',
    ],
    'hygiene': [
      '''Filthy and overwhelmed by it — the grime or smell strong enough to cause physical discomfort and self-consciousness to the point of distress.''',
      '''Genuinely dirty and very aware of it — an urge to cover up or pull away from contact until there's a chance to clean up.''',
      '''A persistent grimy feeling clings — self-conscious, thoughts keep returning to washing or changing.''',
      '''Starting to feel noticeably unkempt — a quiet discomfort, wanting to freshen up soon.''',
      '''A faint background sense of being a little grubby — mildly self-conscious about it.''',
    ],
    'comfort': [
      '''Unbearable physical discomfort — impossible to stay like this any longer; relief will be sought no matter what it disrupts.''',
      '''The body is in real distress — too hot, too cold, cramped, or aching badly; constant shifting, focus on anything else a struggle.''',
      '''A strong physical discomfort wears on — constant adjusting of position or surroundings, clearly unable to settle.''',
      '''Noticeably uncomfortable — a persistent physical irritation (temperature, pressure, stiffness) making it hard to fully relax.''',
      '''A mild but persistent physical discomfort in the background, bringing slight restlessness.''',
    ],
  };

  /// Hygiene descriptions for a character with "enjoys low hygiene" set. For
  /// them the whole scale is inverted: being DIRTY is comfort, being CLEAN is
  /// the aversive state. The normal [needSteppedText] is all phrased "dirty =
  /// bad", so reusing it after the step inversion would describe a freshly-
  /// scrubbed character as "feeling filthy" — the exact opposite of the truth.
  /// This list is worst-first like the others (index 0 = scrubbed unbearably
  /// clean → index 4 = only faintly too fresh). This is an ODOR/MUSK preference
  /// ONLY: the character is soothed by their own unwashed body scent and put off
  /// by feeling soap-clean. It is NOT a drive to make a mess — no seeking dirt,
  /// mud, or filth acts (a character once dumped a mop bucket over herself off
  /// the old wording). The distress is missing their natural scent; the comfort
  /// is simply remaining unwashed and musky. Pronoun-free like
  /// [needSteppedText] (rendered right after a named header).
  static const List<String> hygieneSteppedTextWhenEnjoysLow = [
    '''Scrubbed and scentless in a way that feels wrong on the skin — the familiar musk scoured completely away; exposed and on edge, quietly wishing that natural scent were back. (This is about missing a natural body scent, never about seeking out filth.)''',
    '''Uncomfortably fresh — too soft, too soapy, the natural scent washed thin; its absence is off-putting, that thorough wash already regretted.''',
    '''Still a little too clean for comfort — without the familiar musk comes an odd self-consciousness, as if something comforting were missing.''',
    '''Starting to feel a touch over-scrubbed; the settled, lived-in comfort of an unwashed natural scent is quietly missed.''',
    '''A faint just-washed freshness lingers — mildly unsatisfying next to the natural musk.''',
  ];

  // Mandatory "this just happened" events fired when a HARD-EVENT need bottoms
  // out (≤0). Neutral voice (they/them). Each line carries its OWN observable
  // evidence, so the injection wrapper stays generic (no bladder-centric list).
  // Deliberately NO social/fun entries — those are moods, not discrete events
  // (the old "fun=0 → do something dangerous/sexual/chaotic" line was a model-
  // derailment vector); they max out as intense distress in the stepped text
  // instead. Hygiene is skipped entirely for "enjoys low hygiene" characters
  // (for them 0 hygiene is comfort, not a crisis).
  static const Map<String, String> needCatastropheText = {
    'hunger':
        '''Starvation buckles them — they sag, grey-faced and unsteady, and have to catch themselves on the nearest support just to stay upright. Their body has hit its limit and it shows.''',
    'bladder':
        '''Their control gives out. It's happening right now, in the scene — a hot, unstoppable release, fabric darkening, a spreading wet patch, the smell of it. The accident is occurring this instant, not a warning or a near-miss.''',
    'energy':
        '''Exhaustion drops them mid-action — their knees buckle and they collapse, briefly blacking out as they slump to the floor or the nearest surface. They come to a few seconds later, dazed and groggy, barely able to keep their eyes open or form a clear thought.''',
    'hygiene':
        '''Their own grime and body odor turn undeniable this turn — sharp enough that they notice it on their own skin, or the people around them visibly react to it. It's an unmistakable, distracting presence in the scene.''',
    'comfort':
        '''The strain becomes unbearable — the cramped position, the temperature, the pressure, the restraint, whatever is causing it. They have to shift, break contact with the source, or otherwise ease it; they can't simply hold still through it any longer.''',
  };

  /// Recovery floor by need CLASS after a catastrophe (no magic per-need +N):
  ///   body-reset — a physiological event that (partly) empties the meter:
  ///     bladder (just went → nearly empty), hunger (stabilized, not fed),
  ///     energy (came to groggy, NOT a full rest — user said collapse-and-groggy,
  ///     not fall-asleep).
  ///   crisis-vent — a behavioral/sensory peak with only partial relief:
  ///     hygiene, comfort (the moment passes; nothing was actually cleaned/fixed).
  static const Map<String, int> needPostCatastropheFloor = {
    'bladder': 85,
    'hunger': 70,
    'energy': 65,
    'hygiene': 55,
    'comfort': 60,
  };

  /// The only needs that fire a hard catastrophe (see [needCatastropheText]).
  static const List<String> catastropheNeeds = [
    'bladder',
    'energy',
    'hunger',
    'comfort',
    'hygiene',
  ];

  // Decay modifiers (non-buffer ones retained; afterglow_damp and suppression-conditioned ones removed or simplified).
  static final List<DecayModifier> decayModifiers = <DecayModifier>[
    (
      name: 'low_energy_hunger_boost',
      condition: (key, vector, ctx) => key == 'hunger' && (vector['energy'] ?? 50) <= 30,
      factor: (key, current, ctx) => 1.35,
    ),
    (
      name: 'low_energy_comfort_boost',
      condition: (key, vector, ctx) => key == 'comfort' && (vector['energy'] ?? 50) <= 25,
      factor: (key, current, ctx) => 1.25,
    ),
    (
      name: 'low_fun_social_boost',
      condition: (key, vector, ctx) => key == 'social' && (vector['fun'] ?? 50) <= 20,
      factor: (key, current, ctx) => 1.4,
    ),
    (
      name: 'low_bladder_comfort_boost',
      condition: (key, vector, ctx) => key == 'comfort' && (vector['bladder'] ?? 50) <= 20,
      factor: (key, current, ctx) => 1.25,
    ),
    // (enjoys low hygiene arousal mutation and other buffer-dependent modifiers removed with the buffers)
    // Living Time weather (living-time-features.md §3) — deliberately tiny.
    // Comfort: base 2 ×1.25 → rounds to 3/turn in rough weather.
    // Fun: base 2 ×0.5 → 1/turn on clear days (a plain ×0.75 would round back
    // to 2 and do nothing). Both vanish when weather is off (getWeather null).
    (
      name: 'weather_rough_comfort',
      condition: (key, vector, ctx) {
        if (key != 'comfort') return false;
        final w = ctx.getWeather?.call();
        if (w == null) return false;
        return w.condition == WeatherCondition.storm ||
            w.condition == WeatherCondition.rain ||
            w.temp == TempBand.hot ||
            w.temp == TempBand.cold;
      },
      factor: (key, current, ctx) => 1.25,
    ),
    (
      name: 'weather_clear_fun',
      condition: (key, vector, ctx) =>
          key == 'fun' &&
          ctx.getWeather?.call()?.condition == WeatherCondition.clear,
      factor: (key, current, ctx) => 0.5,
    ),
  ];

  void initializeFresh() {
    _vector = Map<String, int>.from(needDefaults);
    _pendingCatastrophe = null;
    _lastSceneReason = null;
    // No buffer state to zero.
  }

  /// THE single per-key decay rule (rate + modifier pipeline + clamp), shared
  /// by the 1:1 tick, the group tick, and the group per-speaker decay in the
  /// realism dance — so a group member decays exactly like the same card in a
  /// 1:1 chat (parity). [vector] is the live map the modifier conditions read;
  /// pass the map being decayed so later keys see earlier keys' decayed values
  /// (the historical in-loop semantics).
  int decayedValueFor(
    String key,
    int current,
    Map<String, int> vector,
    Map<String, int> customRates,
  ) {
    int decay = customRates[key] ?? needDecay[key] ?? 0;
    for (final mod in decayModifiers) {
      if (mod.condition(key, vector, this)) {
        decay = (decay * mod.factor(key, current, this)).round();
      }
    }
    return (current - decay).clamp(0, 100);
  }

  /// Initialize the needs vector from card-specific baseline values.
  ///
  /// Used when starting a new chat so that the character's
  /// [FrontPorchExtensions] baseline needs (needsBaselineHunger, etc.)
  /// are respected instead of the hardcoded [needDefaults].
  void initializeFreshWithDefaults(Map<String, int> defaults) {
    _vector = Map<String, int>.from(defaults);
    _pendingCatastrophe = null;
    _lastSceneReason = null;
    // No buffer state to zero.
  }

  void clearVector() {
    _vector.clear();
    _pendingCatastrophe = null;
    _lastSceneReason = null;
  }

  void resetBuffers() {
    // Buffer reset is now a no-op (buffers expunged). Kept for god reset hygiene calls.
    _pendingCatastrophe = null;
    _lastSceneReason = null;
  }

  void applySceneImpact(NeedsImpact impact) {
    if (impact.deltas.isNotEmpty) {
      for (final entry in impact.deltas.entries) {
        final k = entry.key;
        if (_vector.containsKey(k)) {
          _vector[k] = (_vector[k]! + entry.value).clamp(0, 100);
        }
      }
    }
    if (impact.reason != null && impact.reason!.isNotEmpty) {
      _lastSceneReason = impact.reason;
    }
    onSaveChat();
    onNotify();
  }

  void applyNeedsDeltas(Map<String, int> deltas, {bool fromSexualActivity = false}) {
    // Kept for any legacy direct callers; delegates to impact path (no buffer side effects).
    applySceneImpact(NeedsImpact(deltas: deltas));
  }

  Map<String, dynamic> computeNeedsDeltasWithReasons(Map<String, int> pre) {
    final out = <String, dynamic>{};
    for (final k in needKeys) {
      final before = pre[k] ?? 0;
      final after = _vector[k] ?? before;
      final delta = after - before;
      String reason = 'Stable';
      if (delta > 0) reason = 'Scene action';
      if (delta < 0) reason = 'Natural decay';
      if (_lastSceneReason != null && _lastSceneReason!.isNotEmpty) reason = _lastSceneReason!;
      if (delta != 0) {
        out[k] = {'delta': delta, 'reason': reason};
      }
    }
    return out;
  }

  void tickDecay() {
    if (!getNeedsSimEnabled() || !getRealismEnabled()) return;

    final customRates = getCustomDecayRates?.call() ?? {};
    final isGroupNonObserver = getIsGroupNonObserverMode();
    if (isGroupNonObserver) {
      final sid = getCurrentSpeakerIdForRealism();
      var needs = getGroupNeeds(sid);
      if (needs.isEmpty) {
        needs = Map.fromEntries(needKeys.map((k) => MapEntry(k, 80)));
      }

      for (final key in needKeys) {
        final current = needs[key] ?? 80;
        needs[key] = decayedValueFor(key, current, needs, customRates);
      }
      setGroupNeeds(sid, needs);
      return;
    }

    // 1:1 scalar path (pure decay + simplified modifiers, no buffer damp/crash)
    for (final key in needKeys) {
      final current = _vector[key];
      if (current == null) continue;
      _vector[key] = decayedValueFor(key, current, _vector, customRates);
    }

    // Fire a catastrophe if any hard-event need bottomed out this tick.
    applyCatastropheIfNeeded();

    onSaveChat();
    onNotify();
  }

  /// When a hard-event need has bottomed out (≤0) this turn, arm ONE mandatory
  /// catastrophe (the worst such need) for the prompt builder and lift that
  /// need to its recovery floor so it can't instantly re-fire. Operates on the
  /// live [_vector] — the 1:1 host's (called from [tickDecay]), or a group
  /// speaker's after their scalars are loaded (called from the realism dance),
  /// so 1:1 and group behave identically. Hygiene is skipped for "enjoys low
  /// hygiene" characters (0 hygiene is comfort, not a crisis, for them).
  void applyCatastropheIfNeeded() {
    if (!getNeedsSimEnabled() || !getRealismEnabled()) return;
    if (_pendingCatastrophe != null) return; // one pending event at a time
    final enjoysLow = getEnjoysLowHygiene();
    String? worst;
    int worstVal = 1; // only needs at 0 or below qualify
    for (final key in catastropheNeeds) {
      if (key == 'hygiene' && enjoysLow) continue;
      final v = _vector[key];
      if (v == null) continue;
      if (v <= 0 && v < worstVal) {
        worstVal = v;
        worst = key;
      }
    }
    if (worst == null) return;
    _pendingCatastrophe = needCatastropheText[worst];
    _vector[worst] = needPostCatastropheFloor[worst] ?? 50;
    debugPrint(
      '[Realism:Needs] ⚠️ CATASTROPHE armed for $worst → floor ${_vector[worst]}',
    );
  }

  // applyLongGenerationNeedsDecay, getInjectionEffectiveStep, and other buffer-aware helpers simplified or removed.
  // For injection, owner falls back to basic step from current vector.

  void restoreFromSnapshot(Map<dynamic, dynamic> needsData) {
    if (needsData['vector'] is Map) {
      // Tolerant restore for snapshots that may come from JSON (numbers as num)
      // or mixed dynamic maps (e.g. persisted realism_state['needs'] or pre_state).
      // Also tolerates the 'deltas' sibling key that capture now includes.
      final raw = needsData['vector'] as Map;
      _vector = {
        for (final e in raw.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toInt(),
      };
    }
    // No buffer restore.
    _lastSceneReason = null;
  }

  /// Clears the scene-level reason so the delta chip falls back to
  /// per-need reasons ("Scene action", "Natural decay", "Stable").
  void clearLastSceneReason() {
    _lastSceneReason = null;
  }

  void consumePendingCatastrophe() {
    _pendingCatastrophe = null;
  }

  int needRestoreAmount(String need) {
    return needRestore[need] ?? needRestoreDefault;
  }

  int getNeedStep(String need, int value) {
    for (int s = 0; s < needStepUpperBounds.length; s++) {
      if (value <= needStepUpperBounds[s]) return s;
    }
    return 5;
  }

  /// Effective stepped urgency for prompt injection.
  ///
  /// [enjoysLowHygieneOverride] lets the caller supply the flag for the SPECIFIC
  /// character whose need is being rendered. This is required in group chats:
  /// the shared [getEnjoysLowHygiene] callback reads the chat's *active*
  /// character, which — after the per-speaker realism dance restores the pointer
  /// — is the PREVIOUS speaker, not the one this line belongs to. Passing the
  /// speaker's own flag stops one filthy-loving member from inverting every
  /// other member's hygiene (the "hygiene 88 shows CATASTROPHIC" bleed). The 1:1
  /// path passes null and keeps using the global (active == host there).
  int getInjectionEffectiveStep(
    String need,
    int value, {
    bool? enjoysLowHygieneOverride,
  }) {
    int step = getNeedStep(need, value);
    final enjoysLow = enjoysLowHygieneOverride ?? getEnjoysLowHygiene();
    if (enjoysLow && need == 'hygiene') {
      step = (5 - step).clamp(0, 5);
    }
    return step;
  }

  /// Returns the lowest (worst) needs that should receive background state
  /// text this turn — those whose effective step is 4 or lower (mild or worse
  /// after the enjoys-low-hygiene inversion), worst-first, capped at 3. Both
  /// 1:1 and group paths use this for consistent selection, and so
  /// slow-decaying needs (Comfort, Hygiene) can appear even when not the
  /// absolute lowest. Sated needs never surface (words-only salience gating,
  /// docs/design/prompt-state-injection.md §3).
  ///
  /// [enjoysLowHygieneOverride] MUST carry the specific speaker's flag in
  /// group chats (same reason as [getInjectionEffectiveStep]) — without it the
  /// hygiene inversion reads the shared active-character flag and one
  /// filthy-loving member corrupts every other member's need SELECTION, not
  /// just its wording.
  List<({String key, int value, int effectiveStep})> getLowNeedsForInjection(
    Map<String, int> vector, {
    bool? enjoysLowHygieneOverride,
  }) {
    if (vector.isEmpty) return const [];
    // Rank by EFFECTIVE step, not raw value: for an enjoys-low-hygiene
    // character the distressed hygiene value is a HIGH number, so a raw-value
    // sort would rank their most urgent need last and let milder needs crowd
    // it out of the cap.
    final ranked = [
      for (final e in vector.entries)
        (
          key: e.key,
          value: e.value,
          effectiveStep: getInjectionEffectiveStep(
            e.key,
            e.value,
            enjoysLowHygieneOverride: enjoysLowHygieneOverride,
          ),
        ),
    ]..sort((a, b) {
        final byStep = a.effectiveStep.compareTo(b.effectiveStep);
        return byStep != 0 ? byStep : a.value.compareTo(b.value);
      });
    return ranked.where((e) => e.effectiveStep <= 4).take(3).toList();
  }

}
