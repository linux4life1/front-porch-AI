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

/// True while [sendMessage] is holding a typed line behind post-gen evals.
/// The composer already cleared; the bubble is not in the list yet.
bool _sendWaitingOnSettle = false;

/// Small streaming / turn-busy accessors (zero behaviour change).
extension ChatServiceGenerationStreamAccessors on ChatService {
  /// The honest "this turn is still in motion" predicate — what the mutation
  /// guards should ask, rather than `_isGenerating` alone.
  ///
  /// NOT for the escape hatches: `stopGeneration` and
  /// `_cancelAndWaitForGeneration` must keep testing `_isGenerating` on its
  /// own. The first aborts an in-flight HTTP stream (there is none during
  /// post-gen), and the second SPINS until the flag clears — broadening it
  /// would hang the caller if post-gen ever failed to settle.
  bool get _isTurnBusy =>
      _isGenerating ||
      _isPostGenerating ||
      isImporting ||
      _narrating ||
      _skipAsked;

  void _notifyStreamListeners() {
    if (_streamNotifyTimer != null) return; // trailing notify already queued
    final elapsed = DateTime.now().difference(_lastStreamNotify);
    if (elapsed >= kStreamNotifyInterval) {
      _notifyStreamTick();
    } else {
      _streamNotifyTimer = Timer(kStreamNotifyInterval - elapsed, () {
        _streamNotifyTimer = null;
        _notifyStreamTick();
      });
    }
  }

  void _notifyStreamTick() {
    _lastStreamNotify = DateTime.now();
    StreamTickNotify.run(notifyListeners);
  }

  void _cancelStreamNotifyThrottle() {
    _streamNotifyTimer?.cancel();
    _streamNotifyTimer = null;
  }

  /// External consumers (the web server's StreamHub) listen to this for
  /// real-time token streaming.
  Stream<String> get tokenStream => _tokenBroadcast.stream;

  /// Emits complete sentences as they're detected during LLM token streaming.
  /// Used by call mode to start TTS on the first sentence immediately.
  Stream<String> get sentenceStream => _sentenceBroadcast.stream;
  // (callMode moved onto the class shell — fake-pinned for the call overlay
  // widget tests, and its setter now owns the call-model swap release.)

  /// True while the turn's awaited post-generation work is still settling.
  /// Exposed so tests can assert the window opens and — more importantly —
  /// always closes. See [_isPostGenerating].
  bool get isSettlingTurn => _isPostGenerating;

  /// Typed send is queued behind post-gen evals. Composer is empty; no bubble
  /// yet. UI shows a holding banner so the wait does not look like a lost send.
  bool get isSendWaitingOnSettle => _sendWaitingOnSettle;

  // ── Round-4b forwarder body (see chat_service_accessors.dart's banner
  // comment for why this stays a one-line forwarder on the class body) ──
  double get _tokensPerSecondImpl {
    if (_tokenTimestamps.length < 2) return 0.0;
    // Use rolling window: tokens in the last 3 seconds
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(seconds: 3));
    final recent = _tokenTimestamps.where((t) => t.isAfter(cutoff)).length;
    if (recent < 2) {
      // Fallback to overall average
      if (_generationStartTime == null || _tokensGenerated == 0) return 0.0;
      final elapsed =
          now.difference(_generationStartTime!).inMilliseconds / 1000.0;
      return elapsed > 0 ? _tokensGenerated / elapsed : 0.0;
    }
    final windowStart = _tokenTimestamps.where((t) => t.isAfter(cutoff)).first;
    final windowElapsed = now.difference(windowStart).inMilliseconds / 1000.0;
    return windowElapsed > 0 ? recent / windowElapsed : 0.0;
  }
}

/// The "Did time pass?" gate a send parks on, and the pre-reply goal check
/// sendMessage awaits (WP10c).
extension ChatServiceSendGates on ChatService {
  /// The "Did time pass?" question the send is waiting on, or null. The
  /// desktop dialog and the web sheet show it while it is non-null.
  PendingSkip? get pendingSkip => _skipGate.pending;

  /// A send is parked on [pendingSkip]: it owns the turn, so no other send,
  /// regen, swipe, Continue or delete starts until it is answered.
  bool get _skipAsked => _skipGate.pending != null;

  /// The player's answer to [pendingSkip]: a skip, [SkipVerdict.none] for
  /// "no skip", or null to keep the reader's guess.
  void answerSkip(SkipVerdict? verdict) {
    if (_skipGate.answer(verdict)) notifyListeners();
  }

  /// Whether a web client is connected to answer [pendingSkip].
  set skipConfirmWebAsker(bool Function() connected) =>
      _skipWebAsker = connected;

  /// Puts a shaky skip reading to whoever is at a chat screen. Null at once
  /// in a voice call or with nobody there (pick E: Director auto-chat and
  /// AFK never send through here anyway), so the guess applies. A chat
  /// change under the question cancels it.
  Future<SkipVerdict?> _askSkip(PendingSkip question, String? token) async {
    if (_callMode || (_chatScreens == 0 && !_skipWebAsker())) return null;
    final answer = _skipGate.ask(question);
    notifyListeners();
    void onChange() {
      if (_sceneChanged(token) && _skipGate.cancel()) notifyListeners();
    }

    addListener(onChange);
    try {
      return await answer;
    } finally {
      removeListener(onChange);
    }
  }

  /// The pre-reply goal check. Send runs it; Continue and Regen do not
  /// (objective_check_gate_test reads this name in the send part).
  Future<void> _maybeCheckTaskCompletionSync() =>
      objectivesDoor.completion.maybeCheckSync();
}

/// The Realism graph's state and objects under the names the rest of this
/// library still uses. Each line is debt its caller's package retires by
/// calling [ChatService.realism] itself (WP10a to WP10c).
extension _ChatServiceRealismNames on ChatService {
  // State the graph owns.
  bool get _realismEvalCancelled => realism.evalStatus.cancelled;
  set _realismEvalCancelled(bool v) => realism.evalStatus.cancelled = v;
  Map<String, dynamic>? get _pendingRealismMetadata =>
      realism.registers.pending;
  set _pendingRealismMetadata(Map<String, dynamic>? v) =>
      realism.registers.pending = v;
  String get _characterEmotion => realism.registers.emotion;
  String get _emotionIntensity => realism.registers.intensity;
  set _isGrowthPassRunning(bool v) => realism.growthPassRunning = v;
  bool get _isEvaluatingRealism => realism.evalStatus.evaluating;
  set _isEvaluatingRealism(bool v) => realism.evalStatus.evaluating = v;
  bool get _isCancellingRealismEval => realism.evalStatus.cancelling;
  set _isCancellingRealismEval(bool v) => realism.evalStatus.cancelling = v;
  String get _realismEvalStreamText => realism.evalStatus.streamText;
  set _realismEvalStreamText(String v) => realism.evalStatus.streamText = v;
  Timer? get _evalChunkTimer => realism.evalStatus.chunkTimer;
  set _evalChunkTimer(Timer? t) => realism.evalStatus.chunkTimer = t;
  ChatPlaceSlots get _chatPlaceSlots => realism.places.slots;
  SceneMoveState get _sceneMoves => realism.places.sceneMoves;
  LorebookTimedEffects get _loreTimedEffects => realism.lore.timedEffects;
  ToolTransportProbe get _toolProbe => realism.transport.probe;
  FireToolEval get _fireToolEval => realism.transport.fireToolEval;

  // The leaves.
  LorebookScanner get _lorebookScanner => realism.lore.scanner;
  LorebookInjector get _lorebookInjector => realism.lore.injector;
  TimeService get _timeService => realism.time;
  StoryClockReader get _clockReader => realism.clockReader;
  StoryClockWriter get _clockWriter => realism.clockWriter;
  EpisodeCrumbMinter get _episodeCrumbs => realism.episodeCrumbs;
  BirthdaySync get _birthdaySync => realism.birthdays;
  ChaosModeService get _chaosModeService => realism.chaos;
  NsfwService get _nsfwService => realism.nsfw;
  NeedsSimulation get _needsSimulation => realism.needs;
  GroupRealismStore get _groupStore => realism.groups;
  Map<String, GroupMemberRealism> get _groupRealism => realism.groups.members;
  NeedsPass get _needsPass => realism.needsPass;
  StandingMood get _standingMood => realism.standingMood;
  MoodRegisters get _mood => realism.mood;
  RealismSnapshot get _realismSnapshot => realism.snapshot;
  RealismJudges get _realismJudges => realism.judges;
  RealismDance get _realismDance => realism.dance;
  RelationshipService get _relationshipService => realism.relationship;
  ExpressionService get _expressionService => realism.expression;
  AuthorNoteBuilder get _authorNoteBuilder => realism.authorNotes;
  InventoryInjection get _inventoryInjection => realism.inventoryInjection;
  PocketsLedger get _pocketsLedger => realism.pocketsLedger;
  PocketsRewinds get _pocketsRewinds => realism.pocketsRewinds;
  PocketsPass get _pocketsPass => realism.pocketsPass;
  ItemCardJournal get _itemCards => realism.itemCards;
  ReplyFacts get _replyFacts => realism.replyFacts;
  AfterglowPass get _afterglow => realism.afterglow;
  PromiseDebtService get _promiseDebtService => realism.promiseDebt;
  DreamService get _dreamService => realism.dreams;
  ChaosInjection get _chaosInjection => realism.chaosInjection;
  RealismStateInjection get _realismStateInjection =>
      realism.realismStateInjection;
  LlmEvalEngine get _llmEvalEngine => realism.llmEvalEngine;
  RealismEvals get _realismEvals => realism.evals;
  ObjectiveProposal get _objectiveProposal => realism.objectiveProposal;
  CastFeelingsJudge get _castFeelingsJudge => realism.castFeelingsJudge;
  JournalStore get _journalStore => realism.journalStore;
  PorchMemoryImportService get _porchMemoryImport => realism.porchImport;
  ToolSupportTester get _toolSupportTester => realism.toolSupportTester;
  JournalMaintenance get _journalMaintenance => realism.journalMaintenance;
  JournalInjection get _journalInjection => realism.journalInjection;
  GrowthStore get _growthStore => realism.growthStore;
  GrowthDesk get _growthDesk => realism.growthDesk;

  // Behaviour.
  RealismScope _realismScope() => realism.scope;
  bool get _realismActiveThisMode => realism.realismActiveThisMode;
  String get _evalBackendIdentity => realism.transport.backendIdentity;
  PlayerSkip _buildPlayerSkip() => realism.playerSkip();
  List<LoreEntryRef> _collectLoreRefs({bool? inheritOverride}) =>
      realism.lore.collectLoreRefs(inheritOverride: inheritOverride);
  void _restoreRealismStateForSpeaker(
    ChatMessage msg, {
    bool restoreClock = false,
  }) => realism.restores.forSpeaker(msg, restoreClock: restoreClock);
  void _restoreRealismStateFromMessage(
    ChatMessage? msg, {
    String? groupSpeakerId,
    bool restoreClock = false,
  }) => realism.restores.fromMessage(
    msg,
    groupSpeakerId: groupSpeakerId,
    restoreClock: restoreClock,
  );
  Future<void> _runPostGenNeedsChecks(String responseText) =>
      realism.restores.runPostGenNeedsChecks(responseText);
  void _applyMoodDecay() => realism.restores.applyMoodDecay();
}
