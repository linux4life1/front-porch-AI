// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/climax_eval.dart';
import 'package:front_porch_ai/services/chat/clock_resolve.dart';
import 'package:front_porch_ai/services/chat/group_member_realism.dart';
import 'package:front_porch_ai/services/chat/group_realism_store.dart';
import 'package:front_porch_ai/services/chat/llm_eval_engine.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/realism_scope.dart';
import 'package:front_porch_ai/services/chat/refractory.dart';
import 'package:front_porch_ai/services/chat/story_clock_writer.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

/// Afterglow's post-generation climax check — the one place it is gated, fired
/// and applied — and the refractory it starts, run down on the story clock.
///
/// Sits beside [PocketsPass] in the same post-gen phase and for the same
/// reason: it reads the reply that was just written. See the class doc on
/// [ClimaxEval] for why it must be post-generation and why it stands alone
/// instead of riding the needs-impact eval.
class AfterglowPass {
  AfterglowPass(
    this._scope,
    this._eval, {
    required this.fusedReply,
    required this.isGuestAuthoredMessage,
    required this.resolveGroupSpeakerForMessage,
  });

  final RealismScope _scope;
  final ClimaxEval _eval;

  /// The fused reply-facts carrier (`ReplyFacts.raw`).
  final String? Function() fusedReply;
  final bool Function(ChatMessage) isGuestAuthoredMessage;
  final CharacterCard? Function(ChatMessage) resolveGroupSpeakerForMessage;

  bool get _realismEnabled => _scope.realismEnabled();
  bool get _clockRunning => _scope.clockRunning();
  NsfwService get _nsfwService => _scope.nsfw();
  TimeService get _timeService => _scope.time();
  GroupChat? get _activeGroup => _scope.activeGroup();
  CharacterCard? get _activeCharacter => _scope.activeCharacter();
  List<CharacterCard> get _groupCharacters => _scope.groupCharacters();
  List<ChatMessage> get _messages => _scope.messages;
  GroupRealismStore get _groupStore => _scope.groups;
  Map<String, GroupMemberRealism> get _groupRealism => _scope.groups.members;
  Map<String, dynamic>? get _pendingRealismMetadata => _scope.pending();
  set _pendingRealismMetadata(Map<String, dynamic>? v) => _scope.setPending(v);
  String _getCharacterIdFromCard(CharacterCard c) => _scope.characterIdFor(c);
  bool _isGuestAuthoredMessage(ChatMessage m) => isGuestAuthoredMessage(m);
  CharacterCard? _resolveGroupSpeakerForMessage(ChatMessage m) =>
      resolveGroupSpeakerForMessage(m);

  /// Whether Afterglow can run at all this turn.
  ///
  /// The Realism Engine and the Afterglow switch. NOT Needs — that dependency
  /// was never declared anywhere, and it is what made the feature dead on most
  /// cards while its row showed green.
  bool get active => _realismEnabled && _nsfwService.nsfwCooldownEnabled;

  /// Ask whether the reply narrated the character's own climax, and start the
  /// refractory if it did.
  ///
  /// On Continue the caller passes the NEW text only (2026-08-12; the pass
  /// used to be skipped outright): a climax the first half already registered
  /// is not re-claimed by its aftermath, and one the continuation adds
  /// finally starts its refractory. `applyClimaxEffects` is absolute
  /// (turns × 15 story minutes, opening turn unspoken, arousal = 0), so even
  /// a re-affirmation cannot stack; the metadata guard below keeps the FIRST
  /// reading's pre-climax arousal, because by the second reading it is
  /// already 0.
  Future<void> runClimaxPass(String reply) async {
    if (!active) return;
    if (reply.trim().isEmpty) return;

    final speaker = _activeCharacter;
    if (speaker == null) return;

    // On a fused reply-facts turn the question was already asked (one call
    // for all three bookkeeping passes) — read this pass's slice through the
    // SAME parser the standalone call feeds. A fused answer without a
    // verdict skips, exactly as a failed standalone call does.
    final fused = fusedReply();
    final turns = fused != null
        ? ClimaxEval.parseRefractory(fused)
        : await _eval.detect(
            charName: speaker.name,
            // Clamped like every judge window (eval diet, hostile
            // review 2026-08-11).
            reply: clampEvalMessage(reply),
            // The same window the needs eval uses, from the one shared helper —
            // this was a hand-rolled copy until Pockets needed a third.
            recentExchange: recentExchange(_messages),
          );
    if (turns == null) return;

    // Metadata first, then the effect — applyClimaxEffects zeroes arousal, so
    // reading it afterwards would record 0 as the pre-climax level and the
    // chip would say the character peaked from nothing.
    final preClimaxArousal = _nsfwService.arousalLevel;
    if (_messages.isNotEmpty && !_messages.last.isUser) {
      final msg = _messages.last;
      final meta = Map<String, dynamic>.from(msg.activeMetadata ?? {});
      if (meta['climax_triggered'] != true) {
        meta['climax_triggered'] = true;
        meta['pre_climax_arousal'] = preClimaxArousal;
        // Through the setter, never `swipeMetadata[swipeIndex] = ...`: the
        // list is persisted only when some entry is non-null, so a reloaded
        // (or imported) message that has 4 swipes and no metadata comes back
        // with a ONE-element list and swipeIndex 3. The raw write threw
        // RangeError inside the post-gen phase, which surfaced as a bogus
        // "generation failed" banner and skipped pockets/posture/restamp.
        // The setter pads first (chat_message.dart).
        msg.activeMetadata = meta;
      }
    }
    _nsfwService.applyClimaxEffects(turns: turns);

    debugPrint(
      '[Afterglow] climax detected (arousal was $preClimaxArousal) — '
      'refractory ${_nsfwService.refractoryMinutesRemaining} min',
    );
    _scope.notify();
  }

  // ── The refractory on the story clock ────────────────────────────────────

  /// After the clock commits. With Passage of Time running, every body's
  /// refractory runs down by this beat's story minutes, a skip or a night
  /// included. With it off, the reply's quarter hour was taken before
  /// generation ([tickPerReply]). Either way the speaker has now
  /// spoken their opening afterglow turn. Continue is the same beat: nothing.
  /// [speakerIdOf] is the turn's speaker, or null for a lite (guest or
  /// soft member) beat; [reply] is the turn's stream target. Both are read
  /// only past the gate, where the old `_GenTurn` reads were.
  void tickAfterClock(
    GenerationMode mode, {
    required String? Function() speakerIdOf,
    required ChatMessage Function() reply,
  }) {
    if (mode != GenerationMode.normal || !_realismEnabled) return;
    final speakerId = speakerIdOf();
    final loadedId = _activeGroup != null ? speakerId : null;
    Map<String, dynamic> slot() => clockWriteSlot(reply());
    if (_clockRunning) {
      final minutes = _refractoryBeatMinutes(reply());
      for (final id in _refractoryBodyIds()) {
        _moveRefractory(
          id,
          slot,
          loadedId,
          (b) => b.refractory.elapse(minutes, arousal: b.arousal),
        );
      }
    }
    if (speakerId == null) return;
    _moveRefractory(
      speakerId,
      slot,
      loadedId,
      (b) => (refractory: b.refractory.markOpened(), arousal: b.arousal),
    );
  }

  /// Clock off: each reply is a quarter hour for every body, so a refractory
  /// ends after as many replies as the judge gave turns. Runs where the
  /// per-reply tick always ran (the 1:1 send and regen; in a group right
  /// after the speaker's scalars load, [loadedId]); the receipt rides the
  /// reply's pending metadata.
  void tickPerReply({String? loadedId}) {
    if (_clockRunning) return;
    // Clock off: a reply is fifteen minutes for the character who spoke, as
    // it was one turn before; the others wait for their own replies, so a
    // refractory still ends after the same number of that character's
    // replies as it did.
    final ids = _refractoryBodyIds();
    final id = loadedId ?? (ids.length == 1 ? ids.single : null);
    if (id == null || !ids.contains(id)) return;
    _moveRefractory(
      id,
      () => _pendingRealismMetadata ??= {},
      loadedId,
      (b) => b.refractory.elapse(kRefractoryMinutesPerTurn, arousal: b.arousal),
    );
  }

  /// Story minutes this reply's beat spanned: the clock now minus where the
  /// beat began. That is the recorded after of the nearest earlier reply (a
  /// skip at send moves the clock before this reply stamps its own before),
  /// else this reply's own before.
  int _refractoryBeatMinutes(ChatMessage reply) {
    DateTime? start;
    final at = _messages.lastIndexWhere((m) => identical(m, reply));
    for (var i = (at < 0 ? _messages.length : at) - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.isUser || m.sender == 'System') continue;
      start = slotClockAfter(m.activeMetadata);
      if (start != null) break;
    }
    start ??= slotClockBefore(reply.activeMetadata);
    if (start == null) return 0;
    final minutes = _timeService.clock.difference(start).inMinutes;
    return minutes > 0 ? minutes : 0;
  }

  /// The 1:1 host, or every group member. Scene guests carry no refractory.
  List<String> _refractoryBodyIds() {
    if (_activeGroup == null) {
      final host = _activeCharacter;
      return host == null ? const [] : [_getCharacterIdFromCard(host)];
    }
    return [
      for (final c in _groupCharacters)
        if (_getCharacterIdFromCard(c) case final id when id.isNotEmpty) id,
    ];
  }

  /// Steps one running refractory: the live scalars for the 1:1 host or the
  /// loaded group speaker, else that member's own entry. A change is recorded
  /// on the beat's receipts in [meta].
  void _moveRefractory(
    String id,
    Map<String, dynamic> Function() meta,
    String? loadedId,
    RefractoryBody Function(RefractoryBody) step,
  ) {
    if (_activeGroup != null && id.isEmpty) return;
    final live = _activeGroup == null || id == loadedId;
    final before = _refractoryBody(id, live: live);
    if (!before.refractory.running) return;
    final after = step(before);
    if (after == before) return;
    _setRefractoryBody(id, after, live: live);
    noteRefractoryBeat(meta(), id, before: before, after: after);
  }

  RefractoryBody _refractoryBody(String id, {required bool live}) {
    if (live) {
      return (
        refractory: _nsfwService.refractory,
        arousal: _nsfwService.arousalLevel,
      );
    }
    final member = _groupRealism[id];
    return (
      refractory: member?.refractory ?? Refractory.none,
      arousal: member?.arousal ?? 0,
    );
  }

  void _setRefractoryBody(
    String id,
    RefractoryBody body, {
    required bool live,
    bool withArousal = true,
  }) {
    if (live) {
      _nsfwService.setRefractory(body.refractory);
      if (withArousal) _nsfwService.setArousalLevel(body.arousal);
      return;
    }
    final member = _groupStore.memberForWrite(id)..refractory = body.refractory;
    if (withArousal) member.arousal = body.arousal;
  }

  /// Regen and a tail delete: every body this reply's beat moved goes back to
  /// where the beat found it. The speaker's arousal stays with the realism
  /// rewind, which owns the rest of their turn.
  void restoreBeforeBeat(ChatMessage msg) => _applyRefractoryReceipt(
    msg.activeMetadata?[kRefractoryPreBeat],
    keepArousalOf: _refractorySpeakerId(msg),
  );

  /// A swipe: every co-present body as this alternative's beat left it. The
  /// speaker comes back with their own realism snapshot.
  void restoreAfterBeat(ChatMessage msg, String speakerId) =>
      _applyRefractoryReceipt(
        msg.activeMetadata?[kRefractoryPostBeat],
        skip: speakerId,
      );

  void _applyRefractoryReceipt(
    Object? raw, {
    String? skip,
    String? keepArousalOf,
  }) {
    final receipt = refractoryReceipt(raw);
    if (receipt.isEmpty) return;
    final ids = _refractoryBodyIds();
    if (_activeGroup == null) {
      final hostId = ids.firstOrNull;
      if (hostId == null || hostId == skip) return;
      final body =
          receipt[hostId] ??
          (receipt.length == 1 ? receipt.values.first : null);
      if (body == null) return;
      _setRefractoryBody(
        hostId,
        body,
        live: true,
        withArousal: hostId != keepArousalOf,
      );
      return;
    }
    for (final MapEntry(key: id, value: body) in receipt.entries) {
      if (id == skip || !ids.contains(id)) continue;
      _setRefractoryBody(
        id,
        body,
        live: false,
        withArousal: id != keepArousalOf,
      );
    }
  }

  /// Whose turn [msg] was: the 1:1 host unless a scene guest wrote it, or the
  /// group member it resolves to.
  String? _refractorySpeakerId(ChatMessage msg) {
    if (_activeGroup == null) {
      final host = _activeCharacter;
      if (host == null || _isGuestAuthoredMessage(msg)) return null;
      return _getCharacterIdFromCard(host);
    }
    final speaker = _resolveGroupSpeakerForMessage(msg);
    return speaker == null ? null : _getCharacterIdFromCard(speaker);
  }
}
