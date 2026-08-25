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

part of '../chat_service.dart';

/// Low-level private helpers for reading/writing the per-character group realism
/// map (`_groupRealism`) and resolving the current speaker's id. Pure plumbing
/// over the map — no orchestration or engine logic — extracted verbatim from
/// `chat_service.dart` (zero behaviour change) to shrink the god file. These are
/// private and never part of the public interface, so they are safe to move to
/// an extension (no `implements`/fake can override them).
extension ChatServiceGroupRealismHelpers on ChatService {
  /// Returns the stable charId of the character whose realism state should be
  /// read/written for the current turn. In group mode this is the speaker
  /// we are about to generate for (or just generated for).
  String _getCurrentSpeakerIdForRealism() {
    if (_activeGroup == null || _groupCharacters.isEmpty) {
      return _getCharacterId();
    }
    // During a turn the speaker is pinned the moment they're picked
    // (_generateResponse). Prefer it — it's the only reliable "who is speaking
    // right now" signal, because `nextCharacter` points at the *upcoming*
    // speaker and is null for random turn order (which made this fall back to
    // the first/primary member for every random turn).
    final pinned = _turnSpeakerIdForRealism;
    if (pinned != null &&
        _groupCharacters.any((c) => _getCharacterIdFromCard(c) == pinned)) {
      return pinned;
    }
    // Outside a turn (pre-pick): the upcoming speaker if known (round-robin),
    // else the first member.
    final next = nextCharacter;
    if (next != null) {
      return _getCharacterIdFromCard(next);
    }
    return _getCharacterIdFromCard(_groupCharacters.first);
  }

  /// Card the work prompt (occupation / hours / brief) reads.
  ///
  /// 1:1 uses [_activeCharacter]. Group looks up the member whose id is
  /// [_getCurrentSpeakerIdForRealism] — never [_activeCharacter], which
  /// [setActiveGroup] nulls for the whole turn. No matching card
  /// (empty roster / unknown id) returns null so the three fields stay empty.
  CharacterCard? _workSpeakerCard() {
    if (_activeGroup == null) return _activeCharacter;
    final sid = _getCurrentSpeakerIdForRealism();
    for (final c in _groupCharacters) {
      if (_getCharacterIdFromCard(c) == sid) return c;
    }
    return null;
  }

  ({
    String occupation,
    String hours,
    String occupationBrief,
    List<int>? workDays,
  })
  _workFieldsForCurrentSpeaker() {
    final card = _workSpeakerCard();
    if (card == null) {
      return (occupation: '', hours: '', occupationBrief: '', workDays: null);
    }
    return _workFieldsFor(card);
  }

  /// Test-only: pin the group speaker the same way `_generateResponse` does
  /// (`_turnSpeakerIdForRealism`). Do not assign `_activeCharacter`.
  @visibleForTesting
  void debugPinTurnSpeakerForRealism(String? charId) {
    _turnSpeakerIdForRealism = charId;
  }

  /// Test-only: live position injection through the wired BehavioralInjection.
  /// Does not stub `getOccupationBrief`.
  @visibleForTesting
  String debugBuildPositionInjection() =>
      _behavioralInjection.buildPositionInjection();

  /// Test-only: first-speaker [_loadGroupRealismIntoScalars] without a turn.
  @visibleForTesting
  void debugReloadFirstGroupSpeakerScalars() {
    if (_groupCharacters.isEmpty) return;
    _loadGroupRealismIntoScalars(
      _getCharacterIdFromCard(_groupCharacters.first),
    );
  }

  /// Test-only: emotion sitting in a group member slot (not live scalars).
  @visibleForTesting
  String debugGroupSlotEmotion(String charId) =>
      _groupRealism[charId]?.emotion ?? '';

  // ── Per-character realism state access (group mode, typed — U7) ─────────
  /// The one write door to a member's typed state. Outside group mode it
  /// hands back a THROWAWAY object, so writes vanish — observationally the
  /// same no-op the old `if (_activeGroup == null) return;` guard performed
  /// (it allocates one discarded object; nothing reaches the map), without
  /// every caller needing to re-check the mode.
  GroupMemberRealism _memberForWrite(String charId) {
    if (_activeGroup == null) return GroupMemberRealism();
    return _groupRealism.putIfAbsent(charId, GroupMemberRealism.new);
  }

  /// Defensive int read for the generic bridge callbacks (counters, nsfw).
  /// Same is-num semantics as the typed getters — Grok's U7 review flagged
  /// that the bridges still THREW on a wrong-typed value while every typed
  /// read defaulted, so one bad blob could crash one path and not another.
  int _groupIntOr(String charId, String key, int defaultValue) =>
      switch (_groupRealism[charId]?.valueFor(key)) {
        final num v => v.toInt(),
        _ => defaultValue,
      };

  // Tolerant coercion for a needs vector that may arrive as JSON-decoded
  // (num values), dynamic map from metadata/snapshots/pre_state, or proper
  // Map<String,int>. Used for pre-turn vectors in chips, restores, and fallbacks.
  Map<String, int> _coerceNeedsVector(dynamic src) {
    if (src == null) return const {};
    if (src is Map<String, int>) return Map<String, int>.from(src);
    if (src is Map) {
      final out = <String, int>{};
      src.forEach((k, v) {
        final key = k.toString();
        if (v is num) {
          out[key] = v.toInt();
        } else if (v is int) {
          out[key] = v;
        }
      });
      return out;
    }
    return const {};
  }

  Map<String, int> _getGroupNeeds(String charId) {
    final raw = _groupRealism[charId]?.needs;
    final result = <String, int>{};
    for (final k in NeedsSimulation.needKeys) {
      final v = raw?[k];
      result[k] = v ?? (NeedsSimulation.needDefaults[k] ?? 80);
    }
    return result;
  }

  void _setGroupNeeds(String charId, Map<String, int> needs) {
    _memberForWrite(charId).needs = needs;
  }

  /// Needs decay rates for the character being decayed on the CURRENT turn.
  ///
  /// Single source of truth for BOTH the 1:1 `tickDecay` closure and the group
  /// realism-dance decay loop — it replaces the old split where 1:1 read the
  /// host card's ext while a group read one shared `_groupDecayRates` map for
  /// everybody. In 1:1 this is the active host; in a group it is the speaker the
  /// dance has impersonated into `_activeCharacter` before decay, so each member
  /// decays at its OWN authored rate exactly like a solo card.
  ///
  /// Falls back to the legacy shared map only for pre-per-member groups whose
  /// member cards genuinely lack ext data; empty there → downstream uses
  /// `NeedsSimulation.needDecay` defaults (identical to the ext defaults).
  Map<String, int> _activeDecayRates() {
    CharacterCard? card = _activeCharacter;
    if (_activeGroup != null && card == null) {
      // Off the main dance path (e.g. the sim's own tickDecay closure in tests
      // where no character is impersonated): resolve the speaker by id.
      final sid = _getCurrentSpeakerIdForRealism();
      for (final c in _groupCharacters) {
        if (_getCharacterIdFromCard(c) == sid) {
          card = c;
          break;
        }
      }
    }
    final ext = card?.frontPorchExtensions;
    if (ext != null) {
      return {
        'hunger': ext.needsDecayHunger,
        'bladder': ext.needsDecayBladder,
        'energy': ext.needsDecayEnergy,
        'social': ext.needsDecaySocial,
        'fun': ext.needsDecayFun,
        'hygiene': ext.needsDecayHygiene,
        'comfort': ext.needsDecayComfort,
      };
    }
    if (_activeGroup != null && _groupDecayRates.isNotEmpty) {
      return _groupDecayRates;
    }
    return const <String, int>{};
  }

  /// Re-stamp the just-generated message's `realism_state` snapshot with the
  /// POST-generation values, so every consumer that restores a message's
  /// snapshot as a baseline (regenerating a later message, the regen merge's
  /// _restoreRealismStateForSpeaker, swipe navigation, delete time-travel)
  /// sees the turn's final state, not the pre-impact one.
  ///
  /// Two shipped bugs live here as warnings:
  ///  * NEEDS: the snapshot is captured during the pre-gen eval, before the
  ///    needs impact applies scene rewards — restoring it reverted them
  ///    ("Hygiene snaps back after regenerating the next message").
  ///  * NSFW (the "orgasm detection doesn't work" report, Violet Vance chat):
  ///    a climax fires in the post-gen checks — arousal to 0, refractory
  ///    started — AFTER the snapshot froze arousal at 100 / cooldown 0. The
  ///    1:1 regen merge then restored that stale snapshot and ERASED the
  ///    climax seconds after detection: the swipe's own metadata carried
  ///    climax_triggered=true while the session row still said 100/0/0.
  ///
  /// SPATIAL STANCE joined them on 2026-08-08, when the posture eval moved to
  /// the post-generation phase so it could read the reply. That moved a WRITE
  /// across the snapshot boundary: without this line every message would
  /// carry the position the character was in BEFORE her reply, and the regen
  /// revert (which rebuilds its baseline from the previous accepted message's
  /// snapshot) would hand the replacement turn a position one exchange stale
  /// — the exact teleport the move was made to stop, reintroduced through the
  /// rewind door. It is also what makes swiping between alternatives move the
  /// character to where THAT alternative left her.
  ///
  /// SPATIAL STANCE ALSO LEAVES A PRE-TURN RECEIPT HERE, and that is not
  /// bookkeeping — it is the other half of moving the write.
  ///
  /// The snapshot below is captured BEFORE generation, so up to the moment
  /// this method runs `rs['spatialStance']` still holds the position the turn
  /// STARTED from. Overwriting it with the post-reply position is right for
  /// everything that reads a snapshot forwards (the next turn's baseline,
  /// swipe navigation, delete time-travel) and fatal for the one thing that
  /// reads it backwards: a REGENERATE has to put the stance back to what it
  /// was before the reply it is discarding, and after the overwrite no record
  /// of that value existed anywhere.
  ///
  /// The regen revert normally papers over this by restoring the PREVIOUS
  /// accepted message's snapshot — whose post-reply stance is, by
  /// construction, this turn's pre-reply stance. But the FIRST reply of a
  /// chat has no previous accepted message: the greeting only carries a
  /// snapshot on the one entry path that runs the greeting baseline eval
  /// (1:1, `startNewChat`, card with NO frontPorchExtensions), which is
  /// neither the common card shape, nor a group, nor the ordinary
  /// open-a-character path. On every other opening the revert found nothing,
  /// left the discarded reply's position in place, and each reroll then
  /// grounded the next attempt in a position invented by the reply the user
  /// had just thrown away — drifting further every press.
  ///
  /// So the pre-reply value is preserved beside the snapshot before it is
  /// overwritten, in exactly the idiom `needs_pre_turn_vector` and
  /// `pre_climax_arousal` already use for the two other post-generation
  /// writes: the rejected message carries the receipt for its own rewind.
  /// `putIfAbsent` is what makes Continue safe — a continuation restamps the
  /// SAME message a second time, by which point the snapshot holds the
  /// post-reply position, and recording that would quietly redefine "before
  /// the turn" as "after it".
  ///
  /// metadata and swipeMetadata[i] share one map instance, so this in-place
  /// update sticks through the regen swipe merge and persists. 1:1 and group
  /// alike: the speaker's scalars are loaded when this runs. Guests carry no
  /// realism_state, so this no-ops for them.
  Future<void> _restampRealismSnapshotPostGen(ChatMessage msg) async {
    if (msg.isUser) return;
    // She named a time ("six in the morning") that disagrees with the
    // pre-gen snap (new_day → 08:00). Fiction wins so the sidebar matches
    // the line you just read. Gated on a moving clock — a frozen clock
    // must not start chasing dialogue.
    if (_clockRunning) {
      final named = clockNamedInReply(msg.text, _timeService.clock);
      if (named != null) await _timeService.applyReconciledClock(named);
    }
    final meta = msg.activeMetadata;
    final rs = meta?['realism_state'];
    if (rs is! Map) return;
    if (_needsSimEnabled &&
        _needsSimulation.vector.isNotEmpty &&
        rs['needs'] is Map) {
      (rs['needs'] as Map)['vector'] = Map<String, int>.from(
        _needsSimulation.vector,
      );
    }
    if (rs.containsKey('arousalLevel')) {
      rs['arousalLevel'] = _nsfwService.arousalLevel;
      rs['cooldownTurnsRemaining'] = _nsfwService.cooldownTurnsRemaining;
      rs['cooldownTurnsTotal'] = _nsfwService.cooldownTurnsTotal;
    }
    if (rs.containsKey('spatialStance')) {
      meta!.putIfAbsent(
        kSpatialStancePreTurn,
        () => rs['spatialStance'] as String? ?? '',
      );
      rs['spatialStance'] = _relationshipService.spatialStance;
    }
    rs['withUser'] = _relationshipService.withUser;
    // Pockets was captured pre-gen in _captureRealismState and never
    // restamped, so swipe/delete restore put the PRE-ops kit back after a
    // successful pass (release audit 2026-08-11). Mirror needs/arousal:
    // the snapshot that rides the accepted message is post-turn truth.
    if (_activeCharacter != null) {
      final p = pocketsFor(_getCharacterIdFromCard(_activeCharacter!));
      if (p != null) {
        rs['pockets'] = p.toJson();
      }
    }
    if (rs.containsKey('storyClock')) {
      rs['storyClock'] = _timeService.storyClockIso;
      rs['timeOfDay'] = _timeService.timeOfDay;
      rs['dayCount'] = _timeService.dayCount;
    }
  }

  /// Give back what a deleted message spent.
  ///
  /// A message's chips (`needs_deltas`) ARE the record of what that turn did to
  /// the speaker's needs, so deleting it subtracts those deltas from the
  /// CURRENT scores. Deliberately arithmetic rather than time travel: a message
  /// buried twenty turns back rolls its cost off exactly like the newest one,
  /// which is what the realism snapshot ("restore the state stamped on the new
  /// last message") could never do — it only ever rewound the tail, so a reply
  /// that cost 20 hunger kept costing it forever once deleted.
  ///
  /// [liveBefore] is the speaker's needs captured BEFORE the delete path's
  /// realism time-travel ran. That restore rewinds the whole realism snapshot
  /// (bond/trust/emotion/time) and its needs half would otherwise fight this
  /// arithmetic, so needs are settled here and here only.
  ///
  /// 1:1/group parity: [groupSid] names the DELETED speaker, so a group refund
  /// lands in their own `_groupRealism` entry exactly as a 1:1 refund lands in
  /// the live vector.
  void _revertNeedsForDeletedMessage(
    ChatMessage deleted,
    Map<String, int> liveBefore, {
    String? groupSid,
  }) {
    if (!_needsSimEnabled || liveBefore.isEmpty) return;
    final raw = deleted.activeMetadata?['needs_deltas'];
    if (raw is! Map || raw.isEmpty) return;

    final refunded = Map<String, int>.from(liveBefore);
    var changed = false;
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final v = entry.value;
      // Chips are {delta, reason}; tolerate a bare number from older rows.
      final delta = (v is Map && v['delta'] is num)
          ? (v['delta'] as num).toInt()
          : (v is num ? v.toInt() : 0);
      if (delta == 0 || !refunded.containsKey(key)) continue;
      refunded[key] = (refunded[key]! - delta).clamp(0, 100);
      changed = true;
    }
    if (!changed) return;

    if (groupSid != null && groupSid.isNotEmpty) {
      _setGroupNeeds(groupSid, refunded);
      // Keep the live scalars in step when the refunded speaker is the one
      // currently loaded, or the sidebar keeps showing the stale figure.
      if (_getCurrentSpeakerIdForRealism() == groupSid) {
        _needsSimulation.restoreFromSnapshot({'vector': refunded});
      }
    } else {
      _needsSimulation.restoreFromSnapshot({'vector': refunded});
    }
    debugPrint(
      '[Realism:Needs] Deleted message refunded its deltas to '
      '${deleted.sender}${groupSid == null ? '' : ' ($groupSid)'}',
    );
  }

  /// Compute + attach this message's needs-delta chips (`needs_deltas`) from the
  /// speaker's pre-turn baseline to their post-turn (decay + impact) needs.
  ///
  /// Called from `_generateResponse` so EVERY generated turn gets chips — 1:1
  /// host, group first responder, group auto-advance (`triggerNextCharacter`),
  /// and `/speak` alike. The old block lived only in `sendMessage`, so any group
  /// speaker after the first (who reaches `_generateResponse` by another door)
  /// showed no needs chips even though their needs were simulated correctly.
  ///
  /// Baseline is the message's own `needs_pre_turn_vector` — stamped per-speaker
  /// (1:1 in `sendMessage` pre-tick; group in the realism dance pre-decay) — with
  /// the `realism_state` snapshot's needs vector as a fallback. No-op when there
  /// is no baseline or no net change (`message_bubble` hides zero-delta needs).
  ///
  /// Deliberately a pure in-memory mutator with NO save of its own. It used to
  /// end in `_saveChat()`, and because it is the LAST thing the post-generation
  /// block does, that made it the accidental persist for the whole phase — one
  /// that never ran when Needs was off, silently costing the spatial stance
  /// (and anything else written after the phase's first save) its trip to
  /// disk. The persist now lives at the end of the block in
  /// `chat_service_generation_postgen.dart`, where it covers every pass rather
  /// than one feature's slice.
  void _attachNeedsDeltaChipToLastMessage() {
    if (!_needsSimEnabled || _messages.isEmpty) return;
    var preVec = _coerceNeedsVector(
      _messages.last.activeMetadata?['needs_pre_turn_vector'],
    );
    if (preVec.isEmpty) {
      preVec = _coerceNeedsVector(
        (_messages.last.activeMetadata?['realism_state']
            as Map<String, dynamic>?)?['needs']?['vector'],
      );
    }
    if (preVec.isEmpty) return;
    final needsDeltas = _needsSimulation.computeNeedsDeltasWithReasons(preVec);
    if (needsDeltas.isEmpty) return;
    _messages.last.activeMetadata ??= {};
    _messages.last.activeMetadata!['needs_deltas'] = needsDeltas;
    debugPrint(
      '[Realism:Needs] Chip: ${needsDeltas.length} need delta(s) attached for '
      '${_messages.last.sender}',
    );
  }
}
