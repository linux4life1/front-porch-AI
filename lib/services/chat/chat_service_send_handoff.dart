// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Generate handoff, director note, guest chime-ins, and dream
// prefetch. preTurnVector is captured before the reply. Wear
// happens after the clock. Continue does not wear.

part of '../chat_service.dart';

extension ChatServiceSendHandoff on ChatService {
  /// Pre-turn needs capture, generate, chips baseline, guest chime-ins,
  /// and vision caption. Called from [sendMessage] after
  /// chaos/call-model/task-completion. Capture stays first so
  /// [preTurnVector] is the body before this beat's wear.
  Future<void> _sendDecayAndGenerate({
    required CharacterCard? addressedGuest,
    required ChatMessage userMsg,
    required String? imagePath,
    required String? sessionToken,
    String? forcedWebQuery,
    String? forcedWikiQuery,
  }) async {
    await _scoreUserTurnBeforeReply(
      userMsg: userMsg,
      addressedGuest: addressedGuest,
    );

    // If cancellation was requested during realism evaluation, abort generation
    if (_realismEvalCancelled) {
      // The turn dies before the request phase can adopt the call-model
      // swap — put the main model back ourselves. Lookup flags are not
      // armed yet; the generate call below is what consumes them.
      _exitCallEvalModelSwap();
      _needsSimulation.consumePendingCatastrophe();
      await _saveChat();
      _realismEvalCancelled = false;
      notifyListeners();
      return;
    }

    if (addressedGuest != null) {
      _armForcedLookup(webQuery: forcedWebQuery, wikiQuery: forcedWikiQuery);
      await generateGuestTurn(addressedGuest);
    } else {
      if (_activeGroup != null) {
        await _runAwayPulse(userText: userMsg.promptText, fromUserSend: true);
      }
      // This is the sole web-search allow-list entry: a newly appended user
      // message receiving its first host/group response. Every follow-up,
      // guest, cast, regen, idle, and command generation keeps the default
      // false and therefore cannot advertise or reach search HTTP.
      // A named /search or /wiki is armed for this first reply only.
      _armForcedLookup(webQuery: forcedWebQuery, wikiQuery: forcedWikiQuery);
      await _generateResponse(GenerationMode.normal, directUserSend: true);
    }
    // Backend-down abort: no response was generated, so none of the
    // post-turn work below may run — no idle-timer arming, no chip attach,
    // no guest chime-ins against the notice text (pre-move parity: the old
    // in-sendMessage guard returned before all of this).
    if (_messages.isNotEmpty && _messages.last.text == _kBackendDownNotice) {
      return;
    }
    // First exchange complete — arm idle timer
    _hasCompletedExchange = true;
    if (_storageService.generationSettings.dynamicResponses) {
      debugPrint(
        '[DynamicResponses] First exchange done, arming idle timer (interval=${_storageService.generationSettings.dynamicResponseInterval}s)',
      );
      _resetIdleTimer();
    }

    // Long-gen decay removed with buffers (decay via tick only now; model deltas via impact).
    // Compute needs_deltas AFTER generation so the post-generation checks
    // (climax, sexual activity, daily activities, fulfillment) are reflected.
    // This ensures UI chips show accurate deltas.
    // Per-message needs-delta chips are attached inside _generateResponse (via
    // _attachNeedsDeltaChipToLastMessage) so EVERY speaker gets them — group
    // auto-advance, /speak and chime-ins reach _generateResponse but never this
    // sendMessage scope, which is why only the first responder used to show
    // chips. preTurnVector is stamped in _scoreUserTurnBeforeReply.

    // ── Scene Guests: auto chime-in ─────────────────────────────────────────
    // The primary 1:1 turn is now 100% finalized (response + chip/realism block
    // above). Let the director decide which guest(s) speak next. Shared with
    // regenerateMainCharacter() so the re-chime gate is identical after a regen.
    // promptText (not raw text) so a photo-only turn feeds the director a
    // "[shared a photo]" marker instead of an empty user message. A routed
    // direct-address speaker is excluded — they already answered this turn.
    await _maybeRunSceneGuestChimeIns(
      userText: userMsg.promptText,
      exclude: addressedGuest,
    );

    // ── Auto-caption the attached photo for future-turn history ─────────────
    // Vision path only (blind models were captioned pre-gen). Runs LAST so the
    // eval never delays the response or guest turns; this turn already saw the
    // pixels, so the caption just lets later turns' history describe the photo.
    if (imagePath != null) {
      await runVisionPhotoCaption(userMsg, imagePath, sessionToken);
    }
  }

  /// Pre-reply scoring of a user turn: needs baseline, decay, and the 1:1
  /// host eval (groups score inside the dance). Shared by [sendMessage]
  /// and Generate reply on a trailing user message so both score alike.
  Future<void> _scoreUserTurnBeforeReply({
    required ChatMessage userMsg,
    CharacterCard? addressedGuest,
  }) async {
    if (addressedGuest == null && _activeGroup == null) {
      _stampUserTurnBaseline(userMsg);
    }
    // Evaluate realism systems before generating response
    // Capture pre-turn needs vector (before decay + fulfillment) so that
    // regenerateLastMessage() and the post-generation delta computation
    // can use the same delta-revert mechanism the classic realism fields
    // (bond/trust/arousal) use.
    // The Needs pass stamps the body before this beat (and nothing, with
    // Needs off); regen and the chip read the stamp from the reply.
    if (addressedGuest == null && _activeGroup == null) _needsStampPreTurn();
    if (_realismActiveThisMode && addressedGuest == null) {
      // 1:1 only. Group per-speaker stamp lives in the realism dance —
      // writing it here used the last loaded (full) member's vector, then
      // a soft turn skipped the dance and attached that leftover to the
      // guest bubble.

      // Short-term bond decay: 1:1 host only. In group mode the speaker isn't
      // picked yet — the old call here fell back to the FIRST member under
      // random turn order, so member #1 absorbed everyone's decay. The group
      // tick now lives per-speaker inside _evaluateRealismForUpcomingSpeaker,
      // on the pinned speaker's own cadence counter (mirrors needs + nsfw).
      if (_activeGroup == null) {
        _applyMoodDecay();
      }
      // Wear waits until the clock commits, after this reply. A send is
      // not a unit of time.
      // Clock off: the reply's refractory quarter hour, 1:1 host only. In a
      // group the speaker isn't picked yet (ticking here hit whichever
      // member was still loaded); theirs runs in
      // _evaluateRealismForUpcomingSpeaker once their scalars load. Clock on,
      // the beat's own minutes tick after the clock instead.
      if (_activeGroup == null) {
        _tickRefractoryPerReply();
      }

      // Single-path bridge: realism evaluation now runs inside _generateResponse
      // for EVERY speaker (1:1 host or group member) via
      // _evaluateRealismForUpcomingSpeaker.
      //
      // No cast-store mirror for the 1:1 host: its scalar fields are already the
      // canonical realism store (loaded by loadSession, decayed just above), and the
      // per-character _groupRealism map is group-only — its writes no-op when
      // _activeGroup == null. Mirroring was a no-op, and the eval path deliberately
      // does NOT reload the host from that empty map (doing so reset
      // bond/trust/emotion/needs to defaults). See _evaluateRealismForUpcomingSpeaker.
      if (_activeGroup == null && _activeCharacter != null) {
        // Run the SINGLE eval path for the host now — on a user turn only.
        // (Regen of a reply and Continue bypass this. Generate reply on a
        // trailing user message rewinds to the stamp first, then re-enters
        // here. Each caller checks cancellation before generating.)
        await _evaluateRealismForUpcomingSpeaker(_activeCharacter!);
      }
    } else if (_clockRunning && addressedGuest == null) {
      // PoT is on and the engine did not run this turn. Stamp the user
      // turn's story day so RAG can ground retrieved lines. The post-reply
      // decide still lives in _finalizeGenerationTurn.
      if (_messages.isNotEmpty) {
        final last = _messages.last;
        if (last.isUser) {
          last.metadata = {
            ...?last.metadata,
            'story_day': _timeService.dayCount,
          };
        }
      }
      await _saveChat();
      notifyListeners();
    }
  }

  /// Run the Scene Guest director's chime-in gate after a finalized primary/host
  /// turn: it decides which present guest(s) (if any) speak next, each via the
  /// parity-safe [generateGuestTurn]. Shared by the normal send path and the
  /// "regenerate the main character beneath a guest reply" path so the re-chime
  /// decision (mention / relevance) is byte-for-byte identical in both.
  ///
  /// No-op in group chats, mid-generation, during entrances, or with no guests
  /// present. Each gate eval + guest turn is a slow LLM call, so it bails if the
  /// user switches chats / the scene changes (so guests never speak into the
  /// wrong conversation).
  Future<void> _maybeRunSceneGuestChimeIns({
    required String userText,
    CharacterCard? exclude,
  }) async {
    if (_activeGroup != null ||
        _sceneGuest.cards.isEmpty ||
        _isTurnBusy ||
        _entrancesInFlight) {
      return;
    }
    final primaryResponse = _messages.isNotEmpty && !_messages.last.isUser
        ? _messages.last.displayText
        : '';
    final token = _currentSessionId;
    await _ensureSceneGuestDirector().runChimeIns(
      userText: userText,
      primaryResponse: primaryResponse,
      isContextValid: () => !_sceneChanged(token) && _activeGroup == null,
      exclude: exclude,
    );
  }

  /// Send a director note — appears as a bracketed instruction in the prompt
  /// but is not part of the in-story dialogue.
  Future<void> sendDirectorNote(String text) async {
    if (_activeGroup == null || text.trim().isEmpty) return;

    _messages.add(
      ChatMessage(
        text: text,
        sender: 'Director',
        isUser: true,
        characterId: '__director__',
      ),
    );
    await _saveChat();
    notifyListeners();

    _lorebookScanner.scanLatest();
    // Note: depth decrement happens after AI response completes inside _generateResponse.
    // Director-triggered lore is visible for the current generate.

    await _generateResponse(GenerationMode.normal);
  }

  /// The dream PRODUCER — fired from the post-generation phase, after the
  /// post-reply clock decide, so a night crossed in this beat is visible
  /// before the next send shows the dream.
  /// Same detection (checkRollover/pending/clear untouched — the dedicated
  /// unit suite drives those APIs directly), same owner rule (the last
  /// assistant speaker ended the day; ONE rule for 1:1 and group), same
  /// fragment sources — only the WHEN moved: the model call runs in the
  /// background here and parks its future; the next sendMessage inserts the
  /// finished text (see the consumer above). A failure skips silently,
  /// exactly as the blocking version did.
  ///
  /// Deliberately synchronous: everything through parkPrefetch runs before
  /// this method returns, so by the time the post-generation phase moves on
  /// the park EXISTS — a user firing the next message instantly can never
  /// beat it and lose the dream. Only the slow work (journal read + model
  /// call) lives inside the parked future.
  void _maybeKickDreamPrefetch() {
    _dreamService.checkRollover(
      sessionId: _currentSessionId,
      dayCount: _timeService.dayCount,
    );
    if (!_dreamService.pending || _currentSessionId == null) return;
    _dreamService.clear();
    String? lastCharId;
    var lastSpeakerFound = false;
    for (final m in _messages.reversed) {
      if (!m.isUser &&
          m.sender != 'System' &&
          m.activeMetadata?['is_dream'] != true) {
        lastCharId = m.characterId;
        lastSpeakerFound = true;
        break;
      }
    }
    final ownerCard = !lastSpeakerFound
        ? null
        : lastCharId == null
        ? _activeCharacter
        : (_groupCharacters
                  .where((c) => _getCharacterIdFromCard(c) == lastCharId)
                  .firstOrNull ??
              _activeCharacter);
    if (ownerCard == null) return;
    final ownerId = _getCharacterIdFromCard(ownerCard);
    final sessionId = _currentSessionId!;
    // Inputs sampled NOW, at the end of the day being dreamed about — if
    // anything more faithful than the old next-morning sample.
    final fixation = _relationshipService.activeFixation;
    final emotion = _characterEmotion;
    final recap = _summary.length > 300 ? _summary.substring(0, 300) : _summary;
    final weatherLine = switch (currentWeather) {
      null => null,
      final w => WeatherEngine.prose(
        w,
        seasonLabels: activeChatBiome.seasonLabels,
      ),
    };
    Future<String?> generate() async {
      try {
        final cards = await _journalStore.cardsFor(sessionId, ownerId);
        final sorted = [...cards]
          ..sort(
            (a, b) => JournalPhysics.cooledHeat(
              b,
            ).compareTo(JournalPhysics.cooledHeat(a)),
          );
        return await _dreamService.generateDream(
          characterName: ownerCard.name,
          memoryFragments: [for (final c in sorted.take(5)) c.content],
          fixation: fixation,
          emotion: emotion,
          recap: recap,
          weatherLine: weatherLine,
          ambitions: ownerCard.frontPorchExtensions?.ambitions ?? const [],
        );
      } catch (e) {
        debugPrint('[Dreams] prefetch skipped: $e');
        return null;
      }
    }

    _dreamService.parkPrefetch(
      sessionId: sessionId,
      ownerName: ownerCard.name,
      ownerId: ownerId,
      ownerCharacterId: lastCharId,
      dream: generate(),
    );
  }

  /// Record where 1:1 realism stood before [userMsg] was first scored. A
  /// later re-score (Generate reply after a rewind) keeps the first record.
  /// Mutated in place: a user bubble's swipeMetadata[0] aliases [metadata].
  void _stampUserTurnBaseline(ChatMessage userMsg) {
    if (!userMsg.isUser) return;
    if (!_realismActiveThisMode && !_needsActive) return;
    final meta = userMsg.metadata ??= <String, dynamic>{};
    if (meta[kRealismPreTurn] is Map) return;
    meta[kRealismPreTurn] = _captureRealismState(
      preTurn: Map<String, int>.from(_needsSimulation.vector),
    );
  }

  /// Group twin of [_stampUserTurnBaseline], per speaker. Runs inside the
  /// dance before decay, while [charId] is impersonated. Every member who
  /// scores the latest user line is stamped on it — an auto-advance or Next
  /// responder too, or deleting both replies would re-score that one twice.
  void _stampGroupUserTurnBaseline(String charId) {
    final i = _messages.lastIndexWhere((m) => m.isUser);
    if (i < 0) return;
    final meta = _messages[i].metadata ??= <String, dynamic>{};
    final raw = meta[kRealismPreTurnBySpeaker];
    final bySpeaker = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    if (bySpeaker[charId] is Map) return;
    _loadGroupRealismIntoScalars(charId);
    bySpeaker[charId] = _captureRealismState(
      preTurn: Map<String, int>.from(_needsSimulation.vector),
    );
    meta[kRealismPreTurnBySpeaker] = bySpeaker;
  }

  /// Generate reply on a trailing user message (reply deleted, cancelled,
  /// failed, or a fork at the user line). The turn's score rode the lost
  /// reply, so rewind to the user message's stamp and score it again, the
  /// same way a send does. Same input, same deltas — never stacked (#339).
  Future<void> _generateFromTrailingUserTurn({
    String? webQuery,
    String? wikiQuery,
  }) async {
    final userMsg = _messages.last;
    final baseAt = _messages.length;
    _rewindToUserTurnBaseline(userMsg);
    // Group scores inside _generateResponse's dance for the picked speaker.
    // A group line from before stamps has nothing to rewind to, so it keeps
    // the old no-dance retry rather than stacking on a still-scored member.
    final groupLegacy =
        _activeGroup != null &&
        userMsg.metadata?[kRealismPreTurnBySpeaker] is! Map;
    var cancelled = false;
    if (_activeGroup == null) {
      await _scoreUserTurnBeforeReply(userMsg: userMsg);
      cancelled = _realismEvalCancelled;
      if (cancelled) {
        // Quests the cancelled score proposed have no reply to ride on.
        await _revertObjectiveTurnOps(
          ChatMessage(
            text: '',
            sender: '',
            isUser: false,
            metadata: _pendingRealismMetadata,
          ),
        );
        _needsSimulation.consumePendingCatastrophe();
        _pendingRealismMetadata = null;
        _realismEvalCancelled = false;
      }
    } else {
      // Send pulses before generating (and honours @Name of an Away
      // member); directUserSend below then skips the in-turn pulse.
      await _runAwayPulse(userText: userMsg.promptText, fromUserSend: true);
    }
    if (!cancelled) {
      _armForcedLookup(webQuery: webQuery, wikiQuery: wikiQuery);
      await _generateResponse(
        GenerationMode.normal,
        directUserSend: true,
        skipSpeakerEval: groupLegacy,
      );
    }
    // Cancelled or failed with no reply: leave the line unscored, as it was
    // before the tap, 1:1 and group alike. A kept partial reply is answered.
    final answered = _messages
        .skip(baseAt)
        .any((m) => !m.isUser && m.sender != 'System' && m.text.isNotEmpty);
    if (!answered) {
      _rewindToUserTurnBaseline(userMsg);
      await _saveChat();
      notifyListeners();
    }
  }

  void _rewindToUserTurnBaseline(ChatMessage userMsg) {
    final meta = userMsg.metadata;
    if (_activeGroup == null) {
      final stamp = meta?[kRealismPreTurn];
      if (stamp is Map) {
        _restoreRealismStateFromMessage(_realismStampCarrier(stamp));
      } else {
        _rewindRelationshipToLastAcceptedReply();
      }
      return;
    }
    final bySpeaker = meta?[kRealismPreTurnBySpeaker];
    if (bySpeaker is! Map) return;
    for (final entry in bySpeaker.entries) {
      final sid = entry.key;
      final stamp = entry.value;
      if (sid is! String || stamp is! Map) continue;
      if (!_groupCharacters.any((c) => _getCharacterIdFromCard(c) == sid)) {
        continue;
      }
      _loadGroupRealismIntoScalars(sid);
      _restoreRealismStateFromMessage(
        _realismStampCarrier(stamp),
        groupSpeakerId: sid,
      );
      _saveScalarsIntoGroupRealism(sid);
      // The save skips an empty mood; a first-turn member had none.
      _memberForWrite(sid)
        ..emotion = stamp['characterEmotion'] as String? ?? ''
        ..emotionIntensity = stamp['emotionIntensity'] as String? ?? '';
    }
  }

  /// Stamp-less 1:1 user line (sent before stamps existed): rewind only the
  /// scored registers to the last accepted reply. Needs and pockets were
  /// already refunded by the delete that left this line trailing.
  bool _rewindRelationshipToLastAcceptedReply() {
    for (var i = _messages.length - 2; i >= 0; i--) {
      final m = _messages[i];
      if (m.isUser || m.sender == 'System') continue;
      final state = m.activeMetadata?['realism_state'];
      if (state is! Map) continue;
      _restoreScoredRegisters(Map<String, dynamic>.from(state));
      return true;
    }
    return false;
  }

  /// Bond/trust/feelings, mood and arousal from one realism stamp.
  void _restoreScoredRegisters(Map<String, dynamic> s) {
    _relationshipService.restoreFromMessageState(s);
    _characterEmotion = s['characterEmotion'] as String? ?? _characterEmotion;
    _emotionIntensity = s['emotionIntensity'] as String? ?? _emotionIntensity;
    _nsfwService.restoreNsfwFromRealismState(s);
  }

  ChatMessage _realismStampCarrier(Map stamp) => ChatMessage(
    text: '',
    sender: '',
    isUser: false,
    metadata: {'realism_state': Map<String, dynamic>.from(stamp)},
  );
}
