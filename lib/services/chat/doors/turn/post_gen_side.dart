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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';

/// What a reply sets going after it lands, none of it awaited by the turn:
/// TTS-paced auto-play, the Journal maintenance pass, RAG embedding, and
/// the dream prefetch for a night the clock just crossed.
class PostGenSide {
  PostGenSide(this._e);

  final TurnEngine _e;

  TurnDeps get _d => _e.deps;
  ChatSessionState get _session => _d.session;
  TurnProgress get _p => _e.progress;
  RealismGraph get _g => _d.doors.graph();
  EntryDoor get _entry => _d.doors.entry();
  SessionStore get _sessions => _d.doors.sessions();
  StorageService get _storageService => _d.services.storage;
  LLMProvider? get _llmProvider => _d.services.llmProvider();
  TtsService? get _ttsService => _d.services.tts();
  MemoryService? get _memoryService => _d.services.memory();
  String _getCharacterIdFromCard(CharacterCard card) => _d.characterIdFor(card);
  String _getCharacterId() => _d.ragCharacterId();

  AutoChatBudget get _autoChatBudget => _entry.autoChat;
  Future<void> _autoPlayNext() => _entry.director.autoPlayNext();
  Future<void> _awaitHistoryHydrated() =>
      _sessions.window.awaitHistoryHydrated();
  String get _characterEmotion => _g.registers.emotion;
  DreamService get _dreamService => _g.dreams;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  SessionHistoryWindow get _history => _sessions.history;
  bool get _isSummaryGenerating => _sessions.isSummaryGenerating;
  JournalMaintenance get _journalMaintenance => _g.journalMaintenance;
  JournalStore get _journalStore => _g.journalStore;
  RelationshipService get _relationshipService => _g.relationship;
  String get _summary => _sessions.summary;
  int get _summaryLastIndex => _sessions.summaryLastIndex;
  bool get _summaryPaused => _sessions.summaryPaused;
  TimeService get _timeService => _g.time;

  /// Wait for TTS to finish speaking, then apply the configured delay before
  /// auto-play. [run] is the auto-chat run that armed the wait.
  void waitForTtsThenContinue(int run) {
    if (!(_session.groupManager?.autoPlayActive ?? false) ||
        !(_session.groupManager?.observerMode ?? false)) {
      return;
    }

    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!(_session.groupManager?.autoPlayActive ?? false) ||
          !(_session.groupManager?.observerMode ?? false)) {
        timer.cancel();
        return;
      }
      if (_ttsService == null || !_ttsService!.isSpeaking) {
        timer.cancel();
        final delayMs =
            ((_session.groupManager?.directorDelaySec ?? 15.0) * 1000).round();
        Future.delayed(Duration(milliseconds: delayMs), () {
          if ((_session.groupManager?.autoPlayActive ?? false) &&
              !_p.isGenerating &&
              _autoChatBudget.run == run) {
            _autoPlayNext();
          }
        });
      }
    });
  }

  /// Check if a Journal maintenance pass is due and trigger it non-blockingly.
  /// Cadence (design §4.2): user messages since the _summaryLastIndex cursor
  /// vs the journalInterval setting, PLUS an immediate pass when the window
  /// holds a significant engine-stamped event (big bond/trust swing, trust
  /// repair, Chance Time) or an objective completed (the eventKickPending
  /// flag, set pre-generation, consumed here post-generation so the pass
  /// never competes with the main LLM call). Guards mirror the old summary
  /// coordinator.
  void maybeRunJournalPass() {
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
      final windowStart = _summaryLastIndex.clamp(0, _session.messages.length);
      var userMessagesSincePass = 0;
      for (var i = windowStart; i < _session.messages.length; i++) {
        if (_session.messages[i].isUser) userMessagesSincePass++;
      }
      if (userMessagesSincePass == 0) return;
      final due =
          userMessagesSincePass >=
          _storageService.memorySettings.journalInterval;
      // Salient immediacy is ONLY eventKickPending, which already passed
      // GrowthDesk.requestSalienceKick. Reading the window again would bypass
      // the shared cooldown Growth already honors.
      if (due || _journalMaintenance.eventKickPending) {
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
  /// retrieves under in [RagSources.sourceIds] — giving guests episodic memory
  /// without touching the host's embeddings.
  void maybeEmbedMessages({String? characterIdOverride}) {
    if (_memoryService == null || !_storageService.memorySettings.ragEnabled) {
      return;
    }
    if (_session.currentSessionId == null) return;

    final sessionId = _session.currentSessionId!;
    final characterId = characterIdOverride ?? _getCharacterId();
    // Fire and forget — wait for the tail backfill first so we never store
    // a 24-row snapshot as positions 0..N (that permanently skips the real
    // start of a long chat, and stamps today's story-day on old lines).
    unawaited(() async {
      await _awaitHistoryHydrated();
      if (_session.currentSessionId != sessionId || _memoryService == null) {
        return;
      }
      if (_session.messages.length <
          _storageService.memorySettings.ragWindowSize) {
        return;
      }
      final formatted = formatForRagEmbedding(_session.messages);
      debugPrint(
        '[RAG:Chat] ▶ Triggering background embedding (session: $sessionId, '
        'char: $characterId, ${formatted.length} msgs, '
        'base=${_history.basePosition})',
      );
      await _memoryService!.embedMessageWindow(
        sessionId: sessionId,
        characterId: characterId,
        formattedMessages: formatted,
        totalMessageCount: formatted.length,
        positionOffset: _history.basePosition,
      );
    }());
  }

  /// Canonical RAG message lines for [MemoryService.embedMessageWindow].
  /// Live post-gen and post-import backfill MUST use this exact shape —
  /// dedup is positional only, so a second formatter permanently splits the
  /// corpus wording for the same session.
  List<String> formatForRagEmbedding(List<ChatMessage> messages) {
    return messages.map((m) {
      if (m.characterId == '__director__') {
        return m.toPromptHistoryLine(); // note or narration
      }
      return '${m.sender}: ${m.text}';
    }).toList();
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
  void maybeKickDreamPrefetch() {
    _dreamService.checkRollover(
      sessionId: _session.currentSessionId,
      dayCount: _timeService.dayCount,
    );
    if (!_dreamService.pending || _session.currentSessionId == null) return;
    _dreamService.clear();
    String? lastCharId;
    var lastSpeakerFound = false;
    for (final m in _session.messages.reversed) {
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
        ? _session.activeCharacter
        : (_groupCharacters
                  .where((c) => _getCharacterIdFromCard(c) == lastCharId)
                  .firstOrNull ??
              _session.activeCharacter);
    if (ownerCard == null) return;
    final ownerId = _getCharacterIdFromCard(ownerCard);
    final sessionId = _session.currentSessionId!;
    // Inputs sampled NOW, at the end of the day being dreamed about — if
    // anything more faithful than the old next-morning sample.
    final fixation = _relationshipService.activeFixation;
    final emotion = _characterEmotion;
    final recap = _summary.length > 300 ? _summary.substring(0, 300) : _summary;
    final weatherLine = switch (_g.weather.currentWeather) {
      null => null,
      final w => WeatherEngine.prose(
        w,
        seasonLabels: _g.weather.activeChatBiome.seasonLabels,
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
