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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';

part 'needs_simulation.tables.dart';

/// Documented decay modifier for the `tickDecay` pipeline.
/// Name for logs; condition decides applicability; factor the multiplier.
/// Applied after base decay + time-of-day.
typedef DecayModifier = ({
  String name,
  bool Function(String key, Map<String, int> vector, NeedsSimulation ctx)
  condition,
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

  /// The card's Needs delta strength (1–5). Optional: absent means 1x, which
  /// is what every existing test harness and the group-member path assume.
  /// Read only by [sceneDepletionCap].
  final int Function()? getNeedsSimStrength;

  /// Today's story weather, or null when the feature is off. Optional so
  /// existing construction sites/tests are untouched; the weather decay
  /// modifiers below no-op on null. Per-chat shared state → both the 1:1 and
  /// group ticks see the identical value through [decayedValueFor] (parity
  /// by construction).
  final DailyWeather? Function()? getWeather;

  Map<String, int> _vector = {};
  String? _pendingCatastrophe;
  String?
  _lastSceneReason; // from model/Director for better chip reasons on scene deltas
  /// Speakers who already got the "I reek" beat at hygiene 0. Cleared
  /// when hygiene rises (they washed). Stops a no-rebound meter from
  /// re-firing the canon scene event every turn.
  final Set<String> _hygieneCrisisAcked = {};

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
    this.getNeedsSimStrength,
    this.getCustomDecayRates,
    this.getWeather,
  });

  Map<String, int> get vector => Map<String, int>.unmodifiable(_vector);
  String? get pendingCatastrophe => _pendingCatastrophe;

  // Buffer state and getters completely removed.

  static const List<String> needKeys = _needKeys;
  static const Map<String, int> needDefaults = _needDefaults;

  /// Stored group-member needs, or empty when the slot has never carried a
  /// vector. Missing keys in a partial map are filled from [needDefaults];
  /// a null/empty map is NOT invented — callers seed from the card instead.
  static Map<String, int> storedNeedsOrEmpty(Map<String, int>? raw) {
    if (raw == null || raw.isEmpty) return const {};
    return {for (final k in needKeys) k: raw[k] ?? (needDefaults[k] ?? 80)};
  }

  /// Card baselines used to seed a fresh 1:1 chat and a group member who
  /// has never had a stored vector. Falls back to [needDefaults] when the
  /// card has no extensions.
  static Map<String, int> baselinesFromExtensions(FrontPorchExtensions? ext) {
    if (ext == null) return Map<String, int>.from(needDefaults);
    return {
      'hunger': ext.needsBaselineHunger,
      'bladder': ext.needsBaselineBladder,
      'energy': ext.needsBaselineEnergy,
      'social': ext.needsBaselineSocial,
      'fun': ext.needsBaselineFun,
      'hygiene': ext.needsBaselineHygiene,
      'comfort': ext.needsBaselineComfort,
    };
  }

  static const Map<String, int> needDecay = _needDecay;
  static const Map<String, int> needRestore = _needRestore;
  static const int needRestoreDefault = 30;

  static const int needUrgentThreshold = 35;
  static const int needCriticalThreshold = 20;

  static const List<int> needStepUpperBounds = [0, 15, 30, 45, 65];

  static const Map<String, List<String>> needSteppedText = _needSteppedText;
  static const List<String> hygieneSteppedTextWhenEnjoysLow =
      _hygieneSteppedTextWhenEnjoysLow;
  static const Map<String, String> needCatastropheText = _needCatastropheText;
  static const Map<String, int> needPostCatastropheFloor =
      _needPostCatastropheFloor;
  static const List<String> catastropheNeeds = _catastropheNeeds;
  static final List<DecayModifier> decayModifiers = _decayModifiers;
  void initializeFresh() {
    _vector = Map<String, int>.from(needDefaults);
    _pendingCatastrophe = null;
    _lastSceneReason = null;
    _hygieneCrisisAcked.clear();
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
    _hygieneCrisisAcked.clear();
    // No buffer state to zero.
  }

  void clearVector() {
    _vector.clear();
    _pendingCatastrophe = null;
    _lastSceneReason = null;
    _hygieneCrisisAcked.clear();
  }

  void resetBuffers() {
    // Buffer reset is now a no-op (buffers expunged). Kept for god reset hygiene calls.
    _pendingCatastrophe = null;
    _lastSceneReason = null;
    _hygieneCrisisAcked.clear();
  }

  static const Map<String, int> sceneDepletionAt1x = _sceneDepletionAt1x;

  /// Fallback for a key not in the table (there is none today; a future need
  /// gets a middling number until someone chooses one for it).
  static const int sceneDepletionFallback = 10;

  /// [key]'s depletion bound at the card's Needs strength (1–5).
  ///
  /// `base + 2 per notch above 1x`, so every notch does something and the
  /// widest bite tops out at 26 — still under the old fixed −30, so no strength
  /// setting is worse off than before this change. A multiplicative scale would
  /// have put bladder at 54 and reintroduced exactly the cliff being fixed.
  int sceneDepletionCapFor(String key) {
    final base = sceneDepletionAt1x[key] ?? sceneDepletionFallback;
    final strength = (getNeedsSimStrength?.call() ?? 1).clamp(1, 5);
    return base + (strength - 1) * 2;
  }

  /// Apply a scene's deltas. A PURE MUTATOR — it does not judge magnitude.
  ///
  /// The depletion policy deliberately does NOT live here, and that was worth
  /// getting wrong once to learn. Putting it on this method bounded the whole
  /// vector, which broke two tests that use it merely to ARRANGE a state (a
  /// composer test making a character hungry, and the raw-clamp golden) — the
  /// bound was reaching past the bug. What needs limiting is what a MODEL
  /// proposes about a scene, not what the simulation is allowed to hold.
  /// See [sceneDepletionCap] and its single application point in
  /// needs_impact_evaluator.
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

  void applyNeedsDeltas(
    Map<String, int> deltas, {
    bool fromSexualActivity = false,
  }) {
    // Kept for any legacy direct callers; delegates to impact path (no buffer side effects).
    applySceneImpact(NeedsImpact(deltas: deltas));
  }

  Map<String, dynamic> computeNeedsDeltasWithReasons(Map<String, int> pre) {
    final out = <String, dynamic>{};
    for (final k in needKeys) {
      // No baseline → no delta. A missing pre-turn value used to read as 0,
      // fabricating "delta = the full current value" chips (a 67 hunger
      // showed delta 67) whenever capture ran without a pre-turn vector —
      // e.g. a time-chevron patch outside any turn (2026-07-28 snapshot).
      final before = pre[k];
      if (before == null) continue;
      final after = _vector[k] ?? before;
      final delta = after - before;
      String reason = 'Stable';
      if (delta > 0) reason = 'Scene action';
      if (delta < 0) reason = 'Natural decay';
      if (_lastSceneReason != null && _lastSceneReason!.isNotEmpty) {
        reason = _lastSceneReason!;
      }
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
  /// catastrophe (the worst such need) for the prompt builder. Needs with a
  /// [needPostCatastropheFloor] lift so they can't instantly re-fire; hygiene
  /// has none — they stay filthy until a scene actually washes them. Operates
  /// on the live [_vector] — the 1:1 host's (called from [tickDecay]), or a
  /// group speaker's after their scalars are loaded (called from the realism
  /// dance), so 1:1 and group behave identically. Enjoys-low-hygiene skips
  /// the hygiene beat (0 is comfort for them).
  void applyCatastropheIfNeeded() {
    if (!getNeedsSimEnabled() || !getRealismEnabled()) return;
    if (_pendingCatastrophe != null) return; // one pending event at a time
    final speaker = getCurrentSpeakerIdForRealism();
    if ((_vector['hygiene'] ?? 80) > 0) {
      _hygieneCrisisAcked.remove(speaker);
    }
    final enjoysLow = getEnjoysLowHygiene();
    String? worst;
    int worstVal = 1; // only needs at 0 or below qualify
    for (final key in catastropheNeeds) {
      if (key == 'hygiene' && enjoysLow) continue;
      if (key == 'hygiene' && _hygieneCrisisAcked.contains(speaker)) continue;
      final v = _vector[key];
      if (v == null) continue;
      if (v <= 0 && v < worstVal) {
        worstVal = v;
        worst = key;
      }
    }
    if (worst == null) return;
    _pendingCatastrophe = needCatastropheText[worst];
    if (worst == 'hygiene') {
      _hygieneCrisisAcked.add(speaker);
    }
    final floor = needPostCatastropheFloor[worst];
    if (floor != null) {
      _vector[worst] = floor;
    }
    debugPrint(
      '[Realism:Needs] ⚠️ CATASTROPHE armed for $worst'
      '${floor == null ? ' (no floor)' : ' → floor $floor'}',
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
    final enjoysLow = enjoysLowHygieneOverride ?? getEnjoysLowHygiene();
    if (enjoysLow && need == 'hygiene') {
      // VALUE inversion, not index inversion. The step bands are asymmetric
      // (widths 1/15/15/15/20/35 over [0,15,30,45,65]), so the old `5 - step`
      // mapped the wide sated band onto "catastrophic" and the 1-point band
      // onto "sated": a filthy character (value 10) read as mildly
      // freshly-washed and NEVER reached the silent sated state, while a
      // merely clean one (value 90) was described as scrubbed-raw
      // catastrophic. Walking the same bands from the other end
      // (100 - value) is what the hygieneSteppedTextWhenEnjoysLow doc has
      // always described. Golden regenerated with maintainer approval
      // 2026-08-15.
      return getNeedStep(need, 100 - value);
    }
    return getNeedStep(need, value);
  }

  /// Returns the lowest (worst) needs that should receive background state
  /// this turn, worst-first, capped at 3. Hunger and bladder stay silent at
  /// mild (step 4) — a faint urge made every chat about peeing and eating.
  /// Other needs still inject at step 4. Sated needs never surface.
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
    final ranked =
        [
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
    return ranked
        .where((e) => _injectsNeed(e.key, e.effectiveStep))
        .take(3)
        .toList();
  }

  /// Hunger/bladder at step 4 is "a faint urge" — too loud for ambient clocks.
  static bool _injectsNeed(String key, int effectiveStep) {
    if (key == 'hunger' || key == 'bladder') return effectiveStep <= 3;
    return effectiveStep <= 4;
  }
}
