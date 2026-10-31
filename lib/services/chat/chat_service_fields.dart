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

/// Runtime fields that are not fake-pinned (no `implements ChatService` double
/// overrides them). Test hooks ride here too — they are written on real
/// [ChatService] instances only.
/// Extensions in this library can still read them; a Dart extension cannot
/// *declare* instance state, so this mixin is the legal home.
mixin ChatServiceFieldBag {
  /// The database's word of every chat it deletes, for KoboldCpp's saved
  /// cache of it. Moves with the database, so it is re-made on a swap.
  StreamSubscription<String>? _deletedChats;

  /// The chat model's key in the eval identity, read from its file once per
  /// model and per engine load.
  final _modelKeys = LocalModelKeys();

  /// The last message when the user stopped a reply from the Realism
  /// overlay. The "you stopped this reply" notice shows while it is still
  /// the chat's last message (same anchor rule as ActionsDoor's suggestions).
  ChatMessage? _stoppedReplyAnchor;

  /// True while Try again (regenerate on a trailing user line) runs. That
  /// regen holds `_isPostGenerating`, but no reply exists to keep.
  bool _answeringUnansweredLine = false;

  bool _isNewChat = false;

  bool _disposed = false;
  // ── Dynamic Responses (idle timer / fourth-wall auto-ping) ─────────────
  Timer? _idleTimer;
  String? _pendingIdleCue;
  bool _autoResponseInProgress = false;
  bool _hasCompletedExchange = false;
  int _consecutiveAutoResponses = 0;
  // The consecutive-response cap lives in the persisted
  // generationSettings.dynamicResponseMaxMessages (default 3) so the sidebar
  // flyout, /afk --messages, and the settings all share one source of truth.

  // ── Scene Guests (Lite NPCs) ────────────────────────────────────────────
  // Every field lives in SceneGuestState (documented there); behaviour stays
  // in the scene_guest / _cast / _guest_flow parts. Guest Growth Rings key by
  // the guest's stable charId in growth_rings, so no evolution state here.
  final SceneGuestState _sceneGuest = SceneGuestState();
  // Slice 6: suggested scene move + per-setting decline memory.
  final SceneMoveState _sceneMoves = SceneMoveState();
  final AwayPulseState _awayPulse = AwayPulseState();

  ChatCommandHandler? _commandHandler;
  bool autoChimeEnabled = true;

  // Scene Guest cast detection: gate is realismSettings.sceneGuestDetectionEnabled
  // (read in _maybeRunCastDetection). _castScanInterval → chat_service_defaults.

  Future<void> _saveChain = Future.value();

  /// Serializes [sendMessage] so two composer taps during settle cannot
  /// both pass `_isGenerating` and then both run after the wait.
  Future<void> _sendChain = Future.value();
  Map<String, dynamic>?
  _pendingRealismMetadata; // stores deltas for the next generation
  bool _isGenerating = false;

  /// True while the awaited POST-generation work is still running.
  ///
  /// `_isGenerating` is cleared the moment the last token lands, but the turn
  /// is not finished there: the needs-impact eval, the realism-state re-stamp,
  /// the `RealismDance.saveScalarsIntoGroup` persist and the chip attach all run
  /// afterwards, and in a group they run under an impersonation dance that
  /// reassigns `_session.activeCharacter` and loads that member's scalars. For those
  /// seconds the app used to report "not generating" while the engine was
  /// still mutating state, so every re-entrancy guard stood open: a delete
  /// could shift the timeline under a running eval, and a new turn could
  /// interleave with the previous one's persist.
  ///
  /// Deliberately NOT held across the fire-and-forget passes (journal, growth,
  /// promise-debt, embed, periodic evals). Those are unawaited by design and
  /// can run indefinitely; blocking input until they finish would trade a race
  /// for a wedged UI, which is the worse bug.
  bool _isPostGenerating = false;
  // An import in flight (`isImporting`) and the `.porch` chat-move claim
  // live on the transfer doors (chatImporter, chatPackager).

  // (_isTurnBusy — "this turn is still in motion" predicate for mutation
  // guards, NOT for stopGeneration/_cancelAndWaitForGeneration which must
  // keep testing _isGenerating alone — moved to chat_service_generation_stream.dart)

  // True while a forked-in character's custom entrance sequence is running
  // (fire-and-forget after forkToGroupChat). Blocks user-triggered turns so the
  // one-shot _entranceDirective can't be consumed/overwritten by a racing user
  // turn. (Follow-up: pass the directive as a local into _generateResponse to
  // drop the shared field entirely.)
  bool _entrancesInFlight = false;
  bool _isLoadingSession = false;
  // New chat / loadSession runs in flight; sends wait them out.
  int _chatSwitches = 0;
  final _history = SessionHistoryWindow();

  /// Saved position of `messages[0]`. Older rows still loading sit
  /// before it, so a row's place in the whole chat is this plus its index.
  /// A class member (not an extension) so test fakes can pin it.
  int get historyBasePosition => _history.basePosition;
  bool _cancelRequested = false;
  int _generationEpoch = 0;

  /// The open chat every domain reads (messages, session id, character,
  /// group manager). Its session id setter tells KoboldCpp which chat is open.
  late final _session = ChatSessionState(onChatOpened: _keeperFollows);

  /// Chat screens open on the desktop ([chatScreenOpened]).
  int _chatScreens = 0;

  /// The "Did time pass?" question, and whether a web client is there to
  /// answer one (see `pendingSkip`).
  final SkipConfirmGate _skipGate = SkipConfirmGate();
  bool Function() _skipWebAsker = () => false;

  /// The desktop's chat page opened: the chat it shows is the open one.
  void chatScreenOpened() {
    if (_chatScreens++ == 0) _keeperFollows(_session.currentSessionId);
  }

  /// The desktop's chat page closed. With none left the user went back to
  /// the library: no chat is open, and KoboldCpp's saved cache can go.
  void chatScreenClosed() {
    if (_chatScreens > 0 && --_chatScreens == 0) _keeperFollows(null);
  }

  void _keeperFollows(String? chat) {
    // This bag is ChatService's; the engine is a field of the class.
    final self = this;
    if (self is! ChatService) return;
    try {
      self._koboldService.openChat(chat);
    } on Object catch (e) {
      debugPrint('[Chat] KoboldCpp could not be told which chat is open: $e');
    }
  }

  double _generationProgress = 0.0;

  // ── Real-absence awareness (Living Time §2) ──
  // Computed in-memory at session load from the last saved message's
  // updatedAt; nothing is stored or transmitted (privacy-by-design contract
  // in absence_tracker.dart). Story clock untouched.
  Duration _absenceGap = Duration.zero;
  bool _absenceAckPending = false;
  bool _absenceAckConsumed = false;
  int _tokensGenerated = 0;
  int _maxTokens = 0;
  DateTime? _generationStartTime;
  GenerationPhase _generationPhase = GenerationPhase.idle;
  DateTime? _prefillStartTime; // When we entered prefill (for elapsed timer)
  int _prefillPromptTokens =
      0; // Estimated prompt token count for progress display
  Map<String, dynamic>? _lastPerfData; // Cached KoboldCPP perf data
  final TokenCountMemo _tokenCountMemo = TokenCountMemo();
  final List<String> _tokenBuffer = [];
  Timer? _drainTimer;
  int _displayedTokenCount = 0;
  final List<DateTime> _tokenTimestamps =
      []; // Rolling window for TPS measurement

  // ── Streaming rebuild throttle ──
  // _notifyStreamListeners coalesces per-token notifies into at most one per
  // ~33 ms with a guaranteed trailing notify (the final token batch always
  // paints). End-of-turn paths still call plain notifyListeners() directly,
  // so terminal state (isGenerating=false, chips, perf) is never throttled.
  DateTime _lastStreamNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _streamNotifyTimer;
  // (_notifyStreamListeners lives in chat_service_generation_stream_accessors)

  // ── Web token broadcast (the web StreamHub's real-time token feed) ──
  final StreamController<String> _tokenBroadcast =
      StreamController<String>.broadcast();

  /// Emits complete sentences as they're detected during LLM token streaming.
  /// Used by call mode to start TTS on the first sentence immediately.
  final StreamController<String> _sentenceBroadcast =
      StreamController<String>.broadcast();
  String _sentenceBuffer = ''; // accumulates tokens until a sentence boundary

  /// Whether the app is in voice call mode (auto-disables reasoning for lower latency).
  bool _callMode = false;

  /// Main model parked by the pre-turn call-model swap (sendMessage enters,
  /// the request phase adopts into the turn carrier — see the request part).
  String? _callEvalModelOriginal;

  // Wired for decoupled group member loading (so setActiveGroup works even if caller
  // doesn't explicitly pass groupRepo every time). Set from main.dart provider setup.
  GroupChatRepository? _groupChatRepository;

  // One-shot hidden directive for a forked-in character's custom entrance
  // (Direction mode). Injected into the prompt, consumed on the next generation;
  // the forced-speaker side is handled by GroupTurnManager.setNextSpeaker.
  String? _entranceDirective;

  /// The director's pinned scene goal and private whispers, saved per chat.
  final DirectorScene _directorScene = DirectorScene();

  /// A `/narrate` call is in flight (it runs before the turn it starts).
  bool _narrating = false;

  /// The running auto-chat's turn budget.
  final AutoChatBudget _autoChatBudget = AutoChatBudget();

  /// The char→char judge, built on first use.
  CastFeelingsJudge? _castFeelingsJudgeCache;

  /// Per-character Author's Notes for group chats (independent of group-level _authorNote).
  /// Keyed by stable charId (from _getCharacterIdFromCard). Populated from the
  /// (legacy comment — now persisted via sessions.group_realism_state column)
  Map<String, String> _groupAuthorNotes = {};
  Map<String, int> _groupAuthorNoteStrengths = {};

  /// Per-character system prompts scoped to the *current group only*.
  /// These are completely independent of each character's normal `systemPrompt`
  /// (the one used in 1:1 chats). When present and non-empty for the speaking
  /// character, they take full precedence over the character's card-level prompt
  /// inside this group. Now persisted via the sessions.group_realism_state column.
  Map<String, String> _groupCharacterSystemPrompts = {};

  // RAG settings for the active group (stored in the hidden checkpoint, no DB schema change)
  bool _groupRagEnabled = true;
  int _groupRetrievalCount = 4;
  double _groupMemoryBudgetPercent = 10.0;
  Map<String, double> _groupCharacterRAGPriorities = {};

  // Director Mode state is now owned by _session.groupManager when active.
  // The public getters below delegate to it.
  // ── Author's Note ──
  String _authorNote = '';
  int _authorNoteStrength = 4;

  // ── Per-chat avatar gallery ("looks") selection ──
  // {characterId: selectedLookAvatarId} for THIS session, decoded from the
  // session's selectedLookAvatarId column on load. A map (not one id) so a group
  // chat remembers a look per participant; 1:1 is just a one-entry map. Reset
  // per session in loadSession; empty when no session.
  Map<String, String> _selectedLooks = {};

  // ── Chat Summary ──
  String _summary = '';
  int _summaryLastIndex = 0;

  /// Session id whose in-memory recap matches the row. Until hydrate,
  /// a save must not blank or replace `sessions.summary`.
  String? _recapBoundSessionId;

  /// The editor or a timeline rewrite cleared "Where we are" on purpose.
  bool _recapClearArmed = false;
  // Secondary runtime flag (like _isSummaryGenerating); must be defensively
  // zeroed on *all* reset/new-chat/0-session/group/setActive/load/delete
  // paths or pause state leaks across contexts (see CLAUDE.md keep-sync).
  bool _summaryPaused = false;
  bool _isSummaryGenerating = false;
  // ── Realism Mode ──
  bool _realismChatSwitch = false; // this chat's own; gate: _realismEnabled
  bool _isEvaluatingRealism = false;
  bool _isCancellingRealismEval = false;
  bool _isProcessingGreeting =
      false; // true while post-greeting baseline eval runs
  bool _greetingEvalPending =
      false; // greeting placed but baseline eval not yet run
  // In-flight opening-position seed. Two entry points call _seedOpeningPosture
  // and the guard they share ("no stance on record") is written only by the
  // completed call, so without this they both fire. See _seedOpeningPosture.
  Future<void>? _openingPostureSeed;
  // The session the opening position has already been ATTEMPTED for. Keyed on
  // the session id rather than a bool precisely so it needs no reset site: the
  // four places that reset per-chat state would each have had to remember it.
  String? _openingPostureSeededFor;
  String _realismEvalStreamText = '';

  // Verifier phase coordination (god-owned for overlay + chips; leaf is stateless/prompt+rule).
  // Set around verify calls (via thin cb from leaves) so "🕵️ Verifying Realism output (pass X/Y)" shows
  // using the *exact same* overlay widgetry. 0 new void _ privates.
  bool _isVerifyingRealism = false;
  int _verificationPass = 0;
  int _verificationMaxPasses = 1;
  // Debounce timer — batches rapid per-chunk notifyListeners() calls during
  // eval streaming into a single rebuild every 150 ms. Without this, a
  // 40-token JSON response fires 40+ notifyListeners() calls and widgets that
  // are mid-deactivation throw "Looking up a deactivated widget's ancestor".
  Timer? _evalChunkTimer;

  // Emotional state. Cause and hold go through MoodRegisters (`_mood`).
  String _characterEmotion = '';
  String _emotionIntensity = ''; // mild/moderate/strong
  String _emotionCause = '';
  int _emotionHeldTurns = 0;

  // Chaos Mode state lives on _chaosModeService. UI park flags stay here.
  bool _chanceTimePendingTrigger =
      false; // true for one cycle to pop the overlay
  // The single event the web/mobile "reveal your fate" modal shows + accepts
  // while sendMessage is parked on the completer below. The desktop samples its
  // own spinning wheel; a phone has no room for one, so we pre-pick one event
  // from the same pool. Lives only during the park (set at the gate, cleared on
  // resume) — see [isAwaitingChanceTime] / [acceptPendingChanceTime].
  String? _webChanceTimeEvent;
  String? _webChanceTimeName; // who it names, fixed at the spin

  // ── Needs simulation + scene-impact evaluator ──
  bool _needsSimEnabled = false;
  // Per-chat Objectives switch (v45). Defaults true; read via objectivesActive.
  bool _objectivesEnabled = true;
  bool _enjoysLowHygiene =
      false; // inversion for hygiene (enjoys being dirty/sweaty/musky)

  /// Per-chat lore session state (ST sticky/cooldown timers, macro locals,
  /// chat-scoped lorebook) — persisted inside the session's groupRealismState
  /// blob via additive keys, hydrated on session load, cleared at session
  /// boundaries via the scanner reset.
  final _loreTimedEffects = LorebookTimedEffects();

  // (chatLorebook / commitChatLorebookEdit / lastLoreOverflow / lastLoreTokens
  // / lastLoreBudget / loreTimedEffects / previewLoreTriggers /
  // currentlyActiveLoreEntries moved to chat_service_accessors.dart)
  List<String> _lastLoreOverflow = const [];
  int _lastLoreTokens = 0;
  int _lastLoreBudget = 0;

  // The group lorebook is stored as a JSON string on the group row. Parse it
  // ONCE and keep the live instance — the scanner writes trigger state onto
  // these entry objects, so a fresh parse per read (the pre-Phase-2 behavior)
  // silently discarded every keyword trigger and left group books constant-only.
  // String-compare invalidation: editing the book in group settings replaces
  // the JSON string, which re-parses (and intentionally clears trigger state,
  // same as editing semantics elsewhere).
  Lorebook? _cachedGroupBook;
  String? _cachedGroupBookJson;
  bool _groupLorebookUnreadable = false;

  /// Living Worlds: Primary Setting + Lore slots for the open session.
  /// Loaded on session open; group template seeds new chats.
  ChatPlaceSlots _chatPlaceSlots = const ChatPlaceSlots();

  /// Hydrated mid-chat climate spans + world default (Living Worlds phase 1).
  BiomeSchedule _biomeSchedule = const BiomeSchedule();

  /// Central macro resolver for prompt template expansion.
  late final _macroResolver = MacroResolver();

  /// In-memory clock for {{idle_duration}} — set on each user send; null
  /// after a restart (the macro passes through untouched then).
  DateTime? _lastUserMessageAt;

  /// The 1:1 speaker's pockets. In a group each member's record lives in their
  /// `_groupRealism` slot instead, which is what keeps it session-scoped and
  /// deleted with the chat; this scalar is the same record for the host.
  Pockets? _pockets;

  Completer<void>?
  _chanceTimeCompleter; // pauses sendMessage while wheel is active (UI coordination)

  final ContextBudgetStore _contextBudget = ContextBudgetStore();
  // ── Session Metadata ──
  String? _sessionName;
  String? _sessionDescription;

  // ── Per-session generation overrides ──
  ChatGenerationSettings _sessionGenSettings = ChatGenerationSettings();
  ({String key, ChatGenerationSettings chat})?
  _promptPickerPending; // prompt-picker SOW: the new 1:1 awaiting the picker

  // ── Per-chat theme ──
  ChatThemeOverrides _sessionThemeOverrides = ChatThemeOverrides();

  // ── Chat Branching ──
  String? _parentSessionId;
  int? _forkIndex;
  int _greetingIndex = 0;
  String? _evalCleanSrc, _evalCleanOut;
  bool _isGrowthPassRunning = false;

  /// Test-only overrides for driving the real LLM paths (realism evals +
  /// chat generation) with canned responses without constructing a full
  /// LLMProvider (heavy deps).
  @visibleForTesting
  LLMService? testLlmServiceOverride;
  @visibleForTesting
  bool testIsLocalOverride = false;
  @visibleForTesting
  LLMService? testWorkerLlmServiceOverride;

  /// True while Manual Reprocess → Feelings runs the judges again. They may
  /// not start quests then, and tier crossings wait in [_rescoreCrossings]
  /// until the new score is kept (see chat_service_reprocess_choice.dart).
  bool _rescoringFeelings = false;
  final List<TierCrossing> _rescoreCrossings = [];

  /// A rewrite from a word waiting for its turn: the next normal reply
  /// starts with this text (see chat_service_variants.dart).
  String? _regenSeed;

  /// Shared Journal/Growth tools-vs-XML probe (one per backend identity).
  final _toolProbe = ToolTransportProbe();
}
