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

import 'package:front_porch_ai/services/chat/refractory.dart';

/// Plain (non-ChangeNotifier) domain service owning the chat-scoped NSFW
/// cooldown & arousal (lust) state: the refractory ([Refractory]: story
/// minutes left, the length at climax for the phased prompt, and the opening
/// turn flag), the arousalLevel (-100..+100), and derived arousalTier /
/// arousalTierName (tier -10..+10 with names matching relationship system:
/// Feverish..Deserted).
///
/// ## The human model
/// Arousal is a *desire* meter. Positive = building want; **negative =
/// genuine aversion** (soured mood, unwanted advances, violations) — it is
/// NEVER used to represent post-climax satedness. A sated human is content
/// and affectionate, not repelled, so:
/// - Climax sets arousal to 0 (sated-neutral) and starts the refractory
///   cooldown; the "not right now" semantics live in the cooldown, not in a
///   negative arousal score.
/// - While the refractory is active, eval-scored deltas are damped (halved)
///   and cannot dig arousal below mild disinterest (-10): a body that just
///   finished is hard to stir and impossible to disgust by mere closeness.
///   See [applyEvalArousalDelta] — the ONE apply path both the multi-call and
///   one-shot evals use, so parity holds by construction.
/// - When the cooldown expires, the total resets and any lingering negative
///   arousal is halved toward neutral (baseline receptivity returns) —
///   previously the character exited cooldown at arousal ≤ -2 and the
///   injection ladder read that as "physically repulsed" forever.
///
/// ChatService owns the instance via a private late final and delegates.
/// Cross-state for group per-character persistence (arousal +
/// nsfwCooldownEnabled + cooldown* in _groupRealism) is accessed exclusively
/// via 3 group cbs supplied at construction (getGroupInt / getGroupValue +
/// setGroupValue), keeping the service testable and cycle-free.
///
/// NSFW state is *chat-scoped* for the enabled flag + cooldowns in 1:1, with
/// per-speaker scalars for group (arousal/refractory/nsfwEnabled per char via
/// impersonation load/save like relationship/needs). Group vs 1:1 parity is
/// strict: the refractory runs down by story minutes for every present body
/// at once (ChatService._tickRefractoryAfterClock), or a quarter hour per
/// reply with the clock off, and every mutation rule lives in [Refractory],
/// shared by both modes. OneShot vs normal parity likewise: arousal mutations
/// + snapshot/restore + apply are identical sites.
class NsfwService {
  // 3 group cbs (onNotify/onSaveChat removed as dead/unused per review; god owns save/notify for post-gen climax/sexual fidelity per plan boundaries).
  // Granular cbs for group per-char nsfw state (arousal + cooldowns +
  // nsfwCooldownEnabled) so load/save scalars for impersonated speaker work
  // without the service owning the _groupRealism map. Mirrors relationship
  // pattern. getGroupInt for numeric arousal; getGroupValue for
  // possibly-bool nsfwCooldownEnabled and the refractory keys; setGroupValue
  // for writes.
  final int Function(String charId, String key) getGroupInt;
  final dynamic Function(String charId, String key) getGroupValue;
  final void Function(String charId, String key, dynamic value) setGroupValue;

  /// Porch Life Passage of Time, live. Only decides the countdown's words:
  /// story minutes while it runs, replies while it is off.
  final bool Function() _isClockRunning;

  // Owned state (moved verbatim from ChatService).
  bool _nsfwCooldownEnabled = false;
  Refractory _refractory = Refractory.none;
  int _arousalLevel =
      0; // -100 to +100 scale (tier-based, matching relationship system)

  NsfwService({
    required this.getGroupInt,
    required this.getGroupValue,
    required this.setGroupValue,
    bool Function()? isClockRunning,
  }) : _isClockRunning = isClockRunning ?? _clockOn;

  static bool _clockOn() => true;

  // ── Public surface (ChatService delegates + direct test/UI callers) ──────

  bool get nsfwCooldownEnabled => _nsfwCooldownEnabled;
  int get arousalLevel => _arousalLevel;

  Refractory get refractory => _refractory;
  int get refractoryMinutesRemaining => _refractory.minutes;
  int get refractoryMinutesTotal => _refractory.total;
  bool get refractoryOpened => _refractory.opened;
  bool get clockRunning => _isClockRunning();

  /// The chip and prompt words for the live refractory (see
  /// [describeRefractory]); empty when none is running.
  ({String chip, String prompt}) get refractoryWords =>
      describeRefractory(_refractory.minutes, clockRunning: _isClockRunning());

  /// First Afterglow reply after the climax reply — the only turn that may
  /// force limp / tired / exhausted body language. Later Afterglow turns
  /// keep the sexual "not yet" and closeness, but energy and comfort
  /// come from Needs.
  ///
  /// A flag, not a count: the climax sets it unspoken, and the first reply
  /// generated after the climax reply marks it spoken in post-gen. A
  /// same-moment second reply (no minutes passed) is therefore not the
  /// opening turn. Continue of the climax reply still reads it as opening.
  bool get isOpeningAfterglowTurn => _refractory.isOpeningTurn;

  /// Calculate arousal tier from level score (-100 to +100)
  int get arousalTier => arousalTierForLevel(_arousalLevel);

  /// Pure arousal tier index for a level (-100..100), so per-member consumers
  /// can ask about somebody OTHER than the live speaker.
  ///
  /// Arousal is a ±100 scale and its tiers are simply level ÷ 10. Without this
  /// the group member card borrowed the BOND ladder (a ±300 scale with bands at
  /// 5/15/30/50/80/…), which put an arousal of 60 at tier 4 instead of 6.
  static int arousalTierForLevel(int level) {
    // Convert -100 to +100 scale to tier index -10 to +10
    // Each tier represents 10 points
    final raw = level ~/ 10; // integer division
    return raw > 10 ? 10 : (raw < -10 ? -10 : raw);
  }

  /// Get arousal tier name matching the relationship system
  String get arousalTierName => arousalTierLabel(_arousalLevel);

  /// Per-level read helper (web per-group-member stats panel).
  String arousalTierNameForLevel(int level) => arousalTierLabel(level);

  /// Pure arousal tier name for a level (-100..100). Shared by the live getter
  /// and read-only per-member consumers (web group stats panel).
  static String arousalTierLabel(int level) {
    final raw = level ~/ 10;
    final tier = raw > 10 ? 10 : (raw < -10 ? -10 : raw);
    // Use same tier names as relationship system but adapted for arousal
    if (tier >= 10) return 'Feverish';
    if (tier == 9) return 'Ecstatic';
    if (tier == 8) return 'Overwhelming';
    if (tier == 7) return 'Overcome';
    if (tier == 6) return 'Intense';
    if (tier == 5) return 'Aroused';
    if (tier == 4) return 'Stimulated';
    if (tier == 3) return 'Interested';
    if (tier == 2) return 'Aware';
    if (tier == 1) return 'Noticed';
    if (tier == 0) return 'Neutral';
    if (tier == -1) return 'Disinterested';
    if (tier == -2) return 'Apathetic';
    if (tier == -3) return 'Distant';
    if (tier == -4) return 'Cold';
    if (tier == -5) return 'Rejected';
    if (tier == -6) return 'Repelled';
    if (tier == -7) return 'Revolted';
    if (tier == -8) return 'Abhorrent';
    if (tier == -9) return 'Loathing';
    if (tier <= -10) return 'Deserted';
    return 'Unknown';
  }

  // ── Mutations (for god thins, needs cbs, climax apply, group load/save) ───

  void setArousalLevel(int v) {
    _arousalLevel = v.clamp(-100, 100);
  }

  /// Restores and rewinds (regen, delete, swipe, receipts).
  void setRefractory(Refractory r) {
    _refractory = r;
  }

  /// The climax pass's one effect on this body: the refractory starts at the
  /// judge's turns × 15 story minutes with its opening turn unspoken.
  ///
  /// Arousal lands at 0, not negative: post-climax satedness is contentment,
  /// not aversion — the refractory cooldown carries the "not right now"
  /// semantics. (The old -3 put the character into the injection ladder's
  /// negative branches the moment the cooldown expired, reading as repulsion
  /// right after wanted sex.)
  void applyClimaxEffects({required int turns}) {
    _refractory = Refractory.fromJudgeTurns(turns);
    _arousalLevel = 0;
  }

  /// The single apply path for eval-scored arousal deltas (multi-call and
  /// one-shot both route here — parity by construction). Returns the delta
  /// that actually landed after clamping and refractory physiology, which is
  /// what chips/metadata must record so regen revert stays exact.
  ///
  /// During the refractory, desire physiology applies: swings are halved (a
  /// spent body is slow to stir either way) and the result never digs below
  /// mild disinterest (-10) — satedness is not aversion, so recovering from a
  /// wanted climax must not walk the character into the repelled tiers.
  int applyEvalArousalDelta(int delta) {
    var effective = delta;
    var floor = -100;
    if (_refractory.running) {
      effective = (effective / 2).round();
      floor = _arousalLevel < -10 ? _arousalLevel : -10;
    }
    final next = (_arousalLevel + effective).clamp(floor, 100);
    effective = next - _arousalLevel;
    _arousalLevel = next;
    return effective;
  }

  /// Mirrors original setNsfwCooldownEnabled behavior for the thin god
  /// wrapper (which performs the async save + notify).
  void setNsfwCooldownEnabled(bool enabled) {
    _nsfwCooldownEnabled = enabled;
    if (!enabled) {
      _refractory = Refractory.none;
      _arousalLevel = 0;
    }
  }

  // Direct scalar sets / load helpers for the documented "keep reset blocks in sync" sites
  // (startNewChat, setActiveCharacter, setActiveGroup, _loadLastSession x2, ext-seed paths,
  // delete flows, empty session, regen, swipe/restore, etc.).
  void resetForFreshChat() {
    _nsfwCooldownEnabled = false;
    _refractory = Refractory.none;
    _arousalLevel = 0;
  }

  /// Runtime arousal/cooldown zero for "New Chat" explicit fresh (even after
  /// ext seed of the enabled flag). Keeps non-ext and ext paths in sync.
  void resetRuntimeArousalAndCooldown() {
    _arousalLevel = 0;
    _refractory = Refractory.none;
  }

  void seedFromV2OrExt({required bool nsfwCooldownEnabled}) {
    _nsfwCooldownEnabled = nsfwCooldownEnabled;
    // arousal + cooldowns are runtime and zeroed explicitly in fresh paths
    // (see resetRuntimeArousalAndCooldown + reset blocks comments).
  }

  void loadNsfwScalars({
    required bool nsfwCooldownEnabled,
    required int arousalLevel,
    Refractory refractory = Refractory.none,
  }) {
    _nsfwCooldownEnabled = nsfwCooldownEnabled;
    _arousalLevel = arousalLevel.clamp(-100, 100);
    _refractory = refractory;
  }

  // For swipe/regen paths that restore prior realism_state.
  void restoreNsfwFromRealismState(Map<String, dynamic> state) =>
      _restoreFromSnapshot(state);

  // For _restoreRealismStateFromMessage (and similar state replay).
  void restoreNsfwFromMessageState(Map<String, dynamic> state) =>
      _restoreFromSnapshot(state);

  /// A key the snapshot does not carry keeps its current value. Snapshots
  /// saved before minutes carry turns, read once as turns × 15.
  void _restoreFromSnapshot(Map<String, dynamic> state) {
    final al = state['arousalLevel'];
    _arousalLevel = (al is int ? al : (al is num ? al.toInt() : _arousalLevel))
        .clamp(-100, 100);
    _refractory = Refractory.read(state) ?? _refractory;
  }

  // ── Group per-char scalars (for impersonation in group realism) ──────────

  /// Loads the given group character's nsfw values from _groupRealism into
  /// the service scalars so existing post-gen checks / eval can operate on
  /// them during impersonation. Includes arousal + cooldowns + nsfwEnabled
  /// per the plan (extends prior arousal-only handling for full parity).
  void loadNsfwScalarsForSpeaker(String charId) {
    // Note: group uses 'arousal' key (historical) vs snapshot 'arousalLevel' for compat.
    _arousalLevel = getGroupInt(charId, 'arousal');

    final rawEnabled = getGroupValue(charId, 'nsfwCooldownEnabled');
    _nsfwCooldownEnabled =
        rawEnabled == true || rawEnabled == 1 || rawEnabled == 'true';

    // A member saved before minutes carries turns: read once as turns × 15.
    _refractory =
        Refractory.read({
          for (final k in RefractoryKeys.all) k: getGroupValue(charId, k),
        }) ??
        Refractory.none;
  }

  /// Writes the current nsfw scalars back into the target group character's
  /// _groupRealism entry after an impersonated post-gen / check round.
  /// Extends prior arousal-only to include cooldown + enabled for parity.
  void saveNsfwScalarsToGroup(String charId) {
    // Note: group uses 'arousal' key (historical) vs snapshot 'arousalLevel' for compat.
    setGroupValue(charId, 'arousal', _arousalLevel);
    setGroupValue(charId, 'nsfwCooldownEnabled', _nsfwCooldownEnabled);
    for (final e in _refractory.toSnapshot().entries) {
      setGroupValue(charId, e.key, e.value);
    }
  }
}
