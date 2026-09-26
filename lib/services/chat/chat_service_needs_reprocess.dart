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

/// Manual needs reprocess + its revert — the two flows that let a user correct
/// a message's Needs deltas after the fact.
///
/// Split out of `chat_service_reprocess.dart` when the scoped-reprocess work
/// pushed that file over the god-file ratchet. The seam is the one its own doc
/// comment already described: these two rebuild a PAST message's needs from a
/// fixed baseline, while the regenerate flows left behind replay a turn against
/// the live model. They share only [_resolveGroupSpeakerForMessage], which
/// stays there because both halves use it.
///
/// The whole reason a baseline key exists rather than reusing realism_state is
/// documented on [ChatServiceNeedsReprocess._needsPreImpactBaseline] — read it
/// before touching either flow.

extension ChatServiceNeedsReprocess on ChatService {
  /// The needs vector as it stood BEFORE this turn touched needs at all — the
  /// one baseline a reprocess and a revert may rebuild from.
  ///
  /// `realism_state['needs']['vector']` cannot serve this role, and that
  /// conflation is the bug this exists to close. It is wrong twice over:
  ///
  ///  * it is captured AFTER the turn's needs impact, so rebuilding from it
  ///    re-applies the turn on top of itself; and
  ///  * both flows below then overwrite it with the post-correction vector,
  ///    because it doubles as the rewind target for swipe navigation and regen.
  ///
  /// Either alone double-counts. Together they compounded on every pass, which
  /// is what the report described: hygiene -6 on the message, a critique about
  /// energy, and hygiene falling further each time while nobody had asked it to
  /// move. `revertNeedsReprocess` rebuilt from the same field and drifted too.
  ///
  /// The honest baseline is `needs_pre_turn_vector` — the pre-decay snapshot
  /// the realism dance already stamps per speaker, and the same one
  /// `needs_deltas` is measured against. Rebuilding from it and re-applying the
  /// message's own deltas reproduces the current state exactly, which is what
  /// makes N passes land where one does. It is copied into `needs_pre_impact`
  /// on first use and never rewritten, so messages that predate the dance
  /// stamp (and the legacy realism_state fallback below) become stable too
  /// after one pass.
  Map<String, int> _needsPreImpactBaseline(
    Map<String, dynamic> meta,
    Map preState,
  ) {
    final stashed = _needsVectorFrom(meta['needs_pre_impact']);
    if (stashed.isNotEmpty) return stashed;
    final preTurn = _needsVectorFrom(meta['needs_pre_turn_vector']);
    if (preTurn.isNotEmpty) return preTurn;
    // Legacy messages only: no pre-turn stamp to trust. Best effort, and the
    // stash above makes even this stable from the second pass onward.
    return _needsVectorFrom((preState['needs'] as Map?)?['vector']);
  }

  /// Tolerant read of a persisted needs vector: these survive a JSON round trip
  /// through the session store, so values arrive as `num` and keys as `dynamic`.
  Map<String, int> _needsVectorFrom(Object? raw) {
    if (raw is! Map) return <String, int>{};
    return {
      for (final e in raw.entries)
        if (e.value is num) e.key.toString(): (e.value as num).toInt(),
    };
  }

  /// Re-evaluate a message's needs deltas under a user critique.
  ///
  /// [onlyNeeds] scopes the pass: needs NOT listed keep the deltas they already
  /// had, untouched and un-re-rolled. Empty = every need the model returns.
  /// Scoping matters beyond the obvious — a full-set pass makes the model
  /// re-emit all seven needs against the same scene text, so correcting energy
  /// silently re-rolls hunger, hygiene and comfort to new numbers nobody asked
  /// for.
  Future<bool> manualReprocessNeeds(
    int index,
    String critique, {
    Set<String> onlyNeeds = const <String>{},
  }) async {
    if (index < 0 || index >= _messages.length) return false;
    if (_isTurnBusy) return false;

    final msg = _messages[index];
    if (msg.isUser || msg.sender == 'System') return false;

    final meta = msg.activeMetadata;
    if (meta == null || !meta.containsKey('realism_state')) return false;

    final preState = meta['realism_state'];
    if (preState is! Map || preState['needs'] == null) return false;

    // A: entry guard (usable needs data) already passed; button in UI also checks now.

    final oldNeedsDeltas = <String, int>{};
    Map<String, dynamic>? originalNeedsDeltasForStash;
    if (meta.containsKey('needs_deltas')) {
      final oldMap = meta['needs_deltas'] as Map;
      originalNeedsDeltasForStash = Map<String, dynamic>.from(oldMap);
      for (final k in oldMap.keys) {
        if (oldMap[k] is Map && oldMap[k]['delta'] is num) {
          oldNeedsDeltas[k.toString()] = (oldMap[k]['delta'] as num).toInt();
        }
      }
    }

    // D: stash original deltas under pre_reprocess key (before any commit)
    final hasPrior = originalNeedsDeltasForStash != null;

    final bool isLast = index == _messages.length - 1;
    final bool isGroupNonObs = _activeGroup != null && !_observerMode;
    String? sid;
    CharacterCard? targetSpeakerCard;
    if (isGroupNonObs) {
      targetSpeakerCard = _resolveGroupSpeakerForMessage(msg);
      if (targetSpeakerCard == null) return false;
      sid = _getCharacterIdFromCard(targetSpeakerCard);
    }

    // Snapshot the *active* live state *before* any historical/target prepare (for strict historical meta-only)
    final Map<String, int> preOpLive;
    String? preOpActiveSid;
    // Captured in BOTH modes, because every restore below is unconditional.
    // A group-only capture left this null for 1:1 chats, so the isLast
    // success path nulled the active character on every successful 1:1
    // reprocess: the chat page fell back to "No character selected." and the
    // trailing _saveChat no-oped (its null-character guard), dropping the
    // reprocess result. In a pure group this still correctly captures null.
    final CharacterCard? preActiveChar = _activeCharacter;
    if (isGroupNonObs) {
      preOpActiveSid = _getCurrentSpeakerIdForRealism();
      preOpLive = Map<String, int>.from(_getGroupNeeds(preOpActiveSid));
    } else {
      preOpLive = Map<String, int>.from(_needsSimulation.vector);
    }

    // Snapshot for rollback (target's at click time; used for last + compute baseline)
    final Map<String, int> livePreClick;
    if (isGroupNonObs && sid != null && sid.isNotEmpty) {
      livePreClick = Map<String, int>.from(_getGroupNeeds(sid));
    } else {
      livePreClick = Map<String, int>.from(_needsSimulation.vector);
    }

    // Group impersonation dance + load for prompt fidelity (personality/stance via getActiveCharacter in evaluate) + prepare scalar to msg pre.
    // For !isLast we still dance (to get correct prompt for that speaker's critique) but will strictly rollback live after.
    if (isGroupNonObs && sid != null && sid.isNotEmpty) {
      if (targetSpeakerCard != null) {
        _activeCharacter = targetSpeakerCard;
      }
      _loadGroupRealismIntoScalars(sid);
    }
    // Rebuild from the immutable pre-impact baseline, never from realism_state
    // (see _needsPreImpactBaseline for why that field drifts after pass one).
    final Map<String, int> baseline = _needsPreImpactBaseline(meta, preState);
    _needsSimulation.restoreFromSnapshot({'vector': baseline});
    final Map<String, int> restoredPreVector = Map<String, int>.from(
      _needsSimulation.vector,
    );

    if (isLast) {
      _isVerifyingRealism = true;
      _verificationPass = 1;
      _verificationMaxPasses = 1;
      notifyListeners();
    }

    _pendingRealismMetadata = null;
    _realismEvalCancelled = false;
    final koboldForReprocess = _llmProvider?.koboldService;
    if (koboldForReprocess != null) {
      await koboldForReprocess.waitForIdle();
    }

    final bool reprocessOk = await _needsImpactEvaluator
        .reprocessWithUserCritique(
          msg.displayText,
          oldNeedsDeltas,
          critique,
          onlyNeeds: onlyNeeds,
        );

    if (!reprocessOk) {
      // A: non-destructive: rollback to pre-op active live (historical leaves current active untouched)
      if (isGroupNonObs &&
          preOpActiveSid != null &&
          preOpActiveSid.isNotEmpty) {
        _loadGroupRealismIntoScalars(preOpActiveSid);
      } else if (isGroupNonObs && sid != null && sid.isNotEmpty) {
        _setGroupNeeds(sid, livePreClick); // fallback
      } else {
        _needsSimulation.restoreFromSnapshot({'vector': preOpLive});
      }
      // Unconditional: in a pure group the pre-op state IS null and the
      // impersonation must be dropped even on failure.
      _activeCharacter = preActiveChar;
      if (isLast) {
        _isVerifyingRealism = false;
        _pendingRealismMetadata = null;
        await _saveChat();
        notifyListeners();
      } else {
        _pendingRealismMetadata = null;
      }
      return false;
    }

    // The evaluator applied the correction onto the baseline restored above,
    // merging over the message's existing deltas when the pass was scoped.

    // Success path: commit metadata always (for the target msg)
    final updatedMeta = Map<String, dynamic>.from(meta);
    // Persist the baseline the moment it is first used, while it is still
    // provably the pre-impact vector. Every later pass reads it back.
    updatedMeta['needs_pre_impact'] = baseline;
    // Measured from the SAME baseline the deltas were applied from, so the
    // recomputed chip is exactly `merged` — no decay tick quietly added or
    // dropped, and a need the pass did not touch reads identically to before.
    final computed = _needsSimulation.computeNeedsDeltasWithReasons(
      restoredPreVector,
    );
    updatedMeta['needs_deltas'] = computed;

    // Keep realism_state['needs'] aligned with manual corrections so swipe
    // navigation and regen do not resurrect a stale pre-reprocess vector.
    if (_needsSimEnabled && updatedMeta['realism_state'] is Map) {
      final postReprocessVector = Map<String, int>.from(
        _needsSimulation.vector,
      );
      final rs = Map<String, dynamic>.from(updatedMeta['realism_state'] as Map);
      final needsSnap = <String, dynamic>{'vector': postReprocessVector};
      if (computed.isNotEmpty) {
        needsSnap['deltas'] = computed;
      }
      rs['needs'] = needsSnap;
      updatedMeta['realism_state'] = rs;
    }

    if (hasPrior) {
      updatedMeta['needs_deltas_pre_reprocess'] = originalNeedsDeltasForStash;
    }
    // D: record critique in verif meta (for history/tooltip)
    final verifMeta =
        (updatedMeta[RealismVerification.kMetaKey] as Map<String, dynamic>?) ??
        <String, dynamic>{};
    verifMeta['reprocess_critique'] = critique;
    updatedMeta[RealismVerification.kMetaKey] = verifMeta;

    if (_pendingRealismMetadata != null) {
      for (final e in _pendingRealismMetadata!.entries) {
        updatedMeta[e.key] = e.value;
      }
    }

    msg.swipeMetadata[msg.swipeIndex] = updatedMeta;

    if (isLast) {
      // Persist live only for current last speaker
      if (isGroupNonObs && sid != null && sid.isNotEmpty) {
        _saveScalarsIntoGroupRealism(sid);
      }
      // Drop the impersonation. The group per-character state is already saved
      // to _groupRealism above; leaving _activeCharacter pointed at the
      // impersonated speaker leaked their card into everything that reads
      // _activeCharacter (verifier flags, pace, which needs are on) until
      // the next dance overwrote it. Unconditional (not `!= null`-guarded): in
      // a pure group preActiveChar IS null and must be restored to null; for
      // 1:1 the capture above grabbed the current character, so this is the
      // no-op it always claimed to be.
      _activeCharacter = preActiveChar;
      _isVerifyingRealism = false;
      _pendingRealismMetadata = null;
    } else {
      // Historical: meta updated; strictly no live/group mutation left behind.
      // Transient onSaveChat may fire from temp apply (critique path); scalars rolled back; _saveChat here is only for target msg metadata.
      if (isGroupNonObs &&
          preOpActiveSid != null &&
          preOpActiveSid.isNotEmpty) {
        _loadGroupRealismIntoScalars(preOpActiveSid);
      } else if (!isGroupNonObs) {
        _needsSimulation.restoreFromSnapshot({'vector': preOpLive});
      }
      _activeCharacter = preActiveChar;
      _pendingRealismMetadata = null;
    }
    await _saveChat();
    notifyListeners();
    return true;
  }

  /// Revert a prior manual reprocess on the given message.
  /// Restores the stashed 'needs_deltas_pre_reprocess' into 'needs_deltas' (with reasons),
  /// rewinds live scalars *only if last* (historical: metadata-only update, live scalars/group untouched).
  /// Safe for 1:1 and group (speaker via msg.sender + dance on last).
  /// Returns true on success.
  Future<bool> revertNeedsReprocess(int index) async {
    if (index < 0 || index >= _messages.length) return false;
    if (_isTurnBusy) return false;
    final msg = _messages[index];
    final meta = msg.activeMetadata;
    if (meta == null || !meta.containsKey('needs_deltas_pre_reprocess')) {
      return false;
    }
    final preState = meta['realism_state'];
    if (preState is! Map || preState['needs'] == null) return false;

    final stashedDeltasMap = meta['needs_deltas_pre_reprocess'] as Map;
    final oldDeltas = <String, int>{};
    stashedDeltasMap.forEach((k, v) {
      if (v is Map && v['delta'] is num) {
        oldDeltas[k.toString()] = (v['delta'] as num).toInt();
      }
    });

    final bool isLast = index == _messages.length - 1;
    final bool isGroupNonObs = _activeGroup != null && !_observerMode;
    String? sid;
    CharacterCard? targetSpeakerCard;
    if (isGroupNonObs) {
      targetSpeakerCard = _resolveGroupSpeakerForMessage(msg);
      if (targetSpeakerCard == null) return false;
      sid = _getCharacterIdFromCard(targetSpeakerCard);
    }

    // Snapshot pre-op active for the restores below (both modes — see the
    // matching capture note in manualReprocessNeeds).
    final CharacterCard? preActiveChar = _activeCharacter;
    Map<String, int> preOpLive = {};
    String? preOpSid;
    if (isGroupNonObs) {
      preOpSid = _getCurrentSpeakerIdForRealism();
      preOpLive = Map<String, int>.from(_getGroupNeeds(preOpSid));
    } else {
      preOpLive = Map<String, int>.from(_needsSimulation.vector);
    }

    // Dance + prepare only if we will keep the effect (isLast); for historical we temp dance but rollback
    if (isGroupNonObs && sid != null && sid.isNotEmpty) {
      if (targetSpeakerCard != null) _activeCharacter = targetSpeakerCard;
      _loadGroupRealismIntoScalars(sid);
    }
    // Same baseline as the reprocess path, and for the same reason: by the
    // time a revert is possible realism_state already holds the POST-correction
    // vector, so rebuilding from it re-applied the original deltas on top of
    // the corrected state rather than in place of it.
    final Map<String, int> baseline = _needsPreImpactBaseline(meta, preState);
    _needsSimulation.restoreFromSnapshot({'vector': baseline});

    if (oldDeltas.isNotEmpty) {
      String? reasonToRestore;
      final values = (stashedDeltasMap as Map?)?.values ?? const [];
      for (final v in values) {
        if (v is Map &&
            v['reason'] is String &&
            (v['reason'] as String).isNotEmpty) {
          reasonToRestore = v['reason'] as String;
          break;
        }
      }
      _needsSimulation.applySceneImpact(
        NeedsImpact(deltas: oldDeltas, reason: reasonToRestore),
      );
    }

    final updated = Map<String, dynamic>.from(meta);
    updated['needs_deltas'] = stashedDeltasMap;
    updated.remove('needs_deltas_pre_reprocess');
    // 'needs_pre_impact' deliberately survives the revert: it describes the
    // turn, not the correction, and dropping it would let the next reprocess
    // re-derive a baseline from the (already post-impact) realism_state.
    updated['needs_pre_impact'] = baseline;
    if (_needsSimEnabled && updated['realism_state'] is Map) {
      final postRevertVector = Map<String, int>.from(_needsSimulation.vector);
      final rs = Map<String, dynamic>.from(updated['realism_state'] as Map);
      final needsSnap = <String, dynamic>{'vector': postRevertVector};
      if (stashedDeltasMap.isNotEmpty) {
        needsSnap['deltas'] = stashedDeltasMap;
      }
      rs['needs'] = needsSnap;
      updated['realism_state'] = rs;
    }
    msg.swipeMetadata[msg.swipeIndex] = updated;

    if (isLast) {
      if (isGroupNonObs && sid != null && sid.isNotEmpty) {
        _saveScalarsIntoGroupRealism(sid);
      }
      // Drop the impersonation set by the dance above — same leak (and same
      // fix) as manualReprocessNeeds' isLast path; this flow was missed when
      // that one was fixed. No-op for 1:1 (no dance ran).
      _activeCharacter = preActiveChar;
    } else {
      // Historical meta-only: rollback live + char, do not persist to group for this op
      if (isGroupNonObs && preOpSid != null && preOpSid.isNotEmpty) {
        _loadGroupRealismIntoScalars(preOpSid);
      } else if (!isGroupNonObs) {
        _needsSimulation.restoreFromSnapshot({'vector': preOpLive});
      }
      _activeCharacter = preActiveChar;
    }

    await _saveChat();
    notifyListeners();
    return true;
  }
}
