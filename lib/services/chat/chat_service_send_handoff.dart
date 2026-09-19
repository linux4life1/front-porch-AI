// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Decay, generate handoff, director note, guest chime-ins,
// and dream prefetch. sendMessage capture/guards stay on
// chat_service_send.dart. preTurnVector is captured before
// tickDecay. Continue does not tick — this is send only.

part of '../chat_service.dart';

extension ChatServiceSendHandoff on ChatService {
  /// Pre-turn needs capture, decay, generate, chips baseline, guest
  /// chime-ins, and vision caption. Called from [sendMessage] after
  /// chaos/call-model/task-completion. Capture stays first so
  /// [preTurnVector] is stamped before [NeedsSimulation.tickDecay].
  Future<void> _sendDecayAndGenerate({
    required CharacterCard? addressedGuest,
    required ChatMessage userMsg,
    required String? imagePath,
    required String? sessionToken,
  }) async {
    // Evaluate realism systems before generating response
    // Capture pre-turn needs vector (before decay + fulfillment) so that
    // regenerateLastMessage() and the post-generation delta computation
    // can use the same delta-revert mechanism the classic realism fields
    // (bond/trust/arousal) use.
    Map<String, int>? preTurnVector;
    if (_realismActiveThisMode && addressedGuest == null) {
      if (_needsSimEnabled && _needsSimulation.vector.isNotEmpty) {
        preTurnVector = Map<String, int>.from(_needsSimulation.vector);
        _pendingRealismMetadata ??= {};
        _pendingRealismMetadata!['needs_pre_turn_vector'] = preTurnVector;
      }

      // Short-term bond decay: 1:1 host only. In group mode the speaker isn't
      // picked yet — the old call here fell back to the FIRST member under
      // random turn order, so member #1 absorbed everyone's decay. The group
      // tick now lives per-speaker inside _evaluateRealismForUpcomingSpeaker,
      // on the pinned speaker's own cadence counter (mirrors needs + nsfw).
      if (_activeGroup == null) {
        _applyMoodDecay();
      }
      // Needs decay for 1:1 always here. For group non-observer, speaker-specific decay
      // (respecting the actual picked speaker for random turn order) is applied inside
      // _evaluateRealismForUpcomingSpeaker after _pickNextGroupCharacter has run.
      if (_activeGroup == null || _observerMode || !_needsSimEnabled) {
        _needsSimulation.tickDecay();
      } else {
        // Group non-obs + needs on: decay is applied per-speaker inside the
        // single eval path (_evaluateRealismForUpcomingSpeaker).
      }
      // Refractory tick for the 1:1 host only. In group mode the speaker
      // hasn't been picked yet — decrementing here mutated whichever member's
      // scalars were still loaded from LAST turn, and the tick was then
      // discarded by _loadGroupRealismIntoScalars, so group cooldowns never
      // actually counted down. The group tick now lives per-speaker in
      // _evaluateRealismForUpcomingSpeaker, right after that speaker's
      // scalars are loaded (mirroring the per-speaker needs decay).
      if (_activeGroup == null) {
        _nsfwService.decrementCooldownIfActive();
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
        // Run the SINGLE eval path for the host now — on a fresh user turn only.
        // (Regen/continue call _generateResponse directly, bypassing this, so the
        // host is not re-evaluated; cancellation is caught by the check below,
        // before generation — preserving the cancel-aborts-generation escape.)
        await _evaluateRealismForUpcomingSpeaker(_activeCharacter!);
      }
    } else if (_standaloneClockActive && addressedGuest == null) {
      // Standalone clock: announce the current time in the prompt; the
      // post-reply decide lives in _finalizeGenerationTurn with the engine
      // path (bucket brigade, Scene Guests included). Only stamp the user
      // turn's story day here so RAG can ground retrieved lines.
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

    // If cancellation was requested during realism evaluation, abort generation
    if (_realismEvalCancelled) {
      // The turn dies before the request phase can adopt the call-model
      // swap — put the main model back ourselves.
      _exitCallEvalModelSwap();
      await _saveChat();
      _realismEvalCancelled = false;
      notifyListeners();
      return;
    }

    if (addressedGuest != null) {
      await generateGuestTurn(addressedGuest);
    } else {
      if (_activeGroup != null) {
        await _runAwayPulse(userText: userMsg.promptText, fromUserSend: true);
      }
      // This is the sole web-search allow-list entry: a newly appended user
      // message receiving its first host/group response. Every follow-up,
      // guest, cast, regen, idle, and command generation keeps the default
      // false and therefore cannot advertise or reach search HTTP.
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
    // chips. preTurnVector is still stamped above as the message's baseline.

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
}
