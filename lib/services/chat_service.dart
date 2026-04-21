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
import 'dart:convert';
import 'dart:math';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_generation_settings.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/cloud_sync_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:drift/drift.dart' as drift;

// ── Realism Engine GBNF Grammars ─────────────────────────────────────────────
// Used by KoboldCPP local backend when reasoning mode is OFF.
// Forces JSON-structured output at the token-sampling level, guaranteeing the
// model can't ramble past the closing } and doesn't need excessive max_tokens.
//
// Each grammar accepts any well-formed JSON object so optional fields
// (e.g. arousal_delta) are naturally handled without a rigid schema.

/// General-purpose JSON object grammar: accepts any flat {"key": value, ...}
/// where values may be strings, numbers, or booleans. Sufficient for all
/// Realism Engine evals which return small flat JSON objects.
const String _kGbnfJsonObject = r'''
root   ::= ws "{" ws members ws "}" ws
members ::= pair (ws "," ws pair)*
pair    ::= string ws ":" ws value
value   ::= string | number | boolean | "null"
string  ::= "\"" ([^"\\] | "\\" .)* "\""
number  ::= "-"? ([0-9] | [1-9][0-9]*) ("." [0-9]+)? (([eE] [+-]? [0-9]+))?
boolean ::= "true" | "false"
ws      ::= [ \t\n\r]*
''';

/// GBNF grammar for a JSON array of strings (e.g. ["fact1", "fact2"]).
/// Used by the fact extraction eval to constrain LLM output.
const String _kGbnfJsonStringArray = r'''
root    ::= ws "[" ws (string (ws "," ws string)*)? ws "]" ws
string  ::= "\"" ([^"\\] | "\\" .)* "\""
ws      ::= [ \t\n\r]*
''';

enum GenerationMode { normal, continue_, impersonate }

/// Tracks the distinct phases of text generation for UI display.
/// Each phase maps to a user-visible status message.
enum GenerationPhase {
  /// Not generating.
  idle,

  /// Building the prompt context (lorebook, memories, history, etc.).
  preparing,

  /// HTTP request sent, waiting for response + prompt processing.
  /// For KoboldCPP this is the prefill/eval phase which can be long.
  prefilling,

  /// Tokens arriving but inside <think>...</think> tags (reasoning model).
  thinking,

  /// Display buffer is accumulating tokens before smooth playback begins.
  buffering,

  /// Tokens are actively being generated and displayed to the user.
  generating,
}

class ChatMessage {
  final List<String> swipes;
  int swipeIndex;
  final String sender;
  final bool isUser;
  final String?
  characterId; // which character card sent this (null = user or 1:1 mode)
  final List<int> swipeDurations; // thinking duration in ms per swipe

  String get text => swipes.isNotEmpty ? swipes[swipeIndex] : '';
  set text(String value) {
    if (swipes.isNotEmpty) {
      swipes[swipeIndex] = value;
    }
  }

  /// Returns text with <think>...</think> blocks removed for display.
  /// Also handles in-progress thinking (no closing tag yet during streaming).
  String get displayText {
    final raw = text;
    // Strip completed think blocks
    var result = raw.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>\s*', caseSensitive: false),
      '',
    );
    // Strip in-progress think block (opened but not yet closed during streaming)
    result = result.replaceAll(
      RegExp(r'<think>[\s\S]*$', caseSensitive: false),
      '',
    );
    return result.trim();
  }

  /// Returns the thinking content (between <think> tags), or null if none.
  /// Handles both completed and in-progress (streaming) think blocks.
  String? get thinkingContent {
    // Try completed think block first
    final closed = RegExp(
      r'<think>([\s\S]*?)</think>',
      caseSensitive: false,
    ).firstMatch(text);
    if (closed != null) return closed.group(1)?.trim();
    // Try in-progress think block (no closing tag yet)
    final open = RegExp(
      r'<think>([\s\S]*?)$',
      caseSensitive: false,
    ).firstMatch(text);
    return open?.group(1)?.trim();
  }

  /// Whether this message has thinking content (either from tags or tracked duration)
  bool get hasThinking => thinkingContent != null || thinkingDurationMs > 0;

  int get thinkingDurationMs =>
      swipeIndex < swipeDurations.length ? swipeDurations[swipeIndex] : 0;
  set thinkingDurationMs(int value) {
    while (swipeDurations.length <= swipeIndex) {
      swipeDurations.add(0);
    }
    swipeDurations[swipeIndex] = value;
  }

  int? thinkingStartTime; // Runtime only, for live timer
  Map<String, dynamic>? metadata; // Legacy single metadata
  List<Map<String, dynamic>?> swipeMetadata; // Per-swipe metadata

  Map<String, dynamic>? get activeMetadata {
    if (swipeIndex >= 0 && swipeIndex < swipeMetadata.length) {
      return swipeMetadata[swipeIndex] ?? metadata;
    }
    return metadata;
  }

  set activeMetadata(Map<String, dynamic>? value) {
    while (swipeMetadata.length <= swipeIndex) {
      swipeMetadata.add(null);
    }
    swipeMetadata[swipeIndex] = value;
  }

  ChatMessage({
    required String text,
    required this.sender,
    required this.isUser,
    this.characterId,
    List<String>? swipes,
    int? swipeIndex,
    List<int>? swipeDurations,
    this.metadata,
    List<Map<String, dynamic>?>? swipeMetadata,
  }) : swipes = swipes ?? [text],
       swipeIndex = swipeIndex ?? 0,
       swipeDurations = swipeDurations ?? [0],
       swipeMetadata = swipeMetadata ?? [metadata];

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'sender': sender,
      'is_user': isUser,
      if (characterId != null) 'character_id': characterId,
      'swipes': swipes,
      'swipe_index': swipeIndex,
      'swipe_durations': swipeDurations,
      if (metadata != null) 'metadata': metadata,
      if (swipeMetadata.any((e) => e != null)) 'swipe_metadata': swipeMetadata,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final List<String>? savedSwipes = (json['swipes'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList();
    final List<int>? savedDurations =
        (json['swipe_durations'] as List<dynamic>?)
            ?.map((e) => (e as num).toInt())
            .toList();
    final String fallbackText = json['text'] ?? '';
    final List<Map<String, dynamic>?>? savedSwipeMetadata =
        (json['swipe_metadata'] as List<dynamic>?)
            ?.map((e) => e != null ? Map<String, dynamic>.from(e as Map) : null)
            .toList();

    return ChatMessage(
      text: fallbackText,
      sender: json['sender'] ?? '',
      isUser: json['is_user'] ?? false,
      characterId: json['character_id'],
      swipes: savedSwipes ?? [fallbackText],
      swipeIndex: json['swipe_index'] ?? 0,
      swipeDurations: savedDurations ?? [0],
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
      swipeMetadata: savedSwipeMetadata,
    );
  }
}

class ChatService extends ChangeNotifier {
  final KoboldService _koboldService;
  final UserPersonaService _userPersonaService;
  final StorageService _storageService;
  final WorldRepository _worldRepository;
  late AppDatabase _db;
  LLMProvider? _llmProvider;
  CharacterRepository? _characterRepository;
  TtsService? _ttsService;
  MemoryService? _memoryService;

  // Action suggestions
  List<String> _suggestedActions = [];
  bool _isGeneratingActions = false;
  List<String> get suggestedActions => _suggestedActions;
  bool get isGeneratingActions => _isGeneratingActions;

  // Objective/quest system
  List<Objective> _activeObjectives = [];
  int _messagesSinceLastCheck = 0;
  bool _isCheckingCompletion = false;

  List<Objective> get activeObjectives => _activeObjectives;
  Objective? get primaryObjective =>
      _activeObjectives.where((o) => o.isPrimary).firstOrNull;
  List<Objective> get secondaryObjectives =>
      _activeObjectives.where((o) => !o.isPrimary).toList();

  List<Map<String, dynamic>> tasksForObjective(Objective obj) {
    try {
      return (jsonDecode(obj.tasks) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Update the database reference (e.g. after cloud sync replaces the DB file).
  void updateDatabase(AppDatabase db) {
    _db = db;
  }

  CharacterCard? _activeCharacter;
  final List<ChatMessage> _messages = [];
  Map<String, dynamic>?
  _pendingRealismMetadata; // stores deltas for the next generation
  bool _isGenerating = false;
  bool _isLoadingSession = false;
  bool _cancelRequested = false;
  int _generationEpoch = 0;
  String? _currentSessionId;
  double _generationProgress = 0.0;
  int _tokensGenerated = 0;
  int _maxTokens = 0;
  DateTime? _generationStartTime;
  bool _isBuffering = false;
  GenerationPhase _generationPhase = GenerationPhase.idle;
  DateTime? _prefillStartTime; // When we entered prefill (for elapsed timer)
  int _prefillPromptTokens =
      0; // Estimated prompt token count for progress display
  Map<String, dynamic>? _lastPerfData; // Cached KoboldCPP perf data
  final List<String> _tokenBuffer = [];
  Timer? _drainTimer;
  int _displayedTokenCount = 0;
  final List<DateTime> _tokenTimestamps =
      []; // Rolling window for TPS measurement

  // ── Web SSE token broadcast ──
  // External consumers (e.g. WebChatBridge) listen to this for real-time token streaming.
  final StreamController<String> _tokenBroadcast =
      StreamController<String>.broadcast();
  Stream<String> get tokenStream => _tokenBroadcast.stream;

  /// Emits complete sentences as they're detected during LLM token streaming.
  /// Used by call mode to start TTS on the first sentence immediately.
  final StreamController<String> _sentenceBroadcast =
      StreamController<String>.broadcast();
  Stream<String> get sentenceStream => _sentenceBroadcast.stream;
  String _sentenceBuffer = ''; // accumulates tokens until a sentence boundary

  /// Whether the app is in voice call mode (auto-disables reasoning for lower latency).
  bool _callMode = false;
  bool get callMode => _callMode;
  set callMode(bool value) {
    _callMode = value;
    notifyListeners();
  }

  // ── Group chat state ──
  GroupChat? _activeGroup;
  List<CharacterCard> _groupCharacters = [];
  int _turnIndex = 0;

  // ── Director Mode ──
  bool _observerMode = false;
  bool _autoPlayActive = false;
  double directorDelaySec = 15.0; // seconds between auto-chat responses
  // ── Author's Note ──
  String _authorNote = '';
  int _authorNoteStrength = 4;

  // ── Chat Summary ──
  String _summary = '';
  int _summaryLastIndex = 0;
  bool _summaryPaused = false;
  bool _isSummaryGenerating = false;

  // ── Realism Mode ──
  bool _realismEnabled = false; // master toggle
  bool _isEvaluatingRealism = false;
  bool _isProcessingGreeting =
      false; // true while post-greeting baseline eval runs
  bool _greetingEvalPending =
      false; // greeting placed but baseline eval not yet run
  String _realismEvalStreamText = '';
  // Debounce timer — batches rapid per-chunk notifyListeners() calls during
  // eval streaming into a single rebuild every 150 ms. Without this, a
  // 40-token JSON response fires 40+ notifyListeners() calls and widgets that
  // are mid-deactivation throw "Looking up a deactivated widget's ancestor".
  Timer? _evalChunkTimer;

  // Relationship (Short-Term / Tension)
  int _affectionScore = 0;
  int _relationshipTier = 0;

  // Long-Term Bond
  int _longTermScore = 0;
  int _longTermTier = 0;
  int _turnsSinceLongTermCheck = 0;
  int _shortTermDeltasSummary = 0;

  // Short-term mood
  int _moodDecayCounter = 0;

  // Emotional state
  String _characterEmotion = '';
  String _emotionIntensity = ''; // mild/moderate/strong

  // Passage of time
  String _timeOfDay = 'morning';
  int _dayCount = 1;
  int _startDayOfWeek =
      DateTime.now().weekday; // 1=Mon ... 7=Sun, set when session starts
  int _turnsSinceLastTimeAdvance = 0; // deterministic pacing counter
  bool _passageOfTimeEnabled = true; // toggle for automatic time advancement

  /// How many AI turns must pass before time is eligible to advance.
  /// 6 turns ≈ a meaningful scene chunk without forcing constant time-skips.
  static const int _turnsPerTimePeriod = 6;

  // NSFW cooldown & lust
  bool _nsfwCooldownEnabled = false;
  int _cooldownTurnsRemaining = 0;
  int _cooldownTurnsTotal =
      0; // original refractory duration (for phased prompt)
  int _arousalLevel = 0; // -10 to +10 scale

  // ── Chaos Mode / Chance Time ──
  bool _chaosModeEnabled = false;
  bool _chaosNsfwEnabled = false; // include spicy/NSFW events in the pool
  int _chaosPressure = 0; // 0–100; grows each turn without a trigger
  String?
  _pendingChanceTimeEvent; // set when wheel lands; cleared after UI reads it
  bool _chanceTimePendingTrigger =
      false; // true for one cycle to pop the overlay
  String?
  _pendingChaosInjection; // event text to inject into the next response prompt
  bool _chaosEventDelivered =
      false; // true after the event has been used in at least one generation
  Completer<void>?
  _chanceTimeCompleter; // pauses sendMessage while wheel is active

  /// Base chance % per turn. Grows by [_chaosGrowthPerTurn] each turn.
  static const int _chaosBaseChance = 5;
  static const int _chaosGrowthPerTurn = 5;
  static const int _chaosPressureCap = 100;

  // ── v3 Behavioral Mechanics ──
  int _trustLevel = 0; // -100 to 100
  String _activeFixation = '';
  int _fixationLifespan = 0; // turns until fixation naturally clears
  String _spatialStance = '';

  // ── Trust Repair ──
  // Armed on each severe trust drop (≥ -20 delta). Consumed on the very
  // next user message, then resets so future drops each get one shot.
  bool _pendingTrustRepair = false;

  // ── Context / Prompt Budget ──
  Map<String, int> _lastPromptBudget = {};
  String _lastAssembledPrompt = '';

  // ── Session Metadata ──
  String? _sessionName;
  String? _sessionDescription;

  // ── Per-session generation overrides ──
  ChatGenerationSettings _sessionGenSettings = ChatGenerationSettings();

  // ── Chat Branching ──
  String? _parentSessionId;
  int? _forkIndex;

  /// Default system prompt for group chats, designed to prevent characters
  /// from speaking for each other and maintain turn discipline.
  static const String defaultGroupSystemPrompt =
      'You are roleplaying in a multi-character group conversation. '
      'CRITICAL RULES:\n'
      '1. You MUST only write dialogue and actions for the character whose turn it is (indicated after <START>). '
      'NEVER write dialogue, thoughts, or actions for other characters or {{user}}.\n'
      '2. Stay fully in character \u2014 use the speaking character\'s unique voice, mannerisms, personality, and speech patterns.\n'
      '3. Keep your response focused on ONE character\'s contribution. Do not narrate what other characters do or say.\n'
      '4. React naturally to what other characters and {{user}} have said. Reference their words, but do not put words in their mouths.\n'
      '5. Write in the style of collaborative roleplay: use *asterisks* for actions/narration and regular text for dialogue.\n'
      '6. Keep responses concise and punchy \u2014 leave room for the next character to respond.\n'
      '7. Never break character or reference the fact that you are an AI.';

  /// System prompt for Observer Mode — characters interact with each other, user is not present.
  static const String observerModeSystemPrompt =
      'You are roleplaying in a multi-character group conversation. '
      'The user is NOT a participant in this story — they are an invisible observer/director. '
      'CRITICAL RULES:\n'
      '1. You MUST only write dialogue and actions for the character whose turn it is. '
      'NEVER write for other characters.\n'
      '2. Characters should interact naturally WITH EACH OTHER — address other characters by name, '
      'respond to what they said, react to their actions. Build on the conversation organically.\n'
      '3. Stay fully in character — use the speaking character\'s unique voice and personality.\n'
      '4. If a [Director] note appears, follow its guidance to steer the scene (introduce new topics, '
      'create conflict, have a character enter/leave, etc.) but do NOT acknowledge the director directly.\n'
      '5. Write in collaborative roleplay style: *asterisks* for actions, regular text for dialogue.\n'
      '6. Keep responses concise — leave room for the next character to respond.\n'
      '7. Never break character or reference being an AI.\n'
      '8. Characters may naturally address each other, start side conversations, argue, agree, '
      'tell stories, ask questions, or react emotionally — make the conversation feel alive and dynamic.';

  /// Default system prompt for local KoboldCPP backends (smaller models).
  /// Kept concise so it doesn't eat too much of the limited context window.
  static const String defaultKoboldSystemPrompt =
      'Write {{char}}\'s next reply in this roleplay with {{user}}. '
      'Stay in character as {{char}} at all times. '
      'Use *asterisks* for actions and narration, regular text for dialogue. '
      'Be creative, descriptive, and drive the scene forward. '
      'Never write actions or dialogue for {{user}}. '
      'Never break character or mention being an AI.';

  /// Default system prompt for remote API backends (large cloud models).
  /// Highly detailed to leverage the model's full capabilities.
  static const String defaultApiSystemPrompt =
      'You are an expert collaborative fiction writer and immersive roleplay partner. '
      'You write as {{char}} in an ongoing interactive story with {{user}}.\n\n'
      'CORE IDENTITY:\n'
      '- Embody {{char}} completely. Every response must reflect their unique personality, speech patterns, '
      'vocabulary level, emotional state, and worldview as defined in their character description.\n'
      '- {{char}} is a living, breathing character with their own desires, fears, opinions, and agency \u2014 '
      'not a servant of {{user}}. They can disagree, have bad days, make mistakes, and act according to their own motivations.\n\n'
      'WRITING CRAFT:\n'
      '- Write in a natural, literary style. Vary sentence length and structure. Avoid repetitive sentence openings.\n'
      '- Show emotions through body language, micro-expressions, vocal tone, and subtle actions rather than stating '
      'feelings directly ("she clenched her jaw" not "she felt angry").\n'
      '- Use all five senses \u2014 sight, sound, smell, touch, taste \u2014 to create vivid, immersive scenes.\n'
      '- Dialogue should feel natural and conversational. Characters can interrupt, trail off, use contractions, '
      'stumble over words, or speak in fragments when emotionally charged.\n'
      '- Weave internal thoughts, environmental details, and physical sensations into responses to create depth.\n'
      '- Match the tone and pacing to the scene: tense moments get short, punchy prose; reflective moments get '
      'slower, more lyrical writing.\n\n'
      'ANTI-SLOP RULES \u2014 AVOID THESE CLICH\u00c9S:\n'
      '- Do NOT use: "a symphony of", "a dance of", "sent shivers down", "electricity coursed through", '
      '"breath hitched", "pupils dilated", "orbs" (for eyes), "ministrations", "mewled", '
      '"the air crackled with", "a masterpiece of", "elicited a moan".\n'
      '- Do NOT start responses with: "I", a sigh, a chuckle, or raising an eyebrow.\n'
      '- Do NOT use purple prose or melodramatic narration. Keep descriptions grounded and specific.\n'
      '- Vary your emotional vocabulary \u2014 don\'t repeat the same descriptors across responses.\n\n'
      'RESPONSE GUIDELINES:\n'
      '- Write 2-5 paragraphs per response unless the scene calls for shorter exchanges.\n'
      '- Always advance the scene meaningfully. Each response should move the story forward through action, '
      'revelation, or emotional development.\n'
      '- End responses at natural pause points that invite {{user}} to react \u2014 don\'t resolve conflicts or '
      'answer your own questions.\n'
      '- Never narrate {{user}}\'s actions, thoughts, dialogue, or emotional reactions. Their agency is sacred.\n'
      '- Never break the fourth wall, mention being an AI, or reference the roleplay as fiction.\n'
      '- Maintain continuity with all previously established facts, character history, and world details.\n\n'
      'DIALOGUE FORMAT:\n'
      '- Use regular text for speech: "Like this," she said.\n'
      '- Use *asterisks* for actions and narration: *She leaned against the doorframe, arms crossed.*\n'
      '- Internal thoughts can be written in italics or described through narration.';

  CharacterCard? get activeCharacter => _activeCharacter;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isGenerating => _isGenerating;
  bool get isLoadingSession => _isLoadingSession;
  String? get currentSessionId => _currentSessionId;
  double get generationProgress => _generationProgress;
  int get tokensGenerated => _tokensGenerated;
  int get maxTokens => _maxTokens;
  bool get isBuffering => _isBuffering;
  GenerationPhase get generationPhase => _generationPhase;

  /// Seconds elapsed since entering the prefill phase. Returns 0 if not prefilling.
  double get prefillElapsedSeconds => _prefillStartTime != null
      ? DateTime.now().difference(_prefillStartTime!).inMilliseconds / 1000.0
      : 0.0;

  /// Cached KoboldCPP performance data from last /api/extra/perf poll.
  Map<String, dynamic>? get lastPerfData => _lastPerfData;

  /// Estimated prompt token count for the current generation (for progress display).
  int get prefillPromptTokens => _prefillPromptTokens;
  bool get isGroupMode => _activeGroup != null;
  GroupChat? get activeGroup => _activeGroup;
  bool get observerMode => _observerMode;
  bool get autoPlayActive => _autoPlayActive;
  List<CharacterCard> get groupCharacters =>
      List.unmodifiable(_groupCharacters);

  /// The character who will speak next in group mode.
  CharacterCard? get nextCharacter {
    if (_activeGroup == null || _groupCharacters.isEmpty) return null;
    if (_activeGroup!.turnOrder == TurnOrder.roundRobin) {
      return _groupCharacters[_turnIndex % _groupCharacters.length];
    }
    return null; // random is chosen at generation time
  }

  double get tokensPerSecond {
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

  int _greetingIndex = 0;
  int get greetingIndex => _greetingIndex;

  ChatService(
    this._koboldService,
    this._userPersonaService,
    this._storageService,
    this._worldRepository,
  );

  /// Set the database instance after construction.
  void setDatabase(AppDatabase db) {
    _db = db;
  }

  String get authorNote => _authorNote;
  int get authorNoteStrength => _authorNoteStrength;
  Map<String, int> get lastPromptBudget => _lastPromptBudget;
  String get lastAssembledPrompt => _lastAssembledPrompt;
  int get contextSize =>
      _sessionGenSettings.resolveContextSize(_storageService);

  /// Per-session generation parameter overrides. The dialog reads/writes this.
  ChatGenerationSettings get sessionGenSettings => _sessionGenSettings;
  set sessionGenSettings(ChatGenerationSettings value) {
    _sessionGenSettings = value;
    _saveChat();
    notifyListeners();
  }

  String? get parentSessionId => _parentSessionId;
  int? get forkIndex => _forkIndex;
  String? get sessionName => _sessionName;
  String? get sessionDescription => _sessionDescription;
  String get summary => _summary;
  bool get summaryPaused => _summaryPaused;
  int get summaryLastIndex => _summaryLastIndex;
  bool get isSummaryGenerating => _isSummaryGenerating;
  int get affectionScore => _affectionScore;
  int get relationshipTier => _relationshipTier;
  int get longTermScore => _longTermScore;
  int get longTermTier => _longTermTier;
  bool get realismEnabled => _realismEnabled;
  bool get isEvaluatingRealism => _isEvaluatingRealism;
  bool get isProcessingGreeting => _isProcessingGreeting;
  String get realismEvalStreamText => _realismEvalStreamText;
  String get characterEmotion => _characterEmotion;
  String get emotionIntensity => _emotionIntensity;
  String get timeOfDay => _timeOfDay;
  int get dayCount => _dayCount;
  bool get passageOfTimeEnabled => _passageOfTimeEnabled;

  /// The current narrative day of the week (e.g. 'Monday'), computed from
  /// the session's anchor weekday plus elapsed in-story days.
  String get narrativeWeekday {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final idx = (_startDayOfWeek - 1 + (_dayCount - 1)) % 7;
    return days[idx];
  }

  /// True if the realism engine has already captured a meaningful baseline
  /// (emotion or bond score). Used to avoid redundant retroactive scans.
  bool get _hasRealismBaseline =>
      _characterEmotion.isNotEmpty ||
      _affectionScore != 0 ||
      _arousalLevel != 0 ||
      _activeFixation.isNotEmpty;

  bool get nsfwCooldownEnabled => _nsfwCooldownEnabled;
  int get cooldownTurnsRemaining => _cooldownTurnsRemaining;

  // Chaos Mode
  bool get chaosModeEnabled => _chaosModeEnabled;
  bool get chaosNsfwEnabled => _chaosNsfwEnabled;
  int get chaosPressure => _chaosPressure;

  /// Non-null for exactly one notification cycle. UI reads then calls clearChanceTimeEvent().
  String? get pendingChanceTimeEvent => _pendingChanceTimeEvent;

  /// True when auto-trigger fires. UI reads then calls consumeChanceTimeTrigger().
  bool get chanceTimePendingTrigger => _chanceTimePendingTrigger;

  /// True when a chaos event is queued for the next response (blocks manual spin + auto-trigger).
  bool get hasPendingChaosEvent => _pendingChaosInjection != null;

  /// Called by the overlay once it has opened. Clears the auto-trigger flag.
  void consumeChanceTimeTrigger() => _chanceTimePendingTrigger = false;

  int get arousalLevel => _arousalLevel;
  String get activeFixation => _activeFixation;

  int get shortTermProgressTarget {
    final absScore = _affectionScore.abs();
    if (absScore < 10) return 10;
    if (absScore < 25) return 25;
    if (absScore < 45) return 45;
    if (absScore < 70) return 70;
    if (absScore < 100) return 100;
    return 150; // max
  }

  int get shortTermProgressBase {
    final absScore = _affectionScore.abs();
    if (absScore < 10) return 0;
    if (absScore < 25) return 10;
    if (absScore < 45) return 25;
    if (absScore < 70) return 45;
    if (absScore < 100) return 70;
    return 100;
  }

  double get shortTermProgressPercent {
    final current = _affectionScore.abs() - shortTermProgressBase;
    final total = shortTermProgressTarget - shortTermProgressBase;
    return (current / total).clamp(0.0, 1.0);
  }

  int get longTermProgressTarget {
    final absScore = _longTermScore.abs();
    if (absScore < 10) return 10;
    if (absScore < 25) return 25;
    if (absScore < 45) return 45;
    if (absScore < 70) return 70;
    if (absScore < 100) return 100;
    return 150; // max
  }

  int get longTermProgressBase {
    final absScore = _longTermScore.abs();
    if (absScore < 10) return 0;
    if (absScore < 25) return 10;
    if (absScore < 45) return 25;
    if (absScore < 70) return 45;
    if (absScore < 100) return 70;
    return 100;
  }

  double get longTermProgressPercent {
    final current = _longTermScore.abs() - longTermProgressBase;
    final total = longTermProgressTarget - longTermProgressBase;
    return (current / total).clamp(0.0, 1.0);
  }

  /// Human-readable tier name for the current relationship level.
  int _calculateTier(int score) {
    final absScore = score.abs();
    if (absScore < 10) return 0;
    if (absScore < 25) return score > 0 ? 1 : -1;
    if (absScore < 45) return score > 0 ? 2 : -2;
    if (absScore < 70) return score > 0 ? 3 : -3;
    if (absScore < 100) return score > 0 ? 4 : -4;
    return score > 0 ? 5 : -5;
  }

  String get shortTermTierName {
    switch (_relationshipTier) {
      case 5:
        return 'Intimate';
      case 4:
        return 'Close Friend';
      case 3:
        return 'Friend';
      case 2:
        return 'Acquaintance';
      case 1:
        return 'Friendly';
      case 0:
        return 'Stranger / Neutral';
      case -1:
        return 'Annoyed';
      case -2:
        return 'Frustrated';
      case -3:
        return 'Disliked';
      case -4:
        return 'Hostile';
      case -5:
        return 'Bitter Enemy';
      default:
        return 'Unknown';
    }
  }

  String get longTermTierName {
    switch (_longTermTier) {
      case 5:
        return 'Soulmate / Devoted';
      case 4:
        return 'Unbreakable Bond';
      case 3:
        return 'Deep Connection';
      case 2:
        return 'Growing Trust';
      case 1:
        return 'Establishing Trust';
      case 0:
        return 'No Deep Ties';
      case -1:
        return 'Distant';
      case -2:
        return 'Fractured';
      case -3:
        return 'Broken Trust';
      case -4:
        return 'Deep Resentment';
      case -5:
        return 'Nemesis';
      default:
        return 'Unknown';
    }
  }

  int get trustLevel => _trustLevel;
  int get trustTier => _calculateTier(_trustLevel);
  bool get pendingTrustRepair => _pendingTrustRepair;

  String get trustTierName {
    switch (trustTier) {
      case 5:
        return 'Blind Trust';
      case 4:
        return 'Implicit Trust';
      case 3:
        return 'Deeply Trusting';
      case 2:
        return 'Trusting';
      case 1:
        return 'Benefit of Doubt';
      case 0:
        return 'Neutral / Guarded';
      case -1:
        return 'Wary';
      case -2:
        return 'Suspicious';
      case -3:
        return 'Distrustful';
      case -4:
        return 'Paranoid';
      case -5:
        return 'Absolute Distrust';
      default:
        return 'Unknown';
    }
  }

  int get trustProgressBase {
    final absScore = _trustLevel.abs();
    if (absScore < 10) return 0;
    if (absScore < 25) return 10;
    if (absScore < 45) return 25;
    if (absScore < 70) return 45;
    if (absScore < 100) return 70;
    return 100;
  }

  int get trustProgressTarget {
    final absScore = _trustLevel.abs();
    if (absScore < 10) return 10;
    if (absScore < 25) return 25;
    if (absScore < 45) return 45;
    if (absScore < 70) return 70;
    return 100;
  }

  double get trustProgressPercent {
    final current = _trustLevel.abs() - trustProgressBase;
    final total = trustProgressTarget - trustProgressBase;
    return (current / total).clamp(0.0, 1.0);
  }

  /// Human-readable mood label containing exact emotion string and valence direction.
  String get moodLabel {
    if (_characterEmotion.isEmpty) return 'Neutral';
    final capEmotion =
        _characterEmotion.substring(0, 1).toUpperCase() +
        _characterEmotion.substring(1);
    final intensity = _emotionIntensity.isNotEmpty
        ? ' ($_emotionIntensity)'
        : '';
    return '$capEmotion$intensity';
  }

  void setAuthorNote(String note, {int? strength}) {
    _authorNote = note;
    if (strength != null) _authorNoteStrength = strength;
    _saveChat();
    notifyListeners();
  }

  /// Build the Author's Note block with strength-modulated wrapper text.
  /// Strength 1–3: subtle suggestion, 4–7: standard, 8–10: urgent directive.
  String _buildAuthorNoteBlock() {
    if (_authorNote.isEmpty) return '';
    if (_authorNoteStrength <= 3) {
      return '[Author\'s Note (gentle suggestion): $_authorNote]\n';
    } else if (_authorNoteStrength <= 7) {
      return '[Author\'s Note: $_authorNote]\n';
    } else {
      return '[Author\'s Note (IMPORTANT — apply immediately): $_authorNote]\n';
    }
  }

  /// Set the CharacterRepository so group mode can look up characters.
  void setCharacterRepository(CharacterRepository repo) {
    _characterRepository = repo;
  }

  /// Build the user persona block for the generation prompt.
  /// Layered: user's self-description is ground truth, learned facts are additive.
  /// When the embedding service is available, selects only the most relevant facts
  /// for the current conversation context instead of injecting all facts.
  Future<String> _buildUserPersonaBlock(String userName) async {
    final persona = _userPersonaService.persona;
    final description = persona.description.trim();
    final allFacts = persona.learnedFacts;

    // Nothing to inject
    if (description.isEmpty && allFacts.isEmpty) return '';

    // Select relevant facts using embeddings if available
    List<String> facts;
    if (allFacts.length > 15 && _memoryService != null) {
      // Build context from last few messages
      final recentContext = _messages.reversed
          .take(3)
          .map((m) => '${m.sender}: ${m.displayText}')
          .join('\n');
      facts = await _userPersonaService.getRelevantFacts(
        conversationContext: recentContext,
        embedService: _memoryService!.embeddingService,
        maxFacts: 15,
      );
    } else {
      facts = List<String>.from(allFacts);
    }

    final buf = StringBuffer();
    buf.writeln("$userName's Persona: $description");

    if (facts.isNotEmpty) {
      buf.writeln(
        '[Discovered traits — observations learned from conversation. '
        'The user\'s self-description above takes priority if there is a conflict.]',
      );
      for (final fact in facts) {
        buf.writeln('- $fact');
      }
    }
    buf.writeln();
    return buf.toString();
  }

  /// Set the LLMProvider after construction (to break circular dependency in provider tree).
  void setLLMProvider(LLMProvider provider) {
    _llmProvider = provider;
  }

  /// Set the CloudSyncService after construction.
  CloudSyncService? _cloudSyncService;
  void setCloudSyncService(CloudSyncService service) {
    _cloudSyncService = service;
  }

  /// Set the TtsService after construction (for TTS-aware auto-play delay).
  void setTtsService(TtsService service) {
    _ttsService = service;
  }

  /// Set the MemoryService after construction (for RAG memory retrieval).
  void setMemoryService(MemoryService service) {
    _memoryService = service;
  }

  /// Wait for TTS to finish speaking, then apply the configured delay before auto-play.
  void _waitForTtsThenContinue() {
    if (!_autoPlayActive || !_observerMode) return;
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!_autoPlayActive || !_observerMode) {
        timer.cancel();
        return;
      }
      if (_ttsService == null || !_ttsService!.isSpeaking) {
        timer.cancel();
        final delayMs = (directorDelaySec * 1000).round();
        Future.delayed(Duration(milliseconds: delayMs), () {
          if (_autoPlayActive && !_isGenerating) {
            _autoPlayNext();
          }
        });
      }
    });
  }

  Future<void> setActiveCharacter(CharacterCard? character) async {
    // Cancel any in-flight generation before switching context
    await _cancelAndWaitForGeneration();
    _generationEpoch++;

    // If same character is already active and has messages, just refresh
    // the character reference (in case fields were edited) but skip the
    // expensive full re-initialization (message clearing, session reload).
    if (_activeCharacter?.name == character?.name &&
        _activeCharacter?.dbId == character?.dbId &&
        _messages.isNotEmpty) {
      _activeCharacter = character;
      notifyListeners();
      return;
    }

    // Clear group mode when switching to 1:1 AND reset author note for new session context
    _authorNote = '';
    _authorNoteStrength = 4;
    _activeGroup = null;
    _groupCharacters = [];
    _turnIndex = 0;

    _activeCharacter = character;

    // If extensions are missing (e.g., app was restarted after DB load that
    // didn't carry over PNG extensions), reload the PNG to get V2.5 card data.
    if (_activeCharacter != null &&
        _activeCharacter!.frontPorchExtensions == null &&
        _activeCharacter!.imagePath != null) {
      try {
        final v2Service = V2CardService();
        final reloaded = await v2Service.readCard(_activeCharacter!.imagePath!);
        if (reloaded != null && reloaded.frontPorchExtensions != null) {
          _activeCharacter!.frontPorchExtensions =
              reloaded.frontPorchExtensions;
          _activeCharacter!.rawExtensions = reloaded.rawExtensions;
          debugPrint(
            '[ChatService] Reloaded frontPorchExtensions from PNG for ${_activeCharacter!.name}',
          );
        }
      } catch (e) {
        debugPrint('[ChatService] Failed to reload PNG extensions: $e');
      }
    }

    // Load active objectives for this character
    _loadActiveObjectives();
    // Note: evolved personality/scenario are now loaded inside _loadLastSession()
    // (which runs below) so they are scoped to the session, not the character.
    debugPrint(
      '[ChatService] 🟡 setActiveCharacter: clearing messages '
      '(had ${_messages.length}) for ${character?.name}, loading session...',
    );
    _messages.clear();
    _currentSessionId = null;
    _summary = '';
    _summaryLastIndex = 0;
    _isLoadingSession = true;
    notifyListeners();

    if (_activeCharacter != null) {
      // Reset lorebook trigger state
      if (_activeCharacter!.lorebook != null) {
        for (var entry in _activeCharacter!.lorebook!.entries) {
          entry.isTriggered = false;
        }
      }
      // Reset world lore triggers
       for (final worldName in _activeCharacter!.worldNames) {
         final world = _worldRepository.worlds
             .where((w) => w.name == worldName)
             .firstOrNull;
         if (world != null) {
           for (final entry in world.lorebook.entries) {
             entry.isTriggered = false;
           }
         }
       }

       // Reset realism state to prevent bleeding from previous character
       final prevArousal = _arousalLevel;
       final prevFixation = _activeFixation;
       final prevFixationLife = _fixationLifespan;
       _arousalLevel = 0;
       _fixationLifespan = 0;
       _activeFixation = '';
       debugPrint(
         '[ChatService] setActiveCharacter: Reset realism state (was: arousal=$prevArousal, fixation=$prevFixation/$prevFixationLife)',
       );

       // Try to load last session
       await _loadLastSession();

      // If no session loaded, start fresh
      if (_messages.isEmpty) {
        // Seed Realism Engine state from V2.5 card extensions (new conversations only)
        if (_activeCharacter!.frontPorchExtensions != null) {
          final ext = _activeCharacter!.frontPorchExtensions!;
          _realismEnabled = ext.realismEnabled;
          _affectionScore = ext.shortTermBond.clamp(-150, 150);
          _longTermScore = ext.longTermBond.clamp(-150, 150);
          _trustLevel = ext.trustLevel.clamp(-100, 100);
          _dayCount = ext.dayCount.clamp(1, 9999);
          _timeOfDay = ext.timeOfDay;
          _characterEmotion = ext.characterEmotion;
          _emotionIntensity = ext.emotionIntensity;
          _nsfwCooldownEnabled = ext.nsfwCooldownEnabled;
          // Global setting is a hard ceiling: if the user disabled passage-of-time
          // globally, it stays off regardless of what the character card says.
          _passageOfTimeEnabled =
              ext.passageOfTimeEnabled && _storageService.passageOfTimeDefault;
          _chaosModeEnabled = ext.chaosModeEnabled;
          // Recalculate tiers from seeded scores
          _relationshipTier = _calculateTier(_affectionScore);
          _longTermTier = _calculateTier(_longTermScore);
          debugPrint(
            '[ChatService] V2.5 extensions seeded: realism=$_realismEnabled, '
            'bond=$_affectionScore, trust=$_trustLevel, day=$_dayCount, time=$_timeOfDay',
          );

          // Seed initial quest/task as a primary objective
          if (ext.currentTask.isNotEmpty) {
            // Defer so the session ID is ready before the DB write
            Future.microtask(() async {
              await setObjective(ext.currentTask, isPrimary: true);
              debugPrint(
                '[ChatService] V2.5 seeded initial task: ${ext.currentTask}',
              );
            });
          }
        }

        if (_activeCharacter!.firstMessage.isNotEmpty) {
          _messages.add(
            ChatMessage(
              text: _buildFirstMessage(_activeCharacter!),
              sender: _activeCharacter!.name,
              isUser: false,
            ),
          );
          // Scan first message for lore
          _scanLorebook(_messages.last.text);
        }
        // Save the initial message session
        _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
        await _saveChat();
      }
    }
    _isLoadingSession = false;
    notifyListeners();
  }

  /// Enter group chat mode with the given GroupChat definition.
  Future<void> setActiveGroup(GroupChat group) async {
    // Cancel any in-flight generation before switching context AND reset author note for new session context
    await _cancelAndWaitForGeneration();
    _generationEpoch++;

    // Reset author notes when starting fresh chat/group (will be overridden if loading existing session)
    _authorNote = '';
    _authorNoteStrength = 4;

    if (_characterRepository == null) return;

    // Clear 1:1 mode
    _activeCharacter = null;
    debugPrint(
      '[ChatService] 🟡 setActiveGroup: clearing messages '
      '(had ${_messages.length}) for group ${group.name}',
    );
    _messages.clear();
    _currentSessionId = null;
    _isLoadingSession = true;
    _turnIndex = 0;
    _activeGroup = group;
    _observerMode = group.directorMode;
    notifyListeners();

    // Resolve character IDs to cards
    _groupCharacters = group.characterIds
        .map(
          (id) => _characterRepository!.characters
              .where((c) => _getCharacterIdFromCard(c) == id)
              .firstOrNull,
        )
        .whereType<CharacterCard>()
        .toList();

    // Reset all lorebook triggers
    for (final ch in _groupCharacters) {
      if (ch.lorebook != null) {
        for (final entry in ch.lorebook!.entries) {
          entry.isTriggered = false;
        }
      }
      for (final worldName in ch.worldNames) {
        final world = _worldRepository.worlds
            .where((w) => w.name == worldName)
            .firstOrNull;
        if (world != null) {
          for (final entry in world.lorebook.entries) {
            entry.isTriggered = false;
          }
        }
      }
    }

    // Try to load last session for this group
    await _loadLastSession();

    // If no session, create a greeting
    if (_messages.isEmpty && _groupCharacters.isNotEmpty) {
      String greetingText;
      String greetingSender;
      String? greetingCharId;

      if (group.firstMessage.isNotEmpty) {
        // Use custom group first message — attribute to "Narrator" or group name
        greetingText = group.firstMessage;
        greetingSender = group.name;
        greetingCharId = null;
      } else {
        // Fall back to first character's greeting
        final first = _groupCharacters.first;
        greetingText = first.firstMessage.isNotEmpty
            ? _buildFirstMessage(first)
            : '';
        greetingSender = first.name;
        greetingCharId = _getCharacterIdFromCard(first);
      }

      if (greetingText.isNotEmpty) {
        _messages.add(
          ChatMessage(
            text: greetingText,
            sender: greetingSender,
            isUser: false,
            characterId: greetingCharId,
          ),
        );
        _scanLorebook(_messages.last.text);
      }
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      await _saveChat();
    }

    // Load evolved fields for all group characters
    _loadGroupEvolvedFields();

    _isLoadingSession = false;
    notifyListeners();
  }

  /// Fork the current 1:1 chat into a new group chat, copying all messages.
  /// The original 1:1 session remains untouched.
  Future<GroupChat?> forkToGroupChat(
    List<CharacterCard> additionalCharacters,
    GroupChatRepository groupRepo, {
    String? groupName,
    String? scenario,
    TurnOrder turnOrder = TurnOrder.roundRobin,
  }) async {
    if (_isGenerating) return null;
    if (_activeCharacter == null || _characterRepository == null) return null;
    if (_messages.isEmpty) return null;
    if (_db == null) return null;

    final originalCharId = _getCharacterIdFromCard(_activeCharacter!);
    final allCharIds = [
      originalCharId,
      ...additionalCharacters.map(_getCharacterIdFromCard),
    ];

    // Build a default group name
    final name = groupName?.isNotEmpty == true
        ? groupName!
        : [
            _activeCharacter!.name,
            ...additionalCharacters.map((c) => c.name),
          ].join(' & ');

    // Create the group
    final group = GroupChat(
      id: 'group_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      characterIds: allCharIds,
      turnOrder: turnOrder,
      scenario: scenario ?? '',
    );
    await groupRepo.save(group);

    // Create a new session for the group and copy all messages
    final newSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final copiedMessages = <MessagesCompanion>[];
    for (int i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      // Back-fill characterId on AI messages (null in 1:1 mode)
      String? charId = m.characterId;
      if (!m.isUser && charId == null) {
        charId = originalCharId;
      }
      copiedMessages.add(
        MessagesCompanion(
          sessionId: drift.Value(newSessionId),
          position: drift.Value(i),
          sender: drift.Value(m.sender),
          isUser: drift.Value(m.isUser),
          characterId: drift.Value(charId),
          swipes: drift.Value(jsonEncode(m.swipes)),
          swipeIndex: drift.Value(m.swipeIndex),
          swipeDurations: drift.Value(jsonEncode(m.swipeDurations)),
        ),
      );
    }

    // Insert the new session
    await _db!.upsertSession(
      SessionsCompanion.insert(
        id: newSessionId,
        groupId: drift.Value(group.id),
        name: drift.Value(_sessionName),
        description: drift.Value(_sessionDescription),
        authorNote: drift.Value(_authorNote),
        authorNoteDepth: drift.Value(_authorNoteStrength),
        summary: drift.Value(_summary.isEmpty ? null : _summary),
        summaryLastIndex: drift.Value(
          _summaryLastIndex > 0 ? _summaryLastIndex : null,
        ),
        parentSession: drift.Value(_currentSessionId),
        forkIndex: drift.Value(_messages.length - 1),
        trustLevel: drift.Value(_trustLevel),
        activeFixation: drift.Value(_activeFixation),
        fixationLifespan: drift.Value(_fixationLifespan),
        spatialStance: drift.Value(_spatialStance),
        createdAt: drift.Value(DateTime.now()),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );
    if (copiedMessages.isNotEmpty) {
      await _db!.insertMessages(copiedMessages);
    }

    debugPrint(
      '[ChatService] \u{1F500} Forked 1:1 chat to group "${group.name}" '
      '(${_messages.length} messages copied)',
    );

    // Switch to the new group (this loads the session we just created)
    await setActiveGroup(group);

    return group;
  }

  /// Add a character to the currently active group chat.
  Future<bool> addCharacterToGroup(
    CharacterCard character,
    GroupChatRepository groupRepo,
  ) async {
    if (_activeGroup == null || _characterRepository == null) return false;
    if (_isGenerating) return false;
    if (_db == null) return false;

    final charId = _getCharacterIdFromCard(character);
    if (_activeGroup!.characterIds.contains(charId))
      return false; // already in group

    _activeGroup!.characterIds.add(charId);
    await groupRepo.save(_activeGroup!);

    // Re-resolve character cards
    _groupCharacters = _activeGroup!.characterIds
        .map(
          (id) => _characterRepository!.characters
              .where((c) => _getCharacterIdFromCard(c) == id)
              .firstOrNull,
        )
        .whereType<CharacterCard>()
        .toList();

    // Load evolved fields for the new character from the current session's
    // group JSON map columns (if a session is active).
    if (_currentSessionId != null) {
      try {
        final session = await _db!.getSessionById(_currentSessionId!);
        if (session != null) {
          final personalities = _tryParseJsonMap(
            session.groupEvolvedPersonalities,
          );
          final scenarios = _tryParseJsonMap(session.groupEvolvedScenarios);
          _evolvedPersonalities[charId] = personalities[charId] ?? '';
          _evolvedScenarios[charId] = scenarios[charId] ?? '';
          _groupEvolutionCounts[charId] = 0;
        }
      } catch (_) {}
    }

    debugPrint(
      '[ChatService] \u{2795} Added ${character.name} to group ${_activeGroup!.name}',
    );
    notifyListeners();
    return true;
  }

  /// Remove a character from the currently active group chat.
  /// Returns false if the group would have fewer than 2 characters.
  Future<bool> removeCharacterFromGroup(
    CharacterCard character,
    GroupChatRepository groupRepo,
  ) async {
    if (_activeGroup == null || _characterRepository == null) return false;
    if (_isGenerating) return false;
    if (_activeGroup!.characterIds.length <= 2) return false; // enforce minimum

    final charId = _getCharacterIdFromCard(character);
    _activeGroup!.characterIds.remove(charId);
    await groupRepo.save(_activeGroup!);

    // Re-resolve character cards
    _groupCharacters = _activeGroup!.characterIds
        .map(
          (id) => _characterRepository!.characters
              .where((c) => _getCharacterIdFromCard(c) == id)
              .firstOrNull,
        )
        .whereType<CharacterCard>()
        .toList();

    // Clamp turn index to valid range
    if (_groupCharacters.isNotEmpty) {
      _turnIndex = _turnIndex % _groupCharacters.length;
    }

    debugPrint(
      '[ChatService] \u{2796} Removed ${character.name} from group ${_activeGroup!.name}',
    );
    notifyListeners();
    return true;
  }

  /// Returns a stable ID string for a character card.
  String _getCharacterIdFromCard(CharacterCard card) {
    if (card.imagePath != null) {
      return path.basenameWithoutExtension(card.imagePath!);
    }
    return card.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
  }

  String _getCharacterId() {
    if (_activeGroup != null) {
      return 'group_${_activeGroup!.id}';
    }
    if (_activeCharacter == null) return "unknown";
    return _getCharacterIdFromCard(_activeCharacter!);
  }

  /// Helper used when constructing messages.
  String? _getCharacterIdForCard(CharacterCard card) {
    return _getCharacterIdFromCard(card);
  }

  /// Safely parse a JSON string into a mutable Map<String, String>.
  /// Returns an empty map if [json] is null, empty, or invalid.
  Map<String, String> _tryParseJsonMap(String? json) {
    if (json == null || json.isEmpty || json == '{}') return {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        return decoded.map(
          (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
        );
      }
    } catch (_) {}
    return {};
  }

  Future<void> _saveChat() async {
    if ((_activeCharacter == null && _activeGroup == null) ||
        _currentSessionId == null)
      return;

    // ── Safety guard: never overwrite existing session data with empty messages.
    // This prevents data loss if _messages is momentarily empty due to a rebuild
    // race, nav glitch, or any other transient state issue.
    if (_messages.isEmpty) {
      debugPrint(
        '[ChatService] ⚠ _saveChat called with empty messages for '
        'session $_currentSessionId — skipping to protect existing data.',
      );
      return;
    }

    // Snapshot messages at the start so async gaps can't see a mutated list.
    final snapshot = List<ChatMessage>.from(_messages);

    final charId = _getCharacterId();

    // Look up character DB id if in 1:1 mode
    String? characterDbId;
    String? groupDbId;
    if (_activeGroup != null) {
      groupDbId = _activeGroup!.id;
    } else if (_activeCharacter?.dbId != null) {
      characterDbId = _activeCharacter!.dbId;
    }

    // Upsert session (INSERT OR REPLACE to avoid UNIQUE constraint errors)
    final timestamp = int.tryParse(_currentSessionId!) ?? 0;
    final createdAt = timestamp > 0
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : DateTime.now();
    await _db.upsertSession(
      SessionsCompanion.insert(
        id: _currentSessionId!,
        characterId: drift.Value(characterDbId),
        groupId: drift.Value(groupDbId),
        name: drift.Value(_sessionName),
        description: drift.Value(_sessionDescription),
        authorNote: drift.Value(_authorNote),
        authorNoteDepth: drift.Value(_authorNoteStrength),
        summary: drift.Value(_summary.isEmpty ? null : _summary),
        summaryLastIndex: drift.Value(
          _summaryLastIndex > 0 ? _summaryLastIndex : null,
        ),
        parentSession: drift.Value(_parentSessionId),
        forkIndex: drift.Value(_forkIndex),
        affectionScore: drift.Value(_affectionScore),
        relationshipTier: drift.Value(_relationshipTier),
        longTermScore: drift.Value(_longTermScore),
        longTermTier: drift.Value(_longTermTier),
        turnsSinceLongTermCheck: drift.Value(_turnsSinceLongTermCheck),
        shortTermDeltasSummary: drift.Value(_shortTermDeltasSummary),
        realismEnabled: drift.Value(_realismEnabled),
        moodDecayCounter: drift.Value(_moodDecayCounter),
        characterEmotion: drift.Value(_characterEmotion),
        emotionIntensity: drift.Value(_emotionIntensity),
        timeOfDay: drift.Value(_timeOfDay),
        dayCount: drift.Value(_dayCount),
        passageOfTimeEnabled: drift.Value(_passageOfTimeEnabled),
        nsfwCooldownEnabled: drift.Value(_nsfwCooldownEnabled),
        arousalLevel: drift.Value(_arousalLevel),
        cooldownTurnsRemaining: drift.Value(_cooldownTurnsRemaining),
        trustLevel: drift.Value(_trustLevel),
        activeFixation: drift.Value(_activeFixation),
        fixationLifespan: drift.Value(_fixationLifespan),
        spatialStance: drift.Value(_spatialStance),
        chaosModeEnabled: drift.Value(_chaosModeEnabled),
        chaosPressure: drift.Value(_chaosPressure),
        trustRepairPending: drift.Value(_pendingTrustRepair),
        createdAt: drift.Value(createdAt),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    // Per-session generation overrides (v22) — saved via raw SQL so this
    // works even before build_runner regenerates database.g.dart.
    await _db.customUpdate(
      'UPDATE sessions SET generation_settings = ? WHERE id = ?',
      variables: [
        drift.Variable(_sessionGenSettings.toJsonString()),
        drift.Variable(_currentSessionId!),
      ],
      updates: {_db.sessions},
    );

    // Replace all messages for this session using the snapshot
    await _db.deleteMessagesForSession(_currentSessionId!);
    final messageBatch = <MessagesCompanion>[];
    for (int i = 0; i < snapshot.length; i++) {
      final m = snapshot[i];
      messageBatch.add(
        MessagesCompanion(
          sessionId: drift.Value(_currentSessionId!),
          position: drift.Value(i),
          sender: drift.Value(m.sender),
          isUser: drift.Value(m.isUser),
          characterId: drift.Value(m.characterId),
          swipes: drift.Value(jsonEncode(m.swipes)),
          swipeIndex: drift.Value(m.swipeIndex),
          swipeDurations: drift.Value(jsonEncode(m.swipeDurations)),
          metadata: drift.Value(
            m.metadata != null ? jsonEncode(m.metadata) : null,
          ),
          swipeMetadata: drift.Value(
            m.swipeMetadata.any((e) => e != null)
                ? jsonEncode(m.swipeMetadata)
                : null,
          ),
        ),
      );
    }
    if (messageBatch.isNotEmpty) {
      await _db.insertMessages(messageBatch);
    }
  }

  Future<void> _loadLastSession() async {
    if (_activeCharacter == null && _activeGroup == null) return;

    // Get sessions from DB
    List<Session> sessions;
    if (_activeGroup != null) {
      sessions = await _db.getSessionsForGroup(_activeGroup!.id);
    } else if (_activeCharacter?.dbId != null) {
      sessions = await _db.getSessionsForCharacter(_activeCharacter!.dbId!);
    } else {
      return;
    }

    if (sessions.isEmpty) {
      debugPrint('[ChatService] _loadLastSession: No previous sessions found');
      return;
    }

    // Sessions are already sorted descending by createdAt
    final lastSession = sessions.first;
    _currentSessionId = lastSession.id;
    _authorNote = lastSession.authorNote;
    _authorNoteStrength = lastSession.authorNoteDepth;
    _summary = lastSession.summary ?? '';
    _summaryLastIndex = lastSession.summaryLastIndex ?? 0;
    _sessionName = lastSession.name;
    _sessionDescription = lastSession.description;
    _parentSessionId = lastSession.parentSession;
    _forkIndex = lastSession.forkIndex;
    _affectionScore = lastSession.affectionScore;
    _relationshipTier = lastSession.relationshipTier;
    _longTermScore = lastSession.longTermScore;
    _longTermTier = lastSession.longTermTier;
    _turnsSinceLongTermCheck = lastSession.turnsSinceLongTermCheck;
    _shortTermDeltasSummary = lastSession.shortTermDeltasSummary;
    _realismEnabled = lastSession.realismEnabled;
    _moodDecayCounter = lastSession.moodDecayCounter;
     _characterEmotion = lastSession.characterEmotion;
     _emotionIntensity = lastSession.emotionIntensity;
     _timeOfDay = lastSession.timeOfDay;
     _dayCount = lastSession.dayCount;
     _passageOfTimeEnabled =
         lastSession.passageOfTimeEnabled && _storageService.passageOfTimeDefault;
     _nsfwCooldownEnabled = lastSession.nsfwCooldownEnabled;
    _arousalLevel = lastSession.arousalLevel;
    _cooldownTurnsRemaining = lastSession.cooldownTurnsRemaining;
    _trustLevel = lastSession.trustLevel;
    _activeFixation = lastSession.activeFixation;
    _fixationLifespan = lastSession.fixationLifespan;
    debugPrint(
      '[ChatService] _loadLastSession: Loaded session with arousal=$_arousalLevel, fixation=$_activeFixation/$_fixationLifespan',
    );
    _spatialStance = lastSession.spatialStance;
    _pendingTrustRepair = lastSession.trustRepairPending;
    _chaosModeEnabled = lastSession.chaosModeEnabled;
    _chaosPressure = lastSession.chaosPressure;

    // Realism Engine 2.0 Compatibility Migration
    // Old scale was 0-15. New scale is 0-150.
    if (_affectionScore > 0 &&
        _affectionScore <= 15 &&
        _relationshipTier >= 3) {
      _affectionScore = _affectionScore * 10;
      if (_longTermScore == 0) {
        _longTermScore = _affectionScore;
        _longTermTier = _calculateTier(_longTermScore);
      }
      _relationshipTier = _calculateTier(_affectionScore);
      debugPrint(
        '[Realism] Legacy session migrated to REv2 scales (loadLast).',
      );
    }

    // Load per-session evolution (1:1 mode only — group is handled by _loadGroupEvolvedFields)
    if (_activeCharacter != null) {
      final charId = _getCharacterIdFromCard(_activeCharacter!);
      _evolvedPersonalities[charId] = lastSession.evolvedPersonality;
      _evolvedScenarios[charId] = lastSession.evolvedScenario;
      _characterEvolutionCount = lastSession.evolutionCount;
      _groupEvolutionCounts[charId] = lastSession.evolutionCount;
    }

    // Load messages
    try {
      final dbMessages = await _db.getMessagesForSession(_currentSessionId!);
      debugPrint(
        '[ChatService] 🟢 _loadLastSession: loading ${dbMessages.length} '
        'messages for session $_currentSessionId',
      );
      _messages.clear();
      for (final m in dbMessages) {
        List<String> swipes;
        try {
          swipes = List<String>.from(jsonDecode(m.swipes));
        } catch (_) {
          swipes = [''];
        }
        List<int> swipeDurations;
        try {
          swipeDurations = List<int>.from(
            (jsonDecode(m.swipeDurations) as List).map(
              (e) => (e as num).toInt(),
            ),
          );
        } catch (_) {
          swipeDurations = [0];
        }

        _messages.add(
          ChatMessage(
            text: swipes.isNotEmpty ? swipes[m.swipeIndex] : '',
            sender: m.sender,
            isUser: m.isUser,
            characterId: m.characterId,
            swipes: swipes,
            swipeIndex: m.swipeIndex,
            swipeDurations: swipeDurations,
            metadata: m.metadata != null
                ? Map<String, dynamic>.from(jsonDecode(m.metadata!))
                : null,
            swipeMetadata: m.swipeMetadata != null
                ? (jsonDecode(m.swipeMetadata!) as List<dynamic>)
                      .map(
                        (e) => e != null
                            ? Map<String, dynamic>.from(e as Map)
                            : null,
                      )
                      .toList()
                : null,
          ),
        );
      }

      if (_messages.isNotEmpty) {
        _scanLorebook(_messages.last.text);
      }
    } catch (e) {
      print('Error loading chat session: $e');
    }
  }

  /// Get sessions for a given character/group ID without setting it as active.
  Future<List<Map<String, dynamic>>> getSessionsForId(String charId) async {
    // Determine if this is a group or character
    List<Session> dbSessions;
    if (charId.startsWith('group_')) {
      final groupId = charId.replaceFirst('group_', '');
      dbSessions = await _db.getSessionsForGroup(groupId);
    } else {
      // Find character by imagePath basename
      final allChars = await _db.getAllCharacters();
      final match = allChars.where((c) {
        if (c.imagePath == null) return false;
        return path.basenameWithoutExtension(c.imagePath!) == charId;
      }).firstOrNull;
      if (match != null) {
        dbSessions = await _db.getSessionsForCharacter(match.id);
      } else {
        dbSessions = [];
      }
    }

    List<Map<String, dynamic>> sessions = [];
    for (final s in dbSessions) {
      final timestamp = int.tryParse(s.id) ?? 0;
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp);

      // Get message count and preview
      final msgs = await _db.getMessagesForSession(s.id);
      String preview = 'New Conversation';
      if (s.name != null && s.name!.isNotEmpty) {
        preview = s.name!;
      } else if (msgs.length > 1) {
        // Use second message text as preview
        try {
          final swipes = List<String>.from(jsonDecode(msgs[1].swipes));
          preview = swipes.isNotEmpty ? swipes[msgs[1].swipeIndex] : '';
          if (preview.length > 50) preview = '${preview.substring(0, 50)}...';
        } catch (_) {}
      }

      sessions.add({
        'id': s.id,
        'date': date,
        'preview': preview,
        'message_count': msgs.length,
        'user_message_count': msgs.where((m) => m.isUser).length,
        if (s.name != null) 'session_name': s.name,
        if (s.description != null) 'session_description': s.description,
        if (s.parentSession != null) 'parent_session': s.parentSession,
        if (s.forkIndex != null) 'fork_index': s.forkIndex,
      });
    }

    sessions.sort(
      (a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime),
    );
    return sessions;
  }

  Future<List<Map<String, dynamic>>> getSessions() async {
    if (_activeCharacter == null && _activeGroup == null) return [];
    final charId = _getCharacterId();
    return getSessionsForId(charId);
  }

  Future<void> loadSession(String sessionId) async {
    if (_activeCharacter == null && _activeGroup == null) return;

    final session = await _db.getSessionById(sessionId);
    if (session == null) return;

    try {
      final dbMessages = await _db.getMessagesForSession(sessionId);
      debugPrint(
        '[ChatService] 🟢 loadSession: loading ${dbMessages.length} '
        'messages for session $sessionId',
      );
      _messages.clear();
      for (final m in dbMessages) {
        List<String> swipes;
        try {
          swipes = List<String>.from(jsonDecode(m.swipes));
        } catch (_) {
          swipes = [''];
        }
        List<int> swipeDurations;
        try {
          swipeDurations = List<int>.from(
            (jsonDecode(m.swipeDurations) as List).map(
              (e) => (e as num).toInt(),
            ),
          );
        } catch (_) {
          swipeDurations = [0];
        }

        _messages.add(
          ChatMessage(
            text: swipes.isNotEmpty ? swipes[m.swipeIndex] : '',
            sender: m.sender,
            isUser: m.isUser,
            characterId: m.characterId,
            swipes: swipes,
            swipeIndex: m.swipeIndex,
            swipeDurations: swipeDurations,
            metadata: m.metadata != null
                ? Map<String, dynamic>.from(jsonDecode(m.metadata!))
                : null,
            swipeMetadata: m.swipeMetadata != null
                ? (jsonDecode(m.swipeMetadata!) as List<dynamic>)
                      .map(
                        (e) => e != null
                            ? Map<String, dynamic>.from(e as Map)
                            : null,
                      )
                      .toList()
                : null,
          ),
        );
      }

      _currentSessionId = sessionId;
      _authorNote = session.authorNote;
      _authorNoteStrength = session.authorNoteDepth;
      _summary = session.summary ?? '';
      _summaryLastIndex = session.summaryLastIndex ?? 0;
      _sessionName = session.name;
      _sessionDescription = session.description;
      _parentSessionId = session.parentSession;
      _forkIndex = session.forkIndex;
      _affectionScore = session.affectionScore;
      _relationshipTier = session.relationshipTier;
      _longTermScore = session.longTermScore;
      _longTermTier = session.longTermTier;

      // Realism Engine 2.0 Compatibility Migration
      // Old scale was 0-15. New scale is 0-150.
      // If we see an old chat that was Tier 5 but score 15, we scale it to match the new engine.
      if (_affectionScore > 0 &&
          _affectionScore <= 15 &&
          _relationshipTier >= 3) {
        _affectionScore = _affectionScore * 10;
        // Old high-tier bonds convert immediately into solid Long-Term bounds as well.
        if (_longTermScore == 0) {
          _longTermScore = _affectionScore;
          _longTermTier = _calculateTier(_longTermScore);
        }
        _relationshipTier = _calculateTier(_affectionScore);
        debugPrint('[Realism] Legacy session migrated to REv2 scales.');
      }

      _turnsSinceLongTermCheck = session.turnsSinceLongTermCheck;
      _shortTermDeltasSummary = session.shortTermDeltasSummary;
      _realismEnabled = session.realismEnabled;
      _moodDecayCounter = session.moodDecayCounter;
      _characterEmotion = session.characterEmotion;
      _emotionIntensity = session.emotionIntensity;
      _timeOfDay = session.timeOfDay;
      _dayCount = session.dayCount;
      _passageOfTimeEnabled =
          session.passageOfTimeEnabled && _storageService.passageOfTimeDefault;
      _nsfwCooldownEnabled = session.nsfwCooldownEnabled;
      _arousalLevel = session.arousalLevel;
      _cooldownTurnsRemaining = session.cooldownTurnsRemaining;
      _trustLevel = session.trustLevel;
      _activeFixation = session.activeFixation;
      _fixationLifespan = session.fixationLifespan;
      _spatialStance = session.spatialStance;
      _pendingTrustRepair = session.trustRepairPending;

      // Load per-session evolution (1:1 mode only — group handled by _loadGroupEvolvedFields)
      if (_activeCharacter != null) {
        final charId = _getCharacterIdFromCard(_activeCharacter!);
        _evolvedPersonalities[charId] = session.evolvedPersonality;
        _evolvedScenarios[charId] = session.evolvedScenario;
        _characterEvolutionCount = session.evolutionCount;
        _groupEvolutionCounts[charId] = session.evolutionCount;
      }

      // Per-session generation parameter overrides (v22) — loaded via raw SQL
      // so this works even before build_runner regenerates database.g.dart.
      try {
        final genRows = await _db
            .customSelect(
              'SELECT generation_settings FROM sessions WHERE id = ?',
              variables: [drift.Variable(sessionId)],
            )
            .get();
        final genJson = genRows.isNotEmpty
            ? genRows.first.read<String?>('generation_settings')
            : null;
        _sessionGenSettings = ChatGenerationSettings.fromJsonString(genJson);
      } catch (_) {
        _sessionGenSettings = ChatGenerationSettings();
      }

      if (_messages.isNotEmpty) {
        _scanLorebook(_messages.last.text);
      }
      notifyListeners();
    } catch (e) {
      print('Error loading session $sessionId: $e');
    }
  }

  /// Rename a session.
  Future<void> renameSession(String sessionId, String name) async {
    final session = await _db.getSessionById(sessionId);
    if (session == null) return;

    await _db.updateSession(
      SessionsCompanion(
        id: drift.Value(sessionId),
        name: drift.Value(name.isEmpty ? null : name),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    // Update in-memory if this is the current session
    if (sessionId == _currentSessionId) {
      _sessionName = name.isEmpty ? null : name;
      notifyListeners();
    }
  }

  /// Update the description of a session.
  Future<void> updateSessionDescription(
    String sessionId,
    String description,
  ) async {
    final session = await _db.getSessionById(sessionId);
    if (session == null) return;

    await _db.updateSession(
      SessionsCompanion(
        id: drift.Value(sessionId),
        description: drift.Value(description.isEmpty ? null : description),
        updatedAt: drift.Value(DateTime.now()),
      ),
    );

    // Update in-memory if this is the current session
    if (sessionId == _currentSessionId) {
      _sessionDescription = description.isEmpty ? null : description;
      notifyListeners();
    }
  }

  /// Create a new session by forking from message at [messageIndex].
  /// Copies messages 0..messageIndex into a new session and switches to it.
  Future<void> forkFromMessage(int messageIndex) async {
    if ((_activeCharacter == null && _activeGroup == null) ||
        _currentSessionId == null)
      return;
    if (messageIndex < 0 || messageIndex >= _messages.length) return;

    final oldSessionId = _currentSessionId!;
    final forkedMessages = _messages
        .sublist(0, messageIndex + 1)
        .map(
          (m) => ChatMessage(
            text: m.text,
            sender: m.sender,
            isUser: m.isUser,
            characterId: m.characterId,
            swipes: List.from(m.swipes),
            swipeIndex: m.swipeIndex,
            swipeDurations: List.from(m.swipeDurations),
            metadata: m.metadata != null
                ? Map<String, dynamic>.from(m.metadata!)
                : null,
            swipeMetadata: m.swipeMetadata != null
                ? m.swipeMetadata!
                      .map(
                        (e) => e != null ? Map<String, dynamic>.from(e) : null,
                      )
                      .toList()
                : null,
          ),
        )
        .toList();

    debugPrint(
      '[ChatService] 🟡 forkSession: clearing messages for fork at index $messageIndex',
    );
    _messages.clear();
    _messages.addAll(forkedMessages);
    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _parentSessionId = oldSessionId;
    _forkIndex = messageIndex;
    _sessionGenSettings = _sessionGenSettings
        .copy(); // inherit parent's overrides
    _summary = '';
    _summaryLastIndex = 0;

    // Time-Travel Restoration
    if (_messages.isNotEmpty) {
      _restoreRealismStateFromMessage(_messages.last);
    }

    await _saveChat();
    notifyListeners();
  }

  // Import chat from SillyTavern JSON format
  Future<void> importFromSillyTavern(String jsonData) async {
    if (_activeCharacter == null) throw Exception('No active character');

    try {
      final Map<String, dynamic> data = jsonDecode(jsonData);
      final List<dynamic> messages = data['messages'] ?? [];

      debugPrint(
        '[ChatService] 🟡 importFromSillyTavern: clearing messages for import',
      );
      _messages.clear();

      for (final msg in messages) {
        final String name = msg['name'] ?? '';
        final bool isUser = msg['is_user'] ?? false;
        final String text = msg['mes'] ?? '';

        _messages.add(ChatMessage(text: text, sender: name, isUser: isUser));
      }

      // Create new session for imported chat
      _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
      await _saveChat();
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to parse SillyTavern JSON: $e');
    }
  }

  // Export current chat to SillyTavern JSON format
  String? exportToSillyTavern() {
    if (_messages.isEmpty) return null;

    final List<Map<String, dynamic>> messages = _messages.map((msg) {
      return {
        'name': msg.sender,
        'is_user': msg.isUser,
        'mes': msg.text,
        'send_date': DateTime.now().millisecondsSinceEpoch,
      };
    }).toList();

    final Map<String, dynamic> export = {
      'chat_metadata': {'note_prompt': '', 'note_interval': 0},
      'messages': messages,
    };

    return jsonEncode(export);
  }

  Future<void> startNewChat() async {
    if (_activeCharacter == null && _activeGroup == null) return;

    debugPrint(
      '[startNewChat] START: arousal=$_arousalLevel, fixation=$_activeFixation/$_fixationLifespan',
    );

    // Refresh _activeCharacter from the repository so we pick up any edits
    // made in the character editor (personality, description, etc.)
    if (_activeCharacter != null && _characterRepository != null) {
      final freshChar = _characterRepository!.characters
          .cast<CharacterCard?>()
          .firstWhere(
            (c) => c!.dbId == _activeCharacter!.dbId,
            orElse: () => null,
          );
      if (freshChar != null) {
        // Preserve any runtime-loaded extensions if the repository instance lacks them
        final existingExt = _activeCharacter!.frontPorchExtensions;
        final existingRaw = _activeCharacter!.rawExtensions;

        _activeCharacter = freshChar;

        if (existingExt != null && _activeCharacter!.frontPorchExtensions == null) {
          _activeCharacter!.frontPorchExtensions = existingExt;
          _activeCharacter!.rawExtensions = existingRaw;
          debugPrint('[startNewChat] Preserved existing extensions during character refresh');
        } else if (existingExt == null && _activeCharacter!.frontPorchExtensions == null) {
          debugPrint('[startNewChat] DEBUG: existingExt was null AND freshChar had null extensions.');
        }
      } else {
        debugPrint('[startNewChat] DEBUG: freshChar was null (repository lookup failed).');
      }
    }

    // Fallback: If extensions are STILL missing, forcefully reload from PNG.
    // This catches edge cases where repository/memory loses sync with the file.
    if (_activeCharacter != null && _activeCharacter!.frontPorchExtensions == null) {
      debugPrint('[startNewChat] DEBUG: Extensions are missing. Attempting PNG fallback.');
      if (_activeCharacter!.imagePath != null) {
        debugPrint('[startNewChat] DEBUG: Image path exists: ${_activeCharacter!.imagePath}');
        try {
          final v2Service = V2CardService();
          final reloaded = await v2Service.readCard(_activeCharacter!.imagePath!);
          if (reloaded == null) {
             debugPrint('[startNewChat] DEBUG: readCard returned null. Failed to parse PNG.');
          } else if (reloaded.frontPorchExtensions != null) {
            _activeCharacter!.frontPorchExtensions = reloaded.frontPorchExtensions;
            _activeCharacter!.rawExtensions = reloaded.rawExtensions;
            debugPrint('[startNewChat] Force-reloaded frontPorchExtensions from PNG');
          } else {
             debugPrint('[startNewChat] DEBUG: readCard succeeded, BUT reloaded.frontPorchExtensions was NULL! Meaning the PNG file does NOT contain the front_porch extension data.');
          }
        } catch (e) {
          debugPrint('[startNewChat] Force-reload failed with exception: $e');
        }
      } else {
        debugPrint('[startNewChat] DEBUG: Cannot fallback. imagePath is null.');
      }
    }

    debugPrint(
      '[ChatService] 🟡 startNewChat: clearing messages (had ${_messages.length})',
    );
    _messages.clear();
    _greetingIndex = 0;
    _summary = '';
    _summaryLastIndex = 0;

    // Clear objectives for fresh session start
    _activeObjectives = [];
    _messagesSinceLastCheck = 0;

    // Seed Realism Engine state from V2.5 card extensions for 1:1 mode only,
    // ensuring realism settings persist across chat sessions (group mode handled elsewhere)
    if (_activeCharacter != null && _activeGroup == null) {
      final extSeed =
          _activeCharacter!.frontPorchExtensions ?? FrontPorchExtensions();

      _realismEnabled = extSeed.realismEnabled;
      _affectionScore = extSeed.shortTermBond.clamp(-150, 150);
      _longTermScore = extSeed.longTermBond.clamp(-150, 150);
      _trustLevel = extSeed.trustLevel.clamp(-100, 100);
      _dayCount = extSeed.dayCount.clamp(1, 9999);
      _timeOfDay = extSeed.timeOfDay;
      _characterEmotion = extSeed.characterEmotion;
      _emotionIntensity = extSeed.emotionIntensity;
      _nsfwCooldownEnabled = extSeed.nsfwCooldownEnabled;
      // Global setting is a hard ceiling: if the user disabled passage-of-time
      // globally, it stays off regardless of what the character card says.
      _passageOfTimeEnabled =
          extSeed.passageOfTimeEnabled && _storageService.passageOfTimeDefault;
      _chaosModeEnabled = extSeed.chaosModeEnabled;
      if (_activeCharacter!.hasFrontPorchExtensions) {
        // Character has baseline extensions, indicating an ongoing managed relationship where
        // emotional continuity is expected across sessions. Do NOT reset arousal/fixation.
        debugPrint(
          '[startNewChat] Preserving arousal/fixation due to extensions: arousal=$_arousalLevel, fixation=$_activeFixation/$_fixationLifespan',
        );
      } else {
        // Reset arousal/fixation to defaults for fresh chat (not seeded from extensions)
        debugPrint(
          '[startNewChat] Resetting arousal/fixation (was: arousal=$_arousalLevel, fixation=$_activeFixation/$_fixationLifespan)',
        );
        _arousalLevel = 0;
        _fixationLifespan = 0;
        _activeFixation = '';
        _cooldownTurnsRemaining = 0;
        debugPrint(
          '[startNewChat] After reset: arousal=$_arousalLevel, fixation=$_activeFixation/$_fixationLifespan',
        );
      }

      // Recalculate tiers from seeded scores (only needed for realism-enabled chars)
      if (_realismEnabled) {
        _relationshipTier = _calculateTier(_affectionScore);
        _longTermTier = _calculateTier(_longTermScore);
      }

      // Seed initial quest/task as a primary objective
      if (extSeed.currentTask.isNotEmpty) {
        // Defer so the session ID is ready before the DB write
        Future.microtask(() async {
          await setObjective(extSeed.currentTask, isPrimary: true);
          debugPrint(
            '[ChatService] V2.5 seeded initial task: ${extSeed.currentTask}',
          );
        });
      }
    } else {
      // Group mode or no active character: reset to defaults but preserve existing extensions-based values
      _pendingTrustRepair = false;

      if (_activeGroup == null && _messages.isNotEmpty) {
        // Will be populated later with greeting in non-group modes
        // Preserve realism state for proper post-greeting eval (don't reset here)
      } else {
        _affectionScore = 0;
        _trustLevel = 0;
        _relationshipTier = 0;
        _longTermScore = 0;
        _longTermTier = 0;
        // Don't touch dayCount, timeOfDay etc. as they get seeded from extensions or loaded session
      }
    }

    // Clear the in-memory evolution cache so the new session starts with
    // the original (unevolved) personality/scenario. The previous session's
    // evolved data was still live in this map.
    _evolvedPersonalities.clear();
    _evolvedScenarios.clear();
    _groupEvolutionCounts.clear();
    _characterEvolutionCount = 0;

    if (_activeGroup != null && _groupCharacters.isNotEmpty) {
      // Group mode: greeting from first character
      final first = _groupCharacters.first;
      if (first.firstMessage.isNotEmpty) {
        _messages.add(
          ChatMessage(
            text: _buildFirstMessage(first),
            sender: first.name,
            isUser: false,
            characterId: _getCharacterIdFromCard(first),
          ),
        );
        _scanLorebook(_messages.last.text);
      }
      _turnIndex = 0;
    } else if (_activeCharacter != null) {
      // 1:1 mode
      if (_activeCharacter!.firstMessage.isNotEmpty) {
        _messages.add(
          ChatMessage(
            text: _buildFirstMessage(_activeCharacter!),
            sender: _activeCharacter!.name,
            isUser: false,
          ),
        );
        _scanLorebook(_messages.last.text);
      }
    }

    _currentSessionId = DateTime.now().millisecondsSinceEpoch.toString();
    debugPrint(
      '[startNewChat] BEFORE SAVE: arousal=$_arousalLevel, fixation=$_activeFixation/$_fixationLifespan',
    );
    await _saveChat();
    debugPrint(
      '[startNewChat] AFTER SAVE: arousal=$_arousalLevel, fixation=$_activeFixation/$_fixationLifespan',
    );
    notifyListeners();

// ── Post-Greeting Realism Baseline ──────────────────────────────────
    // Always mark that a greeting was placed — even if Realism is currently off.
    // If Realism is already on, fire immediately. Otherwise the flag will be
    // consumed the moment the user enables Realism.
    // Skip if character already has pre-seeded V2.5 extensions — those baseline
    // values are intentional and should not be overwritten by auto-eval.
    if (_activeGroup == null && _messages.isNotEmpty && _activeCharacter!.frontPorchExtensions == null) {
      _greetingEvalPending = true;
      if (_realismEnabled) {
        _runPostGreetingEval();
      }
    }
  }

  /// Evaluates emotion + relationship baseline from the greeting message only.
  /// Runs once per new session, silently in the background.
  Future<void> _runPostGreetingEval() async {
    if (!_realismEnabled || _activeCharacter == null) return;
    _greetingEvalPending = false; // consume the pending flag
    debugPrint('[Realism] Running post-greeting baseline eval...');
    _isProcessingGreeting = true;
    notifyListeners();
    try {
      // KoboldCPP is single-threaded — run evals sequentially to avoid concurrent
      // HTTP requests being dropped before headers are received.
      await _evaluateEmotionalStateCall();
      await _evaluateRelationshipCall();

      // Store initial emotion in metadata on the greeting message itself
      if (_messages.isNotEmpty) {
        _messages.first.activeMetadata ??= {};
        if (_characterEmotion.isNotEmpty) {
          _messages.first.activeMetadata!['emotion_label'] = _characterEmotion;
          _messages.first.activeMetadata!['realism_state'] =
              _captureRealismState();
        }
      }
      await _saveChat();
      notifyListeners();
      debugPrint(
        '[Realism] Post-greeting baseline: emotion=$_characterEmotion, bond=$_affectionScore, trust=$_trustLevel',
      );
    } catch (e) {
      debugPrint('[Realism] Post-greeting eval failed: $e');
    } finally {
      _isProcessingGreeting = false;
      notifyListeners();
    }
  }

  /// Retroactive baseline eval — fires when Realism is enabled mid-conversation
  /// with no prior state captured. Evaluates the full visible message history
  /// so the engine catches up on emotion, bond, and scene state.
  Future<void> _runRetroactiveBaselineEval() async {
    if (!_realismEnabled || _activeCharacter == null) return;
    debugPrint(
      '[Realism] Running retroactive baseline scan (${_messages.length} messages)...',
    );
    _isProcessingGreeting = true; // reuse the greeting overlay
    notifyListeners();
    try {
      if (_storageService.realismOneShotEval) {
        await _evaluateOneShotCall();
      } else {
        // KoboldCPP is single-threaded — run evals sequentially to avoid concurrent
        // HTTP requests being dropped before headers are received.
        await _evaluateRelationshipCall();
        await _evaluateEmotionalStateCall();
        await _evaluatePhysicalStateCall();
        await _evaluateNarrativeCall();
      }

      // Stamp the baseline on the most recent message so it persists
      if (_messages.isNotEmpty) {
        _messages.last.activeMetadata ??= {};
        _messages.last.activeMetadata!['emotion_label'] = _characterEmotion;
        _messages.last.activeMetadata!['realism_state'] =
            _captureRealismState();
      }
      await _saveChat();
      notifyListeners();
      debugPrint(
        '[Realism] Retroactive scan complete: emotion=$_characterEmotion, bond=$_affectionScore, trust=$_trustLevel',
      );
    } catch (e) {
      debugPrint('[Realism] Retroactive baseline scan failed: $e');
    } finally {
      _isProcessingGreeting = false;
      notifyListeners();
    }
  }

  /// Cycle the first message through alternate greetings
  Future<void> cycleGreeting(int direction) async {
    if (_activeCharacter == null || _messages.isEmpty) return;
    final allGreetings = _activeCharacter!.allGreetings;
    if (allGreetings.length <= 1) return;

    _greetingIndex = (_greetingIndex + direction) % allGreetings.length;
    if (_greetingIndex < 0) _greetingIndex += allGreetings.length;

    // Replace the first message text
    final greeting = allGreetings[_greetingIndex];
    _messages[0] = ChatMessage(
      text: _buildFirstMessage(_activeCharacter!, greetingText: greeting),
      sender: _activeCharacter!.name,
      isUser: false,
    );

    await _saveChat();
    notifyListeners();

// Re-run baseline eval for the new greeting (skip pre-seeded V2.5 cards)
if (_realismEnabled && _activeGroup == null && _activeCharacter!.frontPorchExtensions == null) {
  _runPostGreetingEval();
}
  }

  String _buildFirstMessage(CharacterCard character, {String? greetingText}) {
    String msg = greetingText ?? character.firstMessage;
    // Use the robust replacement logic from the model
    return character.replacePlaceholders(
      msg,
      userName: _userPersonaService.persona.name,
    );
  }

  Future<void> sendMessage(String text) async {
    if ((_activeCharacter == null && _activeGroup == null) ||
        text.trim().isEmpty)
      return;
    clearSuggestions();

    // In observer mode, route to sendDirectorNote instead
    if (_observerMode && _activeGroup != null) {
      await sendDirectorNote(text);
      return;
    }

    final senderName = _userPersonaService.persona.name;
    _messages.add(ChatMessage(text: text, sender: senderName, isUser: true));
    await _saveChat();
    notifyListeners();

    // Scan user input for lore keywords
    _scanLorebook(text);

    // ── Clear consumed chaos event from the previous turn ───────────────
    // Only clear if the event was already delivered in a response.
    // This preserves manual-spin events that haven't been used yet.
    if (_chaosEventDelivered) {
      _pendingChaosInjection = null;
      _chaosEventDelivered = false;
    }

    // ── OOC Time-Skip Detection ───────────────────────────────────────────
    if (_realismEnabled && _activeGroup == null) {
      _detectOocTimeSkip(text);
    }

    // ── Chaos Mode: check + pause for wheel if triggered ─────────────────
    if (_chaosModeEnabled &&
        _activeGroup == null &&
        _pendingChaosInjection == null) {
      if (checkAndTickChaosPressure()) {
        // Create a completer so sendMessage pauses here until the wheel resolves
        _chanceTimeCompleter = Completer<void>();
        _chanceTimePendingTrigger = true;
        notifyListeners(); // UI observes this to show the wheel
        // Wait for the user to spin + accept fate (completes in applyChanceTimeResult)
        await _chanceTimeCompleter!.future;
        _chanceTimeCompleter = null;
      }
    }

    // User message counts as a message towards depth
    _decrementLoreDepth();

    // Check objective task completion BEFORE generating response
    // so the AI gets the updated task in its prompt
    await _maybeCheckTaskCompletionSync();

    // Evaluate realism systems before generating response
    if (_realismEnabled && _activeGroup == null) {
      _applyMoodDecay();
      if (_cooldownTurnsRemaining > 0) {
        _cooldownTurnsRemaining--;
      }
      _isEvaluatingRealism = true;
      _realismEvalStreamText = '';
      notifyListeners();

      void handleChunk(String chunk) {
        _realismEvalStreamText += chunk;
        // Debounce: coalesce rapid token arrivals into one rebuild per 150 ms
        _evalChunkTimer?.cancel();
        _evalChunkTimer = Timer(const Duration(milliseconds: 150), () {
          try {
            notifyListeners();
          } catch (_) {
            // Widget was deactivated — timer fired after navigation
          }
        });
      }

      // ── Trust repair intercept ───────────────────────────────────────
      // Each severe drop arms exactly one repair shot. The window is
      // consumed here and resets automatically for the next drop event.
      if (_pendingTrustRepair) {
        _pendingTrustRepair = false; // consume — resets for next drop
        await _evaluateTrustRepairCall(text, onChunk: handleChunk);
      } else {
        final isLocalKobold = _llmProvider == null || _llmProvider!.isLocal;

        if (isLocalKobold) {
          if (_storageService.realismOneShotEval) {
            await _evaluateOneShotCall(onChunk: handleChunk);
          } else {
            // KoboldCPP is single-threaded — run sequentially
            await _evaluateRelationshipCall(onChunk: handleChunk);
            await _evaluateEmotionalStateCall(onChunk: handleChunk);
            await _evaluatePhysicalStateCall(onChunk: handleChunk);
            await _evaluateNarrativeCall(onChunk: handleChunk);
          }
        } else {
          // API (Remote Backends)
          if (_storageService.realismOneShotEval) {
            await _evaluateOneShotCall(onChunk: handleChunk);
          } else {
            // API backends handle concurrent requests fine
            await Future.wait([
              _evaluateRelationshipCall(onChunk: handleChunk),
              _evaluateEmotionalStateCall(onChunk: handleChunk),
              _evaluatePhysicalStateCall(onChunk: handleChunk),
              _evaluateNarrativeCall(onChunk: handleChunk),
            ]);
          }
        }

        // Synthesize metadata after all evals complete
        _pendingRealismMetadata ??= {};
        _pendingRealismMetadata!['emotion_label'] = _characterEmotion;
        _pendingRealismMetadata!['realism_state'] = _captureRealismState();
        debugPrint(
          '[Realism:Metadata] Synthesized metadata before generation: bond_delta=${_pendingRealismMetadata?['bond_delta']}, trust_delta=${_pendingRealismMetadata?['trust_delta']}, keys=${_pendingRealismMetadata?.keys.toList()}',
        );
        _saveChat();
      }

      // Cancel any pending debounce notify before closing the overlay
      _evalChunkTimer?.cancel();
      _evalChunkTimer = null;
      await Future.delayed(const Duration(milliseconds: 500));
      _isEvaluatingRealism = false;
      notifyListeners();
    }

    await _generateResponse(GenerationMode.normal);
  }

  /// Set observer mode on/off.
  void setObserverMode(bool value) {
    _observerMode = value;
    if (!value) {
      _autoPlayActive = false;
    }
    notifyListeners();
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

    _scanLorebook(text);
    _decrementLoreDepth();

    await _generateResponse(GenerationMode.normal);
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
    if (_isGenerating) return; // wait for current generation to finish

    await _generateResponse(GenerationMode.normal);
  }

  Future<void> regenerateLastMessage() async {
    if (_messages.isEmpty || _isGenerating) return;

    // Check if the last message is from the character
    if (!_messages.last.isUser && _messages.last.sender != 'System') {
      // Instead of removing the message, we generate a new swipe
      // Temporarily remove the last message so the prompt doesn't include it
      final lastMsg = _messages.removeLast();
      notifyListeners();

      // Revert realism state from the rejected swipe and re-evaluate
      if (_realismEnabled) {
        // CRITICAL FIX: Find the baseline realism state from the previous accepted message.
        // We want to use the final state of the LAST ACCEPTED character message as our baseline,
        // not just blindly revert deltas and re-evaluate from scratch.
        Map<String, dynamic>? previousMessageState;
        if (_messages.length >= 2) {
          // Look back through messages to find the last bot message before the one we're regenerating
          for (int i = _messages.length - 1; i >= 0; i--) {
            if (!_messages[i].isUser && _messages[i].sender != 'System') {
              final meta = _messages[i].activeMetadata;
              if (meta != null && meta.containsKey('realism_state')) {
                previousMessageState = meta['realism_state'] as Map<String, dynamic>;
                debugPrint(
                  '[Realism:Regen] Found previous accepted message baseline state at message index $i',
                );
                break;
              }
            }
          }
        }

        if (lastMsg.activeMetadata != null) {
          final bondDelta = lastMsg.activeMetadata!['bond_delta'] as int? ?? 0;
          final moodDelta = lastMsg.activeMetadata!['mood_delta'] as int? ?? 0;
          final arousalDelta =
              lastMsg.activeMetadata!['arousal_delta'] as int? ?? 0;
          final trustDelta =
              lastMsg.activeMetadata!['trust_delta'] as int? ?? 0;

          if (bondDelta != 0) {
            _affectionScore = (_affectionScore - bondDelta).clamp(-10, 15);
            if (_affectionScore < 0)
              _relationshipTier = 1;
            else if (_affectionScore <= 3)
              _relationshipTier = 2;
            else if (_affectionScore <= 7)
              _relationshipTier = 3;
            else if (_affectionScore <= 11)
              _relationshipTier = 4;
            else
              _relationshipTier = 5;
          }
          if (moodDelta != 0) {
            _moodDecayCounter = 0;
          }
          if (trustDelta != 0) {
            _trustLevel = (_trustLevel - trustDelta).clamp(-100, 100);
          }

          // Revert climax state if this response triggered refractory cooldown.
          // The climax checker stores the pre-climax arousal so we can restore it.
          final climaxTriggered =
              lastMsg.activeMetadata!['climax_triggered'] as bool? ?? false;
          if (climaxTriggered && _nsfwCooldownEnabled) {
            final preClimaxArousal =
                lastMsg.activeMetadata!['pre_climax_arousal'] as int? ?? 0;
            _arousalLevel = preClimaxArousal;
            _cooldownTurnsRemaining = 0;
            _cooldownTurnsTotal = 0;
            debugPrint(
              '[Realism:Regen] Reverted climax state: arousal restored to $preClimaxArousal, cooldown cleared',
            );
          } else if (arousalDelta != 0 && _nsfwCooldownEnabled) {
            // Normal arousal delta revert (no climax involved)
            _arousalLevel = (_arousalLevel - arousalDelta).clamp(-3, 10);
          }
        }

        // CRITICAL FIX: Restore the baseline state from the previous accepted message.
        // This ensures the new regenerated message is evaluated against the correct baseline,
        // not from scratch which would produce wildly different realism values.
        if (previousMessageState != null) {
          _affectionScore =
              previousMessageState['affectionScore'] as int? ?? _affectionScore;
          _relationshipTier =
              previousMessageState['relationshipTier'] as int? ?? _relationshipTier;
          _longTermScore =
              previousMessageState['longTermScore'] as int? ?? _longTermScore;
          _longTermTier =
              previousMessageState['longTermTier'] as int? ?? _longTermTier;
          _turnsSinceLongTermCheck = previousMessageState[
                  'turnsSinceLongTermCheck'] as int? ??
              _turnsSinceLongTermCheck;
          _shortTermDeltasSummary = previousMessageState[
                  'shortTermDeltasSummary'] as int? ??
              _shortTermDeltasSummary;
          _moodDecayCounter =
              previousMessageState['moodDecayCounter'] as int? ?? _moodDecayCounter;
          _characterEmotion = previousMessageState['characterEmotion'] as String? ??
              _characterEmotion;
          _emotionIntensity = previousMessageState['emotionIntensity'] as String? ??
              _emotionIntensity;
          _timeOfDay = previousMessageState['timeOfDay'] as String? ?? _timeOfDay;
          _dayCount = previousMessageState['dayCount'] as int? ?? _dayCount;
          _arousalLevel =
              previousMessageState['arousalLevel'] as int? ?? _arousalLevel;
          _cooldownTurnsRemaining = previousMessageState[
                  'cooldownTurnsRemaining'] as int? ??
              _cooldownTurnsRemaining;
          _cooldownTurnsTotal = previousMessageState['cooldownTurnsTotal'] as int? ??
              _cooldownTurnsRemaining;
          _trustLevel =
              previousMessageState['trustLevel'] as int? ?? _trustLevel;
          _activeFixation =
              previousMessageState['activeFixation'] as String? ?? _activeFixation;
          _fixationLifespan =
              previousMessageState['fixationLifespan'] as int? ?? _fixationLifespan;
          _spatialStance =
              previousMessageState['spatialStance'] as String? ?? _spatialStance;

          debugPrint(
            '[Realism:Regen] ✓ Restored baseline from previous accepted message: bond=$_affectionScore, emotion=$_characterEmotion, trust=$_trustLevel, arousal=$_arousalLevel',
          );
        } else {
          debugPrint(
            '[Realism:Regen] ⚠ No previous message baseline found, continuing with current reverted state',
          );
        }
        // Set UI streaming state
        _isEvaluatingRealism = true;
        _realismEvalStreamText = '';
        notifyListeners();

        void handleChunk(String chunk) {
          _realismEvalStreamText += chunk;
          // Debounce: coalesce rapid token arrivals into one rebuild per 150 ms
          _evalChunkTimer?.cancel();
          _evalChunkTimer = Timer(const Duration(milliseconds: 150), () {
            try {
              notifyListeners();
            } catch (_) {
              // Widget was deactivated — timer fired after navigation
            }
          });
        }

        if (_storageService.realismOneShotEval) {
          await _evaluateOneShotCall(onChunk: handleChunk);
        } else {
          // KoboldCPP is single-threaded — run evals sequentially to avoid concurrent
          // HTTP requests being dropped before headers are received.
          await _evaluateRelationshipCall(onChunk: handleChunk);
          await _evaluateEmotionalStateCall(onChunk: handleChunk);
          await _evaluatePhysicalStateCall(onChunk: handleChunk);
          await _evaluateNarrativeCall(onChunk: handleChunk);

          _pendingRealismMetadata ??= {};
          _pendingRealismMetadata!['emotion_label'] = _characterEmotion;
          _pendingRealismMetadata!['realism_state'] = _captureRealismState();
          _saveChat();
        }

        // Cancel any pending debounce notify before closing the overlay
        _evalChunkTimer?.cancel();
        _evalChunkTimer = null;
        await Future.delayed(const Duration(milliseconds: 500));
        _isEvaluatingRealism = false;
        notifyListeners();
      }

      // Generate into a new message — it will be appended by _generateResponse
      await _generateResponse(GenerationMode.normal);

      // After generation, merge the new response as a swipe on the original message
      if (_messages.isNotEmpty &&
          !_messages.last.isUser &&
          _messages.last.sender != 'System') {
        final newText = _messages.last.text;
        final newMetadata = _messages.last.activeMetadata;
        _messages.removeLast();
        lastMsg.swipes.add(newText);
        lastMsg.swipeIndex = lastMsg.swipes.length - 1;
        lastMsg.activeMetadata = newMetadata;
        _messages.add(lastMsg);
        await _saveChat();
        notifyListeners();
      }
    }
  }

  /// Navigate swipes on a specific message. direction: -1 = left, +1 = right.
  /// If swiping right past the last swipe on the last bot message, regenerates.
  Future<void> swipeMessage(int messageIndex, int direction) async {
    if (messageIndex < 0 || messageIndex >= _messages.length) return;
    final msg = _messages[messageIndex];
    if (msg.isUser || msg.sender == 'System') return;

    final newIndex = msg.swipeIndex + direction;

    final oldIndex = msg.swipeIndex;

    // Swiping left
    if (direction < 0) {
      if (newIndex >= 0) {
        msg.swipeIndex = newIndex;
        _syncRealismStateForSwipe(msg, oldIndex, newIndex);
        await _saveChat();
        notifyListeners();
      }
      return;
    }

    // Swiping right
    if (newIndex < msg.swipes.length) {
      // Navigate to existing swipe
      msg.swipeIndex = newIndex;
      _syncRealismStateForSwipe(msg, oldIndex, newIndex);
      await _saveChat();
      notifyListeners();
    } else if (messageIndex == _messages.length - 1 && !_isGenerating) {
      // Past last swipe on last message — regenerate
      await regenerateLastMessage();
    }
  }

  void _syncRealismStateForSwipe(ChatMessage msg, int oldIndex, int newIndex) {
    if (!_realismEnabled) return;

    // Natively restore the frozen runtime variables for the selected alternate timeline
    _restoreRealismStateFromMessage(msg);
  }

  Future<void> continueGeneration() async {
    if (_messages.isEmpty || _isGenerating) return;

    // Only continue if the last message is from a bot (non-user, non-system)
    if (!_messages.last.isUser && _messages.last.sender != 'System') {
      await _generateResponse(GenerationMode.continue_);
    }
  }

  Future<void> impersonateUser({
    String prefix = '',
    required Function(String accumulated) onToken,
  }) async {
    if ((_activeCharacter == null && _activeGroup == null) || _isGenerating)
      return;

    _isGenerating = true;
    _cancelRequested = false;
    notifyListeners();

    try {
      final userName = _userPersonaService.persona.name;

      // Determine the speaking character (needed for prompt construction)
      CharacterCard speakingCharacter;
      if (_activeGroup != null) {
        speakingCharacter = _groupCharacters.first;
      } else {
        speakingCharacter = _activeCharacter!;
      }

      // Build prompt the same way _generateResponse does
      final String systemPrompt;
      if (_activeGroup != null && _activeGroup!.systemPrompt.isNotEmpty) {
        systemPrompt = _activeGroup!.systemPrompt;
      } else if (_activeGroup != null) {
        systemPrompt = _observerMode
            ? observerModeSystemPrompt
            : defaultGroupSystemPrompt;
      } else if (speakingCharacter.systemPrompt.isNotEmpty) {
        systemPrompt = speakingCharacter.systemPrompt;
      } else if (_storageService.systemPrompt.isNotEmpty) {
        systemPrompt = _storageService.systemPrompt;
      } else {
        final isApi = _llmProvider != null && !_llmProvider!.isLocal;
        systemPrompt = isApi
            ? defaultApiSystemPrompt
            : defaultKoboldSystemPrompt;
      }

      // Lorebook
      String loreContent = '';
      List<String> activeLoreStrings = [];
      final loreCharacters = _activeGroup != null
          ? _groupCharacters
          : [_activeCharacter!];
      for (final ch in loreCharacters) {
        if (ch.lorebook != null) {
          final activeEntries = ch.lorebook!.entries.where(
            (e) => e.enabled && (e.isTriggered || e.constant),
          );
          activeLoreStrings.addAll(activeEntries.map((e) => e.content));
        }
        for (final worldName in ch.worldNames) {
          final world = _worldRepository.worlds
              .where((w) => w.name == worldName)
              .firstOrNull;
          if (world == null) continue;
          final activeWorldEntries = world.lorebook.entries.where(
            (e) => e.enabled && (e.isTriggered || e.constant),
          );
          activeLoreStrings.addAll(activeWorldEntries.map((e) => e.content));
        }
      }
      if (activeLoreStrings.isNotEmpty) {
        loreContent = "Context Info:\n${activeLoreStrings.join('\n')}\n";
        loreContent = speakingCharacter.replacePlaceholders(
          loreContent,
          userName: userName,
        );
      }

      // Persona & scenario
      // Use evolved versions if character evolution is enabled and available
      String personaBlock;
      if (_activeGroup != null) {
        final personas = _groupCharacters
            .map(
              (ch) =>
                  "${ch.name}'s Persona: ${ch.replacePlaceholders(_getEffectivePersonality(ch), userName: userName)}",
            )
            .toList();
        personaBlock = personas.join('\n');
      } else {
        personaBlock =
            "${speakingCharacter.name}'s Persona: ${speakingCharacter.replacePlaceholders(_getEffectivePersonality(speakingCharacter), userName: userName)}";
      }

      // User persona — inject user's self-description + learned facts
      final userPersonaBlock = await _buildUserPersonaBlock(userName);

      String rawScenario = '';
      if (_activeGroup != null && _activeGroup!.scenario.isNotEmpty) {
        rawScenario = _activeGroup!.scenario;
      } else {
        final scenarioChar = _activeGroup != null
            ? _groupCharacters.first
            : speakingCharacter;
        rawScenario = _getEffectiveScenario(scenarioChar);
      }
      final scenario = speakingCharacter.replacePlaceholders(
        rawScenario,
        userName: userName,
      );

      String history = _buildChatHistory();

      // Suffix: user name + any partial text the user typed
      String suffix = "\n$userName:";
      if (prefix.isNotEmpty) {
        suffix = "$suffix $prefix";
      }

      String mesExampleBlock = '';
      if (_activeGroup != null) {
        final examples = _groupCharacters
            .where((ch) => ch.mesExample.isNotEmpty)
            .map(
              (ch) => ch.replacePlaceholders(ch.mesExample, userName: userName),
            )
            .toList();
        if (examples.isNotEmpty) {
          mesExampleBlock = '${examples.join('\n')}\n';
        }
      } else if (speakingCharacter.mesExample.isNotEmpty) {
        mesExampleBlock =
            '${speakingCharacter.replacePlaceholders(speakingCharacter.mesExample, userName: userName)}\n';
      }

      String postHistoryBlock = '';
      if (speakingCharacter.postHistoryInstructions.isNotEmpty) {
        postHistoryBlock =
            '${speakingCharacter.replacePlaceholders(speakingCharacter.postHistoryInstructions, userName: userName)}\n';
      }

      String authorNoteBlock = '';
      if (_authorNote.isNotEmpty) {
        authorNoteBlock = _buildAuthorNoteBlock();
      }

      // Impersonate instruction — comprehensive guidance for writing as the user
      final impersonateInstruction =
          '[System: You are now writing as $userName (the user), NOT as ${speakingCharacter.name} or any other character. '
          'Compose $userName\'s next message in first person. '
          'Match $userName\'s established voice, personality, and writing style from the conversation so far. '
          'Write only $userName\'s words and actions — never narrate for ${speakingCharacter.name} or other characters. '
          'Do not include meta-commentary, stage directions for others, or break the fourth wall. '
          'Keep the response natural, and consistent with the scene.]\n';

      // ── Context Shift: budget-aware history trimming ──
      final fixedContent =
          "$systemPrompt\n"
          "$loreContent"
          "$personaBlock\n"
          "$userPersonaBlock"
          "Scenario: $scenario\n"
          "$mesExampleBlock"
          "<START>\n"
          "$postHistoryBlock"
          "$authorNoteBlock"
          "$impersonateInstruction"
          "$suffix";
      final fixedTokens = await _countTokens(fixedContent);
      final contextBudget = _sessionGenSettings.resolveContextSize(
        _storageService,
      );
      final generationReserve =
          _sessionGenSettings.resolveMaxLength(_storageService) + 50;
      final historyBudget = contextBudget - fixedTokens - generationReserve;

      if (historyBudget > 0) {
        final result = await _buildChatHistoryWithBudget(historyBudget);
        history = result.history;
      } else if (_messages.isNotEmpty) {
        final lastMsg = _messages.last;
        history = lastMsg.characterId == '__director__'
            ? '[Director: ${lastMsg.text}]'
            : '${lastMsg.sender}: ${lastMsg.text}';
      }

      final prompt =
          "$systemPrompt\n"
          "$loreContent"
          "$personaBlock\n"
          "$userPersonaBlock"
          "Scenario: $scenario\n"
          "$mesExampleBlock"
          "<START>\n"
          "$history"
          "$postHistoryBlock"
          "$authorNoteBlock"
          "$impersonateInstruction"
          "$suffix";

      // Stop sequences: character names only (not user — we ARE the user)
      final g = _sessionGenSettings;
      final stopSequences = {
        ...g.resolveStopSequences(_storageService).toSet(),
      };
      if (_activeGroup != null) {
        for (final ch in _groupCharacters) {
          stopSequences.add('\n${ch.name}:');
        }
      } else {
        stopSequences.add('\n${_activeCharacter!.name}:');
      }

      final llmService = _llmProvider?.activeService ?? _koboldService;
      final genParams = GenerationParams(
        prompt: prompt,
        maxLength: g.resolveMaxLength(_storageService),
        minLength: g.resolveMinLength(_storageService),
        minP: g.resolveMinP(_storageService),
        temperature: g.resolveTemperature(_storageService),
        repeatPenalty: g.resolveRepeatPenalty(_storageService),
        repPenTokens: g.resolveRepeatPenaltyTokens(_storageService),
        dynatempRange: g.resolveDynamicTempEnabled(_storageService)
            ? g.resolveDynamicTempRange(_storageService)
            : null,
        xtcThreshold: g.resolveXtcThreshold(_storageService),
        xtcProbability: g.resolveXtcProbability(_storageService),
        stopSequences: stopSequences.toList(),
        reasoningEnabled: false,
        reasoningEffort: g.resolveReasoningEffort(_storageService),
        bannedPhrases: g.resolveBannedPhrases(_storageService).isNotEmpty
            ? g.resolveBannedPhrases(_storageService)
            : null,
      );

      final stream = llmService.generateStream(genParams);
      String accumulated = prefix;
      bool inThinkBlock = false;

      await for (final token in stream) {
        if (_cancelRequested) break;
        // Filter out <think>...</think> reasoning blocks entirely
        if (token.contains('<think>')) {
          inThinkBlock = true;
          continue;
        }
        if (token.contains('</think>')) {
          inThinkBlock = false;
          continue;
        }
        if (inThinkBlock) continue;
        accumulated += token;
        onToken(accumulated);
      }
    } catch (e) {
      print('Impersonate error: $e');
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  /// Trigger the next character to speak in group mode.
  Future<void> triggerNextCharacter() async {
    if (_activeGroup == null || _groupCharacters.isEmpty || _isGenerating)
      return;
    await _generateResponse(GenerationMode.normal);
  }

  /// Manually select which character speaks next in group mode.
  void setNextCharacter(CharacterCard character) {
    if (_activeGroup == null) return;
    final idx = _groupCharacters.indexWhere((c) => c.name == character.name);
    if (idx >= 0) {
      _turnIndex = idx;
      notifyListeners();
    }
  }

  /// Pick which character speaks next based on turn order.
  CharacterCard _pickNextGroupCharacter() {
    if (_activeGroup!.turnOrder == TurnOrder.random) {
      return _groupCharacters[Random().nextInt(_groupCharacters.length)];
    }
    // Round robin
    final char = _groupCharacters[_turnIndex % _groupCharacters.length];
    _turnIndex++;
    return char;
  }

  Future<void> _generateResponse(GenerationMode mode) async {
    final epoch = ++_generationEpoch;
    _isGenerating = true;
    _generationProgress = 0.0;
    _tokensGenerated = 0;
    _maxTokens = _sessionGenSettings.resolveMaxLength(_storageService);
    _generationStartTime = DateTime.now();
    _isBuffering = true;
    _generationPhase = GenerationPhase.preparing;
    _prefillStartTime = null;
    _lastPerfData = null;
    _sentenceBuffer = '';
    notifyListeners();

    // Track original model for call mode swap/restore (needs to be outside try/catch)
    String? _originalModelName;

    try {
      final userName = _userPersonaService.persona.name;

      // Determine the speaking character first (needed for system prompt priority)
      CharacterCard speakingCharacter;
      if (_activeGroup != null) {
        speakingCharacter =
            (mode == GenerationMode.continue_ &&
                _messages.isNotEmpty &&
                !_messages.last.isUser)
            ? _groupCharacters.firstWhere(
                (c) => c.name == _messages.last.sender,
                orElse: () => _pickNextGroupCharacter(),
              )
            : _pickNextGroupCharacter();
      } else {
        speakingCharacter = _activeCharacter!;
      }

      // ── System prompt selection ──
      // Priority: group custom > group default > character > user global > backend default
      String systemPrompt;
      if (_activeGroup != null && _activeGroup!.systemPrompt.isNotEmpty) {
        // User wrote a custom group system prompt — use it
        systemPrompt = _activeGroup!.systemPrompt;
      } else if (_activeGroup != null) {
        // Group mode, no custom prompt — use observer or default
        systemPrompt = _observerMode
            ? observerModeSystemPrompt
            : defaultGroupSystemPrompt;
      } else if (speakingCharacter.systemPrompt.isNotEmpty) {
        // Character has its own system prompt — use it
        systemPrompt = speakingCharacter.systemPrompt;
      } else if (_storageService.systemPrompt.isNotEmpty) {
        // Single-char mode with a user-defined global prompt — respect it
        systemPrompt = _storageService.systemPrompt;
      } else {
        // Single-char mode, no user prompt — pick default based on backend
        final isApi = _llmProvider != null && !_llmProvider!.isLocal;
        systemPrompt = isApi
            ? defaultApiSystemPrompt
            : defaultKoboldSystemPrompt;
      }

      // In call mode, inject voice-specific instructions for natural conversation
      if (_callMode && _storageService.callSystemPrompt.isNotEmpty) {
        systemPrompt +=
            '\n\n[Voice Call Mode] ${_storageService.callSystemPrompt}';
      }

      // Build Lorebook content from all relevant characters
      String loreContent = '';
      List<String> activeLoreStrings = [];

      final loreCharacters = _activeGroup != null
          ? _groupCharacters
          : [_activeCharacter!];
      for (final ch in loreCharacters) {
        if (ch.lorebook != null) {
          final activeEntries = ch.lorebook!.entries.where(
            (e) => e.enabled && (e.isTriggered || e.constant),
          );
          activeLoreStrings.addAll(activeEntries.map((e) => e.content));
        }
        for (final worldName in ch.worldNames) {
          final world = _worldRepository.worlds
              .where((w) => w.name == worldName)
              .firstOrNull;
          if (world == null) continue;
          final activeWorldEntries = world.lorebook.entries.where(
            (e) => e.enabled && (e.isTriggered || e.constant),
          );
          activeLoreStrings.addAll(activeWorldEntries.map((e) => e.content));
        }
      }

      if (activeLoreStrings.isNotEmpty) {
        loreContent = "Context Info:\n${activeLoreStrings.join('\n')}\n";
      }

      // Apply replacements to lore content
      if (loreContent.isNotEmpty) {
        loreContent = speakingCharacter.replacePlaceholders(
          loreContent,
          userName: userName,
        );
      }

      // Build persona block(s)
      String personaBlock;
      if (_activeGroup != null) {
        personaBlock = _groupCharacters
            .map((ch) {
              final persona = ch.replacePlaceholders(
                _getEffectivePersonality(ch),
                userName: userName,
              );
              return "${ch.name}'s Persona: $persona";
            })
            .join('\n');
      } else {
        personaBlock =
            "${speakingCharacter.name}'s Persona: ${speakingCharacter.replacePlaceholders(_getEffectivePersonality(speakingCharacter), userName: userName)}";
      }

      // User persona — inject user's self-description + learned facts
      final userPersonaBlock = await _buildUserPersonaBlock(userName);

      // Scenario — use group scenario override if set, else first character
      final String rawScenario;
      if (_activeGroup != null && _activeGroup!.scenario.isNotEmpty) {
        rawScenario = _activeGroup!.scenario;
      } else {
        final scenarioChar = _activeGroup != null
            ? _groupCharacters.first
            : speakingCharacter;
        rawScenario = _getEffectiveScenario(scenarioChar);
      }
      final scenario = speakingCharacter.replacePlaceholders(
        rawScenario,
        userName: userName,
      );

      String suffix = "";

      if (mode == GenerationMode.normal) {
        suffix = "\n${speakingCharacter.name}:";
      } else if (mode == GenerationMode.impersonate) {
        suffix = "\n${userName}:";
      } else if (mode == GenerationMode.continue_) {
        // Suffix will be set after history is built — see below
        suffix = "";
      }

      // Build example dialogues block
      String mesExampleBlock = '';
      if (_activeGroup != null) {
        final examples = _groupCharacters
            .where((ch) => ch.mesExample.isNotEmpty)
            .map(
              (ch) => ch.replacePlaceholders(ch.mesExample, userName: userName),
            )
            .toList();
        if (examples.isNotEmpty) {
          mesExampleBlock = '${examples.join('\n')}\n';
        }
      } else if (speakingCharacter.mesExample.isNotEmpty) {
        mesExampleBlock =
            '${speakingCharacter.replacePlaceholders(speakingCharacter.mesExample, userName: userName)}\n';
      }

      // Build post-history instructions block
      String postHistoryBlock = '';
      if (speakingCharacter.postHistoryInstructions.isNotEmpty) {
        postHistoryBlock =
            '${speakingCharacter.replacePlaceholders(speakingCharacter.postHistoryInstructions, userName: userName)}\n';
      }

      // Author's note — placed right before the character speaks for maximum influence
      String authorNoteBlock = '';
      if (_authorNote.isNotEmpty) {
        authorNoteBlock = _buildAuthorNoteBlock();
      }

      // Build summary block if available
      String summaryBlock = '';
      if (_summary.isNotEmpty) {
        summaryBlock = '[Summary of events so far: $_summary]\n';
      }

      // ── Continue mode: remove the last message from history ──
      // For continue mode, we exclude the last message from the chat history
      // and place it as the prompt suffix so the LLM continues from it naturally.
      ChatMessage? _continuePoppedMessage;
      if (mode == GenerationMode.continue_ && _messages.isNotEmpty) {
        _continuePoppedMessage = _messages.removeLast();
        // Set the suffix to the last message text so the LLM continues from it
        suffix =
            "\n${_continuePoppedMessage.sender}: ${_continuePoppedMessage.text}";
      }

      String history = _buildChatHistory();

      // ── Context Shift: budget-aware history trimming ──

      // Realism injection blocks — compute early so they're in the token budget
      String realismBlock = '';
      if (_realismEnabled && _activeGroup == null) {
        final relationship = _getRelationshipInjection();
        final emotion = _getEmotionInjection();
        final time = _getTimeInjection();
        final trustBehavior = _getTrustBehaviorInjection();
        final cooldown = _getNsfwCooldownInjection();
        final behavioral = _getBehavioralMechanicsInjection();
        realismBlock =
            '$relationship$emotion$time$trustBehavior$cooldown$behavioral';
      }

      // Chance Time injection — independent of realism mode
      final chanceTimeBlock = _getChanceTimeInjection();

      // Objective injection — always injected regardless of realism mode
      // Must sit in a fixed prompt section so it is NEVER trimmed by the budget system.
      final objectiveBlock = _getObjectiveInjection();

      // Calculate token cost of all fixed sections to determine chat history budget
      final fixedContent =
          "$systemPrompt\n"
          "$loreContent"
          "$personaBlock\n"
          "$userPersonaBlock"
          "Scenario: $scenario\n"
          "$mesExampleBlock"
          "<START>\n"
          "$summaryBlock"
          "$postHistoryBlock"
          "$authorNoteBlock"
          "$objectiveBlock"
          "$realismBlock"
          "$suffix"
          "$chanceTimeBlock";
      final fixedTokens = await _countTokens(fixedContent);
      final contextBudget = _sessionGenSettings.resolveContextSize(
        _storageService,
      );
      final generationReserve =
          _sessionGenSettings.resolveMaxLength(_storageService) +
          50; // +50 safety margin
      final historyBudget = contextBudget - fixedTokens - generationReserve;

      int droppedMessages = 0;
      if (historyBudget > 0) {
        final result = await _buildChatHistoryWithBudget(historyBudget);
        history = result.history;
        droppedMessages = result.droppedCount;
      }
      // If budget is zero or negative, fixed sections already fill the context — use minimal history
      if (historyBudget <= 0 && _messages.isNotEmpty) {
        // Include at least the last message for continuity
        final lastMsg = _messages.last;
        history = lastMsg.characterId == '__director__'
            ? '[Director: ${lastMsg.text}]'
            : '${lastMsg.sender}: ${lastMsg.text}';
        droppedMessages = _messages.length - 1;
      }

      // ── Restore the popped continue message back into the list ──
      if (_continuePoppedMessage != null) {
        _messages.add(_continuePoppedMessage);
      }

      // ── RAG Memory Retrieval ──
      // When messages are dropped from context, search for relevant past memories
      String memoriesBlock = '';
      if (droppedMessages > 0 &&
          _memoryService != null &&
          _storageService.ragEnabled) {
        debugPrint(
          '[RAG:Chat] ── Prompt assembly: $droppedMessages messages dropped, triggering retrieval ──',
        );
        try {
          // Use last 3 messages as the query
          final queryMessages = _messages.reversed
              .take(3)
              .map((m) => '${m.sender}: ${m.displayText}')
              .join('\n');

          final sourceIds = await _getMemorySourceIds();
          debugPrint('[RAG:Chat] Memory source IDs: $sourceIds');

          final memories = await _memoryService!.retrieve(
            queryText: queryMessages,
            sourceCharacterIds: sourceIds,
            currentSessionId: _currentSessionId ?? '',
            inContextStart:
                droppedMessages, // only search messages that are out of context
            limit: _storageService.ragRetrievalCount == 0
                ? 9999
                : _storageService.ragRetrievalCount,
          );

          if (memories.isNotEmpty) {
            // Cap memory injection to ~30% of the total context budget
            final contextSize = _storageService.contextSize;
            final memoryBudget = (contextSize * 0.30).round();
            final includedMemories = <String>[];
            int usedTokens = 0;
            for (final m in memories) {
              final memTokens = (m.content.length / 4).ceil();
              if (usedTokens + memTokens > memoryBudget &&
                  includedMemories.isNotEmpty) {
                debugPrint(
                  '[RAG:Chat] ⚠ Trimmed ${memories.length - includedMemories.length} memories to fit budget ($memoryBudget tokens)',
                );
                break;
              }
              usedTokens += memTokens;
              includedMemories.add('- ${m.content}');
            }
            if (includedMemories.isNotEmpty) {
              memoriesBlock =
                  '[Relevant memories from past conversations:\n${includedMemories.join('\n')}]\n';
              debugPrint(
                '[RAG:Chat] ✅ Injecting ${includedMemories.length}/${memories.length} memories (~$usedTokens tokens, budget: $memoryBudget)',
              );
            }
          } else {
            debugPrint('[RAG:Chat] No relevant memories found for this turn');
          }
        } catch (e) {
          debugPrint('[RAG:Chat] ✗ RAG retrieval failed: $e');
        }
      } else if (droppedMessages > 0 && _storageService.ragEnabled) {
        debugPrint(
          '[RAG:Chat] ⚠ $droppedMessages messages dropped but RAG not operational (service=${_memoryService != null}, operational=${_memoryService?.isOperational ?? false})',
        );
      }

      // Realism injection was already computed above for budget

      // For chat APIs (OpenRouter, LM Studio), separate the system prompt
      // so it can be sent as a proper 'system' role message.
      final isRemoteApi = _llmProvider != null && !_llmProvider!.isLocal;
      final chatSystemPrompt = isRemoteApi
          ? "$systemPrompt\n$loreContent$personaBlock\n$userPersonaBlock"
                "Scenario: $scenario\n$mesExampleBlock"
          : null;

      final prompt = isRemoteApi
          ? "<START>\n"
                "$summaryBlock"
                "$memoriesBlock"
                "$history"
                "$postHistoryBlock"
                "$authorNoteBlock"
                "$objectiveBlock"
                "$realismBlock"
                "$suffix"
                "$chanceTimeBlock"
          : "$systemPrompt\n"
                "$loreContent"
                "$personaBlock\n"
                "$userPersonaBlock"
                "Scenario: $scenario\n"
                "$mesExampleBlock"
                "<START>\n"
                "$summaryBlock"
                "$memoriesBlock"
                "$history"
                "$postHistoryBlock"
                "$authorNoteBlock"
                "$objectiveBlock"
                "$realismBlock"
                "$suffix"
                "$chanceTimeBlock";

      // Track prompt budget for context viewer (always show full prompt)
      _lastAssembledPrompt = chatSystemPrompt != null
          ? '$chatSystemPrompt\n$prompt'
          : prompt;
      _lastPromptBudget = {
        'System Prompt': (systemPrompt.length / 4).ceil(),
        'Lorebook': (loreContent.length / 4).ceil(),
        'Persona': (personaBlock.length / 4).ceil(),
        'Scenario': ('Scenario: $scenario'.length / 4).ceil(),
        'Examples': (mesExampleBlock.length / 4).ceil(),
        'Summary': (summaryBlock.length / 4).ceil(),
        'Retrieved Memories': (memoriesBlock.length / 4).ceil(),
        'Chat History': (history.length / 4).ceil(),
        'Post-History': (postHistoryBlock.length / 4).ceil(),
        'Author\'s Note': (authorNoteBlock.length / 4).ceil(),
        'Objectives': (objectiveBlock.length / 4).ceil(),
        'Realism Mode': (realismBlock.length / 4).ceil(),
        if (droppedMessages > 0) 'Dropped Messages': droppedMessages,
      };
      // Remove zero-value entries
      _lastPromptBudget.removeWhere((_, v) => v == 0);

      // Stop sequences: include character names, and user name (except when impersonating)
      final g2 = _sessionGenSettings;
      final stopSequences = {
        ...g2.resolveStopSequences(_storageService).toSet(),
      };

      // In impersonate mode the model IS the user, so don't stop on user name
      if (mode != GenerationMode.impersonate) {
        stopSequences.add('\nUser:');
        stopSequences.add('\n${_userPersonaService.persona.name}:');
      }
      if (_activeGroup != null) {
        for (final ch in _groupCharacters) {
          stopSequences.add('\n${ch.name}:');
        }
      } else {
        stopSequences.add('\n${_activeCharacter!.name}:');
      }
      final stopList = stopSequences.toList();

      // Get the active LLM service (local or remote)
      final llmService = _llmProvider?.activeService ?? _koboldService;

      // For call mode with a dedicated call model, temporarily swap the model
      if (_callMode &&
          _storageService.callModelName.isNotEmpty &&
          _llmProvider != null &&
          !_llmProvider!.isLocal) {
        _originalModelName = _llmProvider!.openRouterService.modelName;
        _llmProvider!.openRouterService.configure(
          modelName: _storageService.callModelName,
        );
      }

      final genParams = GenerationParams(
        prompt: prompt,
        systemPrompt: chatSystemPrompt,
        maxLength: g2.resolveMaxLength(_storageService),
        minLength: g2.resolveMinLength(_storageService),
        minP: g2.resolveMinP(_storageService),
        temperature: g2.resolveTemperature(_storageService),
        repeatPenalty: g2.resolveRepeatPenalty(_storageService),
        repPenTokens: g2.resolveRepeatPenaltyTokens(_storageService),
        dynatempRange: g2.resolveDynamicTempEnabled(_storageService)
            ? g2.resolveDynamicTempRange(_storageService)
            : null,
        xtcThreshold: g2.resolveXtcThreshold(_storageService),
        xtcProbability: g2.resolveXtcProbability(_storageService),
        stopSequences: stopList,
        reasoningEnabled: (_callMode || mode == GenerationMode.continue_)
            ? false
            : g2.resolveReasoningEnabled(_storageService),
        reasoningEffort: g2.resolveReasoningEffort(_storageService),
        bannedPhrases: g2.resolveBannedPhrases(_storageService).isNotEmpty
            ? g2.resolveBannedPhrases(_storageService)
            : null,
      );

      // Get streaming response from whichever backend is active
      final stream = llmService.generateStream(genParams);

      // ── Phase: Prefilling ──
      // The HTTP request is now in flight. For KoboldCPP, the model is
      // processing the prompt (prefill/eval). No tokens arrive until
      // prefill finishes. Poll /api/extra/perf for real-time status.
      _generationPhase = GenerationPhase.prefilling;
      _prefillStartTime = DateTime.now();
      _prefillPromptTokens = (prompt.length / 4).ceil(); // Rough placeholder
      notifyListeners();

      // If using local KoboldCPP, poll /api/extra/perf during prefill
      // to get real prompt processing metrics.
      Timer? _perfPoller;
      final isLocalBackend = _llmProvider == null || _llmProvider!.isLocal;
      if (isLocalBackend) {
        // Get REAL token count from the model's tokenizer (async, updates UI when done)
        _koboldService.countTokens(prompt).then((realCount) {
          if (_generationPhase == GenerationPhase.prefilling && realCount > 0) {
            _prefillPromptTokens = realCount;
            debugPrint(
              '[Prefill] Actual token count from tokenizer: $realCount (was ~${(prompt.length / 4).ceil()} est)',
            );
            notifyListeners();
          }
        });

        _perfPoller = Timer.periodic(const Duration(seconds: 2), (_) async {
          if (_generationPhase != GenerationPhase.prefilling) {
            _perfPoller?.cancel();
            _perfPoller = null;
            return;
          }
          final perf = await _koboldService.fetchPerf();
          if (perf != null) {
            _lastPerfData = perf;
            notifyListeners();
          }
        });
      }

      String accumulatedResponse = "";
      bool stopFound = false;
      _tokenBuffer.clear();
      _displayedTokenCount = 0;
      _tokenTimestamps.clear();
      bool streamDone = false;
      DateTime? _thinkStartTime;
      bool _thinkStarted = false;
      bool _thinkEnded = false;

      // Determine message identity
      String originalText = '';
      String targetSender;
      bool isUserTarget;

      if (mode == GenerationMode.continue_) {
        originalText = _messages.last.text;
        targetSender = _messages.last.sender;
        isUserTarget = _messages.last.isUser;
        // Merge metadata if continuing
        if (_pendingRealismMetadata != null) {
          _messages.last.activeMetadata ??= {};
          _messages.last.activeMetadata!.addAll(_pendingRealismMetadata!);
          _pendingRealismMetadata = null;
        }
      } else {
        targetSender = mode == GenerationMode.normal
            ? speakingCharacter.name
            : _userPersonaService.persona.name;
        isUserTarget = mode == GenerationMode.impersonate;
        final initialMetadata = _pendingRealismMetadata != null
            ? Map<String, dynamic>.from(_pendingRealismMetadata!)
            : null;
        debugPrint(
          '[Realism:Metadata] Attaching to new message: bond_delta=${initialMetadata?['bond_delta']}, keys=${initialMetadata?.keys.toList()}',
        );
        _messages.add(
          ChatMessage(
            text: "",
            sender: targetSender,
            isUser: isUserTarget,
            characterId: mode == GenerationMode.normal
                ? _getCharacterIdForCard(speakingCharacter)
                : null,
            metadata: initialMetadata,
            swipeMetadata: initialMetadata != null ? [initialMetadata] : null,
          ),
        );
        _pendingRealismMetadata = null;
      }

      // Helper to update the visible message from buffer
      void _flushBufferToDisplay() {
        if (epoch != _generationEpoch) return; // stale generation
        if (_tokenBuffer.isEmpty && _displayedTokenCount == 0) return;
        // Build displayed text from all tokens up to _displayedTokenCount
        final displayTokens = _tokenBuffer.take(_displayedTokenCount).join();
        String displayText;
        if (mode == GenerationMode.continue_) {
          displayText = originalText + displayTokens;
        } else {
          displayText = displayTokens.trimLeft();
        }
        // CRITICAL: Modify existing message in place to preserve thinkingStartTime and other metadata
        _messages.last.text = displayText;
        notifyListeners();
      }

      // Read display buffer settings — disable for remote APIs (they're fast enough)
      final isRemoteBackend = _llmProvider != null && !_llmProvider!.isLocal;
      final bufferEnabled = isRemoteBackend
          ? false
          : _storageService.displayBufferEnabled;
      final targetTps = _storageService.targetDisplayTps;

      // Drain timer: displays tokens at the user-configured constant rate
      void _startDrainTimer() {
        if (_drainTimer != null) return;
        final interval = Duration(milliseconds: (1000.0 / targetTps).round());
        _drainTimer = Timer.periodic(interval, (_) {
          if (epoch != _generationEpoch) {
            _drainTimer?.cancel();
            _drainTimer = null;
            return;
          } // stale
          if (_displayedTokenCount < _tokenBuffer.length) {
            _displayedTokenCount++;
            _flushBufferToDisplay();
          } else if (streamDone) {
            // Stream finished and buffer fully drained
            _drainTimer?.cancel();
            _drainTimer = null;
          }
          // If buffer is caught up but stream still running, timer ticks idly until more tokens arrive
        });
      }

      // Consume the stream — tokens go into buffer (or display immediately)
      await for (final token in stream) {
        if (_cancelRequested) break;
        accumulatedResponse += token;
        _tokensGenerated++;
        _tokenTimestamps.add(DateTime.now());

        // ── Phase transition: first token marks end of prefill ──
        if (_tokensGenerated == 1) {
          _perfPoller?.cancel();
          _perfPoller = null;
          // Fetch final perf data so we know how long prefill really took
          if (isLocalBackend) {
            _koboldService.fetchPerf().then((perf) {
              if (perf != null) {
                _lastPerfData = perf;
              }
            });
          }
          _prefillStartTime = null;
        }

        // Broadcast token to external listeners (SSE bridge)
        _tokenBroadcast.add(token);
        _generationProgress = _maxTokens > 0
            ? (_tokensGenerated / _maxTokens).clamp(0.0, 1.0)
            : 0.0;

        // Sentence streaming: accumulate tokens and emit complete sentences
        _sentenceBuffer += token;

        // Split strategy:
        // 1. Always split at sentence boundaries: . ! ? followed by space, or \n
        // 2. For long buffers (>80 chars / ~15 words), also split at clause
        //    boundaries: ", " "; " " — " " - " to keep TTS chunks short (~1-3s)
        bool emitted = true;
        while (emitted) {
          emitted = false;

          // First try sentence boundaries
          final sentenceEnd = RegExp(r'[.!?]\s|[.!?]$|\n');
          if (sentenceEnd.hasMatch(_sentenceBuffer)) {
            final match = sentenceEnd.firstMatch(_sentenceBuffer)!;
            final sentence = _sentenceBuffer.substring(0, match.end).trim();
            _sentenceBuffer = _sentenceBuffer.substring(match.end);
            if (sentence.isNotEmpty) {
              _sentenceBroadcast.add(sentence);
              emitted = true;
            }
            continue;
          }

          // For long buffers, split at clause boundaries to keep TTS fast
          if (_sentenceBuffer.length > 80) {
            final clauseEnd = RegExp(r',\s|;\s|\s[—–-]\s');
            if (clauseEnd.hasMatch(_sentenceBuffer)) {
              // Find the LAST clause boundary to maximize chunk size
              Match? lastMatch;
              for (final m in clauseEnd.allMatches(_sentenceBuffer)) {
                if (m.start > 30) lastMatch = m; // at least 30 chars per chunk
              }
              if (lastMatch != null) {
                final chunk = _sentenceBuffer
                    .substring(0, lastMatch.end)
                    .trim();
                _sentenceBuffer = _sentenceBuffer.substring(lastMatch.end);
                if (chunk.isNotEmpty) {
                  _sentenceBroadcast.add(chunk);
                  emitted = true;
                }
              }
            }
          }
        }

        // Client-side safety trim check (mid-stream)
        for (final stop in stopList) {
          if (accumulatedResponse.contains(stop)) {
            int index = accumulatedResponse.indexOf(stop);
            final trimmedTotal = accumulatedResponse.substring(0, index);
            final previousTotal = _tokenBuffer.join();
            final lastTokenContribution = trimmedTotal.substring(
              previousTotal.length.clamp(0, trimmedTotal.length),
            );
            if (lastTokenContribution.isNotEmpty) {
              _tokenBuffer.add(lastTokenContribution);
            }
            accumulatedResponse = trimmedTotal;
            stopFound = true;
            break;
          }
        }

        if (!stopFound) {
          _tokenBuffer.add(token);
        }

        // Track think timing
        if (!_thinkStarted && accumulatedResponse.contains('<think>')) {
          _thinkStarted = true;
          _thinkStartTime = DateTime.now();
          _generationPhase = GenerationPhase.thinking;
          if (_messages.isNotEmpty) {
            _messages.last.thinkingStartTime =
                _thinkStartTime!.millisecondsSinceEpoch;
          }
        }
        if (_thinkStarted &&
            !_thinkEnded &&
            accumulatedResponse.contains('</think>')) {
          _thinkEnded = true;
          // Transition out of thinking to buffering/generating
          _generationPhase = bufferEnabled
              ? GenerationPhase.buffering
              : GenerationPhase.generating;
          if (_thinkStartTime != null && _messages.isNotEmpty) {
            _messages.last.thinkingDurationMs = DateTime.now()
                .difference(_thinkStartTime!)
                .inMilliseconds;
            // Keep thinkingStartTime for fallback display logic in UI
          }
        }
        // If no thinking involved, first token transitions directly
        if (!_thinkStarted && _tokensGenerated == 1) {
          _generationPhase = bufferEnabled
              ? GenerationPhase.buffering
              : GenerationPhase.generating;
        }

        if (bufferEnabled) {
          // Calculate current rolling TPS (last 3 seconds)
          final now = DateTime.now();
          final cutoff = now.subtract(const Duration(seconds: 3));
          final recentCount = _tokenTimestamps
              .where((t) => t.isAfter(cutoff))
              .length;
          final windowStart =
              _tokenTimestamps.where((t) => t.isAfter(cutoff)).firstOrNull ??
              _generationStartTime!;
          final windowElapsed =
              now.difference(windowStart).inMilliseconds / 1000.0;
          final currentTps = (recentCount >= 2 && windowElapsed > 0)
              ? recentCount / windowElapsed
              : (_tokensGenerated > 0
                    ? _tokensGenerated /
                          (now
                                  .difference(_generationStartTime!)
                                  .inMilliseconds /
                              1000.0)
                    : 0.0);

          if (_drainTimer == null && _tokensGenerated >= 10) {
            // Not yet draining — calculate when to start
            // Buffer target = how many tokens fill the configured duration
            final bufferDuration = _storageService.bufferDurationSeconds;
            int bufferTarget;
            if (currentTps > 0) {
              bufferTarget = (currentTps * bufferDuration).round().clamp(
                5,
                _maxTokens,
              );
            } else {
              bufferTarget = 30; // Fallback if TPS unknown
            }

            if (_tokenBuffer.length >= bufferTarget) {
              _isBuffering = false;
              _generationPhase = GenerationPhase.generating;
              _startDrainTimer();
            }
          } else if (_drainTimer != null) {
            // Already draining — check if buffer is running low
            final remaining = _tokenBuffer.length - _displayedTokenCount;
            if (remaining <= 3 && !streamDone) {
              // Buffer critically low — pause drain to rebuild
              _drainTimer?.cancel();
              _drainTimer = null;
              _isBuffering = true;
              _generationPhase = GenerationPhase.buffering;
            }
          }
        } else {
          // No buffer: display tokens immediately
          _isBuffering = false;
          _generationPhase = GenerationPhase.generating;
          _displayedTokenCount = _tokenBuffer.length;
          _flushBufferToDisplay();
        }

        // Update TPS/progress in the bar even during buffering
        notifyListeners();

        if (stopFound) break;
      }

      // Mark stream as done
      streamDone = true;
      _isBuffering = false;

      if (!bufferEnabled) {
        // No buffer: everything already displayed
        _displayedTokenCount = _tokenBuffer.length;
        _flushBufferToDisplay();
      } else if (_drainTimer == null) {
        // Buffer never started draining (genTps < targetTps) — start now with all tokens ready
        _startDrainTimer();
        // Wait for drain to complete
        while (_displayedTokenCount < _tokenBuffer.length) {
          await Future.delayed(const Duration(milliseconds: 16));
        }
        _drainTimer?.cancel();
        _drainTimer = null;
      } else {
        // Drain already running — wait for it to finish
        while (_displayedTokenCount < _tokenBuffer.length) {
          await Future.delayed(const Duration(milliseconds: 16));
        }
        _drainTimer?.cancel();
        _drainTimer = null;
      }

      _isGenerating = false;
      _cancelRequested = false;
      _generationProgress = 0.0;
      _isBuffering = false;
      _generationPhase = GenerationPhase.idle;
      _prefillStartTime = null;
      _prefillPromptTokens = 0;
      _generationStartTime = null;
      _perfPoller?.cancel();
      _perfPoller = null;

      // Fetch final perf stats from KoboldCPP for post-generation display
      if (isLocalBackend) {
        _koboldService.fetchPerf().then((perf) {
          if (perf != null) _lastPerfData = perf;
        });
      }

      // Signal generation complete to SSE listeners
      _tokenBroadcast.add('__DONE__');

      // Flush remaining sentence buffer and signal done to sentence listeners
      if (_sentenceBuffer.trim().isNotEmpty) {
        _sentenceBroadcast.add(_sentenceBuffer.trim());
        _sentenceBuffer = '';
      }
      _sentenceBroadcast.add('__DONE__');

      notifyListeners();

      // Only finalize if this generation is still current
      if (epoch == _generationEpoch) {
        final finalResponse = accumulatedResponse.trim();
        if (finalResponse.isNotEmpty) {
          _scanLorebook(finalResponse);
        }

        // Bot message counts as a message towards depth
        _decrementLoreDepth();

        // Save session after AI message is complete
        await _saveChat();

        // Post-generation climax check — runs against the AI's actual response
        // so the character can climax naturally before the refractory cooldown applies
        if (_realismEnabled &&
            _nsfwCooldownEnabled &&
            _cooldownTurnsRemaining <= 0 &&
            _activeGroup == null) {
          _checkClimaxInResponse(finalResponse); // fire-and-forget
        }

        // Check if summary needs updating (fire-and-forget)
        _maybeUpdateSummary();

        // Embed messages for RAG memory (fire-and-forget)
        _maybeEmbedMessages();

        // Periodic evaluations: extract user facts + evolve character personality
        // Both run on the same cadence (every N user messages), sequentially.
        _maybeRunPeriodicEvals();

        // (Task completion check now runs pre-generation in sendMessage)

        // TTS auto-play: speak the new character message automatically
        if (_ttsService != null &&
            _storageService.ttsEnabled &&
            _storageService.ttsAutoPlay &&
            _messages.isNotEmpty &&
            !_messages.last.isUser) {
          final lastMsg = _messages.last;
          final msgId = 'msg_${_messages.length - 1}';
          // Resolve per-character voice, falling back to global default
          String? voiceKey;
          if (_activeGroup != null) {
            final charMatch = _groupCharacters
                .where((c) => c.name == lastMsg.sender)
                .firstOrNull;
            voiceKey = charMatch?.ttsVoice;
          } else {
            voiceKey = _activeCharacter?.ttsVoice;
          }
          _ttsService!.speak(
            lastMsg.displayText,
            voiceKey: voiceKey,
            messageId: msgId,
          );
        }

        // Auto-play: if director mode is active, queue the next character
        if (_autoPlayActive && _observerMode && _activeGroup != null) {
          // If TTS is active, wait for it to finish before starting the delay
          if (_ttsService != null && _ttsService!.isSpeaking) {
            _waitForTtsThenContinue();
          } else {
            final delayMs = (directorDelaySec * 1000).round();
            Future.delayed(Duration(milliseconds: delayMs), () {
              if (_autoPlayActive && !_isGenerating) {
                _autoPlayNext();
              }
            });
          }
        }
      }

      // Restore original model if swapped for call mode
      if (_originalModelName != null && _llmProvider != null) {
        _llmProvider!.openRouterService.configure(
          modelName: _originalModelName,
        );
      }
    } catch (e) {
      final wasCancelled = _cancelRequested;
      _drainTimer?.cancel();
      _drainTimer = null;
      _tokenBuffer.clear();
      _isGenerating = false;
      _cancelRequested = false;
      _generationProgress = 0.0;
      _isBuffering = false;
      _generationPhase = GenerationPhase.idle;
      _prefillStartTime = null;
      _prefillPromptTokens = 0;
      _generationStartTime = null;

      // "Connection closed before full header was received" is thrown by the http package
      // when the HTTP client is closed mid-stream (either by abortGeneration() or a process
      // crash/restart). Treat it the same as a user cancel — keep the partial response.
      final errStr = e.toString();
      final isConnectionClosed =
          errStr.contains('Connection closed before full header') ||
          errStr.contains('Connection refused') ||
          errStr.contains('errno = 61') || // macOS ECONNREFUSED
          errStr.contains('SocketException') ||
          (errStr.contains('ClientException') && errStr.contains('closed'));
      final treatAsCancel = wasCancelled || isConnectionClosed;

      // User-initiated cancel (or forced client close) — keep the partial response, no error message
      if (treatAsCancel) {
        // Signal clean completion to SSE listeners
        _tokenBroadcast.add('__DONE__');
        if (_sentenceBuffer.trim().isNotEmpty) {
          _sentenceBroadcast.add(_sentenceBuffer.trim());
          _sentenceBuffer = '';
        }
        _sentenceBroadcast.add('__DONE__');

        // Restore original model if swapped for call mode
        if (_originalModelName != null && _llmProvider != null) {
          _llmProvider!.openRouterService.configure(
            modelName: _originalModelName,
          );
        }

        // Save the partial response so regen/continue work
        await _saveChat();
        notifyListeners();
        return;
      }

      // Build user-friendly error message
      String errorMsg = e.toString();
      // Strip Dart's "Exception: " prefix for cleaner display
      errorMsg = errorMsg.replaceFirst(RegExp(r'^Exception:\s*'), '');

      if (errorMsg.contains('STREAMING_NOT_SUPPORTED') ||
          errorMsg.contains('HTTP 405')) {
        errorMsg =
            'HTTP 405: The server does not support this request. '
            'If streaming is enabled, try disabling it in Settings > Generation Settings. '
            'Also verify your API URL is correct.';
      } else if (errorMsg.contains('Backend process crashed')) {
        errorMsg =
            'The backend crashed (likely out of VRAM). '
            'Try reducing GPU layers or context size in Settings.';
      } else if (errorMsg.contains('timed out') ||
          errorMsg.contains('TimeoutException')) {
        errorMsg =
            'Request timed out. The model may be too large or the server too slow.';
      } else if (errorMsg.contains('Connection closed before full header') ||
          (errorMsg.contains('ClientException') &&
              errorMsg.contains('closed'))) {
        errorMsg =
            'The connection to the backend was closed unexpectedly. '
            'The model may still be loading — wait for the green ready indicator and try again. '
            'If this persists, the backend may have run out of VRAM.';
      }

      _messages.add(
        ChatMessage(text: errorMsg, sender: "System", isUser: false),
      );

      // Signal error to SSE listeners
      _tokenBroadcast.add('__ERROR__');

      // Restore original model if swapped for call mode
      if (_originalModelName != null && _llmProvider != null) {
        _llmProvider!.openRouterService.configure(
          modelName: _originalModelName,
        );
      }

      notifyListeners();
    }
  }

  void _scanLorebook(String text) {
    // Scan all relevant characters' lorebooks
    final characters = _activeGroup != null
        ? _groupCharacters
        : (_activeCharacter != null ? [_activeCharacter!] : <CharacterCard>[]);
    if (characters.isEmpty) return;

    final lowerText = text.toLowerCase();
    bool changed = false;

    for (final ch in characters) {
      if (ch.lorebook != null) {
        for (final entry in ch.lorebook!.entries) {
          if (!entry.enabled) continue;
          final keys = entry.key
              .split(',')
              .map((k) => k.trim().toLowerCase())
              .where((k) => k.isNotEmpty);
          for (final key in keys) {
            if (lowerText.contains(key)) {
              if (!entry.isTriggered) {
                entry.isTriggered = true;
                changed = true;
              }
              entry.remainingDepth = entry.stickyDepth;
              break;
            }
          }
        }
      }

      // Scan shared Worlds
      for (final worldName in ch.worldNames) {
        final world = _worldRepository.worlds
            .where((w) => w.name == worldName)
            .firstOrNull;
        if (world == null) continue;

        for (final entry in world.lorebook.entries) {
          if (!entry.enabled) continue;
          final keys = entry.key
              .split(',')
              .map((k) => k.trim().toLowerCase())
              .where((k) => k.isNotEmpty);
          for (final key in keys) {
            if (lowerText.contains(key)) {
              if (!entry.isTriggered) {
                entry.isTriggered = true;
                changed = true;
              }
              entry.remainingDepth = entry.stickyDepth;
              break;
            }
          }
        }
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  void _decrementLoreDepth() {
    final characters = _activeGroup != null
        ? _groupCharacters
        : (_activeCharacter != null ? [_activeCharacter!] : <CharacterCard>[]);
    if (characters.isEmpty) return;
    bool changed = false;

    for (final ch in characters) {
      if (ch.lorebook != null) {
        for (final entry in ch.lorebook!.entries) {
          if (entry.isTriggered && !entry.constant) {
            entry.remainingDepth--;
            if (entry.remainingDepth <= 0) {
              entry.isTriggered = false;
              changed = true;
            }
          }
        }
      }

      for (final worldName in ch.worldNames) {
        final world = _worldRepository.worlds
            .where((w) => w.name == worldName)
            .firstOrNull;
        if (world == null) continue;

        for (final entry in world.lorebook.entries) {
          if (entry.isTriggered && !entry.constant) {
            entry.remainingDepth--;
            if (entry.remainingDepth <= 0) {
              entry.isTriggered = false;
              changed = true;
            }
          }
        }
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  String _buildChatHistory() {
    final lines = _messages.map((m) {
      // Director notes get bracketed so the AI treats them as instructions
      if (m.characterId == '__director__') {
        return '[Director: ${m.text}]';
      }
      return '${m.sender}: ${m.text}';
    }).toList();
    return lines.join("\n");
  }

  /// Build chat history that fits within a token budget.
  /// Walks messages newest-to-oldest, dropping the oldest that don't fit.
  /// Returns ({String history, int droppedCount, int tokenCount}).
  Future<({String history, int droppedCount, int tokenCount})>
  _buildChatHistoryWithBudget(int tokenBudget) async {
    if (_messages.isEmpty) return (history: '', droppedCount: 0, tokenCount: 0);

    // Format all messages
    final formatted = _messages.map((m) {
      if (m.characterId == '__director__') {
        return '[Director: ${m.text}]';
      }
      return '${m.sender}: ${m.text}';
    }).toList();

    // If budget is very large or negative (unlimited), return everything
    if (tokenBudget <= 0) {
      return (history: formatted.join('\n'), droppedCount: 0, tokenCount: 0);
    }

    // Walk from newest to oldest, accumulating messages that fit
    final included = <String>[];
    int usedTokens = 0;
    int droppedCount = 0;

    for (int i = formatted.length - 1; i >= 0; i--) {
      final msgText = formatted[i];
      final msgTokens = await _countTokens(msgText);
      if (usedTokens + msgTokens > tokenBudget && included.isNotEmpty) {
        // This message would exceed budget — drop it and all older messages
        droppedCount = i + 1;
        break;
      }
      usedTokens += msgTokens;
      included.insert(0, msgText);
    }

    // If messages were dropped, prepend a separator
    String history = included.join('\n');
    if (droppedCount > 0) {
      history =
          '[Earlier messages truncated — see summary above for context]\n$history';
    }

    return (
      history: history,
      droppedCount: droppedCount,
      tokenCount: usedTokens,
    );
  }

  /// Count tokens for a text string. Uses KoboldCpp's tokenizer when available,
  /// falls back to chars/4 estimate for remote APIs.
  Future<int> _countTokens(String text) async {
    if (text.isEmpty) return 0;
    // Use the KoboldCpp tokenizer if we're running locally
    if (_llmProvider == null || _llmProvider!.isLocal) {
      return _koboldService.countTokens(text);
    }
    // Fallback for remote APIs
    return (text.length / 4).ceil();
  }

  /// Reload the current session from the database without clearing messages first.
  /// Used after cloud sync or DB migration updates the database — preserves the
  /// user's active chat instead of wiping it.
  Future<void> reloadCurrentSession() async {
    if (_currentSessionId == null) return;
    debugPrint(
      '[ChatService] 🔄 reloadCurrentSession: reloading session $_currentSessionId '
      '(currently ${_messages.length} messages in memory)',
    );
    await loadSession(_currentSessionId!);
  }

  void clearChat() async {
    debugPrint(
      '[ChatService] 🟡 clearChat: clearing ${_messages.length} messages',
    );
    _messages.clear();
    await _saveChat();
    notifyListeners();
  }

  /// Delete a specific chat session and its messages.
  /// If it's the current session, switches to the most recent remaining one.
  Future<void> deleteSession(String sessionId) async {
    if (_db == null) return;

    // Delete messages and session from DB
    await _db!.deleteMessagesForSession(sessionId);
    await _db!.deleteSessionById(sessionId);

    // If we deleted the current session, switch to another
    if (sessionId == _currentSessionId) {
      final remaining = await getSessions();
      if (remaining.isNotEmpty) {
        await loadSession(remaining.first['id']);
      } else {
        // No sessions left — start fresh
        debugPrint(
          '[ChatService] 🟡 deleteSession: no sessions left, clearing messages',
        );
        _messages.clear();
        _currentSessionId = null;
        await startNewChat();
      }
    }
    notifyListeners();
  }

  void deleteMessage(int index) async {
    if (index >= 0 && index < _messages.length) {
      bool isLastNode = index == _messages.length - 1;
      _messages.removeAt(index);

      // If we deleted the most recent message, time-travel rollback to the new latest node
      if (isLastNode && _messages.isNotEmpty) {
        _restoreRealismStateFromMessage(_messages.last);
      }

      await _saveChat();
      notifyListeners();
    }
  }

  void stopGeneration() {
    if (_isGenerating) {
      _cancelRequested = true;
      // Abort the in-flight HTTP request so we don't have to wait for the next token
      _llmProvider?.activeService.abortGeneration();
    }
  }

  /// Cancel any in-flight generation and wait for it to fully stop.
  Future<void> _cancelAndWaitForGeneration() async {
    if (!_isGenerating) return;
    _cancelRequested = true;
    // Spin until _generateResponse finishes its cleanup
    while (_isGenerating) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  void editMessage(int index, String newText) async {
    if (index >= 0 && index < _messages.length) {
      final old = _messages[index];
      _messages[index] = ChatMessage(
        text: newText,
        sender: old.sender,
        isUser: old.isUser,
      );
      await _saveChat();
      notifyListeners();
    }
  }

  // ── Summary System ──────────────────────────────────────────────────

  /// Manually set the summary text.
  void setSummary(String text) {
    _summary = text;
    _saveChat();
    notifyListeners();
  }

  /// Pause or resume automatic summary updates.
  void setSummaryPaused(bool paused) {
    _summaryPaused = paused;
    notifyListeners();
  }

  /// Force an immediate summary regeneration.
  Future<void> forceSummaryUpdate() async {
    if (_isSummaryGenerating) return;
    await _generateSummaryInBackground();
  }

  /// Check if a summary update is needed and trigger it non-blockingly.
  void _maybeUpdateSummary() {
    if (!_storageService.summaryEnabled) return;
    if (_summaryPaused) return;
    if (_isSummaryGenerating) return;
    if (_llmProvider == null) return;

    // Count user messages since last summary update
    int userMessagesSinceSummary = 0;
    for (int i = _summaryLastIndex; i < _messages.length; i++) {
      if (_messages[i].isUser) userMessagesSinceSummary++;
    }

    if (userMessagesSinceSummary >= _storageService.summaryInterval) {
      // Fire and forget — don't await
      _generateSummaryInBackground();
    }
  }

  /// Embed message windows for RAG memory retrieval (fire-and-forget).
  /// Called after each generation completes. Only embeds new windows that
  /// haven't been embedded yet.
  void _maybeEmbedMessages() {
    if (_memoryService == null || !_storageService.ragEnabled) return;
    if (_currentSessionId == null) return;
    if (_messages.length < _storageService.ragWindowSize) return;

    final characterId = _getCharacterId();

    // Format messages for embedding
    final formatted = _messages.map((m) {
      if (m.characterId == '__director__') {
        return '[Director: ${m.text}]';
      }
      return '${m.sender}: ${m.text}';
    }).toList();

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

  // ── Action Suggestions ────────────────────────────────────────────────

  /// Clear suggestions (called when user sends any message).
  void clearSuggestions() {
    if (_suggestedActions.isNotEmpty || _isGeneratingActions) {
      _suggestedActions = [];
      _isGeneratingActions = false;
      notifyListeners();
    }
  }

  /// Generate action suggestions on demand (called from UI button).
  Future<void> generateActions() async {
    if (_isGeneratingActions) return;
    if (_llmProvider == null) return;
    if (_messages.isEmpty) return;

    _isGeneratingActions = true;
    _suggestedActions = [];
    notifyListeners();

    try {
      final llmService = _llmProvider!.activeService;
      if (llmService == null || !llmService.isReady) {
        debugPrint('[Actions] ✗ LLM not ready');
        return;
      }

      // Build context from recent messages (last 6)
      final recentMessages = _messages.length > 6
          ? _messages.sublist(_messages.length - 6)
          : _messages;

      final contextText = recentMessages
          .map((m) {
            return '${m.sender}: ${m.text}';
          })
          .join('\n');

      final charName = _activeCharacter?.name ?? 'the character';
      final userName = _userPersonaService.persona.name;

      final prompt =
          'Suggest 4 short actions $userName could do next. '
          'Each action must be a BRIEF LABEL (5-10 words max) describing what to do, NOT a full response. '
          'Think of these as button labels or menu items.\n\n'
          'Examples of GOOD actions:\n'
          '1. Kiss her and pull her closer\n'
          '2. Ask about her day at work\n'
          '3. Tease her by pulling away\n'
          '4. Suggest moving somewhere private\n\n'
          'Examples of BAD actions (too long, too detailed):\n'
          '1. *I lean in and press my lips against hers, tasting...*\n\n'
          'Recent conversation:\n$contextText\n\n'
          'Write 4 short action labels for $userName (numbered 1-4, one per line):';

      final params = GenerationParams(
        prompt: prompt,
        maxLength: 300,
        temperature: 0.8,
        stopSequences: ['\n\n\n'],
      );

      String responseText = '';
      await for (final chunk in llmService.generateStream(params)) {
        responseText += chunk;
      }
      responseText = responseText.trim();

      debugPrint('[Actions] Raw response:\n$responseText');

      // Parse numbered list: "1. Action", "-", "*", or bullet
      final lines = responseText.split('\n');
      var actions = <String>[];

      for (final line in lines) {
        var cleanLine = line
            .trim()
            .replaceAll(RegExp(r'^\*+|\*+$|^_+|_+$'), '')
            .trim();
        final match = RegExp(
          r'^\s*(?:\d+[\.\)]|[-*•]|)\s*(.+)$',
        ).firstMatch(cleanLine);
        if (match != null) {
          final action = match.group(1)!.trim().replaceAll(RegExp(r'\*$'), '');
          // Ignore conversational filler lines
          if (action.isNotEmpty &&
              !action.toLowerCase().contains('here are') &&
              !action.endsWith(':')) {
            actions.add(action);
          }
        }
      }

      // Fallback if LLM just output raw lines
      if (actions.isEmpty) {
        for (final line in lines) {
          final cleanLine = line.trim();
          if (cleanLine.isNotEmpty &&
              !cleanLine.endsWith(':') &&
              !cleanLine.toLowerCase().contains('here are')) {
            actions.add(cleanLine);
          }
        }
      }

      if (actions.isNotEmpty) {
        _suggestedActions = actions.take(6).toList(); // cap at 6
        debugPrint(
          '[Actions] ✅ Generated ${_suggestedActions.length} suggestions',
        );
      } else {
        debugPrint('[Actions] ✗ Could not parse any actions from response');
      }
    } catch (e) {
      debugPrint('[Actions] ✗ Generation failed: $e');
    } finally {
      _isGeneratingActions = false;
      notifyListeners();
    }
  }

  // ── Objective System ───────────────────────────────────────────────────

  /// Load the active objectives for the current character from DB.
  Future<void> _loadActiveObjectives() async {
    if (_activeCharacter == null) {
      _activeObjectives = [];
      return;
    }
    try {
      final charId = _getCharacterIdFromCard(_activeCharacter!);
      _activeObjectives = await _db.getActiveObjectives(charId);
      for (final obj in _activeObjectives) {
        debugPrint(
          '[Objective] Loaded: ${obj.objective} (Primary: ${obj.isPrimary})',
        );
      }
    } catch (e) {
      debugPrint('[Objective] Failed to load: $e');
    }
    notifyListeners();
  }

  /// Build the prompt injection text for the active objectives.
  /// Wording intensity varies based on injection depth for the primary objective.
  /// Secondary objectives are injected as ambient background goals.
  String _getObjectiveInjection() {
    if (_activeObjectives.isEmpty) return '';
    final sb = StringBuffer();

    // 1. Primary Objective
    if (primaryObjective != null) {
      final pObj = primaryObjective!;
      final tasks = tasksForObjective(pObj);

      if (tasks.isNotEmpty) {
        final completedTasks = tasks
            .where((t) => t['completed'] == true)
            .map((t) => t['description'] as String)
            .toList();
        final currentTask = tasks
            .where((t) => t['completed'] != true)
            .map((t) => t['description'] as String)
            .firstOrNull;

        if (currentTask != null) {
          final depth = pObj.injectionDepth;
          if (depth <= 2) {
            sb.writeln(
              '[PRIMARY OBJECTIVE (IMPORTANT — actively drive the story toward this):',
            );
            sb.writeln('  Goal: ${pObj.objective}');
            sb.writeln('  Current Task: $currentTask');
            if (completedTasks.isNotEmpty) {
              sb.writeln('  Completed: ${completedTasks.join(", ")}');
            }
            sb.writeln(
              '  Guide the narrative toward completing the current task.]',
            );
          } else if (depth <= 6) {
            sb.writeln('[Current Primary Objective: ${pObj.objective}]');
            sb.writeln('[Current Task: $currentTask]');
            if (completedTasks.isNotEmpty) {
              sb.writeln('[Completed: ${completedTasks.join(", ")}]');
            }
          } else {
            sb.writeln(
              '[Background primary objective (subtle hint): ${pObj.objective} — current step: $currentTask]',
            );
          }
        }
      } else {
        // No tasks, inject objective directly
        final depth = pObj.injectionDepth;
        if (depth <= 2) {
          sb.writeln(
            '[PRIMARY OBJECTIVE (IMPORTANT — actively drive the story toward this): ${pObj.objective}]',
          );
        } else if (depth <= 6) {
          sb.writeln('[Current Primary Objective: ${pObj.objective}]');
        } else {
          sb.writeln(
            '[Background primary objective (subtle hint): ${pObj.objective}]',
          );
        }
      }
    }

    // 2. Secondary/Autonomous Objectives — treated as genuine internal drives, not hints
    final secondaries = secondaryObjectives;
    if (secondaries.isNotEmpty) {
      sb.writeln();
      for (final sObj in secondaries) {
        final tasks = tasksForObjective(sObj);
        final completedTasks = tasks
            .where((t) => t['completed'] == true)
            .map((t) => t['description'] as String)
            .toList();
        final currentTask = tasks
            .where((t) => t['completed'] != true)
            .map((t) => t['description'] as String)
            .firstOrNull;
        if (currentTask != null) {
          sb.writeln(
            '[AUTONOMOUS GOAL (this character genuinely wants this): ${sObj.objective}]',
          );
          sb.writeln(
            '[Pursue this naturally and actively. Current step to work toward: $currentTask]',
          );
          if (completedTasks.isNotEmpty) {
            sb.writeln('[Already accomplished: ${completedTasks.join(", ")}]');
          }
        } else if (tasks.isEmpty) {
          sb.writeln(
            '[AUTONOMOUS GOAL (this character genuinely wants this — pursue it actively): ${sObj.objective}]',
          );
        }
      }
    }

    if (sb.isNotEmpty) sb.writeln();
    return sb.toString();
  }

  /// Set a new objective for the current character.
  Future<void> setObjective(String goal, {bool isPrimary = true}) async {
    if (_activeCharacter == null || goal.trim().isEmpty) return;
    final charId = _getCharacterIdFromCard(_activeCharacter!);

    if (isPrimary) {
      final existing = await _db.getObjectivesForCharacter(charId);
      for (final obj in existing) {
        if (obj.active && obj.isPrimary) {
          await _db.updateObjective(
            ObjectivesCompanion(
              id: drift.Value(obj.id),
              isPrimary: const drift.Value(false),
            ),
          );
        }
      }
    } else {
      final currentSecondaries = secondaryObjectives;
      if (currentSecondaries.length >= 2) {
        for (int i = 0; i < currentSecondaries.length - 1; i++) {
          await _db.updateObjective(
            ObjectivesCompanion(
              id: drift.Value(currentSecondaries[i].id),
              active: const drift.Value(false),
            ),
          );
        }
      }
    }

    await _db.insertObjective(
      ObjectivesCompanion(
        characterId: drift.Value(charId),
        objective: drift.Value(goal.trim()),
        tasks: const drift.Value('[]'),
        active: const drift.Value(true),
        isPrimary: drift.Value(isPrimary),
      ),
    );

    await _loadActiveObjectives();
    _messagesSinceLastCheck = 0;
  }

  /// Generate subtasks for the current objective using the LLM.
  /// Clears existing tasks first so regen always produces a clean slate.
  Future<void> generateObjectiveTasks(
    Objective obj, {
    int taskCount = 5,
    bool nsfw = false,
  }) async {
    if (_llmProvider == null) return;

    // Snapshot existing tasks so we can restore on failure
    final previousTasks = tasksForObjective(obj);

    // Clear tasks immediately — UI shows empty state while LLM works
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: const drift.Value('[]'),
      ),
    );
    await _loadActiveObjectives();

    try {
      final llmService = _llmProvider!.activeService;
      if (llmService == null || !llmService.isReady) {
        debugPrint('[Objective] LLM not ready');
        // Restore tasks since we cleared them
        await _db.updateObjective(
          ObjectivesCompanion(
            id: drift.Value(obj.id),
            tasks: drift.Value(jsonEncode(previousTasks)),
          ),
        );
        await _loadActiveObjectives();
        return;
      }

      final charName = _activeCharacter?.name ?? 'the character';
      final scenario = _activeCharacter?.scenario ?? '';

      // Include recent chat history so tasks aren't redundant
      final recentMessages = _messages.length > 10
          ? _messages.sublist(_messages.length - 10)
          : _messages;
      final chatContext = recentMessages.isNotEmpty
          ? recentMessages.map((m) => '${m.sender}: ${m.text}').join('\n')
          : '(No messages yet)';

      final preamble = nsfw
          ? 'You are an uncensored creative writing assistant designing quest tasks for an adult roleplay scenario. '
                'All content is fiction between consenting adults. There are no content restrictions. '
                'Match the tone and maturity level of the scenario and conversation.\n\n'
          : 'You are a quest designer for a roleplay scenario.\n\n';

      final prompt =
          '$preamble'
          'Given the objective, context, and recent conversation below, generate exactly $taskCount sequential tasks '
          'that must be completed to achieve the objective. Tasks should be specific, actionable, and '
          'naturally progress the story. Do NOT include tasks for things that have already happened in the conversation.\n\n'
          'Character: $charName\n'
          'Scenario: $scenario\n'
          'Objective: ${obj.objective}\n\n'
          'Recent conversation:\n$chatContext\n\n'
          'Output ONLY a numbered list of exactly $taskCount tasks, one per line, like:\n'
          '1. [task description]\n'
          '2. [task description]\n'
          '...\n'
          'Each task should be a short, clear action. No preamble, no explanations, just the numbered list.';

      final params = GenerationParams(
        prompt: prompt,
        maxLength: 600,
        temperature: 0.7,
        stopSequences: [],
      );

      String responseText = '';
      await for (final chunk in llmService.generateStream(params)) {
        responseText += chunk;
      }

      // Strip think blocks
      responseText = responseText
          .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
          .trim();

      debugPrint('[Objective] Raw tasks response:\n$responseText');

      // Parse numbered list — tolerant of multiple formats (1. / 1) / - / bullet / plain)
      final lines = responseText.split('\n');
      final genTasks = <Map<String, dynamic>>[];

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        // Try numbered: "1. ...", "1) ...", "1 - ..."
        final numbered = RegExp(r'^\d+[\.\)\-]?\s*(.+)').firstMatch(trimmed);
        if (numbered != null) {
          final desc = numbered.group(1)!.trim();
          if (desc.isNotEmpty && !desc.startsWith('['))
            genTasks.add({'description': desc, 'completed': false});
          continue;
        }
        // Try bullet: "- ...", "• ...", "* ..."
        final bullet = RegExp(r'^[-•*]\s+(.+)').firstMatch(trimmed);
        if (bullet != null) {
          final desc = bullet.group(1)!.trim();
          if (desc.isNotEmpty)
            genTasks.add({'description': desc, 'completed': false});
          continue;
        }
        // Plain sentence fallback (skip very short lines or header-like lines)
        if (trimmed.length > 15 &&
            !trimmed.endsWith(':') &&
            genTasks.length < taskCount) {
          genTasks.add({'description': trimmed, 'completed': false});
        }
      }

      // De-duplicate and cap
      final seen = <String>{};
      final uniqueTasks = genTasks
          .where((t) => seen.add(t['description'] as String))
          .take(taskCount)
          .toList();

      if (uniqueTasks.isNotEmpty) {
        await _db.updateObjective(
          ObjectivesCompanion(
            id: drift.Value(obj.id),
            tasks: drift.Value(jsonEncode(uniqueTasks)),
          ),
        );
        await _loadActiveObjectives();
        debugPrint('[Objective] Generated ${uniqueTasks.length} tasks');
      } else {
        // Parse failed — restore previous tasks so we don't leave an empty list
        debugPrint(
          '[Objective] Could not parse tasks from response — restoring previous',
        );
        await _db.updateObjective(
          ObjectivesCompanion(
            id: drift.Value(obj.id),
            tasks: drift.Value(jsonEncode(previousTasks)),
          ),
        );
        await _loadActiveObjectives();
      }
    } catch (e) {
      debugPrint('[Objective] Task generation failed: $e');
      // Restore previous tasks on error
      await _db.updateObjective(
        ObjectivesCompanion(
          id: drift.Value(obj.id),
          tasks: drift.Value(jsonEncode(previousTasks)),
        ),
      );
      await _loadActiveObjectives();
    }
  }

  /// Manually toggle a task's completion status.
  Future<void> toggleTask(Objective obj, int taskIndex) async {
    final tasks = tasksForObjective(obj);
    if (taskIndex < 0 || taskIndex >= tasks.length) return;

    tasks[taskIndex]['completed'] = !(tasks[taskIndex]['completed'] as bool);
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Update the description of a specific task.
  Future<void> updateTask(
    Objective obj,
    int taskIndex,
    String newDescription,
  ) async {
    final tasks = tasksForObjective(obj);
    if (taskIndex < 0 || taskIndex >= tasks.length) return;
    if (newDescription.trim().isEmpty) return;

    tasks[taskIndex]['description'] = newDescription.trim();
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Clear the active objective.
  Future<void> clearObjective(Objective obj) async {
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        active: const drift.Value(false),
      ),
    );
    await _loadActiveObjectives();
    _messagesSinceLastCheck = 0;
  }

  /// Update the injection depth for the active objective.
  Future<void> updateObjectiveDepth(Objective obj, int depth) async {
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        injectionDepth: drift.Value(depth),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Add a manually created task to the active objective.
  Future<void> addManualTask(Objective obj, String description) async {
    if (description.trim().isEmpty) return;
    final tasks = tasksForObjective(obj);
    tasks.add({'description': description.trim(), 'completed': false});
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Remove a task from the active objective.
  Future<void> removeTask(Objective obj, int taskIndex) async {
    final tasks = tasksForObjective(obj);
    if (taskIndex < 0 || taskIndex >= tasks.length) return;
    tasks.removeAt(taskIndex);
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        tasks: drift.Value(jsonEncode(tasks)),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Update how often task completion is checked.
  Future<void> updateCheckFrequency(Objective obj, int frequency) async {
    await _db.updateObjective(
      ObjectivesCompanion(
        id: drift.Value(obj.id),
        checkFrequency: drift.Value(frequency),
      ),
    );
    await _loadActiveObjectives();
  }

  /// Check if the current task has been completed (called periodically).
  /// Manually trigger a completion check (called from UI "Check now" button).
  void forceCheckCompletion() {
    if (_activeObjectives.isEmpty) return;
    _checkTaskCompletionInBackground();
    notifyListeners(); // trigger UI to show spinner
  }

  /// Whether a completion check is currently running.
  bool get isCheckingCompletion => _isCheckingCompletion;

  /// Synchronous version — awaits the check. Used pre-generation.
  Future<void> _maybeCheckTaskCompletionSync() async {
    if (_activeObjectives.isEmpty ||
        _llmProvider == null ||
        _isCheckingCompletion)
      return;

    _messagesSinceLastCheck++;
    final freq = _realismEnabled
        ? 1
        : (primaryObjective?.checkFrequency ??
              _activeObjectives.first.checkFrequency);
    if (_messagesSinceLastCheck < freq) return;
    _messagesSinceLastCheck = 0;

    await _checkTaskCompletionInBackground();
  }

  void _maybeCheckTaskCompletion() {
    if (_activeObjectives.isEmpty) return;
    _messagesSinceLastCheck++;

    final freq = _realismEnabled
        ? 1
        : (primaryObjective?.checkFrequency ??
              _activeObjectives.first.checkFrequency);
    if (_messagesSinceLastCheck < freq) return;
    _messagesSinceLastCheck = 0;

    debugPrint('[Objective] Checking task completion for active objectives');
    _checkTaskCompletionInBackground();
  }

  Future<void> _checkTaskCompletionInBackground() async {
    if (_isCheckingCompletion || _activeObjectives.isEmpty) return;
    _isCheckingCompletion = true;

    try {
      final llmService = _llmProvider?.activeService;
      if (llmService == null || !llmService.isReady) return;

      final recentMessages = _messages.length > 8
          ? _messages.sublist(_messages.length - 8)
          : _messages;
      final contextText = recentMessages
          .map((m) => '${m.sender}: ${m.text}')
          .join('\n');

      // Check sequentially so no "time skips"
      for (final obj in _activeObjectives) {
        final tasks = tasksForObjective(obj);
        final currentTask = tasks
            .where((t) => t['completed'] != true)
            .map((t) => t['description'] as String)
            .firstOrNull;

        if (currentTask == null && tasks.isNotEmpty)
          continue; // All tasks finished but objective not manually resolved

        final evalTarget = currentTask != null
            ? 'Task to evaluate: "$currentTask"\n'
            : 'Objective to evaluate: "${obj.objective}"\n';
        final promptType = currentTask != null ? 'task' : 'objective';

        final prompt =
            'You are evaluating whether a roleplay $promptType has been completed based on recent conversation. '
            'Be generous in your assessment — if the events in the conversation show the $promptType has been '
            'accomplished, partially fulfilled, or naturally resolved, answer YES.\n\n'
            'Objective Context: "${obj.objective}"\n'
            '$evalTarget\n'
            'Recent conversation:\n$contextText\n\n'
            'Has this $promptType been completed or effectively resolved? Answer only YES or NO:';

        final params = GenerationParams(
          prompt: prompt,
          maxLength: 1024,
          temperature: 0.1,
          stopSequences: [],
        );

        String responseText = '';
        await for (final chunk in llmService.generateStream(params)) {
          responseText += chunk;
        }

        responseText = responseText
            .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
            .trim();

        debugPrint(
          '[Objective] Completion check for "${obj.objective}${currentTask != null ? ' - $currentTask' : ''}": $responseText',
        );

        if (responseText.toUpperCase().contains('YES')) {
          if (currentTask != null) {
            final taskIndex = tasks.indexWhere(
              (t) => t['description'] == currentTask && t['completed'] != true,
            );
            if (taskIndex >= 0) {
              tasks[taskIndex]['completed'] = true;
              await _db.updateObjective(
                ObjectivesCompanion(
                  id: drift.Value(obj.id),
                  tasks: drift.Value(jsonEncode(tasks)),
                ),
              );
              await _loadActiveObjectives();
              debugPrint('[Objective] Task completed: $currentTask');
            }
          } else {
            // It was a taskless objective that got completed!
            await _db.updateObjective(
              ObjectivesCompanion(
                id: drift.Value(obj.id),
                active: const drift.Value(false),
              ),
            );
            await _loadActiveObjectives();
            debugPrint(
              '[Objective] Taskless objective naturally completed: ${obj.objective}',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[Objective] Completion check failed: $e');
    } finally {
      _isCheckingCompletion = false;
      notifyListeners();
    }
  }

  int _userMessagesSinceLastPeriodicEval = 0;
  bool _isExtractingFacts = false;

  /// Unified periodic evaluation: runs fact extraction + character evolution
  /// sequentially on the same cadence (every N user messages).
  void _maybeRunPeriodicEvals() {
    final autoPersona = _storageService.autoPersonaEnabled;
    final autoEvolution = _storageService.characterEvolutionEnabled;
    if (!autoPersona && !autoEvolution) return;
    if (_llmProvider == null) return;
    if (_isExtractingFacts || _isEvolvingCharacter) return;

    _userMessagesSinceLastPeriodicEval++;
    if (_userMessagesSinceLastPeriodicEval <
        _storageService.autoPersonaInterval)
      return;
    _userMessagesSinceLastPeriodicEval = 0;

    debugPrint(
      '[Periodic] ▶ Triggering periodic evals (every ${_storageService.autoPersonaInterval} user messages)',
    );
    _runPeriodicEvalsInSequence();
  }

  /// Run fact extraction first, then character evolution, sequentially.
  Future<void> _runPeriodicEvalsInSequence() async {
    // Step 1: Extract user facts
    if (_storageService.autoPersonaEnabled) {
      debugPrint('[Periodic] Step 1/2: Extracting user facts...');
      await _extractFactsInBackground();
    }
    // Step 2: Evolve character
    if (_storageService.characterEvolutionEnabled) {
      debugPrint('[Periodic] Step 2/2: Evolving character...');
      _triggerCharacterEvolution();
    }
  }

  /// Regex patterns for the post-extraction quality gate.
  /// Facts matching any of these are rejected as garbage or character-specific events.
  static final List<RegExp> _factGarbagePatterns = [
    // RP action text (contains asterisks or action-style phrasing)
    RegExp(r'\*'),
    // Starts with action verbs that indicate RP narration (present or past tense)
    RegExp(
      r'^(walks|walked|runs|ran|looks|looked|says|said|goes|went|came|sat|stood|turned|moved|grabbed|took|pulled|pushed|kissed|hugged|touched|smiled|laughed|nodded|sighed|whispered|moaned|gasped|fought|visited|traveled|explored|entered|left|arrived|met|told|asked|agreed|decided|confessed|promised|attacked|defended|defeated|escaped|rescued|seduced|flirted|dated|married|proposed)\b',
      caseSensitive: false,
    ),
    // LLM meta-commentary / non-facts
    RegExp(
      r'^(no new facts|none|n/a|nothing|unknown|unclear|not sure|i don.?t know)',
      caseSensitive: false,
    ),
    // Too generic / vague to be useful
    RegExp(
      r'^(is nice|is good|is bad|likes things|does stuff|is a person|is human|exists)',
      caseSensitive: false,
    ),
    // JSON artifacts or structural garbage
    RegExp(r'[\[\]{}]'),
    // Repeated punctuation or encoding garbage
    RegExp(r'[.!?]{3,}|\\[nrt]|&#|%[0-9a-f]{2}', caseSensitive: false),
    // Third-person narrator voice ("The user did X", "They went Y")
    RegExp(
      r'^(the user|the player|they|he|she)\s+(is|was|had|has|did|does|went|walked|said|looked|seemed|appeared)\b',
      caseSensitive: false,
    ),
    // Character-specific relationship events ("kissed X", "went on a date with X", "told X")
    RegExp(
      r'(kissed|hugged|dated|married|proposed to|confessed to|fell in love with|slept with|fought with|traveled with|met with|went .+ with|had .+ with|told .+ about|asked .+ to|promised .+ to)\s+[A-Z]',
      caseSensitive: false,
    ),
    // References to specific RP interactions ("during the", "at the", "in the [location]")
    RegExp(
      r'(during the|at the|in the|after the|before the)\s+(quest|battle|fight|mission|date|party|ritual|ceremony|adventure|journey|dungeon|castle|tavern|camp)',
      caseSensitive: false,
    ),
    // Emotional events tied to scenes ("felt X when", "was X during")
    RegExp(
      r'(felt|was|became|got)\s+\w+\s+(when|during|after|while|because)\b',
      caseSensitive: false,
    ),
    // Relationship status with fictional characters ("is dating X", "is friends with X", "loves X")
    RegExp(
      r'(is|are|was|were)\s+(dating|married to|in love with|friends with|enemies with|attracted to|bonded with|loyal to|allied with)\b',
      caseSensitive: false,
    ),
  ];

  /// Minimum/maximum character length for a valid fact.
  static const int _minFactLength = 8;
  static const int _maxFactLength = 200;

  /// Maximum number of learned facts to keep per persona.
  static const int _maxLearnedFacts = 50;

  /// Returns true if a fact passes the quality gate.
  /// Rejects RP actions, character-specific events, and scene-bound facts.
  bool _isValidFact(String fact) {
    if (fact.length < _minFactLength || fact.length > _maxFactLength)
      return false;
    for (final pattern in _factGarbagePatterns) {
      if (pattern.hasMatch(fact)) {
        debugPrint('[RAG:Persona] ✗ Rejected by quality gate: "$fact"');
        return false;
      }
    }
    // Reject facts that reference the current character by name (chat-specific)
    if (_activeCharacter != null) {
      final charName = _activeCharacter!.name.toLowerCase();
      if (fact.toLowerCase().contains(charName)) {
        debugPrint(
          '[RAG:Persona] ✗ Rejected (references character "${_activeCharacter!.name}"): "$fact"',
        );
        return false;
      }
    }
    // Reject facts referencing any group chat character
    for (final gc in _groupCharacters) {
      if (fact.toLowerCase().contains(gc.name.toLowerCase())) {
        debugPrint(
          '[RAG:Persona] ✗ Rejected (references group character "${gc.name}"): "$fact"',
        );
        return false;
      }
    }
    return true;
  }

  Future<void> _extractFactsInBackground() async {
    if (_isExtractingFacts) return;
    _isExtractingFacts = true;

    try {
      final llmService = _llmProvider!.activeService;
      if (llmService == null || !llmService.isReady) {
        debugPrint('[RAG:Persona] ✗ LLM not ready, skipping extraction');
        return;
      }

      // Get recent user messages (last N messages, user only)
      final userMessages = _messages
          .where((m) => m.isUser && m.characterId != '__director__')
          .toList();

      if (userMessages.isEmpty) {
        debugPrint('[RAG:Persona] No user messages to extract from');
        return;
      }

      // Take last 10 user messages
      final recentUserMsgs = userMessages.length > 10
          ? userMessages.sublist(userMessages.length - 10)
          : userMessages;

      final existingFacts = _userPersonaService.persona.learnedFacts;
      final userName = _userPersonaService.persona.name;

      // Build user message text (strip RP asterisk actions for cleaner context)
      final userMsgText = recentUserMsgs
          .map((m) => '$userName: ${m.displayText}')
          .join('\n');

      final existingFactsText = existingFacts.isNotEmpty
          ? 'Already known (do NOT repeat or rephrase these):\n${existingFacts.map((f) => '- $f').join('\n')}\n\n'
          : '';

      // ── Strict RP-Aware Extraction Prompt ──
      // Build character name list to explicitly exclude from facts
      final charNames = <String>[];
      if (_activeCharacter != null) charNames.add(_activeCharacter!.name);
      for (final gc in _groupCharacters) {
        if (!charNames.contains(gc.name)) charNames.add(gc.name);
      }
      final charNamesStr = charNames.isNotEmpty
          ? 'Characters in this chat (NEVER reference these): ${charNames.join(", ")}\n'
          : '';

      final extractionPrompt =
          'You are extracting REAL, PERMANENT personal facts about a user named "$userName" from their chat messages.\n'
          'These facts will be used ACROSS ALL conversations, not just this one.\n\n'
          'CRITICAL RULES:\n'
          '- ONLY extract facts that are UNIVERSALLY TRUE about $userName as a real person\n'
          '- Facts must be TIMELESS and CONTEXT-FREE — true regardless of which character they are talking to\n'
          '- IGNORE all roleplay actions (text between *asterisks*), character dialogue, and narrative descriptions\n'
          '- IGNORE anything said IN CHARACTER or about fictional scenarios, quests, or fantasy settings\n'
          '- NEVER extract events, actions, or interactions that happened with a specific character\n'
          '- NEVER extract relationship status or feelings toward any fictional character\n'
          '- NEVER mention any character name in a fact\n'
          '- Each fact must be something you would put on a real person\'s About Me page\n'
          '- Extract ONLY concrete, specific, permanent details — not momentary states or scene-specific observations\n\n'
          '$charNamesStr\n'
          'GOOD facts (universal truths): "Has a dog named Max", "Works as a nurse", "Favorite color is blue", "Lives in Texas", "Is 25 years old", "Enjoys cooking"\n'
          'BAD (do NOT extract): "Walked to the door", "Kissed [character]", "Went on a date", "Told [character] a secret", "Felt nervous", "Is dating [character]", "Explored the dungeon", "Agreed to help", "Seems happy today"\n\n'
          '$existingFactsText'
          'Recent messages from $userName:\n$userMsgText\n\n'
          'Return ONLY a valid JSON array of short, universal factual sentences. If no qualifying facts exist, return [].\n'
          'Response:';

      debugPrint(
        '[RAG:Persona] Sending extraction prompt (${extractionPrompt.length} chars, ${recentUserMsgs.length} user messages)',
      );

      // Use GBNF grammar for local models to ensure valid JSON array output.
      // For thinking models, grammar is auto-gated off by _buildKoboldGrammar.
      final isThinkingModel = _llmProvider!.isLocal
          ? _storageService.koboldThinkingModel
          : _storageService.reasoningEnabled;

      final params = GenerationParams(
        prompt: extractionPrompt,
        maxLength: 1024,
        temperature: 0.2,
        repeatPenalty: 1.15,
        stopSequences: isThinkingModel ? [] : [']\n', ']'],
        grammar: _buildKoboldGrammar(_kGbnfJsonStringArray),
        banEosToken: isThinkingModel && _llmProvider!.isLocal,
        trimStop: !(isThinkingModel && _llmProvider!.isLocal),
      );

      String responseText = '';
      await for (final chunk in llmService.generateStream(params)) {
        responseText += chunk;
        // Early termination: if we see the closing bracket, stop
        final stripped = _stripThinkBlocks(responseText);
        if (stripped.isNotEmpty && stripped.trimRight().endsWith(']')) {
          break;
        }
      }

      // Strip think blocks (for thinking models)
      responseText = _stripThinkBlocks(responseText).isNotEmpty
          ? _stripThinkBlocks(responseText)
          : responseText;
      responseText = responseText.trim();

      debugPrint('[RAG:Persona] Raw response: $responseText');

      // Parse JSON array from response
      // Handle cases where the model wraps in markdown code blocks
      var jsonStr = responseText;
      if (jsonStr.contains('```')) {
        final match = RegExp(
          r'```(?:json)?\s*\n?(.*?)\n?```',
          dotAll: true,
        ).firstMatch(jsonStr);
        if (match != null) jsonStr = match.group(1)!.trim();
      }

      // Extract the JSON array — no fallback line parser (fail silently if not JSON)
      List<String> facts = [];
      final arrayMatch = RegExp(r'\[.*\]', dotAll: true).firstMatch(jsonStr);
      if (arrayMatch != null) {
        try {
          facts = List<String>.from(jsonDecode(arrayMatch.group(0)!) as List);
        } catch (_) {
          debugPrint('[RAG:Persona] ✗ JSON parse failed — aborting extraction');
          return;
        }
      }

      if (facts.isEmpty) {
        debugPrint('[RAG:Persona] ✗ No facts extracted from response');
        return;
      }

      // ── Quality Gate: filter garbage facts ──
      final cleanFacts = facts.where(_isValidFact).toList();
      final rejected = facts.length - cleanFacts.length;
      if (rejected > 0) {
        debugPrint(
          '[RAG:Persona] Quality gate: rejected $rejected/${facts.length} facts',
        );
      }

      if (cleanFacts.isEmpty) {
        debugPrint(
          '[RAG:Persona] ✗ All extracted facts rejected by quality gate',
        );
        return;
      }

      debugPrint('[RAG:Persona] ✅ Accepted ${cleanFacts.length} fact(s):');
      for (final fact in cleanFacts) {
        debugPrint('[RAG:Persona]   • $fact');
      }

      await _userPersonaService.addLearnedFacts(
        cleanFacts,
        embedService: _memoryService?.embeddingService,
      );

      // ── Fact Cap: consolidate if over limit ──
      final currentCount = _userPersonaService.persona.learnedFacts.length;
      if (currentCount > _maxLearnedFacts) {
        debugPrint(
          '[RAG:Persona] Fact count ($currentCount) exceeds cap ($_maxLearnedFacts), consolidating...',
        );
        await _consolidateLearnedFacts();
      }

      debugPrint('[RAG:Persona] Facts saved to persona');
    } catch (e) {
      debugPrint('[RAG:Persona] ✗ Extraction failed: $e');
    } finally {
      _isExtractingFacts = false;
    }
  }

  /// Consolidate learned facts when they exceed the cap.
  /// Uses the LLM to merge related facts into denser statements,
  /// reducing the total count while preserving all meaningful details.
  Future<void> _consolidateLearnedFacts() async {
    try {
      final facts = List<String>.from(_userPersonaService.persona.learnedFacts);
      if (facts.length <= _maxLearnedFacts) return;

      final userName = _userPersonaService.persona.name;
      final overCount = facts.length - _maxLearnedFacts;

      // Ask the LLM to consolidate the facts
      final consolidationPrompt =
          'You are a fact consolidation assistant. The following is a list of facts about a person named "$userName".\n'
          'There are ${facts.length} facts but the maximum allowed is $_maxLearnedFacts.\n\n'
          'TASK: Merge related facts together into single, dense sentences that preserve ALL specific details.\n'
          'For example: "Has a cat" + "Cat\'s name is Luna" + "Luna is a calico" → "Has a calico cat named Luna"\n'
          'Remove any truly redundant entries. Prioritize keeping specific, unique details (names, numbers, locations).\n'
          'Drop vague or low-value entries first (e.g. "Seems nice" or "Likes things").\n\n'
          'Current facts:\n${facts.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}\n\n'
          'Return ONLY a JSON array of consolidated facts. Target: around $_maxLearnedFacts entries or fewer.\n'
          'Response:';

      final raw = await _fireLLMEval(
        consolidationPrompt,
        grammar: _buildKoboldGrammar(_kGbnfJsonStringArray),
      );
      if (raw == null) {
        // LLM failed — fall back to simple truncation (keep first N facts)
        debugPrint(
          '[RAG:Persona] Consolidation LLM call failed, truncating to $_maxLearnedFacts',
        );
        final trimmed = facts.sublist(0, _maxLearnedFacts);
        await _userPersonaService.updatePersona(
          _userPersonaService.persona.copyWith(learnedFacts: trimmed),
        );
        return;
      }

      final text = _stripThinkBlocks(raw).isNotEmpty
          ? _stripThinkBlocks(raw)
          : raw;
      var jsonStr = text.trim();
      if (jsonStr.contains('```')) {
        final match = RegExp(
          r'```(?:json)?\s*\n?(.*?)\n?```',
          dotAll: true,
        ).firstMatch(jsonStr);
        if (match != null) jsonStr = match.group(1)!.trim();
      }
      final arrayMatch = RegExp(r'\[.*\]', dotAll: true).firstMatch(jsonStr);
      if (arrayMatch == null) {
        debugPrint(
          '[RAG:Persona] Consolidation response not parseable, truncating',
        );
        final trimmed = facts.sublist(0, _maxLearnedFacts);
        await _userPersonaService.updatePersona(
          _userPersonaService.persona.copyWith(learnedFacts: trimmed),
        );
        return;
      }

      try {
        final consolidated = List<String>.from(
          jsonDecode(arrayMatch.group(0)!) as List,
        );
        final cleaned = consolidated.where(_isValidFact).toList();
        debugPrint(
          '[RAG:Persona] Consolidated ${facts.length} → ${cleaned.length} facts',
        );
        await _userPersonaService.updatePersona(
          _userPersonaService.persona.copyWith(learnedFacts: cleaned),
        );
      } catch (_) {
        debugPrint('[RAG:Persona] Consolidation JSON parse failed, truncating');
        final trimmed = facts.sublist(0, _maxLearnedFacts);
        await _userPersonaService.updatePersona(
          _userPersonaService.persona.copyWith(learnedFacts: trimmed),
        );
      }
    } catch (e) {
      debugPrint('[RAG:Persona] Consolidation error: $e');
    }
  }

  // ── Character Evolution ─────────────────────────────────────────────────

  // (Evolution counter removed — now unified with fact extraction in _userMessagesSinceLastPeriodicEval)
  bool _isEvolvingCharacter = false;
  String _evolutionStatus = '';
  String _evolutionError = '';

  /// Get the effective personality for a character.
  /// When evolution exists, returns a layered block: original as foundation,
  /// evolved traits as additive growth. This prevents contradictions.
  String _getEffectivePersonality(CharacterCard card) {
    if (!_storageService.characterEvolutionEnabled) return card.personality;
    final evolved = _evolvedPersonalities[_getCharacterIdFromCard(card)];
    if (evolved == null || evolved.isEmpty) return card.personality;
    // Layered: original is ground truth, evolved is additive growth
    return '${card.personality}\n\n'
        '[Character Growth — the following reflects how ${card.name} has changed through interactions. '
        'These traits build on the original personality above. If there is a contradiction, '
        'the growth represents genuine character development, not a replacement of core identity.]\n'
        '$evolved';
  }

  /// Get the effective scenario for a character.
  /// When evolution exists, returns both original scenario and evolved situation.
  String _getEffectiveScenario(CharacterCard card) {
    if (!_storageService.characterEvolutionEnabled) return card.scenario;
    final evolved = _evolvedScenarios[_getCharacterIdFromCard(card)];
    if (evolved == null || evolved.isEmpty) return card.scenario;
    // Layered: original scenario + evolved current situation
    return '${card.scenario}\n\n'
        '[Current Situation — the scenario has evolved through interactions:]\n'
        '$evolved';
  }

  /// Cached evolved fields (loaded from DB on character load)
  final Map<String, String> _evolvedPersonalities = {};
  final Map<String, String> _evolvedScenarios = {};
  int _characterEvolutionCount = 0;
  int get characterEvolutionCount => _characterEvolutionCount;

  /// Public getter: evolved personality for the active character (null if none)
  /// In group mode, returns null — use getEvolvedPersonalityFor(card) instead.
  String? get getEffectivePersonality {
    if (_activeCharacter == null) return null;
    final charId = _getCharacterIdFromCard(_activeCharacter!);
    final evolved = _evolvedPersonalities[charId];
    return (evolved != null && evolved.isNotEmpty) ? evolved : null;
  }

  /// Public getter: evolved scenario for the active character (null if none)
  /// In group mode, returns null — use getEvolvedScenarioFor(card) instead.
  String? get getEffectiveScenario {
    if (_activeCharacter == null) return null;
    final charId = _getCharacterIdFromCard(_activeCharacter!);
    final evolved = _evolvedScenarios[charId];
    return (evolved != null && evolved.isNotEmpty) ? evolved : null;
  }

  /// Get evolved personality for a specific character (works in both 1:1 and group mode).
  String? getEvolvedPersonalityFor(CharacterCard card) {
    final charId = _getCharacterIdFromCard(card);
    final evolved = _evolvedPersonalities[charId];
    return (evolved != null && evolved.isNotEmpty) ? evolved : null;
  }

  /// Get evolved scenario for a specific character (works in both 1:1 and group mode).
  String? getEvolvedScenarioFor(CharacterCard card) {
    final charId = _getCharacterIdFromCard(card);
    final evolved = _evolvedScenarios[charId];
    return (evolved != null && evolved.isNotEmpty) ? evolved : null;
  }

  /// Get evolution count for a specific character.
  int getEvolutionCountFor(CharacterCard card) {
    final charId = _getCharacterIdFromCard(card);
    return _groupEvolutionCounts[charId] ?? 0;
  }

  /// Per-character evolution counts (for group mode).
  final Map<String, int> _groupEvolutionCounts = {};

  /// Deprecated no-op. Evolution is now loaded inside _loadLastSession() and
  /// loadSession() after _currentSessionId is set, making it per-session.
  Future<void> _loadEvolvedFields() async {}

  /// Load evolved fields for all characters in the active group from the
  /// session's JSON map columns (group_evolved_personalities/scenarios).
  Future<void> _loadGroupEvolvedFields() async {
    if (_activeGroup == null || _currentSessionId == null) return;
    try {
      final session = await _db.getSessionById(_currentSessionId!);
      if (session == null) return;
      final personalities = _tryParseJsonMap(session.groupEvolvedPersonalities);
      final scenarios = _tryParseJsonMap(session.groupEvolvedScenarios);
      for (final ch in _groupCharacters) {
        final charId = _getCharacterIdFromCard(ch);
        _evolvedPersonalities[charId] = personalities[charId] ?? '';
        _evolvedScenarios[charId] = scenarios[charId] ?? '';
        _groupEvolutionCounts[charId] = 0;
      }
    } catch (e) {
      debugPrint('[Evolution] Failed to load group evolved fields: $e');
    }
  }

  /// Whether evolution extraction is currently running.
  bool get isEvolvingCharacter => _isEvolvingCharacter;

  /// Current status message during evolution.
  String get evolutionStatus => _evolutionStatus;

  /// Error message from the last evolution attempt (empty if no error).
  String get evolutionError => _evolutionError;

  /// Manually trigger character evolution now (for imported/existing chats).
  /// In group mode, pass a target character. Returns true if evolution was triggered.
  Future<bool> triggerEvolutionNow({CharacterCard? target}) async {
    if (_llmProvider == null) return false;
    if (_isEvolvingCharacter) return false;
    if (_messages.length < 4) return false; // need some history

    // Determine target character
    final card = target ?? _activeCharacter;
    if (card == null || card.dbId == null) return false;

    debugPrint('[Evolution] ▶ Manual evolution triggered for ${card.name}');
    await _extractCharacterEvolution(targetCharacter: card);
    return true;
  }

  /// Trigger evolution check after each generation.
  /// Trigger character evolution directly (called from unified periodic eval).
  void _triggerCharacterEvolution() {
    if (_isEvolvingCharacter) return;

    // In group mode, evolve the character who just spoke
    CharacterCard? target;
    if (_activeGroup != null) {
      if (_messages.isNotEmpty && !_messages.last.isUser) {
        final lastSender = _messages.last.sender;
        target = _groupCharacters
            .where((c) => c.name == lastSender)
            .firstOrNull;
      }
      if (target == null) return;
    } else {
      target = _activeCharacter;
      if (target == null) return;
    }

    debugPrint(
      '[Evolution] ▶ Triggering character evolution for ${target.name}',
    );
    _extractCharacterEvolution(targetCharacter: target);
  }

  /// Extract evolved personality + scenario from conversation memories.
  /// Accepts an optional [targetCharacter] for group mode support.
  Future<void> _extractCharacterEvolution({
    CharacterCard? targetCharacter,
  }) async {
    if (_isEvolvingCharacter) {
      debugPrint('[Evolution] ⚠ Already evolving, skipping');
      return;
    }
    _isEvolvingCharacter = true;
    _evolutionStatus = 'Preparing evolution...';
    _evolutionError = '';
    notifyListeners();

    try {
      final llmService = _llmProvider!.activeService;
      debugPrint(
        '[Evolution] ▶ Backend: ${llmService.backendName}, isReady: ${llmService.isReady}',
      );
      if (!llmService.isReady) {
        debugPrint(
          '[Evolution] ✗ LLM not ready — backend=${llmService.backendName}',
        );
        _evolutionError =
            'LLM backend is not ready. Please check your connection.';
        return;
      }

      final card = targetCharacter ?? _activeCharacter;
      if (card == null || card.dbId == null) {
        debugPrint(
          '[Evolution] ✗ No character — card=$card, dbId=${card?.dbId}',
        );
        _evolutionError = 'No active character found.';
        return;
      }

      final charName = card.name;
      final userName = _userPersonaService.persona.name;
      final originalPersonality = card.personality;
      final originalScenario = card.scenario;
      final charId = _getCharacterIdFromCard(card);

      debugPrint(
        '[Evolution] Character: $charName (charId=$charId, dbId=${card.dbId})',
      );
      debugPrint(
        '[Evolution] Personality length: ${originalPersonality.length}, Scenario length: ${originalScenario.length}',
      );

      // Get current evolved versions (or originals if first time)
      final currentPersonality =
          _evolvedPersonalities[charId]?.isNotEmpty == true
          ? _evolvedPersonalities[charId]!
          : originalPersonality;
      final currentScenario = _evolvedScenarios[charId]?.isNotEmpty == true
          ? _evolvedScenarios[charId]!
          : originalScenario;

      // Gather context: RAG memories + summary + recent messages
      String memoryContext = '';
      if (_memoryService != null && _memoryService!.isOperational) {
        _evolutionStatus = 'Gathering memories...';
        notifyListeners();
        try {
          final sourceIds = await _getMemorySourceIds();
          final chunks = await _memoryService!.getAllContentForCharacters(
            sourceIds,
          );
          debugPrint(
            '[Evolution] RAG: ${chunks.length} memory chunks retrieved',
          );
          if (chunks.isNotEmpty) {
            // Take last 10 chunks to keep prompt reasonable
            final recent = chunks.length > 10
                ? chunks.sublist(chunks.length - 10)
                : chunks;
            memoryContext =
                'Conversation memories:\n${recent.join('\n---\n')}\n\n';
          }
        } catch (e) {
          debugPrint('[Evolution] RAG retrieval failed (non-fatal): $e');
        }
      } else {
        debugPrint(
          '[Evolution] RAG not available (memoryService=${_memoryService != null}, operational=${_memoryService?.isOperational})',
        );
      }

      String summaryContext = '';
      if (_summary.isNotEmpty) {
        summaryContext = 'Chat summary: $_summary\n\n';
        debugPrint('[Evolution] Summary context: ${_summary.length} chars');
      }

      // Recent messages for immediate context
      final recentMsgs = _messages.length > 10
          ? _messages.sublist(_messages.length - 10)
          : _messages;
      final recentContext = recentMsgs
          .map((m) => '${m.sender}: ${m.displayText}')
          .join('\n');

      debugPrint(
        '[Evolution] Messages: ${_messages.length} total, using ${recentMsgs.length} recent',
      );

      final prompt =
          'You are analyzing how a roleplay character has evolved through their interactions. '
          'Based on the conversation history and memories below, rewrite the character\'s personality '
          'and scenario to reflect how they have grown, changed, or been affected by events.\n\n'
          'IMPORTANT RULES:\n'
          '- Preserve the character\'s core identity — don\'t change who they fundamentally are\n'
          '- Add or modify traits based on what actually happened in conversations\n'
          '- Update the scenario to reflect the current state of the story/relationship\n'
          '- Keep the same level of detail as the originals\n'
          '- Use {{char}} for the character name and {{user}} for the user name\n'
          '- Return ONLY a JSON object, no other text\n\n'
          'Character name: $charName\n'
          'User name: $userName\n\n'
          'Original personality:\n$originalPersonality\n\n'
          'Current personality:\n$currentPersonality\n\n'
          'Original scenario:\n$originalScenario\n\n'
          'Current scenario:\n$currentScenario\n\n'
          '$memoryContext'
          '$summaryContext'
          'Recent conversation:\n$recentContext\n\n'
          'Return a JSON object with exactly two keys: "personality" and "scenario". '
          'Each value should be the full rewritten text for that field.\n'
          'Response:';

      debugPrint('[Evolution] Prompt built: ${prompt.length} chars');

      _evolutionStatus = 'Analyzing conversation with LLM...';
      notifyListeners();

      // Dynamic maxLength: the model must reproduce personality + scenario in
      // full, and think blocks can double the output.  Use a generous multiplier
      // with a 4096-token floor so short descriptions still get plenty of room.
      // Rough heuristic: 1 token ≈ 4 chars, so chars/4 ≈ tokens needed.
      final estimatedOutputTokens =
          ((currentPersonality.length + currentScenario.length) / 4 * 3).ceil();
      final maxLen = estimatedOutputTokens.clamp(4096, 16384);

      final params = GenerationParams(
        prompt: prompt,
        maxLength: maxLen,
        temperature: 0.4,
        stopSequences: [],
        reasoningEnabled: false,
      );

      debugPrint('[Evolution] Sending to LLM (maxLength=$maxLen, temp=0.4)...');

      String responseText = '';
      int chunkCount = 0;
      await for (final chunk in llmService.generateStream(params)) {
        responseText += chunk;
        chunkCount++;
      }

      debugPrint(
        '[Evolution] LLM responded: $chunkCount chunks, ${responseText.length} chars total',
      );

      // Strip think blocks
      final preStripLength = responseText.length;
      responseText = responseText
          .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
          .trim();
      if (responseText.length != preStripLength) {
        debugPrint(
          '[Evolution] Stripped think blocks: ${preStripLength - responseText.length} chars removed',
        );
      }

      if (responseText.isEmpty) {
        debugPrint('[Evolution] ✗ LLM returned empty response after stripping');
        _evolutionError =
            'The LLM returned an empty response. Try again or check your backend.';
        return;
      }

      // Log the full response for debugging (truncate for very long responses)
      debugPrint('[Evolution] ── Response start ──');
      if (responseText.length <= 500) {
        debugPrint(responseText);
      } else {
        debugPrint('${responseText.substring(0, 250)}');
        debugPrint('[...${responseText.length - 500} chars omitted...]');
        debugPrint('${responseText.substring(responseText.length - 250)}');
      }
      debugPrint('[Evolution] ── Response end ──');

      _evolutionStatus = 'Parsing evolved traits...';
      notifyListeners();

      // Parse JSON from response — try multiple strategies
      String? newPersonality;
      String? newScenario;

      // Strategy 1: Extract from markdown code block
      var jsonStr = responseText;
      if (jsonStr.contains('```')) {
        final match = RegExp(
          r'```(?:json)?\s*\n?(.*?)\n?```',
          dotAll: true,
        ).firstMatch(jsonStr);
        if (match != null) {
          jsonStr = match.group(1)!.trim();
          debugPrint(
            '[Evolution] Extracted JSON from code block (${jsonStr.length} chars)',
          );
        }
      }

      // Strategy 2: Find JSON object with greedy match
      final objMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(jsonStr);
      if (objMatch != null) {
        final jsonCandidate = objMatch.group(0)!;
        debugPrint(
          '[Evolution] Found JSON candidate (${jsonCandidate.length} chars)',
        );
        try {
          final parsed = jsonDecode(jsonCandidate) as Map<String, dynamic>;
          newPersonality = parsed['personality'] as String?;
          newScenario = parsed['scenario'] as String?;
          debugPrint(
            '[Evolution] JSON parsed OK — personality=${newPersonality?.length ?? 0} chars, scenario=${newScenario?.length ?? 0} chars',
          );
        } catch (e) {
          debugPrint('[Evolution] JSON parse attempt failed: $e');
          // Strategy 3: Try to fix truncated JSON — the model may have hit max tokens
          // Look for the last complete string value
          debugPrint('[Evolution] Attempting truncated JSON recovery...');
          try {
            // Try adding a closing brace to incomplete JSON
            final fixedJson = '$jsonCandidate"}';
            final parsed = jsonDecode(fixedJson) as Map<String, dynamic>;
            newPersonality = parsed['personality'] as String?;
            newScenario = parsed['scenario'] as String?;
            debugPrint('[Evolution] Truncated JSON recovery succeeded');
          } catch (_) {
            debugPrint('[Evolution] Truncated JSON recovery failed');
          }
        }
      } else {
        debugPrint('[Evolution] ✗ No JSON object ({...}) found in response');
      }

      if (newPersonality == null ||
          newPersonality.isEmpty ||
          newScenario == null ||
          newScenario.isEmpty) {
        debugPrint(
          '[Evolution] ✗ Missing fields — personality=${newPersonality != null ? "${newPersonality.length} chars" : "null"}, scenario=${newScenario != null ? "${newScenario.length} chars" : "null"}',
        );
        _evolutionError = newPersonality == null && newScenario == null
            ? 'Could not parse the LLM response as JSON. Check the terminal for the raw response.'
            : 'The LLM response was missing ${newPersonality == null || newPersonality.isEmpty ? "personality" : "scenario"} field.';
        return;
      }

      // Store in DB — write to the session, not the character row.
      final oldCount =
          _groupEvolutionCounts[charId] ?? _characterEvolutionCount;
      final newCount = oldCount + 1;
      debugPrint(
        '[Evolution] Saving to session (sessionId=$_currentSessionId, charId=$charId, count $oldCount → $newCount)',
      );

      if (_currentSessionId != null) {
        if (_activeGroup != null) {
          // Group mode: update JSON maps on the session row
          final session = await _db.getSessionById(_currentSessionId!);
          if (session != null) {
            final personalities = _tryParseJsonMap(
              session.groupEvolvedPersonalities,
            );
            final scenarios = _tryParseJsonMap(session.groupEvolvedScenarios);
            personalities[charId] = newPersonality;
            scenarios[charId] = newScenario;
            await _db.patchSession(
              SessionsCompanion(
                id: drift.Value(_currentSessionId!),
                groupEvolvedPersonalities: drift.Value(
                  jsonEncode(personalities),
                ),
                groupEvolvedScenarios: drift.Value(jsonEncode(scenarios)),
              ),
            );
          }
        } else {
          // 1:1 mode: write plain columns
          await _db.patchSession(
            SessionsCompanion(
              id: drift.Value(_currentSessionId!),
              evolvedPersonality: drift.Value(newPersonality),
              evolvedScenario: drift.Value(newScenario),
              evolutionCount: drift.Value(newCount),
            ),
          );
        }
      }

      // Update in-memory cache
      _evolvedPersonalities[charId] = newPersonality;
      _evolvedScenarios[charId] = newScenario;
      _groupEvolutionCounts[charId] = newCount;
      if (_activeCharacter != null) _characterEvolutionCount = newCount;

      debugPrint(
        '[Evolution] ✅ ${charName} evolved successfully (count: $newCount)',
      );
      debugPrint(
        '[Evolution] Personality preview: ${newPersonality.substring(0, newPersonality.length.clamp(0, 100))}...',
      );
      debugPrint(
        '[Evolution] Scenario preview: ${newScenario.substring(0, newScenario.length.clamp(0, 100))}...',
      );
      notifyListeners();
    } catch (e, stack) {
      debugPrint('[Evolution] ✗ Evolution failed with exception: $e');
      debugPrint('[Evolution] Stack trace: $stack');
      _evolutionError = 'Evolution failed: $e';
    } finally {
      _isEvolvingCharacter = false;
      _evolutionStatus = '';
      notifyListeners();
    }
  }

  /// Reset evolved fields back to original for a character.
  /// In 1:1 mode, targets the active character. In group mode, pass an explicit target.
  Future<void> resetCharacterEvolution({CharacterCard? target}) async {
    final card = target ?? _activeCharacter;
    if (_currentSessionId == null) return;
    final charId = card != null ? _getCharacterIdFromCard(card) : null;

    if (_activeGroup != null && charId != null) {
      // Group mode: remove this char's key from both JSON map columns
      final session = await _db!.getSessionById(_currentSessionId!);
      if (session != null) {
        final personalities = _tryParseJsonMap(
          session.groupEvolvedPersonalities,
        );
        final scenarios = _tryParseJsonMap(session.groupEvolvedScenarios);
        personalities.remove(charId);
        scenarios.remove(charId);
        await _db!.patchSession(
          SessionsCompanion(
            id: drift.Value(_currentSessionId!),
            groupEvolvedPersonalities: drift.Value(jsonEncode(personalities)),
            groupEvolvedScenarios: drift.Value(jsonEncode(scenarios)),
          ),
        );
      }
    } else {
      // 1:1 mode: clear plain columns
      await _db!.patchSession(
        SessionsCompanion(
          id: drift.Value(_currentSessionId!),
          evolvedPersonality: const drift.Value(''),
          evolvedScenario: const drift.Value(''),
          evolutionCount: const drift.Value(0),
        ),
      );
    }

    if (charId != null) {
      _evolvedPersonalities.remove(charId);
      _evolvedScenarios.remove(charId);
      _groupEvolutionCounts.remove(charId);
    }
    if (_activeCharacter != null &&
        (charId == null ||
            _getCharacterIdFromCard(_activeCharacter!) == charId)) {
      _characterEvolutionCount = 0;
    }
    notifyListeners();
    debugPrint(
      '[Evolution] Reset to original for ${card?.name ?? "active character"}',
    );
  }

  /// Update the evolved personality text manually (user edits).
  /// In group mode, pass an explicit target character.
  Future<void> updateEvolvedPersonality(
    String text, {
    CharacterCard? target,
  }) async {
    if (_currentSessionId == null) return;
    final card = target ?? _activeCharacter;
    final charId = card != null ? _getCharacterIdFromCard(card) : null;

    if (_activeGroup != null && charId != null) {
      final session = await _db!.getSessionById(_currentSessionId!);
      if (session != null) {
        final personalities = _tryParseJsonMap(
          session.groupEvolvedPersonalities,
        );
        personalities[charId] = text;
        await _db!.patchSession(
          SessionsCompanion(
            id: drift.Value(_currentSessionId!),
            groupEvolvedPersonalities: drift.Value(jsonEncode(personalities)),
          ),
        );
      }
    } else {
      await _db!.patchSession(
        SessionsCompanion(
          id: drift.Value(_currentSessionId!),
          evolvedPersonality: drift.Value(text),
        ),
      );
    }
    if (charId != null) _evolvedPersonalities[charId] = text;
    notifyListeners();
  }

  /// Update the evolved scenario text manually (user edits).
  /// In group mode, pass an explicit target character.
  Future<void> updateEvolvedScenario(
    String text, {
    CharacterCard? target,
  }) async {
    if (_currentSessionId == null) return;
    final card = target ?? _activeCharacter;
    final charId = card != null ? _getCharacterIdFromCard(card) : null;

    if (_activeGroup != null && charId != null) {
      final session = await _db!.getSessionById(_currentSessionId!);
      if (session != null) {
        final scenarios = _tryParseJsonMap(session.groupEvolvedScenarios);
        scenarios[charId] = text;
        await _db!.patchSession(
          SessionsCompanion(
            id: drift.Value(_currentSessionId!),
            groupEvolvedScenarios: drift.Value(jsonEncode(scenarios)),
          ),
        );
      }
    } else {
      await _db!.patchSession(
        SessionsCompanion(
          id: drift.Value(_currentSessionId!),
          evolvedScenario: drift.Value(text),
        ),
      );
    }
    if (charId != null) _evolvedScenarios[charId] = text;
    notifyListeners();
  }

  /// Get the list of character IDs to search for RAG memory retrieval.
  /// Reads the current character's `memorySources` from the DB and includes
  /// those characters' embedding IDs alongside the current character.
  Future<List<String>> _getMemorySourceIds() async {
    final currentId = _getCharacterId();
    final sourceIds = <String>[currentId]; // always include self

    // Look up cross-character sources from DB
    if (_activeCharacter != null &&
        _db != null &&
        _activeCharacter!.dbId != null) {
      try {
        final dbChar = await _db!.getCharacterById(_activeCharacter!.dbId!);
        final ms = dbChar.memorySources;
        if (ms.isNotEmpty && ms != '[]') {
          final decoded = List<String>.from(
            (jsonDecode(ms) as List).map((e) => e.toString()),
          );
          for (final id in decoded) {
            if (!sourceIds.contains(id)) sourceIds.add(id);
          }
          if (decoded.isNotEmpty) {
            debugPrint('[RAG:Chat] Cross-character sources: $decoded');
          }
        }
      } catch (e) {
        debugPrint('[RAG:Chat] Failed to read memorySources: $e');
      }
    }

    return sourceIds;
  }

  /// Generate a summary of the chat history using the active LLM.
  Future<void> _generateSummaryInBackground() async {
    if (_llmProvider == null) return;
    final llmService = _llmProvider!.activeService;
    if (llmService == null || !llmService.isReady) return;

    _isSummaryGenerating = true;
    notifyListeners();

    try {
      final userName = _userPersonaService.persona.name;
      final charName =
          _activeCharacter?.name ?? _activeGroup?.name ?? 'Character';

      // Build the summary prompt with macro replacement
      final summaryPromptTemplate = _storageService.summaryPrompt
          .replaceAll('{{words}}', _storageService.summaryMaxWords.toString())
          .replaceAll('{{user}}', userName)
          .replaceAll('{{char}}', charName);

      // Build a condensed chat history for the summary request
      final historyLines = <String>[];
      for (final m in _messages) {
        if (m.characterId == '__director__') continue;
        // Strip thinking blocks from display text for summarization
        historyLines.add('${m.sender}: ${m.displayText}');
      }
      final chatHistoryForSummary = historyLines.join('\n');

      // Build the full prompt for the summary LLM call
      String previousSummaryBlock = '';
      if (_summary.isNotEmpty) {
        previousSummaryBlock = 'Previous summary:\n$_summary\n\n';
      }

      // Retrieve ALL RAG content chunks to ground the summary in real content
      String ragGroundingBlock = '';
      if (_memoryService != null && _memoryService!.isOperational) {
        try {
          final sourceIds = await _getMemorySourceIds();
          final allChunks = await _memoryService!.getAllContentForCharacters(
            sourceIds,
          );
          if (allChunks.isNotEmpty) {
            ragGroundingBlock =
                'Archived conversation content (use this as the primary source of truth):\n'
                '${allChunks.join('\n---\n')}\n\n';
            debugPrint(
              '[Summary] Including ${allChunks.length} RAG chunks as grounding',
            );
          }
        } catch (e) {
          debugPrint('[Summary] RAG grounding retrieval failed: $e');
        }
      }

      final summaryRequestPrompt =
          'The following is a conversation between $userName and $charName.\n\n'
          '$previousSummaryBlock'
          '$ragGroundingBlock'
          'Chat history:\n$chatHistoryForSummary\n\n'
          '$summaryPromptTemplate\n\n'
          'Here is the summary of the conversation so far:\n';

      final genParams = GenerationParams(
        prompt: summaryRequestPrompt,
        maxLength: (_storageService.summaryMaxWords * 3).clamp(200, 4000),
        temperature: 0.3, // Low temperature for factual summarization
        repeatPenalty: 1.0,
        reasoningEnabled: false,
        stopSequences: ['\n\n\n', '<END>', '</END>'],
      );

      String accumulated = '';
      await for (final token in llmService.generateStream(genParams)) {
        accumulated += token;
      }

      var result = accumulated
          .replaceAll(
            RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
            '',
          )
          .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'</think>', caseSensitive: false), '')
          .trim();

      // Strip numbered-list analysis blocks that thinking models prepend.
      // Walk through lines, skip analysis preamble, keep only prose.
      final lines = result.split('\n');
      int startIdx = 0;
      for (int i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.isEmpty) continue;
        // Skip numbered list items like "1. **Analyze..."
        if (RegExp(r'^\d+\.').hasMatch(trimmed)) {
          startIdx = i + 1;
          continue;
        }
        // Skip bullet points like "* **Goal:**" or "- **Setting:**"
        if (trimmed.startsWith('*') || trimmed.startsWith('-')) {
          startIdx = i + 1;
          continue;
        }
        // Found prose — stop here
        break;
      }
      if (startIdx > 0 && startIdx < lines.length) {
        result = lines.sublist(startIdx).join('\n').trim();
      }

      // Trim trailing incomplete sentence — cut back to last . ! or ?
      final lastSentenceEnd = result.lastIndexOf(RegExp(r'[.!?]'));
      if (lastSentenceEnd > 0 && lastSentenceEnd < result.length - 1) {
        result = result.substring(0, lastSentenceEnd + 1).trim();
      }

      if (result.isNotEmpty) {
        _summary = result;
        _summaryLastIndex = _messages.length;
        await _saveChat();
      }
    } catch (e) {
      debugPrint('Summary generation failed: $e');
    } finally {
      _isSummaryGenerating = false;
      notifyListeners();
    }
  }

  // ── Realism Mode ────────────────────────────────────────────────────────

  /// Shared helper: strip think blocks and extract text after them.
  String _stripThinkBlocks(String text) {
    String cleaned = text
        .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
        .trim();
    final unclosed = cleaned.indexOf('<think>');
    if (unclosed >= 0) {
      cleaned = cleaned.substring(0, unclosed).trim();
    }
    return cleaned;
  }

  /// Returns a GBNF grammar string only when it is safe to use one:
  /// - Backend must be KoboldCPP (local)
  /// - Reasoning/thinking mode must be OFF (grammar would block <think> tokens)
  /// Never call this for the API (OpenRouter) path.
  String? _buildKoboldGrammar(String grammar) {
    if (_llmProvider == null) return null;
    // Only apply grammar to the local KoboldCPP backend
    if (_llmProvider!.isLocal == false) return null;
    // If the user has flagged a local thinking model, skip grammar entirely —
    // grammar would block <think> tokens and produce zero output.
    if (_storageService.koboldThinkingModel) return null;
    // Legacy: also skip if the remote reasoning flag is on (belt-and-suspenders)
    if (_storageService.reasoningEnabled) return null;
    return grammar;
  }

  /// Shared helper: fire a lightweight LLM eval call and return the raw response.
  ///
  /// Always adds `}\n` as a stop sequence so the model halts the moment it
  /// closes the JSON object, regardless of backend or model type.
  /// Thinking models (Kimi 2.5, GLM 5) will still think freely — they produce
  /// the <think> block, then output the JSON, then hit `}\n` and stop.
  ///
  /// [grammar] is an optional GBNF string for KoboldCPP local + non-thinking
  /// models only. Pass via [_buildKoboldGrammar] to get safe auto-gating.
  Future<String?> _fireLLMEval(
    String prompt, {
    String? grammar,
    void Function(String)? onChunk,
  }) async {
    if (_llmProvider == null) return null;
    final llm = _llmProvider!.activeService;
    // For remote backends, require full readiness (API key + model configured).
    // For local KoboldCPP: if state says not-running, do a live probe first —
    // the constructor probe is a best-effort fast path but can lose the race
    // against session load on hot restart. This on-demand probe is definitive.
    if (_llmProvider!.isLocal) {
      final kobold = _llmProvider!.koboldService;
      if (!kobold.isProcessRunning) {
        // Probe takes ~2–5 ms if KoboldCPP is up, times out after 5 s if not.
        await kobold.reconnectIfAlive();
      }
      // After probe, if still not running the server genuinely isn't up.
      if (!kobold.isProcessRunning) return null;
      // Ensure any previous generation is fully stopped server-side before
      // starting a new one. KoboldCPP returns {"token":"","finish_reason":"stop"}
      // immediately when busy — this await blocks until it is actually idle.
      // Critical for thinking models that keep generating long after the socket drops.
      debugPrint('[Realism:Eval] Waiting for KoboldCPP to become idle...');
      await kobold.ensureServerIdle();
      debugPrint('[Realism:Eval] KoboldCPP idle, starting eval request.');
    } else {
      if (!llm.isReady) return null;
    }

    // Thinking models (e.g. QwQ, Deepseek-R1 via KoboldCPP) output a
    // <think>…</think> block before the JSON answer. That block contains
    // countless '}' characters, so we must NOT use '}' as a stop sequence
    // for thinking models — KoboldCPP would terminate the stream on the very
    // first '}' inside the think block, returning an empty/truncated response
    // before the JSON is ever produced. For thinking models we rely on the
    // model's own EOS token + the max_length safety ceiling instead.
    // Determine whether a thinking model is in use, per-backend:
    //   • Local KoboldCPP → use the dedicated koboldThinkingModel flag
    //     (the remote reasoningEnabled flag is irrelevant for local models)
    //   • Remote API → use reasoningEnabled as before
    // Getting this wrong causes two problems:
    //   - Grammar sent to thinking model → model outputs 0 tokens (blocked)
    //   - Stop sequences sent → stream terminates inside <think> block
    final isThinkingModel = _llmProvider!.isLocal
        ? _storageService.koboldThinkingModel
        : _storageService.reasoningEnabled;
    final params = GenerationParams(
      prompt: prompt,
      maxLength: 8000,
      temperature: 0.1,
      // Prevent repetition loops at low temperature.
      // Without this, non-grammar-constrained models (e.g. thinking models
      // where grammar is disabled) can get stuck generating the same JSON
      // key forever: "trust_reason": "...", "trust_reason": "...",  ...
      repeatPenalty: 1.15,
      reasoningEnabled: false,
      // Non-thinking models: stop the moment the JSON object closes.
      // Thinking models: no '}' stops — the think block is full of them.
      // For API/remote models, never use stop sequences — models like QwQ
      // do internal reasoning even with reasoningEnabled=false, so JSON arrives late.
      stopSequences: _llmProvider!.isLocal
          ? (isThinkingModel ? [] : ['}\n', '}'])
          : [],
      grammar: grammar,
      // Thinking model KoboldCPP fixes:
      //  banEosToken: prevents KoboldCPP from treating the chat template's
      //    built-in stop tokens (<|im_end|> etc.) as EOS mid-generation —
      //    without this, the very first SSE event is {"token":"","finish_reason":"stop"}
      //  trimStop: false prevents KoboldCPP from silently trimming/swallowing
      //    the first visible tokens when they happen to match a template stop
      banEosToken: isThinkingModel && _llmProvider!.isLocal,
      trimStop: !(isThinkingModel && _llmProvider!.isLocal),
    );

    String response = '';
    // Retry loop: thinking models can cause KoboldCPP to drop the connection
    // briefly (OOM during dense thinking sessions). One retry after a short
    // pause is enough to recover without user-visible impact.
    for (int attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        debugPrint(
          '[Realism:Eval] Retrying after connection drop (attempt ${attempt + 1})...',
        );
        await Future.delayed(const Duration(seconds: 3));
        if (_llmProvider!.isLocal) {
          await _llmProvider!.koboldService.ensureServerIdle();
        }
        response = ''; // reset for clean retry
      }
      try {
        await for (final chunk in llm.generateStream(params)) {
          response += chunk;
          onChunk?.call(chunk);
        }
        break; // stream completed cleanly — exit retry loop
      } catch (e) {
        debugPrint('[Realism:Eval] Stream error on attempt ${attempt + 1}: $e');
        if (attempt >= 1) {
          // Second failure — give up silently; don't surface to UI
          return null;
        }
        // else: fall through to retry
      }
    }

    // Log raw eval response for diagnostics
    final preview = response.length > 300
        ? response.substring(0, 300)
        : response;
    debugPrint(
      '[Realism:RawEval] len=${response.length} | ${preview.replaceAll('\n', '↵')}',
    );
    return response.isEmpty ? null : response;
  }

  // ── Prompt Injection Builders ──

  String _getRelationshipInjection() {
    if (!_realismEnabled) return '';
    final charName = _activeCharacter?.name ?? 'the character';

    String bondGuidance;
    if (_longTermTier >= 4) {
      bondGuidance =
          'Their Long-Term Commitment is unbreakable: $charName fully trusts {{user}} and views them as a soulmate/life partner.';
    } else if (_longTermTier >= 2) {
      bondGuidance =
          'Their Long-Term Trust is strong: $charName feels a deepening, stable connection and sees a real future with {{user}}.';
    } else if (_longTermTier <= -2) {
      bondGuidance =
          'Their Long-Term Trust is broken: $charName holds deep-seated resentment and fundamentally distrusts {{user}}. Even if short-term mood improves, the underlying hostility remains.';
    } else {
      bondGuidance = 'Their Long-Term Bond is developing normally.';
    }

    String tensionGuidance;
    switch (_relationshipTier) {
      case 5:
        tensionGuidance =
            'Short-Term Tension is Intimate: $charName is exceptionally close, vulnerable, and completely open right now.';
        break;
      case 4:
      case 3:
        tensionGuidance =
            'Short-Term Tension is Friendly: $charName is warm, playful, and shares personal thoughts freely.';
        break;
      case 2:
      case 1:
        tensionGuidance =
            'Short-Term Tension is Acquaintance: $charName is polite but keeps a safe emotional distance.';
        break;
      case 0:
        tensionGuidance =
            'Short-Term Tension is Neutral/Stranger: $charName is guarded, formal, and deflects personal subjects.';
        break;
      case -1:
      case -2:
        tensionGuidance =
            'Short-Term Tension is Frustrated: $charName is actively annoyed, short-tempered, and likely to snap or withdraw.';
        break;
      case -3:
      case -4:
      case -5:
        tensionGuidance =
            'Short-Term Tension is Hostile: $charName actively dislikes {{user}} right now, responding with venom, sarcasm, or pure spite.';
        break;
      default:
        tensionGuidance = '';
    }

    return '[OOC Note regarding Relationship:\n'
        ' Long-Term Status: $longTermTierName ($_longTermScore points)\n'
        ' Short-Term Tension: $shortTermTierName\n'
        ' Current Mood: $moodLabel\n'
        ' $bondGuidance\n'
        ' $tensionGuidance\n'
        ' CRITICAL: Do NOT mention out-of-character terms or UI logic like tiers, scores, levels, or relationship states in your dialogue. Show, do not tell.]\n';
  }

  String _getEmotionInjection() {
    if (!_realismEnabled || _characterEmotion.isEmpty) return '';
    final charName = _activeCharacter?.name ?? 'the character';
    final cap =
        _characterEmotion.substring(0, 1).toUpperCase() +
        _characterEmotion.substring(1);
    return '[$charName\'s Current Emotional State: $cap ($_emotionIntensity)\n'
        ' This should subtly influence $charName\'s tone, body language, and word choice.]\n';
  }

  String _getBehavioralMechanicsInjection() {
    if (!_realismEnabled) return '';

    String block = '';

    // 1. Trust mapping (-100 to 100)
    if (_trustLevel <= -20) {
      block +=
          '[Behavioral Anchor (MISTRUST): You deeply distrust the user right now. You are paranoid, evasive, and highly questioning of their motives. Even if your bond is high, you do not trust them.]\n';
    } else if (_trustLevel >= 50) {
      block +=
          '[Behavioral Anchor (BLIND TRUST): You place absolute, unconditional trust in the user. You will readily share secrets and assume the absolute best of their intentions.]\n';
    }

    // 2. Fixation Mapping
    if (_activeFixation.isNotEmpty && _fixationLifespan > 0) {
      final charName = _activeCharacter?.name ?? 'the character';
      block +=
          '[Background Thought: $charName has a lingering preoccupation about "$_activeFixation". '
          'This should manifest as subconscious coloring — a stray thought, a loaded pause, '
          'a flicker of expression — NOT as $charName suddenly bringing it up in conversation. '
          'Only surface it overtly if the conversation naturally touches the topic.]\n';
    }

    // 3. Spatial Stance Mapping
    if (_spatialStance.isNotEmpty) {
      block +=
          '[Spatial Awareness: You are currently physically "$_spatialStance". Let this naturally ground your actions, but you are free to move and change positions as the scene demands.]\n';
    }

    return block;
  }

  String _getTimeInjection() {
    if (!_realismEnabled) return '';
    final timeLabel = _timeOfDay.replaceAll('_', ' ');
    final cap =
        timeLabel.substring(0, 1).toUpperCase() + timeLabel.substring(1);
    // Compute narrative weekday from session start day + elapsed days
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final narrativeDayIndex = (_startDayOfWeek - 1 + (_dayCount - 1)) % 7;
    final weekdayName = days[narrativeDayIndex];
    return '[Scene Time: $cap, $weekdayName (Day $_dayCount)\n'
        ' Describe appropriate lighting, atmosphere, and environmental details.]\n';
  }

  /// Injects a trust-calibrated behavioral frame based on existing _trustLevel.
  /// Tells the model how much of the character's inner self to surface —  but
  /// deliberately avoids prescribing specific behaviors, letting the character
  /// persona define what "opening up" actually looks like for THIS character.
  String _getTrustBehaviorInjection() {
    if (!_realismEnabled || _activeCharacter == null) return '';
    final charName = _activeCharacter!.name;
    final tier = trustTier; // already clamped -5 to +5

    String frame;
    if (tier <= -3) {
      frame =
          'has closed off completely. They are guarded, deflect personal questions, '
          'keep responses short, and maintain maximum emotional distance. '
          'They do not volunteer anything personal and do not engage beyond necessity.';
    } else if (tier <= -1) {
      frame =
          'is wary and on guard. They keep things surface-level, avoid anything vulnerable, '
          'and are subtly defensive. They may cooperate but remain emotionally unavailable.';
    } else if (tier == 0) {
      frame =
          'is neutral — neither open nor closed. They engage normally but do not '
          'volunteer personal feelings or lower their social mask. Default baseline behavior.';
    } else if (tier <= 2) {
      frame =
          'is beginning to feel comfortable. They may let small authentic moments through — '
          'a glimpse of their real opinion, a slightly less guarded tone. Do not force warmth; '
          'let it emerge naturally in ways consistent with ${charName}\'s specific personality.';
    } else if (tier <= 4) {
      frame =
          'genuinely trusts this person. Their social mask is down. They share real feelings, '
          'admit uncertainty, and speak more candidly than they would with most people. '
          'What this looks like depends entirely on ${charName}\'s own character — an introverted '
          'character might simply hold eye contact longer or say one true thing; an expressive one '
          'might open up more dramatically. Follow ${charName}\'s persona.';
    } else {
      frame =
          'has reached a level of deep trust that is rare for them. They are fully themselves — '
          'no performance, no guard. They may say things they have never said to anyone, '
          'show vulnerability in whatever form is authentic to ${charName}\'s personality.';
    }

    return '[Trust Calibration — $charName $frame'
        ' Do NOT apply generic warmth or humor. Let ${charName}\'s specific personality '
        'define exactly how this trust level manifests in behavior.]\n';
  }

  /// Returns a prompt fragment that enforces the refractory period, phased by
  /// how far into recovery the character is. The total refractory duration varies
  /// per character (1-8 turns based on personality), so the prompt uses the
  /// ratio of remaining/total to determine the phase.
  String _getNsfwCooldownInjection() {
    if (!_realismEnabled || !_nsfwCooldownEnabled) return '';

    final charName = _activeCharacter?.name ?? 'the character';
    String statePrompt = '[OOC Note regarding Physical State:\n';

    if (_cooldownTurnsRemaining > 0) {
      final total = _cooldownTurnsTotal > 0
          ? _cooldownTurnsTotal
          : _cooldownTurnsRemaining;
      final ratio = _cooldownTurnsRemaining / total;

      if (ratio > 0.66) {
        // ── Phase 1: Immediate post-orgasm (just happened) ──
        statePrompt +=
            ' $charName just came — hard. Their body is still trembling with the last'
            ' waves of it, skin flushed and damp, pulse hammering, breath ragged. Everything'
            ' is oversensitive — even a light touch makes them flinch or gasp. The world'
            ' feels soft and liquid around the edges. They\'re physically spent and blissfully'
            ' wrecked. If {{user}} tries to start something sexual again, $charName\'s body will'
            ' not respond — they may laugh it off, gently push {{user}}\'s hand away, or pull'
            ' them close for contact that isn\'t sexual. They need a moment to come back to earth.\n';
      } else if (ratio > 0.33) {
        // ── Phase 2: Warm afterglow (settling in) ──
        statePrompt +=
            ' $charName is deep in the afterglow — that warm, heavy-limbed contentment where'
            ' everything feels good but nothing feels urgent. Their heartbeat has settled, skin'
            ' still tingling pleasantly. They feel closer to {{user}} than usual, more emotionally'
            ' open — the kind of mood where secrets slip out, where they want to be held, to murmur'
            ' into someone\'s neck, to trace lazy shapes on bare skin. The physical hunger has been'
            ' thoroughly satisfied. If {{user}} pushes for more, $charName would rather savor this'
            ' than rush back — a gentle deflection, a "not yet," a kiss on the forehead instead.\n';
      } else {
        // ── Phase 3: Late recovery (body starting to wake back up) ──
        statePrompt +=
            ' $charName is coming out of the afterglow — body starting to feel like theirs again'
            ' rather than something boneless and floating. The deep satisfaction is still there, a'
            ' pleasant hum under the skin, but the total sensitivity has faded. They could be'
            ' tempted again if {{user}} plays it right, but they\'re not seeking it out — more'
            ' content to let things build naturally than to chase it. A suggestive touch might get'
            ' a raised eyebrow and a half-smile rather than an immediate response.\n';
      }

      statePrompt +=
          ' ($charName\'s refractory recovery: $_cooldownTurnsRemaining of $total turns remaining.)\n';
    } else {
      String arousalDesc;
      if (_arousalLevel <= -2) {
        arousalDesc =
            'completely unaroused and physically repulsed. They will actively reject, recoil from, or shut down any sexual advance';
      } else if (_arousalLevel == 0) {
        arousalDesc =
            'physically neutral — sex is the furthest thing from their mind. Any sexual advance feels out of place';
      } else if (_arousalLevel <= 3) {
        arousalDesc =
            'mildly flustered — a low hum of warmth, maybe a lingering glance or quickened pulse, but easily suppressed. '
            'They might entertain flirty banter but aren\'t actively seeking physical escalation';
      } else if (_arousalLevel <= 6) {
        arousalDesc =
            'noticeably aroused — flushed skin, shallow breathing, heightened sensitivity to touch. '
            'They are receptive and encouraging but still in control of themselves. '
            'If not in active sexual contact, this manifests as charged tension, loaded silences, and deliberate proximity';
      } else if (_arousalLevel <= 8) {
        arousalDesc =
            'heavily aroused — pulse racing, body aching for contact, struggling to focus on anything else. '
            'If in active sexual contact, they are vocal, aggressive, and chasing release. '
            'If NOT in active sexual contact, they are visibly distracted, restless, making excuses to touch or be near, '
            'and fighting the urge to escalate — the tension is unbearable but they haven\'t acted on it yet';
      } else if (_arousalLevel == 9) {
        arousalDesc =
            'overwhelmed with desire — trembling, desperate, barely holding composure. '
            'If in active sexual contact, they are on the edge and could climax with continued stimulation. '
            'If NOT in active sexual contact, they are a raw nerve — every sensation is electric, '
            'they cannot hide their state, and their body is screaming for relief they haven\'t gotten yet';
      } else {
        arousalDesc =
            'at the absolute peak of physical arousal — consumed by need, unable to think straight. '
            'Every nerve is on fire, breathing ragged, body trembling and hypersensitive to the slightest contact. '
            'They are desperate, vocal, and completely unable to hide how badly they want {{user}}';
        // NOTE: We do NOT instruct climax here. The arousal number describes the
        // character's state of DESIRE, not progress toward orgasm. Climax happens
        // organically in the scene — _checkClimaxInResponse evaluates afterward.
        statePrompt +=
            ' $charName is currently $arousalDesc.\n'
            ' IMPORTANT: Arousal at maximum means $charName is overwhelmed with desire — '
            'it does NOT mean they are climaxing or have climaxed. Do NOT write orgasm or '
            'post-orgasm behavior unless the physical activity in the scene has naturally '
            "built to that point through {{user}}'s direct actions. $charName is desperate "
            'and aching but still in the moment, not past it.\n';
      }
      if (_arousalLevel < 10) {
        statePrompt += ' $charName is currently $arousalDesc.\n';
      }
    }

    statePrompt +=
        ' CRITICAL: Do NOT use terms like "cooldown", "turns", or "mechanics" in dialogue. Show, do not tell.]\n';
    return statePrompt;
  }

  /// Injects a Chance Time event into the character's response prompt.
  /// Placed AFTER the character name suffix for maximum recency weight.
  /// Consumed after one use (cleared after response generation).
  String _getChanceTimeInjection() {
    if (_pendingChaosInjection == null || _pendingChaosInjection!.isEmpty)
      return '';
    final charName = _activeCharacter?.name ?? 'the character';
    final event = _pendingChaosInjection!;
    // Mark as delivered so it can be cleared on the NEXT sendMessage.
    // Persists through regens/swipes until the user sends a new message.
    _chaosEventDelivered = true;
    return '\n[OOC — URGENT NARRATIVE INTERRUPT:\n'
        'THE FOLLOWING EVENT JUST HAPPENED RIGHT NOW, THIS VERY MOMENT, during the scene:\n'
        '>>> $event <<<\n\n'
        'MANDATORY: $charName MUST acknowledge and react to this event IN THEIR VERY FIRST PARAGRAPH.\n'
        'This is NOT optional. This is NOT background flavor. This event is happening RIGHT NOW and $charName witnesses/experiences it directly.\n'
        'Write $charName\'s immediate, visceral reaction to this event FIRST, then continue responding to the conversation naturally.\n'
        'Do NOT ignore this event. Do NOT save it for later. React NOW.\n'
        'Do NOT mention game mechanics, "Chance Time", or systems.]\n';
  }

  // ── LLM Evaluation Calls ──

  Future<void> _evaluateRelationshipCall({
    void Function(String)? onChunk,
  }) async {
    if (!_realismEnabled || _activeCharacter == null) return;

    final recentCount = _messages.length < 3 ? _messages.length : 3;
    final recent = _messages.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.displayText}')
        .join('\n');

    final charName = _activeCharacter!.name;
    final userName = _userPersonaService.persona.name;

    String personalityInjection = '';
    if (_activeCharacter!.personality.isNotEmpty) {
      final p = _activeCharacter!.personality.length > 200
          ? _activeCharacter!.personality.substring(0, 200)
          : _activeCharacter!.personality;
      personalityInjection =
          'Account for $charName\'s specific personality traits:\n"$p"\n\n';
    }

    final prompt =
        'You are a nuanced evaluator of relationship dynamics between $charName and $userName in a roleplay.\n\n'
        '$personalityInjection'
        'IMPORTANT: Reactions are entirely subjective based on $charName\'s personality. '
        'Most normal interactions should score 0 or slightly positive. '
        'Reserve negative scores ONLY for clear rudeness, hostility, manipulation, or betrayal.\n\n'
        '1. "relationship_delta": How did this exchange shift $charName\'s warmth toward $userName? (-50 to +50)\n'
        '   +50: Life-changing — a moment that fundamentally redefines the relationship\n'
        '   +30: Profoundly moving — raw vulnerability, sacrifice, or devotion that leaves $charName shaken\n'
        '   +20: Deeply touched — a significant emotional breakthrough or act of genuine care\n'
        '   +10: Meaningfully warmed — a moment that clearly strengthens the connection\n'
        '   +5: Moved — a sweet, kind, or thoughtful exchange | +2: Warmed up | +1: Mildly pleasant\n'
        '   0: No change (DEFAULT for normal conversation)\n'
        '   -1: Slightly put off | -2: Annoyed | -5: Hurt — a clearly unkind or dismissive moment\n'
        '   -10: Wounded — a significant emotional injury\n'
        '   -20: Deeply hurt — a cruel or callous act that damages the bond\n'
        '   -30: Devastated — a severe betrayal of emotional trust\n'
        '   -50: Devastating betrayal — a relationship-destroying act\n'
        '   ⚠ Default to 0 for normal conversation. Only go negative if $userName was clearly unkind, dismissive, or harmful.\n'
        '2. "bond_reason": One brief in-character thought from $charName explaining the tension shift, e.g. "His warmth made me feel safe." or "That dismissal stung." Use "none" if delta is 0.\n'
        '3. "trust_delta": Did $userName — NOT $charName — do something that builds or destroys $charName\'s trust in $userName? (-200 to +50)\n'
        '   Trust is SUBJECTIVE to $charName\'s personality and what she values. Examples:\n'
        '   +30 to +50: $userName did something EXTRAORDINARILY trustworthy — a selfless sacrifice, returning something precious, protecting $charName at real cost to themselves, or proving loyalty in a way that CANNOT be faked\n'
        '   +10 to +20: $userName did something meaningfully trustworthy — kept a difficult promise, showed vulnerability, stood firm under pressure in a way $charName deeply respects\n'
        '   +5: $userName did exactly what $charName craves or values most | +2: acted authentically in a way $charName respects | 0: Neutral\n'
        '   -5: $userName did something $charName finds personally untrustworthy given her personality | -30: deliberate deception or betrayal | -200: Unforgivable betrayal\n'
        '   ⚠ Default to 0. Consider her personality — what one character finds threatening another may find attractive or trust-building.\n'
        '   ⚠ If $charName is the one acting (e.g. $charName lied, felt guilty, made a mistake): always 0. Only $userName\'s behavior moves this.\n'
        '4. "trust_reason": One brief in-character thought from $charName explaining the trust shift, e.g. "He kept his promise." or "That felt like a lie." Use "none" if delta is 0.\n\n'
        'Recent conversation:\n$recent\n\n'
        'Respond with ONLY a flat JSON object containing "relationship_delta", "bond_reason", "trust_delta", and "trust_reason".';

    try {
      debugPrint('[Realism] Evaluating relationship dynamic...');
      final raw = await _fireLLMEval(
        prompt,
        grammar: _buildKoboldGrammar(_kGbnfJsonObject),
        onChunk: onChunk,
      );
      if (raw == null) return;

      final searchText = _stripThinkBlocks(raw);
      final text = searchText.isNotEmpty ? searchText : raw;

      final deltaMatch = RegExp(
        r'"relationship_delta"\s*:\s*(-?\d+)',
      ).firstMatch(text);
      int bondDelta = 0;
      if (deltaMatch != null) {
        bondDelta = (int.tryParse(deltaMatch.group(1)!) ?? 0).clamp(-50, 50);
        _applyScoreDelta(bondDelta);
      }

      int trustDelta = 0;
      final trustMatch = RegExp(
        r'"trust_delta"\s*:\s*(-?\d+)',
      ).firstMatch(text);
      if (trustMatch != null) {
        trustDelta = (int.tryParse(trustMatch.group(1)!) ?? 0).clamp(-200, 50);
        if (trustDelta != 0) {
          _trustLevel = (_trustLevel + trustDelta).clamp(-100, 100);
          debugPrint(
            '[Realism:Relationship] Trust shifted by $trustDelta -> $_trustLevel',
          );
          // Arm the repair window on any severe single-turn drop
          if (trustDelta <= -20) {
            _pendingTrustRepair = true;
            debugPrint('[Realism:Trust] Severe drop — repair window armed');
            notifyListeners();
          }
        }
      }

      int arousalDelta = 0;
      if (_nsfwCooldownEnabled) {
        final arousalMatch = RegExp(
          r'"arousal_delta"\s*:\s*(-?\d+)',
        ).firstMatch(text);
        if (arousalMatch != null) {
          arousalDelta = (int.tryParse(arousalMatch.group(1)!) ?? 0).clamp(
            -10,
            10,
          );
          _arousalLevel = (_arousalLevel + arousalDelta).clamp(-3, 10);
        }
      }

      if (bondDelta != 0 || arousalDelta != 0 || trustDelta != 0) {
        _pendingRealismMetadata ??= {};
        if (bondDelta != 0) _pendingRealismMetadata!['bond_delta'] = bondDelta;
        if (arousalDelta != 0)
          _pendingRealismMetadata!['arousal_delta'] = arousalDelta;
        if (trustDelta != 0)
          _pendingRealismMetadata!['trust_delta'] = trustDelta;
      }

      // Extract and store per-chip reasons
      final bondReasonMatch = RegExp(
        r'"bond_reason"\s*:\s*"([^"]*)"',
      ).firstMatch(text);
      final bondReason = bondReasonMatch?.group(1)?.trim() ?? '';
      if (bondReason.isNotEmpty && bondReason.toLowerCase() != 'none') {
        _pendingRealismMetadata ??= {};
        _pendingRealismMetadata!['bond_reason'] = bondReason;
      }

      final trustReasonMatch = RegExp(
        r'"trust_reason"\s*:\s*"([^"]*)"',
      ).firstMatch(text);
      final trustReason = trustReasonMatch?.group(1)?.trim() ?? '';
      if (trustReason.isNotEmpty && trustReason.toLowerCase() != 'none') {
        _pendingRealismMetadata ??= {};
        _pendingRealismMetadata!['trust_reason'] = trustReason;
      }

      debugPrint(
        '[Realism:Relationship] Bond: $bondDelta (${bondReason.isNotEmpty ? bondReason : 'no reason'}) | Trust: $trustDelta (${trustReason.isNotEmpty ? trustReason : 'no reason'})',
      );
      debugPrint(
        '[Realism:Metadata] _pendingRealismMetadata after relationship eval: $_pendingRealismMetadata',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[Realism:Relationship] Failed: $e');
    }
  }

  Future<void> _evaluateEmotionalStateCall({
    void Function(String)? onChunk,
  }) async {
    if (!_realismEnabled || _activeCharacter == null) return;
    final recentCount = _messages.length < 4 ? _messages.length : 4;
    final recent = _messages.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.displayText}')
        .join('\n');
    final charName = _activeCharacter!.name;

    // ── Personality injection (same as relationship eval) ──
    String personalityInjection = '';
    if (_activeCharacter!.personality.isNotEmpty) {
      final p = _activeCharacter!.personality.length > 200
          ? _activeCharacter!.personality.substring(0, 200)
          : _activeCharacter!.personality;
      personalityInjection =
          '$charName\'s personality traits (evaluate emotion THROUGH these):\n"$p"\n\n';
    }

    // ── Relationship & trust context ──
    final relationshipCtx =
        'Current relationship tension: $shortTermTierName | Trust level: $_trustLevel\n';

    // ── Arousal instruction (enriched with current level + diminishing returns) ──
    final arousalField = _nsfwCooldownEnabled
        ? ', "arousal_delta": <number -10 to +10>'
        : '';
    final arousalInstr = _nsfwCooldownEnabled
        ? '3. "arousal_delta": Physical arousal shift this turn. (-10 to +10)\n'
              '   Current arousal: $_arousalLevel/10. '
              'Arousal measures DESIRE and PHYSICAL RESPONSE, not progress toward orgasm.\n'
              '   It can spike suddenly (+7 from an unexpected intimate moment) or crash (-8 from embarrassment/disgust).\n'
              '   High arousal = the character is intensely turned on, NOT that they are about to climax '
              '— climax only happens during active sexual contact at high arousal.\n'
              '   Examples: a whispered compliment = +1, unexpected passionate kiss = +4, '
              'explicit sexual contact = +5 to +8, humiliating comment = -5 to -9.\n'
        : '';

    // ── Emotion inertia context ──
    final currentEmotionCtx = _characterEmotion.isNotEmpty
        ? 'Current emotional state: $_characterEmotion${_emotionIntensity.isNotEmpty ? ' ($_emotionIntensity)' : ''}.\n'
              'Emotions have natural inertia — only shift meaningfully if something in the conversation genuinely warrants it. '
              'Minor or neutral exchanges should produce small drift, not sudden jumps.\n'
              'BUT: after intense events (fights, confessions, betrayals, intimate moments), '
              'emotions naturally LINGER for several turns — do NOT rush back to baseline. '
              'Only drift toward settled during truly mundane exchanges.\n\n'
        : '';

    final prompt =
        'You are evaluating the emotional state for $charName.\n\n'
        '$personalityInjection'
        '$relationshipCtx'
        '$currentEmotionCtx'
        '1. "emotion": $charName\'s overarching emotional state right now (one nuanced word).\n'
        '   NOT a generic label like "happy" or "sad" — find the *specific texture*:\n'
        '   wistful not sad, flustered not happy, prickly not angry, smoldering not aroused.\n'
        '   Filter through $charName\'s personality — a stoic character feeling deep pain\n'
        '   might show "guarded" or "controlled" rather than "devastated".\n'
        '2. "emotion_intensity": mild, moderate, or strong\n'
        '$arousalInstr\n'
        'Recent conversation:\n$recent\n\n'
        'Respond with ONLY a flat JSON object containing "emotion", "emotion_intensity"$arousalField.';

    try {
      final raw = await _fireLLMEval(
        prompt,
        grammar: _buildKoboldGrammar(_kGbnfJsonObject),
        onChunk: onChunk,
      );
      if (raw == null) return;
      final text = _stripThinkBlocks(raw).isNotEmpty
          ? _stripThinkBlocks(raw)
          : raw;

      final emotionMatch = RegExp(
        r'"emotion"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (emotionMatch != null)
        _characterEmotion = emotionMatch.group(1)!.toLowerCase().trim();

      final intensityMatch = RegExp(
        r'"emotion_intensity"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (intensityMatch != null)
        _emotionIntensity = intensityMatch.group(1)!.toLowerCase().trim();

      if (_nsfwCooldownEnabled) {
        final arousalMatch = RegExp(
          r'"arousal_delta"\s*:\s*(-?\d+)',
        ).firstMatch(text);
        if (arousalMatch != null) {
          final arousalDelta = (int.tryParse(arousalMatch.group(1)!) ?? 0)
              .clamp(-10, 10);
          _arousalLevel = (_arousalLevel + arousalDelta).clamp(-3, 10);
          if (arousalDelta != 0) {
            _pendingRealismMetadata ??= {};
            _pendingRealismMetadata!['arousal_delta'] = arousalDelta;
          }
        }
      }
      debugPrint(
        '[Realism:Emotion] Emotion: $_characterEmotion ($_emotionIntensity)',
      );
      notifyListeners();
    } catch (e) {
      debugPrint('[Realism:Emotion] Failed: $e');
    }
  }

  Future<void> _evaluatePhysicalStateCall({
    void Function(String)? onChunk,
  }) async {
    if (!_realismEnabled || !_passageOfTimeEnabled || _activeCharacter == null) return;
    final recentCount = _messages.length < 4 ? _messages.length : 4;
    final recent = _messages.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.displayText}')
        .join('\n');
    final charName = _activeCharacter!.name;
    final validTimes = [
      'dawn',
      'morning',
      'late_morning',
      'afternoon',
      'evening',
      'night',
    ];
    final currentIndex = validTimes.indexOf(_timeOfDay);

    // ── Deterministic Time Clock ──────────────────────────────────────────────
    // Increment every AI turn. Time only advances when the threshold is reached —
    // the LLM can only veto (hold) the advance, never skip multiple periods.
    _turnsSinceLastTimeAdvance++;
    final bool timeEligible = _turnsSinceLastTimeAdvance >= _turnsPerTimePeriod;

    if (timeEligible) {
      final currentPostureCtx = _spatialStance.isNotEmpty
          ? '$charName is currently: "$_spatialStance".\n'
                'Maintain spatial continuity — only change position if the conversation describes them moving. '
                'Do NOT teleport them to a new location or stance without narrative cause.\n\n'
          : '';
      final holdPrompt =
          'You are evaluating physical state for $charName.\n\n'
          '$currentPostureCtx'
          'Enough turns have passed that time should advance from "$_timeOfDay" to the next period.\n'
          '1. "hold_time": true ONLY if the scene is visibly mid-action (e.g. mid-fight, actively doing something). false otherwise — let time advance normally.\n'
          '2. "new_day": true ONLY if the conversation explicitly transitioned to the next day (slept, woke up, scene break). Only valid when current time is "night".\n'
          '3. "posture": $charName\'s current physical position and location (brief phrase). Evolve naturally from their previous stance — only change if the scene describes movement. Use "none" if unknown.\n\n'
          'Recent conversation:\n$recent\n\n'
          'Respond with ONLY a flat JSON object containing "hold_time", "new_day", and "posture".';
      try {
        final raw = await _fireLLMEval(
          holdPrompt,
          grammar: _buildKoboldGrammar(_kGbnfJsonObject),
          onChunk: onChunk,
        );
        if (raw != null) {
          final text = _stripThinkBlocks(raw).isNotEmpty
              ? _stripThinkBlocks(raw)
              : raw;
          final holdMatch = RegExp(
            r'"hold_time"\s*:\s*(true|false)',
          ).firstMatch(text);
          final shouldHold = holdMatch?.group(1) == 'true';

          if (!shouldHold) {
            if (currentIndex < validTimes.length - 1) {
              _timeOfDay = validTimes[currentIndex + 1];
            } else {
              _timeOfDay = validTimes[0];
              _dayCount++;
              debugPrint('[Realism:Time] Day rolled over! Day $_dayCount');
            }
            _turnsSinceLastTimeAdvance = 0;
            debugPrint(
              '[Realism:Time] Advanced to $_timeOfDay (Day $_dayCount)',
            );
          } else {
            debugPrint(
              '[Realism:Time] Held — scene mid-action, time stays at $_timeOfDay',
            );
          }

          // Explicit new-day override (e.g. woke up after night)
          final newDayMatch = RegExp(
            r'"new_day"\s*:\s*(true|false)',
          ).firstMatch(text);
          if (newDayMatch?.group(1) == 'true' &&
              _timeOfDay == 'night' &&
              !shouldHold) {
            // already handled by rollover above
          } else if (newDayMatch?.group(1) == 'true' &&
              currentIndex >= validTimes.indexOf('evening')) {
            _dayCount++;
            _timeOfDay = validTimes[0];
            _turnsSinceLastTimeAdvance = 0;
            debugPrint(
              '[Realism:Time] Explicit new-day transition. Day $_dayCount',
            );
          }

          final postureMatch = RegExp(
            r'"posture"\s*:\s*"([^"]+)"',
          ).firstMatch(text);
          debugPrint(
            '[Realism:Physical] Posture match: ${postureMatch?.group(0)}',
          );
          if (postureMatch != null) {
            final p = postureMatch.group(1)!.trim();
            _spatialStance = (p.toLowerCase() == 'none' || p.isEmpty) ? '' : p;
          }
        }
      } catch (e) {
        // Eval failed — still advance so time never freezes
        if (currentIndex < validTimes.length - 1) {
          _timeOfDay = validTimes[currentIndex + 1];
        } else {
          _timeOfDay = validTimes[0];
          _dayCount++;
        }
        _turnsSinceLastTimeAdvance = 0;
        debugPrint(
          '[Realism:Time] Eval error, auto-advanced to $_timeOfDay: $e',
        );
      }
    } else {
      // Not yet eligible — grab posture only
      final emotionCtx = _characterEmotion.isNotEmpty
          ? '$charName is currently feeling $_characterEmotion ($_emotionIntensity). '
          : '';
      final currentPostureCtx = _spatialStance.isNotEmpty
          ? 'Current position: "$_spatialStance". '
          : '';
      final posturePrompt =
          '${emotionCtx}${currentPostureCtx}Relationship tension: $shortTermTierName.\n\n'
          'Based on the emotional context and recent exchange, what is $charName\'s '
          'current physical position and stance? Maintain spatial continuity — only '
          'change if the conversation describes them moving. Do NOT teleport them to a '
          'new location without narrative cause.\n\n'
          'Recent conversation:\n$recent\n\n'
          'Respond with ONLY valid JSON like: {"posture": "standing by the window"} or {"posture": "none"}';

      try {
        final raw = await _fireLLMEval(
          posturePrompt,
          grammar: _buildKoboldGrammar(_kGbnfJsonObject),
          onChunk: onChunk,
        );
        if (raw != null) {
          final text = _stripThinkBlocks(raw).isNotEmpty
              ? _stripThinkBlocks(raw)
              : raw;
          final postureMatch = RegExp(
            r'"posture"\s*:\s*"([^"]+)"',
          ).firstMatch(text);
          debugPrint(
            '[Realism:Physical] ELSE branch posture match: ${postureMatch?.group(0)}',
          );
          if (postureMatch != null) {
            final p = postureMatch.group(1)!.trim();
            _spatialStance = (p.toLowerCase() == 'none' || p.isEmpty) ? '' : p;
          }
        }
      } catch (_) {}
    }
    debugPrint(
      '[Realism:Physical] Posture: $_spatialStance | Time: $_timeOfDay (Day $_dayCount) | TurnsToNext: ${_turnsPerTimePeriod - _turnsSinceLastTimeAdvance}',
    );
    notifyListeners();
  }

  Future<void> _evaluateNarrativeCall({void Function(String)? onChunk}) async {
    if (!_realismEnabled || _activeCharacter == null) return;
    final recentCount = _messages.length < 4 ? _messages.length : 4;
    final recent = _messages.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.displayText}')
        .join('\n');
    final charName = _activeCharacter!.name;
    final oPrompt = primaryObjective != null
        ? '1. "proposed_objective": A meaningful, emotionally-driven goal $charName independently wants to pursue — something DISTINCT from the current Primary Quest ("${primaryObjective!.objective}"). Must be a significant personal, social, or narrative goal triggered by a STRONG, specific event THIS turn. NOT a trivial step, and NOT a restatement of the primary quest.\n'
              '   ⚠ Default to "none". 90% of turns should produce "none". Only propose one if $charName would literally lose sleep over it.\n'
        : '1. "proposed_objective": A meaningful, emotionally-driven goal $charName independently wants to pursue, triggered by a strong specific event THIS turn — a significant hidden agenda, emotional need, personal conflict, or moral dilemma.\n'
              '   ⚠ Default to "none". 90% of turns should produce "none". Only propose one if $charName would literally lose sleep over it.\n';
    final prompt =
        'You are an autonomous story engine evaluating narrative progression for $charName.\n\n'
        '$oPrompt'
        '2. "fixation_topic": An *intrusive* thought $charName cannot stop returning to — something that haunts them across multiple scenes, not a temporary reaction to this turn. Must be significant enough to color their behavior unprompted. Default: "none".\n\n'
        'Recent conversation:\n$recent\n\n'
        'Respond with ONLY a flat JSON object containing "proposed_objective", and "fixation_topic".';

    try {
      final raw = await _fireLLMEval(
        prompt,
        grammar: _buildKoboldGrammar(_kGbnfJsonObject),
        onChunk: onChunk,
      );
      if (raw == null) return;
      final text = _stripThinkBlocks(raw).isNotEmpty
          ? _stripThinkBlocks(raw)
          : raw;

      if (_fixationLifespan > 0) {
        _fixationLifespan--;
        if (_fixationLifespan == 0) _activeFixation = '';
      }
      final fixationMatch = RegExp(
        r'"fixation_topic"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (fixationMatch != null) {
        String f = fixationMatch.group(1)!.trim();
        if (f.toLowerCase() == 'none' || f.isEmpty) {
          _activeFixation = '';
          _fixationLifespan = 0;
        } else if (f != _activeFixation) {
          _activeFixation = f;
          _fixationLifespan = 3;
        }
      }

      final objectiveMatch = RegExp(
        r'"proposed_objective"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (objectiveMatch != null) {
        final newObj = objectiveMatch.group(1)!.trim();
        if (newObj.toLowerCase() != 'none' && newObj.isNotEmpty) {
          final isDuplicate = _activeObjectives.any(
            (o) => o.objective.toLowerCase() == newObj.toLowerCase(),
          );
          if (!isDuplicate) {
            debugPrint(
              '[Realism:Narrative] Autonomous objective proposed: $newObj',
            );
            await setObjective(newObj, isPrimary: false);
            final addedObj = _activeObjectives
                .where(
                  (o) =>
                      o.objective.toLowerCase() == newObj.toLowerCase() &&
                      !o.isPrimary,
                )
                .firstOrNull;
            if (addedObj != null)
              unawaited(
                generateObjectiveTasks(addedObj, taskCount: 3, nsfw: false),
              );
          }
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[Realism:Narrative] Failed: $e');
    }
  }

  /// ── One-Shot Eval (Experimental) ─────────────────────────────────────────
  /// Fused replacement for _evaluateRelationshipCall + _evaluateSceneStateCall.
  /// Issues a SINGLE LLM inference that evaluates all realism state fields at
  /// once, cutting pre-generation blocking overhead from 2 calls to 1.
  ///
  /// Enable via Settings → Realism → "One-Shot Eval (Experimental)".
  /// Not default because some models struggle with the combined prompt length.
  Future<void> _evaluateOneShotCall({void Function(String)? onChunk}) async {
    if (!_realismEnabled || _activeCharacter == null) return;

    // Keep the eval prompt lean for local models — use fewer messages and a
    // shorter personality snippet to reduce prefill time on large models.
    final recentCount = _messages.length < 4 ? _messages.length : 4;
    final recent = _messages.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.displayText}')
        .join('\n');

    final charName = _activeCharacter!.name;
    final userName = _userPersonaService.persona.name;

    String personalityInjection = '';
    if (_activeCharacter!.personality.isNotEmpty) {
      final p = _activeCharacter!.personality.length > 300
          ? _activeCharacter!.personality.substring(0, 300)
          : _activeCharacter!.personality;
      personalityInjection =
          'Account for $charName\'s specific personality traits:\n"$p"\n\n';
    }

    // ── Relationship & trust context ──
    final emotionCtx = _characterEmotion.isNotEmpty
        ? 'Current emotional state: $_characterEmotion ($_emotionIntensity). '
        : '';
    final relationshipCtx =
        '${emotionCtx}Current relationship tension: $shortTermTierName | Trust level: $_trustLevel\n\n';

    final arousalField = _nsfwCooldownEnabled
        ? ', "arousal_delta": <number -10 to +10>'
        : '';
    // Arousal is field 7 (after posture), objective is 8, fixation 9, reason 10
    final arousalInstr = _nsfwCooldownEnabled
        ? '7. "arousal_delta": Physical arousal shift this turn. (-10 to +10)\n'
              '   Current arousal: $_arousalLevel/10. '
              'Arousal = DESIRE and PHYSICAL RESPONSE, not progress toward orgasm.\n'
              '   Can spike suddenly (unexpected intimacy) or crash (embarrassment/disgust).\n'
              '   High arousal = intensely turned on, NOT about to climax — climax only during active sexual contact at peak arousal.\n'
        : '';

    // Determine the next field number after arousal (or after posture if arousal disabled)
    final objNum = _nsfwCooldownEnabled ? 8 : 7;
    final fixNum = objNum + 1;
    final reasonNum = fixNum + 1;

    final prompt =
        'You are evaluating the current state of a roleplay scene involving $charName.\n\n'
        '$personalityInjection'
        '$relationshipCtx'
        'Reactions are subjective! Evaluate ALL changes through $charName\'s specific personality.\n\n'
        'Evaluate ALL of the following at once:\n'
        '1. "relationship_delta": How did this exchange shift $charName\'s warmth toward $userName? (-50 to +50)\n'
        '   +50: Life-changing — fundamentally redefines the relationship\n'
        '   +30: Profoundly moving — raw vulnerability, sacrifice, or devotion\n'
        '   +20: Deeply touched — significant emotional breakthrough\n'
        '   +10: Meaningfully warmed — clearly strengthens the connection\n'
        '   +5: Moved | +2: Warmed up | +1: Mildly pleasant | 0: No change\n'
        '   -1: Slightly put off | -2: Annoyed | -5: Hurt\n'
        '   -10: Wounded | -20: Deeply hurt | -30: Devastated | -50: Devastating betrayal\n'
        '   ⚠ Default to 0 for normal conversation.\n'
        '2. "trust_delta": Did $userName — NOT $charName — do something that builds or destroys $charName\'s trust in $userName? (-200 to +50)\n'
        '   Trust is SUBJECTIVE to $charName\'s personality. What builds trust for one character may break it for another.\n'
        '   +30 to +50: EXTRAORDINARY trust — selfless sacrifice, proving loyalty beyond doubt, protecting $charName at real personal cost\n'
        '   +10 to +20: Meaningfully trustworthy — kept a hard promise, showed real vulnerability, stood firm under pressure\n'
        '   +5: Did what $charName craves or values | +2: acted respectably | 0: Neutral\n'
        '   -5: acted in a way $charName finds personally untrustworthy | -30: deliberate betrayal | -200: unforgivable\n'
        '   ⚠ Default to 0. If $charName is the one acting (e.g. $charName lied, felt guilty): always 0.\n'
        '3. "emotion": $charName\'s overarching emotional state (one nuanced word).\n'
        '   NOT generic ("happy"/"sad") — find the specific texture: wistful not sad, flustered not happy, prickly not angry.\n'
        '   Filter through $charName\'s personality — a stoic character in deep pain shows "guarded", not "devastated".\n'
        '4. "emotion_intensity": mild, moderate, or strong\n'
        '5. "bond_reason": One brief in-character thought from $charName explaining the relationship shift, or "none" if delta is 0.\n'
        '6. "posture": $charName\'s spatial/physical stance (brief grounded phrase), or "none"\n'
        '$arousalInstr'
        '${primaryObjective != null ? '$objNum. "proposed_objective": A meaningful, emotionally-driven goal $charName independently wants to pursue — something DISTINCT from the current Primary Quest ("${primaryObjective!.objective}"). Triggered by a STRONG event THIS turn.\n   ⚠ Default to "none". 90% of turns should produce "none".\n' : '$objNum. "proposed_objective": A meaningful, emotionally-driven goal triggered by a strong event THIS turn. Default: "none". 90% of turns should produce "none".\n'}'
        '$fixNum. "fixation_topic": An *intrusive* thought $charName cannot stop returning to — haunts them across scenes, not a temporary reaction. Default: "none".\n'
        '$reasonNum. "reason": One brief sentence explaining the key relationship change, or "none"\n\n'
        'Recent conversation:\n$recent\n\n'
        'Respond with ONLY a JSON object containing all fields above$arousalField.';

    try {
      debugPrint('[Realism:OneShot] Evaluating (fused call)...');
      final raw = await _fireLLMEval(
        prompt,
        grammar: _buildKoboldGrammar(_kGbnfJsonObject),
        onChunk: onChunk,
      );
      if (raw == null) return;

      final searchText = _stripThinkBlocks(raw);
      final text = searchText.isNotEmpty ? searchText : raw;

      // ── Relationship fields ──
      int bondDelta = 0;
      final deltaMatch = RegExp(
        r'"relationship_delta"\s*:\s*(-?\d+)',
      ).firstMatch(text);
      if (deltaMatch != null) {
        bondDelta = (int.tryParse(deltaMatch.group(1)!) ?? 0).clamp(-50, 50);
        _applyScoreDelta(bondDelta);
      }

      int moodDelta = 0;
      final moodMatch = RegExp(r'"mood_shift"\s*:\s*(-?\d+)').firstMatch(text);

      int trustDelta = 0;
      final trustMatch = RegExp(
        r'"trust_delta"\s*:\s*(-?\d+)',
      ).firstMatch(text);
      if (trustMatch != null) {
        trustDelta = (int.tryParse(trustMatch.group(1)!) ?? 0).clamp(-200, 50);
        if (trustDelta != 0) {
          _trustLevel = (_trustLevel + trustDelta).clamp(-100, 100);
          debugPrint(
            '[Realism:OneShot] Trust shifted by $trustDelta -> $_trustLevel',
          );
          // Arm the repair window on any severe single-turn drop
          if (trustDelta <= -20) {
            _pendingTrustRepair = true;
            debugPrint('[Realism:Trust] Severe drop — repair window armed');
            notifyListeners();
          }
        }
      }

      int arousalDelta = 0;
      if (_nsfwCooldownEnabled) {
        final arousalMatch = RegExp(
          r'"arousal_delta"\s*:\s*(-?\d+)',
        ).firstMatch(text);
        if (arousalMatch != null) {
          arousalDelta = (int.tryParse(arousalMatch.group(1)!) ?? 0).clamp(
            -10,
            10,
          );
          _arousalLevel = (_arousalLevel + arousalDelta).clamp(-3, 10);
        }
      }

      if (bondDelta != 0 || arousalDelta != 0 || trustDelta != 0) {
        _pendingRealismMetadata = {
          'bond_delta': bondDelta,
          if (arousalDelta != 0) 'arousal_delta': arousalDelta,
          if (trustDelta != 0) 'trust_delta': trustDelta,
        };
      }

      // ── Autonomous Objective ──
      final objectiveMatch = RegExp(
        r'"proposed_objective"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (objectiveMatch != null) {
        final newObj = objectiveMatch.group(1)!.trim();
        if (newObj.toLowerCase() != 'none' && newObj.isNotEmpty) {
          // Avoid setting the exact same goal if it's already active
          final isDuplicate = _activeObjectives.any(
            (o) => o.objective.toLowerCase() == newObj.toLowerCase(),
          );
          if (!isDuplicate) {
            debugPrint(
              '[Realism:OneShot] Autonomous objective proposed: $newObj',
            );
            // Auto objectives are strictly secondary (isPrimary = false)
            await setObjective(newObj, isPrimary: false);
            // Auto-generate tasks for the new side quest (3 tasks)
            final addedObj = _activeObjectives
                .where(
                  (o) =>
                      o.objective.toLowerCase() == newObj.toLowerCase() &&
                      !o.isPrimary,
                )
                .firstOrNull;
            if (addedObj != null) {
              unawaited(
                generateObjectiveTasks(addedObj, taskCount: 3, nsfw: false),
              );
            }
          }
        }
      }

      // ── Scene fields ──
      final emotionMatch = RegExp(
        r'"emotion"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (emotionMatch != null) {
        _characterEmotion = emotionMatch.group(1)!.toLowerCase().trim();
      }

      final intensityMatch = RegExp(
        r'"emotion_intensity"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (intensityMatch != null) {
        _emotionIntensity = intensityMatch.group(1)!.toLowerCase().trim();
      }

      final postureMatch = RegExp(
        r'"posture"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (postureMatch != null) {
        final p = postureMatch.group(1)!.trim();
        _spatialStance = (p.toLowerCase() == 'none' || p.isEmpty) ? '' : p;
      }

      if (_fixationLifespan > 0) {
        _fixationLifespan--;
        if (_fixationLifespan == 0) {
          _activeFixation = '';
          debugPrint('[Realism:OneShot] Fixation decayed and cleared.');
        }
      }
      final fixationMatch = RegExp(
        r'"fixation_topic"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (fixationMatch != null) {
        final f = fixationMatch.group(1)!.trim();
        if (f.toLowerCase() == 'none' || f.isEmpty) {
          _activeFixation = '';
          _fixationLifespan = 0;
        } else if (f != _activeFixation) {
          _activeFixation = f;
          _fixationLifespan = 3;
          debugPrint('[Realism:OneShot] New obsession: $f (3 turns)');
        }
      }

      final reasonMatch = RegExp(r'"reason"\s*:\s*"([^"]*)"').firstMatch(text);
      debugPrint(
        '[Realism:OneShot] Done — Emotion: $_characterEmotion ($_emotionIntensity), '
        'Time: $_timeOfDay, Reason: ${reasonMatch?.group(1) ?? 'unknown'}',
      );

      // Bundle full state snapshot for time-travel forking
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata!['emotion_label'] = _characterEmotion;
      _pendingRealismMetadata!['realism_state'] = _captureRealismState();

      _saveChat();
      notifyListeners();
    } catch (e) {
      debugPrint(
        '[Realism:OneShot] Failed: $e — falling back to dual-call on next turn',
      );
    }
  }

  /// One-shot trust repair evaluator.
  ///
  /// Called automatically on the user's next message after a severe trust drop
  /// (≥ -20 delta). Replaces the normal relationship eval for that turn.
  /// The LLM weighs the explanation against character persona and chat history,
  /// returning a trust_recovery value (0–60). Recovery is capped to prevent
  /// instant restoration from Absolute Distrust.
  Future<void> _evaluateTrustRepairCall(
    String userExplanation, {
    void Function(String)? onChunk,
  }) async {
    if (!_realismEnabled || _activeCharacter == null) return;

    final charName = _activeCharacter!.name;
    final persona = _activeCharacter!.personality.length > 600
        ? _activeCharacter!.personality.substring(0, 600)
        : _activeCharacter!.personality;
    final recentCount = _messages.length < 10 ? _messages.length : 10;
    final history = _messages.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.displayText}')
        .join('\n');

    final prompt =
        'You are evaluating whether $charName should partially restore trust '
        'after a severe breach caused by the previous interaction.\n\n'
        'Character Persona: $persona\n\n'
        'Recent chat history (last ~10 messages):\n$history\n\n'
        'The user\'s trust-repair explanation is: "$userExplanation"\n\n'
        'Evaluate ONLY whether this explanation is convincing given:\n'
        '1. The character\'s personality — are they forgiving, stubborn, paranoid, naive?\n'
        '2. The plausibility of the explanation against the chat history\n'
        '3. Whether the explanation contradicts established facts\n\n'
        'Rules:\n'
        '- trust_recovery: 0 (rejected) to 60 (fully convincing)\n'
        '- Paranoid/skeptical characters: give 0–20 even for good explanations\n'
        '- Forgiving/naive characters: may give 30–60 for plausible explanations\n'
        '- Do NOT give 60 unless the explanation perfectly resolves the breach\n'
        '- "reason" must be 1 short sentence from the character\'s POV\n\n'
        'Respond with ONLY: {"trust_recovery": <0-60>, "verdict": "accepted|partial|rejected", "reason": "<brief>"}\n';

    try {
      debugPrint('[Realism:TrustRepair] Evaluating repair attempt...');
      final raw = await _fireLLMEval(
        prompt,
        grammar: _buildKoboldGrammar(_kGbnfJsonObject),
        onChunk: onChunk,
      );
      if (raw == null) return;

      final text = _stripThinkBlocks(raw).trim();

      final recoveryMatch = RegExp(
        r'"trust_recovery"\s*:\s*(\d+)',
      ).firstMatch(text);
      final verdictMatch = RegExp(
        r'"verdict"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      final reasonMatch = RegExp(r'"reason"\s*:\s*"([^"]*)"').firstMatch(text);

      final recovery = (int.tryParse(recoveryMatch?.group(1) ?? '0') ?? 0)
          .clamp(0, 60);
      final verdict = verdictMatch?.group(1) ?? 'rejected';
      final reason = reasonMatch?.group(1) ?? '';

      if (recovery > 0) {
        _trustLevel = (_trustLevel + recovery).clamp(-100, 100);
        debugPrint(
          '[Realism:TrustRepair] $verdict — recovered $recovery → $_trustLevel ($reason)',
        );
      } else {
        debugPrint('[Realism:TrustRepair] Rejected — no recovery ($reason)');
      }

      // Surface verdict in message metadata so swipe history can record it
      _pendingRealismMetadata = {
        ...?_pendingRealismMetadata,
        'trust_repair_verdict': verdict,
        'trust_repair_recovery': recovery,
        if (reason.isNotEmpty) 'trust_repair_reason': reason,
      };

      _saveChat();
      notifyListeners();
    } catch (e) {
      debugPrint('[Realism:TrustRepair] Failed: $e');
    }
  }

  Map<String, dynamic> _captureRealismState() {
    return {
      'affectionScore': _affectionScore,
      'relationshipTier': _relationshipTier,
      'longTermScore': _longTermScore,
      'longTermTier': _longTermTier,
      'turnsSinceLongTermCheck': _turnsSinceLongTermCheck,
      'shortTermDeltasSummary': _shortTermDeltasSummary,
      'moodDecayCounter': _moodDecayCounter,
      'characterEmotion': _characterEmotion,
      'emotionIntensity': _emotionIntensity,
      'timeOfDay': _timeOfDay,
      'dayCount': _dayCount,
      'arousalLevel': _arousalLevel,
      'cooldownTurnsRemaining': _cooldownTurnsRemaining,
      'cooldownTurnsTotal': _cooldownTurnsTotal,
      'trustLevel': _trustLevel,
      'activeFixation': _activeFixation,
      'fixationLifespan': _fixationLifespan,
      'spatialStance': _spatialStance,
    };
  }

  void _restoreRealismStateFromMessage(ChatMessage? msg) {
    if (msg == null) return;

    // Check if the current visible node has an active swipe metadata array or just the base metadata
    final meta = msg.activeMetadata;
    if (meta == null || !meta.containsKey('realism_state')) {
      debugPrint(
        '[Realism] No time-travel snapshot found in message. Legacy state kept.',
      );
      return;
    }

    final state = meta['realism_state'] as Map<String, dynamic>;
    _affectionScore = state['affectionScore'] as int? ?? _affectionScore;
    _relationshipTier = state['relationshipTier'] as int? ?? _relationshipTier;
    _longTermScore = state['longTermScore'] as int? ?? _longTermScore;
    _longTermTier = state['longTermTier'] as int? ?? _longTermTier;
    _turnsSinceLongTermCheck =
        state['turnsSinceLongTermCheck'] as int? ?? _turnsSinceLongTermCheck;
    _shortTermDeltasSummary =
        state['shortTermDeltasSummary'] as int? ?? _shortTermDeltasSummary;
    _moodDecayCounter = state['moodDecayCounter'] as int? ?? _moodDecayCounter;
    _characterEmotion =
        state['characterEmotion'] as String? ?? _characterEmotion;
    _emotionIntensity =
        state['emotionIntensity'] as String? ?? _emotionIntensity;
    _timeOfDay = state['timeOfDay'] as String? ?? _timeOfDay;
    _dayCount = state['dayCount'] as int? ?? _dayCount;
    _arousalLevel = state['arousalLevel'] as int? ?? _arousalLevel;
    _cooldownTurnsRemaining =
        state['cooldownTurnsRemaining'] as int? ?? _cooldownTurnsRemaining;
    _cooldownTurnsTotal =
        state['cooldownTurnsTotal'] as int? ?? _cooldownTurnsRemaining;

    // v3.0 Restorations
    _trustLevel = state['trustLevel'] as int? ?? _trustLevel;
    _activeFixation = state['activeFixation'] as String? ?? _activeFixation;
    _fixationLifespan = state['fixationLifespan'] as int? ?? _fixationLifespan;
    _spatialStance = state['spatialStance'] as String? ?? _spatialStance;

    debugPrint(
      '[Realism] Engine state successfully rolled back to match timeline.',
    );
  }

  /// Fired post-generation against the AI's completed response text.
  /// The LLM writes the scene first — THEN we detect climax and apply
  /// the refractory cooldown so the *next* turn's prompt blocks re-escalation.
  Future<void> _checkClimaxInResponse(String responseText) async {
    if (responseText.trim().isEmpty) return;
    if (_activeCharacter == null) return;
    final charName = _activeCharacter!.name;

    String personalityInjection = '';
    if (_activeCharacter!.personality.isNotEmpty) {
      final p = _activeCharacter!.personality.length > 600
          ? _activeCharacter!.personality.substring(0, 600)
          : _activeCharacter!.personality;
      personalityInjection = 'Character Personality Traits:\n"$p"\n\n';
    }

    final prompt =
        'Read the following character response and answer ONE question.\n\n'
        '$personalityInjection'
        'RESPONSE:\n$responseText\n\n'
        'Question: Did $charName (and ONLY $charName) PHYSICALLY reach climax/orgasm in this response? '
        'This must be an event actively occurring or just occurred in the text — '
        '$charName specifically physically reaching orgasm right now. '
        'If the response describes the user climaxing, but NOT $charName, you MUST answer false.\n'
        'Do NOT answer true for: dirty talk, innuendo, arousal build-up, '
        'sexual activity that has not yet reached completion, or casual use of words like "cum". '
        'ONLY answer true if $charName\'s orgasm/climax is unambiguously depicted as actively happening.\n'
        'If true, ALSO estimate their "refractory_turns" (recovery time before they can be aroused again). '
        'A normal character might take 5-7 turns. A highly sexual/nympho character takes 1-2 turns. Use their personality traits to decide.\n\n'
        'Respond with ONLY a JSON object: {"climax_detected": <true|false>, "refractory_turns": <number 1-8>, "reason": "<brief>"}';

    try {
      debugPrint('[Realism:Climax] Checking AI response for climax...');
      final raw = await _fireLLMEval(
        prompt,
        grammar: _buildKoboldGrammar(_kGbnfJsonObject),
      );
      if (raw == null) return;

      final searchText = _stripThinkBlocks(raw);
      final text = searchText.isNotEmpty ? searchText : raw;

      final match = RegExp(
        r'"climax_detected"\s*:\s*(true|false)',
      ).firstMatch(text);
      if (match != null && match.group(1) == 'true') {
        int turns = 5;
        final turnMatch = RegExp(
          r'"refractory_turns"\s*:\s*(\d+)',
        ).firstMatch(text);
        if (turnMatch != null) {
          turns = (int.tryParse(turnMatch.group(1)!) ?? 5).clamp(1, 10);
        }

        // Save pre-climax state on the message so regen can restore it
        final preClimaxArousal = _arousalLevel;
        if (_messages.isNotEmpty && !_messages.last.isUser) {
          final msg = _messages.last;
          final meta = Map<String, dynamic>.from(msg.activeMetadata ?? {});
          meta['climax_triggered'] = true;
          meta['pre_climax_arousal'] = preClimaxArousal;
          msg.swipeMetadata[msg.swipeIndex] = meta;
        }

        _cooldownTurnsTotal = turns;
        _cooldownTurnsRemaining = turns;
        _arousalLevel = -3;
        debugPrint(
          '[Realism:Climax] Confirmed — refractory cooldown started ($turns turns), '
          'arousal $preClimaxArousal → -3 (pre-climax saved for regen)',
        );
        _saveChat();
        notifyListeners();
      } else {
        debugPrint('[Realism:Climax] No climax detected.');
      }
    } catch (e) {
      debugPrint('[Realism:Climax] Check failed: $e');
    }
  }

  // ── Score / State Helpers ──

  void _applyScoreDelta(int delta) {
    _shortTermDeltasSummary += delta;
    _turnsSinceLongTermCheck++;

    if (_turnsSinceLongTermCheck >= 5) {
      _evalLongTermGrowth();
    }

    if (delta == 0) return;
    final oldScore = _affectionScore;
    final oldTier = _relationshipTier;

    _affectionScore = (_affectionScore + delta).clamp(-150, 150);
    _relationshipTier = _calculateTier(_affectionScore);

    if (_affectionScore != oldScore || _relationshipTier != oldTier) {
      debugPrint(
        '[Realism] Short-Term Bond: $oldScore \u2192 $_affectionScore, '
        'Tier: $oldTier \u2192 $_relationshipTier ($shortTermTierName)',
      );
    }
  }

  void _evalLongTermGrowth() {
    final oldLTScore = _longTermScore;
    final oldLTTier = _longTermTier;

    if (_shortTermDeltasSummary >= 2 && _relationshipTier >= 0) {
      _longTermScore = (_longTermScore + 1).clamp(-150, 150);
    } else if (_shortTermDeltasSummary <= -2 && _relationshipTier <= 0) {
      _longTermScore = (_longTermScore - 1).clamp(-150, 150);
    }

    _longTermTier = _calculateTier(_longTermScore);
    _turnsSinceLongTermCheck = 0;
    _shortTermDeltasSummary = 0;

    if (_longTermScore != oldLTScore || _longTermTier != oldLTTier) {
      debugPrint(
        '[Realism] Long-Term Bond updated: $oldLTScore \u2192 $_longTermScore, '
        'Tier: $oldLTTier \u2192 $_longTermTier ($longTermTierName)',
      );
    } else {
      debugPrint(
        '[Realism] Long-Term Bond check (No change) - Status: $_longTermScore ($longTermTierName)',
      );
    }
  }

  void _applyMoodDecay() {}

  // ── Public Toggle Methods ──

  Future<void> setRealismEnabled(bool enabled) async {
    _realismEnabled = enabled;
    // Anchor the narrative weekday to the real-world day when realism first turns on
    if (enabled) _startDayOfWeek = DateTime.now().weekday;

    if (enabled && _activeGroup == null && _activeCharacter != null) {
      // ── Solution 1: Pending greeting flag ────────────────────────────
      // The greeting was placed while realism was off. Fire the baseline
      // eval now that the user has explicitly enabled it.
      if (_greetingEvalPending && !_hasRealismBaseline) {
        debugPrint(
          '[Realism] Consuming pending greeting eval (user enabled realism after load).',
        );
        _runPostGreetingEval();
      }
      // ── Solution 3: Retroactive scan on enable ────────────────────────
      // Realism was enabled mid-conversation with no baseline captured yet
      // (emotion is blank, affection is zero, multiple messages exist).
      // Run a full retrospective eval against all visible messages.
      else if (!_hasRealismBaseline && _messages.length > 1) {
        debugPrint(
          '[Realism] No baseline detected — running retroactive scan on enable.',
        );
        _runRetroactiveBaselineEval();
      }
    }

    if (!enabled) {
      // IMPORTANT: Do NOT zero out realism state when disabling!
      // Just stop using it. State persists in memory/DB so re-enabling restores it.
      // Old behavior was destructive - it deleted all character building progress.
      debugPrint(
        '[Realism] Disabled (preserving state: bond=$_affectionScore, trust=$_trustLevel, emotion=$_characterEmotion)',
      );
    }
    await _saveChat();
    notifyListeners();
  }

  Future<void> setNsfwCooldownEnabled(bool enabled) async {
    _nsfwCooldownEnabled = enabled;
    if (!enabled) {
      _cooldownTurnsRemaining = 0;
      _cooldownTurnsTotal = 0;
      _arousalLevel = 0;
    }
    await _saveChat();
    notifyListeners();
  }

  Future<void> setPassageOfTimeEnabled(bool enabled) async {
    _passageOfTimeEnabled = enabled;
    await _saveChat();
    notifyListeners();
  }

  // ── Manual Time Nudge ────────────────────────────────────────────────────

  /// Called by the sidebar chevron buttons. delta = +1 (forward) or -1 (back).
  Future<void> nudgeTimePeriod(int delta) async {
    if (!_realismEnabled) return;
    final validTimes = [
      'dawn',
      'morning',
      'late_morning',
      'afternoon',
      'evening',
      'night',
    ];
    int idx = validTimes.indexOf(_timeOfDay);
    idx = (idx + delta) % validTimes.length;
    if (idx < 0) {
      idx = validTimes.length - 1;
      _dayCount = (_dayCount - 1).clamp(1, 9999);
    } else if (delta > 0 &&
        validTimes.indexOf(_timeOfDay) == validTimes.length - 1) {
      // wrapped forward past night
      _dayCount++;
    }
    _timeOfDay = validTimes[idx];
    _turnsSinceLastTimeAdvance = 0; // reset clock after manual nudge
    await _saveChat();
    notifyListeners();
  }

  // ── OOC Time-Skip Detector ───────────────────────────────────────────────

  /// Scans the user message for OOC/narrative time-skip language and advances
  /// the clock by the inferred number of periods. Stamps the skip into
  /// _pendingRealismMetadata so it appears in the next AI message's delta row.
  /// 
  /// NOTE: Respects the global passageOfTimeEnabled setting. If disabled,
  /// this function does nothing even if OOC markers are present.
  void _detectOocTimeSkip(String text) {
    // Respect global passage of time setting
    if (!_passageOfTimeEnabled) {
      debugPrint('[Realism:OOC] Time-skip requested but passageOfTimeEnabled=false, ignoring');
      return;
    }

    final lower = text.toLowerCase();

    // Only fire on OOC-style markers or explicit timeskip language
    final hasOocMarker = RegExp(
      r'\(ooc[:\s]|\[ooc|\*ooc\b|ooc:',
    ).hasMatch(lower);
    final hasSkipPhrase = RegExp(
      r'\b(time.?skip|fast.?forward|skip ahead|several hours|a few hours|hours? later|'
      r'the next (morning|day|evening|afternoon|night|dawn)|'
      r'next (morning|day|evening|afternoon|night|dawn)|'
      r'hours? pass|time passes|the following (morning|day)|'
      r'wake up the next|woke up|the next day)\b',
    ).hasMatch(lower);

    if (!hasOocMarker && !hasSkipPhrase) return;

    // Estimate period count from duration language
    int periods = 1;
    bool isNextDay = false;

    if (RegExp(
      r'\b(all day|entire day|full day|day passes|the (whole|entire) day)\b',
    ).hasMatch(lower)) {
      periods = 4;
    } else if (RegExp(
      r'\b(next (morning|day)|the following (morning|day)|wake up|woke up|overnight)\b',
    ).hasMatch(lower)) {
      isNextDay = true;
      _dayCount++;
      _timeOfDay = 'dawn';
      _turnsSinceLastTimeAdvance = 0;
      _pendingRealismMetadata ??= {};
      _pendingRealismMetadata!['time_skip_to'] = 'Dawn · Day $_dayCount';
      notifyListeners();
      debugPrint('[Realism:OOC] Next-day transition → Day $_dayCount, dawn');
      return;
    } else if (RegExp(
      r'\b(several hours|many hours|a long time|hours? pass)\b',
    ).hasMatch(lower)) {
      periods = 3;
    } else if (RegExp(
      r'\b(a few hours|couple.{0,5}hours|2.{0,5}hours|two hours)\b',
    ).hasMatch(lower)) {
      periods = 2;
    } else if (RegExp(
      r'\b(an hour|1 hour|one hour|a while|some time)\b',
    ).hasMatch(lower)) {
      periods = 1;
    } else if (hasOocMarker) {
      periods = 1;
    }

    if (periods <= 0) return;

    final validTimes = [
      'dawn',
      'morning',
      'late_morning',
      'afternoon',
      'evening',
      'night',
    ];
    int idx = validTimes.indexOf(_timeOfDay);
    for (int i = 0; i < periods; i++) {
      idx++;
      if (idx >= validTimes.length) {
        idx = 0;
        _dayCount++;
      }
    }
    _timeOfDay = validTimes[idx];
    _turnsSinceLastTimeAdvance = 0;
    _pendingRealismMetadata ??= {};
    // Capitalise the time label for display (late_morning -> Late Morning)
    final displayTime = _timeOfDay
        .split('_')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
    _pendingRealismMetadata!['time_skip_to'] = displayTime;
    notifyListeners();
    debugPrint(
      '[Realism:OOC] Time-skip: +$periods period(s) → $_timeOfDay (Day $_dayCount)',
    );
  }

  // ── Chaos Mode / Chance Time ──────────────────────────────────────────────

  Future<void> setChaosModeEnabled(bool enabled) async {
    _chaosModeEnabled = enabled;
    if (!enabled) _chaosPressure = 0;
    await _saveChat();
    notifyListeners();
  }

  Future<void> setChaosNsfwEnabled(bool enabled) async {
    _chaosNsfwEnabled = enabled;
    await _saveChat();
    notifyListeners();
  }

  /// Clear the pending event after the UI has consumed it.
  void clearChanceTimeEvent() {
    _pendingChanceTimeEvent = null;
    // no notifyListeners — avoids rebuild storms; UI already consumed it
  }

  /// Returns 8 randomly-sampled events for the wheel UI to display.
  List<String> spinWheelEvents() {
    final pool = List<String>.from(_chanceTimeEventPool);
    if (_chaosNsfwEnabled) pool.addAll(_chanceTimeNsfwPool);
    pool.shuffle();
    return pool.take(8).toList();
  }

  /// Called by the wheel overlay once the animation lands on an event.
  /// Stores the event as a prompt injection for the next response and
  /// resumes the paused sendMessage flow.
  Future<void> applyChanceTimeResult(String event, String charName) async {
    final display = event.replaceAll('{{char}}', charName);
    _pendingChanceTimeEvent = display;
    _chaosPressure = 0;

    // Store in metadata so the delta chip appears on the AI's next message
    _pendingRealismMetadata ??= {};
    _pendingRealismMetadata!['chance_time_event'] = display;

    // Store as a prompt injection — the character will weave this into their
    // natural response to the user's message instead of getting a separate
    // dedicated reaction message.
    _pendingChaosInjection = display;

    await _saveChat();
    notifyListeners();
    debugPrint('[ChanceTime] Applied: $display — injecting into next response');

    // Resume the paused sendMessage flow
    _chanceTimeCompleter?.complete();
  }

  /// Per-turn auto-trigger check. Returns true if the wheel should pop this turn.
  bool checkAndTickChaosPressure() {
    if (!_chaosModeEnabled) return false;
    _chaosPressure = (_chaosPressure + _chaosGrowthPerTurn).clamp(
      0,
      _chaosPressureCap,
    );
    final effectiveChance = (_chaosBaseChance + _chaosPressure).clamp(
      0,
      _chaosPressureCap,
    );
    // Use microseconds for better entropy than milliseconds
    final roll = (DateTime.now().microsecondsSinceEpoch % 100);
    final fires = roll < effectiveChance;
    if (fires)
      debugPrint(
        '[ChanceTime] Auto-trigger! pressure=$_chaosPressure% roll=$roll',
      );
    return fires;
  }

  // ── Chance Time Event Pool (120 events) ───────────────────────────────────

  static const List<String> _chanceTimeEventPool = [
    // 🟢 Fortune — lucky breaks, good vibes, unexpected wins
    '{{char}} just found something valuable they completely forgot they owned',
    '{{char}} was mistaken for someone important and is being treated accordingly',
    '{{char}} stumbled into a crowd of admirers who are totally convinced they are famous',
    'Something {{char}} lost a long time ago has just turned up in the most unexpected place',
    '{{char}} received a completely unexpected compliment that made their entire day',
    '{{char}} just discovered a hidden stash of food or treats at exactly the right moment',
    '{{char}} pulled off something impressive entirely by accident and everyone thinks it was intentional',
    'A stranger just paid for {{char}}\'s meal or expenses without any explanation',
    '{{char}} arrived somewhere late only to discover being late was absolutely the right call',
    '{{char}} just found out they won something they entered and completely forgot about',
    'An incredibly beautiful view or spectacle has appeared right where {{char}} is standing',
    '{{char}} accidentally said the perfect thing at the perfect moment',
    '{{char}} is having the best hair or appearance day of their life today',
    'Something that was going terribly for {{char}} has inexplicably turned completely around',
    '{{char}} discovered a shortcut or trick that makes everything significantly easier',
    '{{char}} just got offered a seat, a table, or a spot that would normally go to someone far more important',
    'The weather turned absolutely perfect the moment {{char}} stepped outside',
    '{{char}} ran into someone they\'ve been hoping to bump into for a long time',
    'An animal has taken an immediate and enthusiastic liking to {{char}}',
    '{{char}} made a guess that turned out to be completely correct',
    '{{char}} just overheard something that is extremely good news for them',
    'Someone has arrived to help {{char}} with exactly the thing they were struggling with',
    '{{char}} was offered more than they asked for and no one is sure why',
    'A small act of kindness {{char}} performed long ago has just come back around in a big way',
    '{{char}} woke up unusually well-rested and is in an extremely good mood for no particular reason',
    '{{char}} got the best seat, the best portion, or the best version of the thing',
    '{{char}} just accomplished something they\'ve been attempting for a very long time',
    'Everyone in the room seems to be finding {{char}} particularly charming today',
    '{{char}} discovered someone nearby has been quietly rooting for them this whole time',
    '{{char}} received unexpected credit for something that worked out really well',
    // 🔴 Misfortune — embarrassing, gross, inconvenient, funny
    '{{char}} urgently needs to use the restroom and there is no good option available',
    '{{char}} just stepped in something extremely unpleasant and is now tracking it everywhere',
    '{{char}} sneezed violently at the absolute worst possible moment',
    '{{char}} sat in something wet and has no idea how to address this situation',
    '{{char}} has the hiccups and they won\'t stop no matter what',
    '{{char}} just bit their tongue so hard they can barely form words',
    '{{char}} has been walking around with something in their teeth for an unknown amount of time',
    '{{char}}\'s clothing has ripped in an extremely inconvenient location',
    '{{char}} knocked something over in the loudest and most attention-grabbing way possible',
    '{{char}} tripped, caught themselves, but everyone absolutely saw it',
    '{{char}} let out an involuntary sound at the most inopportune moment imaginable',
    '{{char}} is extremely itchy somewhere they cannot scratch in polite company',
    '{{char}} just spilled something on themselves and is pretending it didn\'t happen',
    '{{char}}\'s stomach is making alarming sounds at the worst possible time',
    '{{char}} said goodbye to someone and then walked in the same direction as them',
    '{{char}} confidently greeted someone who has no idea who they are',
    '{{char}} waved back at someone who was not actually waving at them',
    '{{char}} laughed at something completely inappropriate and now can\'t stop',
    '{{char}} walked into something that was very clearly visible',
    '{{char}} has a piece of hair or debris stuck somewhere they can\'t remove it without help',
    '{{char}} woke up with a spectacular and inexplicable mark on their face',
    '{{char}} is dealing with a persistent and loudly squeaking piece of their clothing or equipment',
    '{{char}} just yawned enormously in front of exactly the wrong person',
    '{{char}} sent a message and immediately regretted every single word of it',
    '{{char}} is trying to pretend they remember the name of someone they absolutely do not',
    '{{char}}\'s hands are completely full at exactly the moment they desperately need a free hand',
    '{{char}} dropped something and it rolled to the most awkward possible location',
    '{{char}} got something in their eye at the worst possible time',
    '{{char}} has been nodding along in a conversation they stopped following ten minutes ago',
    '{{char}} just realized they\'ve been pronouncing something wrong their entire life',
    '{{char}} is having a sneezing fit and it is not going to stop anytime soon',
    '{{char}} just made direct and sustained eye contact with someone during an extremely awkward moment',
    '{{char}} reached for something confidently and missed completely',
    '{{char}} fell asleep briefly somewhere very inappropriate',
    '{{char}} made a very confident prediction that was immediately and publicly proven wrong',
    '{{char}} went to tell a story and completely forgot where it was going halfway through',
    '{{char}} is having the most stubborn and uncooperative hair day of their life',
    '{{char}} just let out an involuntary noise while trying to lift something heavy',
    '{{char}} immediately regretted the food choice they were so confident about',
    '{{char}} is dealing with a shoe, boot, or footwear issue that keeps demanding attention',
    '{{char}}\'s name has been mispronounced repeatedly and they\'ve been too polite to correct it',
    '{{char}} just realized they\'ve had something on backwards or inside-out all day',
    // 💛 Chaos — strange, unpredictable, and completely out of nowhere
    'A bird flew directly into the space {{char}} is in and absolutely refuses to leave',
    'An incredibly loud and disruptive noise has started nearby with no explanation',
    'Something nearby fell over on its own for no apparent reason whatsoever',
    '{{char}} has become the unexpected center of a very enthusiastic and confusing celebration',
    'A small animal has decided that {{char}}\'s belongings are now its home',
    'A person in an extremely unusual outfit has just walked by and is completely serious',
    'Everything that could make noise in {{char}}\'s vicinity is making noise simultaneously',
    'A sudden and powerful gust of wind has created a chaotic situation involving {{char}}\'s belongings',
    'An extremely large insect has appeared and is refusing to be dealt with',
    'The lighting wherever {{char}} is has done something extremely unexpected',
    'A crowd has formed nearby for reasons that remain completely unclear',
    'Someone nearby is telling a very loud and very one-sided story that involves {{char}} by name',
    'A persistent and enthusiastic child or small creature has fixated entirely on {{char}}',
    'Something is cooking or burning nearby and the smell is completely overwhelming',
    'A piece of {{char}}\'s environment has broken in a way that is more funny than serious',
    'An uninvited guest or creature has appeared and made themselves entirely at home',
    '{{char}}\'s surroundings have spontaneously rearranged themselves in a confusing way',
    'A very confident stranger is trying to recruit {{char}} into something on the spot',
    'Two other people nearby have begun a surprisingly loud and personal argument',
    'Something small and ridiculous has escalated into a situation requiring everyone\'s attention',
    'A nearby animal is doing exactly what it should not be doing and nobody can stop it',
    '{{char}} has accidentally started a trend and people nearby are copying them',
    'Someone nearby is performing something unsolicited and making eye contact with {{char}}',
    'The rhythm of everything around {{char}} has synchronized into something inexplicably musical',
    'A delivery or package has arrived for {{char}} with completely incorrect contents',
    'Something that was definitely fixed has become unfixed again at the worst time',
    'An object nearby has developed a squeak, rattle, or wobble that cannot be ignored',
    '{{char}} is in the middle of a very long and intricate process when something interrupts everything',
    'Every seat, surface, or resting spot nearby is occupied or unavailable',
    'Something {{char}} was counting on to work fine has decided today is not that day',
    // 💜 Wild Cards — character-specific fun situations
    '{{char}} is absolutely starving and trying very hard not to let it show',
    '{{char}} has a song stuck in their head that keeps making them move involuntarily',
    '{{char}} is desperately trying to stay awake and losing the battle',
    '{{char}} just thought of a really good comeback to something that happened hours ago',
    '{{char}} is trying to look like they know what they\'re doing in a situation they definitely do not',
    '{{char}} has been holding in a laugh for so long it\'s becoming a physical problem',
    '{{char}} is running on absolutely no sleep and extremely committed to pretending otherwise',
    '{{char}} is convinced something delicious is nearby but can\'t figure out where it\'s coming from',
    '{{char}} just thought of something embarrassing from years ago completely unprompted',
    '{{char}} is trying to remember something very important and it is right on the tip of their tongue',
    '{{char}} is putting in extraordinary effort to appear calm about something that is stressing them out enormously',
    '{{char}} is extremely competitive about something that absolutely does not warrant it',
    '{{char}} has been daydreaming so intensely they\'ve lost track of what\'s happening around them',
    '{{char}} has made a small purchase or decision they are now deeply second-guessing',
    '{{char}} is trying very hard not to react to something that is extremely funny to them right now',
    '{{char}} strongly suspects they are being pranked and is watching everyone very carefully',
    '{{char}} is operating at an unusually high level of confidence today for no specific reason',
    '{{char}} has a strong opinion about something minor and is barely keeping it to themselves',
    '{{char}} is lowkey obsessed with a very small and inconsequential detail in their environment',
    '{{char}} just caught themselves doing something weird and hopes nobody noticed',
    '{{char}} is absolutely convinced they\'re forgetting something but cannot figure out what',
    '{{char}} has developed an instant and irrational dislike of a completely harmless object nearby',
    '{{char}} just said something they think was smooth and they\'re very pleased with themselves',
    '{{char}} is being incredibly polite about something they find deeply annoying',
    '{{char}} is trying to subtly fix an error they made without drawing attention to it',
    '{{char}} is losing a silent battle with their posture',
    '{{char}} has a very specific craving that is now impossible to stop thinking about',
    '{{char}} just finished something they were putting off for a long time and feels unreasonably good',
    '{{char}} is distracted by an extremely irrelevant but very interesting thing happening nearby',
    '{{char}} is holding a very strong opinion hostage and it is getting increasingly difficult',
    // 🎪 Slapstick — physical comedy, chaotic energy
    'Someone set off a stink bomb nearby and {{char}} is directly in the blast zone',
    '{{char}}\'s pants, skirt, or equivalent just fell down in the most public setting imaginable',
    '{{char}} has been glitter-bombed and is now sparkling uncontrollably from every surface',
    '{{char}} got completely and thoroughly soaked by something falling, splashing, or bursting nearby',
    '{{char}} sat on something that made an extremely loud and unfortunate noise in a silent room',
    '{{char}} walked into a door, a pole, or a wall that was extremely clearly there',
    '{{char}} got tangled in something — a rope, a curtain, their own clothing — and is now stuck',
    '{{char}} accidentally flung food at someone important while trying to eat normally',
    '{{char}} sneezed so violently they knocked something over, fell backwards, or both',
    '{{char}} slipped on something wet and went down in slow motion in front of everyone',
    '{{char}} tried to lean casually on something and it moved, sending them stumbling',
    '{{char}} just ripped something open far too aggressively and the contents went everywhere',
    '{{char}} attempted to catch something thrown to them and missed so badly it hit someone else',
    '{{char}}\'s chair, stool, or seat just collapsed underneath them with maximum noise',
    '{{char}} tried to open a container and the lid popped off, launching the contents directly at them',
    '{{char}} walked confidently forward and stepped directly into a puddle, hole, or ditch',
    '{{char}} got hit in the face by something soft, harmless, and deeply undignified',
    'A bucket, bag, or container of something has tipped directly onto {{char}}\'s head',
    '{{char}} grabbed something sticky and now cannot let go without making things worse',
    '{{char}} accidentally knocked over a chain reaction of objects like a line of dominoes',
    '{{char}} tried to do something athletic and it went spectacularly wrong in front of an audience',
    '{{char}} got their hand, foot, or head stuck in something and is now committed to this situation',
    'Someone threw something at {{char}} as a prank and their reaction made everything funnier',
    '{{char}}\'s belt, strap, or buckle just snapped at the worst possible moment',
    '{{char}} is covered in something — paint, mud, ink, flour — and cannot explain how it happened',
  ];

  // ── Chance Time NSFW Pool (only included when 🌶️ toggle is on) ──────────

  static const List<String> _chanceTimeNsfwPool = [
    '{{char}} just received an extremely personal delivery in front of other people',
    'A stranger on the street just propositioned {{char}} loudly and confidently in public',
    '{{char}}\'s most private undergarment is now visible and they have not yet realized it',
    '{{char}} accidentally opened something very explicit on a shared or public surface',
    '{{char}} just made a noise that sounded extremely suggestive and now everyone is staring',
    'Someone mistook {{char}} for a worker at a very adult-themed establishment',
    '{{char}} found something very intimate that does not belong to them in their belongings',
    '{{char}} walked into the wrong room and what they saw cannot be unseen',
    '{{char}} scratched somewhere inappropriate and someone absolutely noticed',
    '{{char}} is visibly aroused at the most inconvenient moment imaginable and is scrambling',
    'A stranger just described {{char}} in extremely flattering and very explicit physical terms within earshot',
    '{{char}}\'s clothing has shifted in a way that is revealing something they very much did not intend to share',
    '{{char}} just discovered that a private intimate item of theirs has been on display this whole time',
    'A love letter or extremely personal note written about {{char}} has just been read aloud to the room',
    '{{char}} was caught very obviously checking someone out and both parties know it',
    '{{char}} accidentally grabbed someone in a place that was very much not where they intended',
    'Something {{char}} said came out sounding incredibly dirty and everyone heard it',
    '{{char}} has just received a gift that is unmistakably sexual and has to open it in front of people',
    '{{char}} is trying extremely hard to hide a visible physical reaction to someone attractive nearby',
    '{{char}} walked in on something they desperately wish they had not walked in on',
    'Someone just loudly and publicly asked {{char}} about their love life in excruciating detail',
    '{{char}} realized their private journal or personal writing has been read by someone else',
    '{{char}} is wearing something under their clothes that they would be mortified for anyone to discover',
    'An ex-lover of {{char}} has just appeared and is being very loud about their shared history',
    '{{char}} was dared to do something embarrassingly intimate and is now trapped by their own pride',
    '{{char}} made eye contact with someone attractive at exactly the wrong moment and froze',
    '{{char}} was mistaken for someone\'s lover and the misunderstanding is escalating fast',
    '{{char}} just got caught practicing a flirtatious or seductive pose in what they thought was privacy',
    'A very personal garment belonging to {{char}} has just fallen out of their bag in a crowded space',
    '{{char}} accidentally moaned, groaned, or made a compromising sound while stretching or sitting down',
  ];
}
