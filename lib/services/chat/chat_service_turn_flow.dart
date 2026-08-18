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

/// Turn-progression surfaces that sit outside the [ChatServiceSend] spine:
/// Director/observer/auto-play controls, group speaker picking, TTS-paced
/// auto-play, the web/mobile Chance Time reveal surface, the Journal recap
/// controls, background RAG embedding, and the periodic (cast-detection)
/// eval coordinator. Extracted verbatim from `chat_service.dart` — zero
/// behaviour change.
extension ChatServiceTurnFlow on ChatService {
  /// Set observer mode on/off.
  void setObserverMode(bool value) {
    _observerMode = value;
    if (!value) {
      _autoPlayActive = false;
    }
    notifyListeners();
  }

  /// Start auto-play: characters keep chatting automatically.
  void startAutoPlay() {
    if (_activeGroup == null || !_observerMode) return;
    _autoPlayActive = true;
    notifyListeners();
    _autoPlayNext();
  }

  /// Stop auto-play.
  void stopAutoPlay() {
    _autoPlayActive = false;
    notifyListeners();
  }

  /// Internal: trigger the next auto-play response.
  Future<void> _autoPlayNext() async {
    if (!_autoPlayActive || !_observerMode || _activeGroup == null) return;
    // Both auto-play schedulers (generation.dart and _waitForTtsThenContinue)
    // arm their delay AFTER the awaited post-gen section has already finished,
    // so this is clear by the time they fire; no re-arm machinery is needed.
    if (_isTurnBusy) return; // wait for the current turn to finish settling

    if (_clockRunning) {
      await _realismEvals.evaluatePhysicalStateCall(timeOnly: true);
    }
    // Already ticked above. Skip and speak must not tick again.
    await _generateResponse(GenerationMode.normal, skipClockAdvance: true);
  }

  /// Trigger the next character to speak in group mode.
  Future<void> triggerNextCharacter() async {
    if (_activeGroup == null || _groupCharacters.isEmpty || _isTurnBusy) {
      return;
    }
    // Story time is chat-scoped: Send already advanced it for this user
    // turn. A follow-up speaker (Next Character and /speak) must not tick
    // again. Explicit flag — not a TimeService latch — so regen / unit
    // tests / Director auto-play keep their own advance.
    await _generateResponse(GenerationMode.normal, skipClockAdvance: true);
  }

  /// Manually select which character speaks next in group mode.
  /// Delegated to GroupTurnManager.
  void setNextCharacter(CharacterCard character) {
    _groupManager?.setNextSpeaker(character);
    notifyListeners(); // ensure UI updates even if manager didn't notify

    // In group mode, switch the active objectives to this character's personal ones.
    if (_activeGroup != null) {
      _loadObjectivesForCurrentSpeaker();
    }
  }

  /// Pick which character speaks next based on turn order.
  /// A _forcedNextSpeakerId (set by manual user choice) is consumed first
  /// and works for both TurnOrder.random and roundRobin. After consumption
  /// we resume normal cycling / random behavior.
  CharacterCard _pickNextGroupCharacter() {
    if (_groupManager == null) {
      throw StateError('No active group');
    }
    return _groupManager!.pickNextSpeaker();
  }

  /// At work (and Away when we know they are not in scene). 1:1 never skips.
  bool _groupSpeakerSkips(CharacterCard card) {
    if (_activeGroup == null) return false;
    final ext = card.frontPorchExtensions;
    final library = originLibraryCardFor(card);
    final work = workFieldsForGroupMember(
      copyOccupation: ext?.occupation ?? '',
      copyHours: ext?.hours ?? '',
      libraryOccupation: library?.frontPorchExtensions?.occupation,
      libraryHours: library?.frontPorchExtensions?.hours,
    );
    final where = derivePresence(
      occupation: work.occupation,
      hours: work.hours,
      timeOfDay: _timeService.timeOfDay,
      inScene: _memberInScene(card),
    );
    return groupTurnSkips(where);
  }

  /// Skip path only. 1:1 never skips (caller returns false first).
  /// Group: recent line, or stance that does not say they left.
  bool _memberInScene(CharacterCard card) {
    if (_activeGroup == null) return true;
    var seen = 0;
    for (final m in _messages.reversed) {
      if (m.isUser) continue;
      if (m.sender == card.name) return true;
      if (++seen >= 8) break;
    }
    final id = _getCharacterIdFromCard(card);
    final stance = _groupRealism[id]?.spatialStance ?? '';
    return !stanceSaysAway(stance);
  }


  /// Wait for TTS to finish speaking, then apply the configured delay before auto-play.
  void _waitForTtsThenContinue() {
    if (!(_groupManager?.autoPlayActive ?? false) ||
        !(_groupManager?.observerMode ?? false)) {
      return;
    }

    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!(_groupManager?.autoPlayActive ?? false) ||
          !(_groupManager?.observerMode ?? false)) {
        timer.cancel();
        return;
      }
      if (_ttsService == null || !_ttsService!.isSpeaking) {
        timer.cancel();
        final delayMs = ((_groupManager?.directorDelaySec ?? 15.0) * 1000)
            .round();
        Future.delayed(Duration(milliseconds: delayMs), () {
          if ((_groupManager?.autoPlayActive ?? false) && !_isGenerating) {
            _autoPlayNext();
          }
        });
      }
    });
  }

  /// True when auto-trigger fires. UI reads then calls consumeChanceTimeTrigger().
  bool get chanceTimePendingTrigger => _chanceTimePendingTrigger;

  /// True when a chaos event is queued for the next response (blocks manual spin + auto-trigger).
  bool get hasPendingChaosEvent => _chaosModeService.hasPendingChaosEvent;

  /// Called by the overlay once it has opened. Clears the auto-trigger flag.
  void consumeChanceTimeTrigger() => _chanceTimePendingTrigger = false;

  // ── Web/mobile Chance Time surface ──────────────────────────────────────
  // The desktop pops its wheel from the one-shot [chanceTimePendingTrigger] via
  // a ChangeNotifier. Web clients (which drive the same shared ChatService over
  // HTTP/WS) have no such hook and no spinning wheel, so they observe the park
  // through these accessors and resolve it with [acceptPendingChanceTime]. All
  // of this is UI-coordination glue for the completer above — the simulation is
  // untouched, so 1:1/group parity is unaffected.

  /// True from the moment a Chance Time parks [sendMessage] until it is
  /// accepted. The durable signal the web surface uses to show — and, after a
  /// phone wakes and reconnects, re-show — the reveal modal.
  bool get isAwaitingChanceTime =>
      _chanceTimeCompleter != null && !_chanceTimeCompleter!.isCompleted;

  /// The speaker a Chance Time event is attributed to: the upcoming group
  /// speaker, else the 1:1 host. Shared by the desktop wheel overlay and the
  /// web accept path so both attribute the event identically.
  String get chanceTimeSpeakerName =>
      nextCharacter?.name ?? activeCharacter?.name ?? 'Character';

  /// The pre-picked pending event with `{{char}}` resolved, for the web reveal
  /// modal. Null when nothing is parked.
  String? get webChanceTimeDisplay =>
      _webChanceTimeEvent?.replaceAll('{{char}}', chanceTimeSpeakerName);

  /// Web/mobile "Accept Your Fate": applies the pre-picked pending event using
  /// the same attribution the desktop wheel uses, then lets generation resume.
  /// No-op if nothing is parked (e.g. the desktop already accepted).
  Future<void> acceptPendingChanceTime() async {
    final raw = _webChanceTimeEvent;
    if (raw == null) return;
    await applyChanceTimeResult(raw, chanceTimeSpeakerName);
  }

  // ── The Journal recap ("Where we are") ──────────────────────────────
  // The recap reuses the _summary scalar + Sessions.summary persistence the
  // old summary system used, so the public surface below (sidebar, web
  // facade, the growth pass's getRecap cb) is unchanged. The generator is
  // the Journal maintenance pass (journal_maintenance leaf), which also
  // produces the per-character memory cards in the same LLM call.

  /// Manually set the recap text.
  void setSummary(String text) {
    _summary = text;
    _saveChat();
    notifyListeners();
  }

  /// Pause or resume the automatic Journal maintenance pass.
  void setSummaryPaused(bool paused) {
    _summaryPaused = paused;
    notifyListeners();
  }

  /// Force an immediate Journal maintenance pass (cards + recap), bypassing
  /// the interval. Backs the sidebar/web "Regenerate" button (name kept for
  /// the existing public surface).
  Future<void> forceSummaryUpdate() async {
    if (_isSummaryGenerating) return;
    await _awaitHistoryHydrated();
    await _journalMaintenance.runMaintenancePass(force: true);
  }

  // _maybeRunPromiseDebtPass lives in chat_service_objectives.dart (the
  // commitment-tracking part).

  /// Check if a Journal maintenance pass is due and trigger it non-blockingly.
  /// Cadence (design §4.2): user messages since the _summaryLastIndex cursor
  /// vs the journalInterval setting, PLUS an immediate pass when the window
  /// holds a significant engine-stamped event (big bond/trust swing, trust
  /// repair, Chance Time) or an objective completed (the eventKickPending
  /// flag, set pre-generation, consumed here post-generation so the pass
  /// never competes with the main LLM call). Guards mirror the old summary
  /// coordinator.
  void _maybeRunJournalPass() {
    if (!_storageService.memorySettings.journalEnabled) return;
    if (_summaryPaused) return;
    if (_isSummaryGenerating) return;
    if (_llmProvider == null) return;

    // Cursor is an index into the FULL transcript. Wait for the
    // background backfill so we don't clamp 11200 down to 24.
    unawaited(() async {
      await _awaitHistoryHydrated();
      if (!_storageService.memorySettings.journalEnabled) return;
      if (_summaryPaused || _isSummaryGenerating) return;
      final windowStart = _summaryLastIndex.clamp(0, _messages.length);
      var userMessagesSincePass = 0;
      for (var i = windowStart; i < _messages.length; i++) {
        if (_messages[i].isUser) userMessagesSincePass++;
      }
      if (userMessagesSincePass == 0) return;
      final due = userMessagesSincePass >=
          _storageService.memorySettings.journalInterval;
      final eventKick = _journalMaintenance.eventKickPending ||
          JournalPhysics.hasSalientEvent(_messages.sublist(windowStart));
      if (due || eventKick) {
        _journalMaintenance.runMaintenancePass();
      }
    }());
  }

  /// Embed message windows for RAG memory retrieval (fire-and-forget).
  /// Called after each generation completes. Only embeds new windows that
  /// haven't been embedded yet.
  /// Embed the recent message window for RAG memory (fire-and-forget).
  ///
  /// Normally keyed on the active character (or group bucket). Scene Guests
  /// Phase 4 passes [characterIdOverride] = the guest's id so the just-finished
  /// guest exchange is stored under the GUEST's own id — the same id the guest
  /// retrieves under in [_getMemorySourceIds] — giving guests episodic memory
  /// without touching the host's embeddings.
  void _maybeEmbedMessages({String? characterIdOverride}) {
    if (_memoryService == null || !_storageService.memorySettings.ragEnabled) {
      return;
    }
    if (_currentSessionId == null) return;
    if (_messages.length < _storageService.memorySettings.ragWindowSize) return;

    final characterId = characterIdOverride ?? _getCharacterId();

    // One formatter shared with import backfill (fpchat) so the corpus text
    // is identical whether a window was first written live or after reimport.
    final formatted = _formatMessagesForRagEmbedding(_messages);

    debugPrint(
      '[RAG:Chat] ▶ Triggering background embedding (session: $_currentSessionId, char: $characterId, ${formatted.length} msgs)',
    );

    // Fire and forget — don't await
    _memoryService!.embedMessageWindow(
      sessionId: _currentSessionId!,
      characterId: characterId,
      formattedMessages: formatted,
      totalMessageCount: _messages.length,
    );
  }

  /// Canonical RAG message lines for [MemoryService.embedMessageWindow].
  /// Live post-gen and post-import backfill MUST use this exact shape —
  /// dedup is positional only, so a second formatter permanently splits the
  /// corpus wording for the same session.
  List<String> _formatMessagesForRagEmbedding(List<ChatMessage> messages) {
    return messages.map((m) {
      if (m.characterId == '__director__') {
        return '[Director: ${m.text}]';
      }
      return '${m.sender}: ${m.text}';
    }).toList();
  }

  /// Coordinator for the periodic background evals (now just Scene Guest cast
  /// detection). User-fact extraction and chat summaries were replaced by the
  /// Journal maintenance pass (_maybeRunJournalPass); character evolution was
  /// replaced by the growth pass (_maybeRunGrowthPass in
  /// chat_service_growth.dart), which has its own cursor-based cadence.
  void _maybeRunPeriodicEvals() {
    // Scene Guest cast detection (1:1 only). Runs on its own cadence and
    // fires-and-forget so it never blocks the turn. See _maybeRunCastDetection.
    _maybeRunCastDetection();
  }

  /// Cadence + trigger for Scene Guest cast detection (1:1 only). Advances the
  /// dedicated counter on each primary turn and, on the interval, runs the
  /// detector fire-and-forget. A non-null result is surfaced as a pending popup
  /// (Chance-Time-style flag + notifyListeners). Never offers while one is
  /// already pending. The detector itself filters out the host/user/existing
  /// guests/already-offered names. Does ZERO Realism/Needs work.
  void _maybeRunCastDetection() {
    // The one gate, and it is the AUTOMATIC path only. `/scan` deliberately
    // still works with this off: the complaint this switch answers is being
    // interrupted by offers nobody asked for, and typing `/scan` is asking.
    if (!_storageService.realismSettings.sceneGuestDetectionEnabled) return;
    if (_activeGroup != null) return; // 1:1 only by design
    if (_activeCharacter == null) return;
    if (_sceneGuest.pendingDetection != null) return; // one offer at a time

    _sceneGuest.turnsSinceCastScan++;
    if (_sceneGuest.turnsSinceCastScan < _castScanInterval) return;
    _sceneGuest.turnsSinceCastScan = 0;

    // Fire-and-forget: never block the turn on the eval.
    _performCastScan();
  }

  /// Force an immediate cast-detection scan, bypassing the per-turn cadence.
  /// Backs the manual `/scan` command, so a recurring side character can be
  /// surfaced on demand — including in an already-loaded chat whose cadence
  /// counter reset on load. Returns true when a candidate was found and the
  /// offer popup was raised. Resets the cadence counter so the automatic scan
  /// won't immediately re-fire on the next turn.
  Future<bool> runCastDetectionNow() async {
    if (_activeGroup != null || _activeCharacter == null) return false;
    if (_sceneGuest.pendingDetection != null) return false;
    _sceneGuest.turnsSinceCastScan = 0;
    // Re-resolve first so any guest whose library card was deleted is pruned
    // from the scene list — otherwise the detector still treats them as "already
    // a scene guest" and silently rejects re-detecting them (the exact symptom
    // of deleting a guest's card then /scan-ning for them again).
    await _resolveSceneGuestCards();
    // A manual scan is an explicit "look again", so forget prior in-session
    // dismissals/offers — otherwise a character you ignored (or added then
    // deleted) can never be re-surfaced without starting a fresh chat. Names
    // still genuinely in the scene are excluded by the live scene-guest filter.
    _sceneGuest.offeredOrIgnoredNames.clear();
    final detected = await _performCastScan();
    return detected != null;
  }

  /// Run one detection pass and, on a fresh hit, raise the offer popup (set the
  /// pending flag + notify). Shared by the automatic per-turn path and the
  /// manual `/scan` command so there is exactly ONE detect→surface path.
  /// Returns the surfaced candidate, or null when nothing was found.
  Future<DetectedCharacter?> _performCastScan() async {
    final token = _currentSessionId; // the scan is slow; the chat may switch
    final detected = await _ensureCastDetector().detect();
    if (detected == null) return null;
    // Bail if the chat/character/session changed (or we were disposed) during
    // the eval — otherwise a character detected from chat A's narration would
    // pop as an offer inside chat B and get minted into B's scene.
    if (_sceneChanged(token) || _activeGroup != null) return null;
    if (_sceneGuest.pendingDetection != null) return null;
    // Mark as offered immediately so a later scan won't re-propose it even if
    // the user leaves the popup open.
    _sceneGuest.offeredOrIgnoredNames.add(detected.name.trim().toLowerCase());
    _sceneGuest.pendingDetection = detected;
    notifyListeners();
    return detected;
  }
}
