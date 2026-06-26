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

/// Plain (non-ChangeNotifier) domain service owning the chat-scoped NSFW
/// cooldown & arousal (lust) state: the refractory cooldown (enabled flag,
/// remaining turns, original total for phased prompt), the arousalLevel
/// (-100..+100), and derived arousalTier / arousalTierName (tier -10..+10
/// with names matching relationship system: Feverish..Deserted).
///
/// ChatService owns the instance via a private late final (declared before
/// NeedsSimulation for cb init safety) and delegates. Cross-state for group
/// per-character persistence (arousal + nsfwCooldownEnabled + cooldown* in
/// _groupRealism) is accessed exclusively via 3 group cbs supplied
/// at construction (getGroupInt / getGroupValue + setGroupValue). This keeps
/// the extracted service testable, avoids cycles with the god's _groupRealism
/// map / pending / messages, and is friendly to future extractions.
///
/// NSFW state is *chat-scoped* for the enabled flag + cooldowns in 1:1, but
/// supports per-speaker scalars for group (arousal/cooldowns/nsfwEnabled per
/// char via impersonation load/save like relationship/needs). Group vs 1:1
/// parity is preserved: owner uses _loadGroupRealismIntoScalars (which now
/// thins to service) before per-char eval/checks (so checks see correct active
/// charName/personality for climax/sexual prompts, but nsfw scalars are per
/// speaker in group). No behavior change.
///
/// Boundaries kept in god (per plan for step 6 / step 8):
/// - Climax/sexual/daily activity LLM checks (_checkClimaxInResponse etc) and
///   _runPostGenNeedsChecks orchestration + guards stay in god (they perform
///   LLM evals with charName/personality injection + apply needs deltas +
///   postClimaxCrash; only the nsfw cooldown/arousal mutations and tier
///   calc are extracted). Full prompt builders (nsfw injection) thin here,
///   real in step 8.
/// - OneShot vs normal path parity for nsfw (cooldown/arousal deltas,
///   snapshot/restore in realism_state, post-gen apply) is strict: both paths
///   use the same service state + restore + decrement + apply sites.
/// - UI coordination, drift session columns (nsfwCooldownEnabled/arousalLevel/
///   cooldownTurnsRemaining), _groupRealism map itself, and some prompt
///   conditionals using the enabled flag stay in god or thin to shims.
/// - Capture/restore sites, drift save sites, the ~10 "keep reset blocks in
///   sync" sites, group impersonation load/save scalars, and regen revert call
///   service helpers + tightened comments now list /nsfw alongside
///   needs/chaos/relationship/expression/time.
///
/// @Deprecated shims on ChatService (exactly 5): nsfwCooldownEnabled,
/// cooldownTurnsRemaining, arousalLevel, arousalTier, arousalTierName.
/// (setNsfwCooldownEnabled also forwarded via thin wrapper.)
///
/// 0 new private methods added to ChatService as part of this step (thins +
/// delegations + call-site updates only; deletions of moved code are
/// mandatory part of the task). Reset/seed/load/restore/group helpers on
/// service support the documented keep-sync sites without god privates or
/// duplication.
///
/// climax/sexual/daily LLM checks only thin or stayed in god for now; full
/// prompt builders in step 8.
/// aug exercising only passive/qualified (resets/loads hit by pre-existing
/// startNew/setActive/_loadLast/group; full climax apply + checks only in
/// dedicated + manual).
/// oneShot vs normal nsfw parity: cooldown/arousal mutations + snapshot/restore
/// + decrement + apply identical across paths (dispatch preserved).
class NsfwService {
  // 3 group cbs (onNotify/onSaveChat removed as dead/unused per review; god owns save/notify for post-gen climax/sexual fidelity per plan boundaries).
  // Granular cbs for group per-char nsfw state (arousal + cooldowns +
  // nsfwCooldownEnabled) so load/save scalars for impersonated speaker work
  // without the service owning the _groupRealism map. Mirrors relationship
  // pattern. getGroupInt for numeric (arousal, cooldown turns); getGroupValue
  // for possibly-bool nsfwCooldownEnabled; setGroupValue for writes.
  final int Function(String charId, String key) getGroupInt;
  final dynamic Function(String charId, String key) getGroupValue;
  final void Function(String charId, String key, dynamic value) setGroupValue;

  // Owned state (moved verbatim from ChatService).
  bool _nsfwCooldownEnabled = false;
  int _cooldownTurnsRemaining = 0;
  int _cooldownTurnsTotal =
      0; // original refractory duration (for phased prompt)
  int _arousalLevel =
      0; // -100 to +100 scale (tier-based, matching relationship system)

  NsfwService({
    required this.getGroupInt,
    required this.getGroupValue,
    required this.setGroupValue,
  });

  // ── Public surface (for @Deprecated shims in ChatService + direct test/UI callers) ──────

  bool get nsfwCooldownEnabled => _nsfwCooldownEnabled;
  int get cooldownTurnsRemaining => _cooldownTurnsRemaining;
  int get cooldownTurnsTotal => _cooldownTurnsTotal;
  int get arousalLevel => _arousalLevel;

  /// Calculate arousal tier from level score (-100 to +100)
  int get arousalTier {
    // Convert -100 to +100 scale to tier index -10 to +10
    // Each tier represents 10 points
    final raw = _arousalLevel ~/ 10; // integer division
    final tierIndex = raw > 10 ? 10 : (raw < -10 ? -10 : raw);
    return tierIndex;
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

  void setCooldownTurnsRemaining(int v) {
    _cooldownTurnsRemaining = v;
  }

  void setCooldownTurnsTotal(int v) {
    _cooldownTurnsTotal = v;
  }

  /// Centralize the 3 mutations performed on confirmed climax (called from
  /// god's _checkClimaxInResponse after meta pre-save; caller does needs
  /// deltas + postClimaxCrash + save/notify for fidelity).
  void applyClimaxEffects({required int turns}) {
    _cooldownTurnsTotal = turns;
    _cooldownTurnsRemaining = turns;
    _arousalLevel = -3;
  }

  void decrementCooldownIfActive() {
    if (_cooldownTurnsRemaining > 0) {
      _cooldownTurnsRemaining--;
    }
  }

  /// Mirrors original setNsfwCooldownEnabled behavior for the thin god
  /// wrapper (which performs the async save + notify).
  void setNsfwCooldownEnabled(bool enabled) {
    _nsfwCooldownEnabled = enabled;
    if (!enabled) {
      _cooldownTurnsRemaining = 0;
      _cooldownTurnsTotal = 0;
      _arousalLevel = 0;
    }
  }

  // Direct scalar sets / load helpers for the documented "keep reset blocks in sync" sites
  // (startNewChat, setActiveCharacter, setActiveGroup, _loadLastSession x2, ext-seed paths,
  // delete flows, empty session, regen, swipe/restore, etc.).
  void resetForFreshChat() {
    _nsfwCooldownEnabled = false;
    _cooldownTurnsRemaining = 0;
    _cooldownTurnsTotal = 0;
    _arousalLevel = 0;
  }

  /// Runtime arousal/cooldown zero for "New Chat" explicit fresh (even after
  /// ext seed of the enabled flag). Keeps non-ext and ext paths in sync.
  void resetRuntimeArousalAndCooldown() {
    _arousalLevel = 0;
    _cooldownTurnsRemaining = 0;
    _cooldownTurnsTotal = 0;
  }

  void seedFromV2OrExt({required bool nsfwCooldownEnabled}) {
    _nsfwCooldownEnabled = nsfwCooldownEnabled;
    // arousal + cooldowns are runtime and zeroed explicitly in fresh paths
    // (see resetRuntimeArousalAndCooldown + reset blocks comments).
  }

  void loadNsfwScalars({
    required bool nsfwCooldownEnabled,
    required int arousalLevel,
    required int cooldownTurnsRemaining,
    int cooldownTurnsTotal = 0,
  }) {
    _nsfwCooldownEnabled = nsfwCooldownEnabled;
    _arousalLevel = arousalLevel.clamp(-100, 100);
    _cooldownTurnsRemaining = cooldownTurnsRemaining;
    _cooldownTurnsTotal = cooldownTurnsTotal;
  }

  // For swipe/regen paths that restore prior realism_state.
  void restoreNsfwFromRealismState(Map<String, dynamic> state) {
    final al = state['arousalLevel'];
    _arousalLevel = (al is int ? al : (al is num ? al.toInt() : _arousalLevel))
        .clamp(-100, 100);
    final cr = state['cooldownTurnsRemaining'];
    _cooldownTurnsRemaining = cr is int
        ? cr
        : (cr is num ? cr.toInt() : _cooldownTurnsRemaining);
    final ct = state['cooldownTurnsTotal'];
    _cooldownTurnsTotal = ct is int
        ? ct
        : (ct is num ? ct.toInt() : _cooldownTurnsTotal);
  }

  // For _restoreRealismStateFromMessage (and similar state replay).
  void restoreNsfwFromMessageState(Map<String, dynamic> state) {
    final al = state['arousalLevel'];
    _arousalLevel = (al is int ? al : (al is num ? al.toInt() : _arousalLevel))
        .clamp(-100, 100);
    final cr = state['cooldownTurnsRemaining'];
    _cooldownTurnsRemaining = cr is int
        ? cr
        : (cr is num ? cr.toInt() : _cooldownTurnsRemaining);
    final ct = state['cooldownTurnsTotal'];
    _cooldownTurnsTotal = ct is int
        ? ct
        : (ct is num ? ct.toInt() : _cooldownTurnsTotal);
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

    _cooldownTurnsRemaining = getGroupInt(charId, 'cooldownTurnsRemaining');
    _cooldownTurnsTotal = getGroupInt(charId, 'cooldownTurnsTotal');
  }

  /// Writes the current nsfw scalars back into the target group character's
  /// _groupRealism entry after an impersonated post-gen / check round.
  /// Extends prior arousal-only to include cooldown + enabled for parity.
  void saveNsfwScalarsToGroup(String charId) {
    // Note: group uses 'arousal' key (historical) vs snapshot 'arousalLevel' for compat.
    setGroupValue(charId, 'arousal', _arousalLevel);
    setGroupValue(charId, 'nsfwCooldownEnabled', _nsfwCooldownEnabled);
    setGroupValue(charId, 'cooldownTurnsRemaining', _cooldownTurnsRemaining);
    setGroupValue(charId, 'cooldownTurnsTotal', _cooldownTurnsTotal);
  }
}
