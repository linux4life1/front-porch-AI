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
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/services/capability/vision_support_resolver.dart';
import 'package:front_porch_ai/services/caption/local_caption_service.dart';
import 'package:front_porch_ai/services/vision_eval.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/worker_backend.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/avatar_gallery.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/group_turn_manager.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/services/expression_classifier.dart'; // top-level for ExpressionClassifierService type in @Dep shim (pre-existing)
import 'package:front_porch_ai/services/live_gen_progress.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:drift/drift.dart' as drift;

part 'chat/chat_service_group_read.dart';
part 'chat/chat_service_group_settings.dart';
part 'chat/chat_service_growth.dart';
part 'chat/chat_service_sillytavern.dart';
part 'chat/chat_service_import_seed.dart';
part 'chat/chat_service_import_walk.dart';
part 'chat/chat_service_chat_package.dart';
part 'chat/chat_service_chat_package_import.dart';
part 'chat/chat_service_enhance_chats.dart';
part 'chat/chat_service_package_extras.dart';
part 'chat/chat_service_group_realism_helpers.dart';
part 'chat/chat_service_history.dart';
part 'chat/chat_service_group_membership.dart';
part 'chat/chat_service_group_members.dart';
part 'chat/chat_service_reprocess.dart';
part 'chat/chat_service_regen_revert.dart';
part 'chat/chat_service_needs_reprocess.dart';
part 'chat/chat_service_chat_entry.dart';
part 'chat/chat_service_group_entry.dart';
part 'chat/chat_service_session_state.dart';
part 'chat/chat_service_session_state_save.dart';
part 'chat/chat_service_session_load.dart';
part 'chat/chat_service_session_hydrate.dart';
part 'chat/chat_service_session_window.dart';
part 'chat/chat_service_realism_evals.dart';
part 'chat/chat_service_actions.dart';
part 'chat/chat_service_objectives.dart';
part 'chat/chat_service_objective_tasks.dart';
part 'chat/chat_service_objective_completion.dart';
part 'chat/chat_service_realism_dance.dart';
part 'chat/chat_service_speaker_objectives.dart';
part 'chat/chat_service_impersonate.dart';
part 'chat/chat_service_session_manage.dart';
part 'chat/chat_service_session_fork.dart';
part 'chat/chat_service_session_new_chat_prep.dart';
part 'chat/chat_service_generation.dart';
part 'chat/chat_service_generation_blocks.dart';
part 'chat/chat_service_generation_plan.dart';
part 'chat/chat_service_generation_rag.dart';
part 'chat/chat_service_generation_request.dart';
part 'chat/chat_service_generation_stream.dart';
part 'chat/chat_service_generation_postgen.dart';
part 'chat/chat_service_generation_postgen_engine.dart';
part 'chat/chat_service_pockets.dart';
part 'chat/chat_service_pockets_pass.dart';
part 'chat/chat_service_item_cards.dart';
part 'chat/chat_service_birthday.dart';
part 'chat/chat_service_episode_crumbs.dart';
part 'chat/chat_service_night_skip.dart';
part 'chat/chat_service_reply_facts.dart';
part 'chat/chat_service_mood.dart';
part 'chat/chat_service_climax.dart';
part 'chat/chat_service_cast.dart';
part 'chat/chat_service_cast_shrink.dart';
part 'chat/chat_service_images.dart';
part 'chat/chat_service_photo.dart';
part 'chat/chat_service_idle_autonomous.dart';
part 'chat/chat_service_greeting.dart';
part 'chat/chat_service_greeting_seed.dart';
part 'chat/chat_service_variants.dart';
part 'chat/chat_service_prompt_blocks.dart';
part 'chat/chat_service_scene_guest.dart';
part 'chat/chat_service_controls.dart';
part 'chat/chat_service_context_budget.dart';
part 'chat/chat_service_wiring_realism.dart';
part 'chat/chat_service_web_search.dart';
part 'chat/chat_service_wiring_evals.dart';
part 'chat/chat_service_wiring_evals_judges.dart';
part 'chat/chat_service_llm_lanes.dart';
part 'chat/chat_service_wiring_memory.dart';
part 'chat/chat_service_wiring_injection.dart';
part 'chat/chat_service_wiring_injection_leaves.dart';
part 'chat/chat_service_send.dart';
part 'chat/chat_service_send_handoff.dart';
part 'chat/chat_service_turn_flow.dart';
part 'chat/chat_service_message_ops.dart';
part 'chat/chat_service_timeline.dart';
part 'chat/chat_service_guest_flow.dart';
part 'chat/chat_service_accessors.dart';
part 'chat/chat_service_accessors_living.dart';
part 'chat/chat_service_today_sentence.dart';
part 'chat/chat_service_planner_resolve.dart';
part 'chat/chat_service_defaults.dart';
part 'chat/chat_service_fields.dart';

// Realism-eval cancel flag + GBNF note live in chat_service_defaults.dart.

class ChatService extends ChangeNotifier
    with ChatServiceTodaySentence, ChatServiceFieldBag {
  final KoboldService _koboldService;
  final UserPersonaService _userPersonaService;
  final StorageService _storageService;
  final WorldRepository _worldRepository;
  late AppDatabase _db;
  LLMProvider? _llmProvider;
  CharacterRepository? _characterRepository;
  TtsService? _ttsService;
  ImageGenService? _imageGenService;
  MemoryService? _memoryService;

  /// Test-only overrides for driving the real LLM paths (realism evals +
  /// chat generation) with canned responses without constructing a full
  /// LLMProvider (heavy deps). Used by chat_service_*_test.dart and
  /// chat_service_realism_engine_test.dart (the new real-engine suite).
  @visibleForTesting
  LLMService? testLlmServiceOverride;
  @visibleForTesting
  bool testIsLocalOverride = false;

  @visibleForTesting
  LLMService? testWorkerLlmServiceOverride;

  /// Test hook: import awaits this before mutating so a Send can race it.
  @visibleForTesting
  Completer<void>? testImportHold;

  List<String> get suggestedActions => _suggestedActions;
  bool get isGeneratingActions => _isGeneratingActions;

  Objective? get primaryObjective =>
      _activeObjectives.where((o) => o.isPrimary).firstOrNull;
  List<Objective> get secondaryObjectives =>
      _activeObjectives.where((o) => !o.isPrimary).toList();

  /// Whether a completion check is currently running.
  ///
  /// Kept in the class body (not the objectives extension) because
  /// [FakeChatService] overrides it in golden tests — extension members are
  /// statically dispatched and cannot be overridden.
  bool get isCheckingCompletion => _isCheckingCompletion;

  /// Web-facade fakes override this; body in chat_service_accessors.dart.
  Future<void> addGeneratedImageMessage(
    String path,
    String prompt, {
    String? senderName,
    String? characterId,
  }) => _addGeneratedImageMessageImpl(
    path,
    prompt,
    senderName: senderName,
    characterId: characterId,
  );

  /// Fake-pinned (widget fakes override; extension members can't be).
  /// Ending a call also releases any parked call-model swap.
  bool get callMode => _callMode;
  set callMode(bool value) {
    _callMode = value;
    if (!value) _exitCallEvalModelSwap();
    notifyListeners();
  }

  /// Per-character realism / needs / state for group chats.
  /// Keyed by stable charId. Populated from the hidden checkpoint.
  /// Per-member realism state, typed (U7). Keys are runtime member ids
  /// (stableGroupId). The wrapper preserves the legacy wire format exactly —
  /// see group_member_realism.dart for why it is a wrapper and not fields.
  Map<String, GroupMemberRealism> _groupRealism = {};

  /// The group member id (`_getCharacterIdFromCard`) whose realism state is being
  /// processed for the turn currently generating. Set the moment the speaker is
  /// picked in `_generateResponse` and cleared in its `finally`, so every realism
  /// consumer (prompt injection, decay, post-gen) keys on the character actually
  /// speaking — `nextCharacter` points at the *upcoming* speaker and is null for
  /// random turn order, so it cannot be that signal. Null outside a turn (the
  /// pre-pick window keeps its prior nextCharacter-based behaviour).
  String? _turnSpeakerIdForRealism;

  List<Objective> getObjectivesForGroupCharacter(CharacterCard character) =>
      _getObjectivesForGroupCharacterImpl(character);

  late final _lorebookScanner = _buildLorebookScanner();
  late final _lorebookInjector = _buildLorebookInjector();
  late final _timeService = _buildTimeService();

  Biome get activeChatBiome => _biomeSchedule.biomeAt(_timeService.dayCount);
  late final _chaosModeService = _buildChaosModeService();
  late final _webSearchService = _buildWebSearchService();
  late final _wikiSearchService = _buildWikiSearchService();
  late final _nsfwService = _buildNsfwService();
  late final _needsSimulation = _buildNeedsSimulation();
  late final _relationshipService = _buildRelationshipService();
  late final _expressionService = _buildExpressionService();
  late final _authorNoteBuilder = _buildAuthorNoteBuilder();
  late final _relationshipInjection = _buildRelationshipInjection();
  late final _emotionInjection = _buildEmotionInjection();
  late final _behavioralInjection = _buildBehavioralInjection();
  late final _timeInjection = _buildTimeInjection();

  /// Today's story weather, or null when off. Body in chat_service_accessors.dart.
  DailyWeather? get currentWeather => _currentWeatherImpl;

  /// Tomorrow's forecast under the same gate. Body in chat_service_accessors.dart.
  DailyWeather? get upcomingWeather => _upcomingWeatherImpl;

  /// The current DAY-PART's weather. Body in chat_service_accessors.dart.
  SegmentWeather? get currentSegmentWeather => _currentSegmentWeatherImpl;

  late final _weatherInjection = _buildWeatherInjection();
  late final _ambitionService = _buildAmbitionService();

  /// Sidebar/web read surface (Living Time §6). Body in chat_service_accessors.dart.
  List<({String text, int progress})> ambitionsFor(CharacterCard card) =>
      _ambitionsForImpl(card);

  late final _ambitionInjection = _buildAmbitionInjection();
  late final _planInjection = _buildPlanInjection();

  /// Likes & Dislikes fragment — NOT realism-gated (see PreferencesInjection).
  late final _preferencesInjection = _buildPreferencesInjection();

  /// Pockets & Wardrobe — the per-turn record fragment. Answers to its own
  /// switch only (see PocketsEval for why it depends on nothing else).
  late final _inventoryInjection = _buildInventoryInjection();

  /// The Pockets detection pass. Its own eval by design — see PocketsEval.
  late final _pocketsEval = _buildPocketsEval();

  /// Afterglow's climax check. Its own pass — see ClimaxEval.
  late final _climaxEval = _buildClimaxEval();

  // `_pockets` / `_replyFactsRaw` live on ChatServiceFieldBag (extensions
  // cannot declare fields). pocketsFor / characterIdFor stay HERE — FakeChatService
  // can only override class members.

  /// The record for [characterId], whichever mode the chat is in — the ONE
  /// read every Pockets surface uses, so 1:1 and group cannot diverge about
  /// whose pockets are whose.
  ///
  /// **Absent when the feature is off, and that is the whole gate.** The design
  /// doc's rule is "off means off: no eval fires, no injection block is built,
  /// and the sidebar panel is absent — not greyed, absent", and putting it here
  /// is what makes that true by construction rather than by three call sites
  /// remembering to ask. Two of them did remember (the injection wiring and the
  /// web facade) and the sidebar did not, so a chat that had run with Pockets ON
  /// went on showing its Wardrobe row after the switch went down — a panel for a
  /// disabled feature, and a desktop/web split, since the web facade hid it
  /// correctly.
  ///
  /// This HIDES, it never erases. `_pockets` and the per-member records are left
  /// exactly as they were, the v47 save wire writes `_pockets` directly, and the
  /// load wire restores it directly — all deliberately outside this gate — so
  /// switching Pockets off and back on finds everything they were carrying still
  /// there. The rewind path likewise writes through `setPocketsFor`, not here.
  Pockets? pocketsFor(String characterId) {
    if (!_storageService.realismSettings.pocketsEnabled) return null;
    if (_activeGroup == null) return _pockets;
    return _groupRealism[characterId]?.pockets;
  }

  /// The one Pockets switch, exposed for UI gating. [pocketsFor] returning
  /// null cannot distinguish "feature off" (panel absent) from "no record
  /// yet" (panel present with just the add affordance) — this can. A CLASS
  /// member, not an extension one, on purpose: the sidebar calls it in
  /// build(), and the golden FakeChatService can only override class members
  /// (its pocketsFor note documents the same contract — this getter riding
  /// the extension is exactly how bcea783 turned a sidebar golden red).
  bool get pocketsFeatureEnabled =>
      _storageService.realismSettings.pocketsEnabled;

  /// The stable id for a card, exposed so UI can look a record up without
  /// reaching for a private. Same resolver every Pockets surface uses.
  String characterIdFor(CharacterCard c) => _getCharacterIdFromCard(c);

  late final _promiseDebtService = _buildPromiseDebtService();
  late final _promiseDebtInjection = _buildPromiseDebtInjection();
  late final _dreamService = _buildDreamService();
  late final _nsfwInjection = _buildNsfwInjection();
  late final _chaosInjection = _buildChaosInjection();
  late final _needsInjection = _buildNeedsInjection();
  late final _realismStateInjection = _buildRealismStateInjection();
  late final _llmEvalEngine = _buildLlmEvalEngine();
  late final _realismVerifier = _buildRealismVerifier();
  late final _needsImpactEvaluator = _buildNeedsImpactEvaluator();
  late final _realismEvals = _buildRealismEvals();
  late final _objectiveProposal = _buildObjectiveProposal();
  late final _journalStore = _buildJournalStore();
  late final _porchMemoryImport = _buildPorchMemoryImport();
  late final _journalReview = _buildJournalReview();

  JournalReview get journalReview => _journalReview;

  /// Shared Journal/Growth tools-vs-XML probe (one per backend identity).
  final _toolProbe = ToolTransportProbe();
  late final _toolSupportTester = _buildToolSupportTester();
  late final _journalMaintenance = _buildJournalMaintenance();

  /// Journal UI door — class member so FakeChatService can override it.
  JournalStore get journalStore => _journalStore;

  late final MilestoneFeed milestoneFeed = _buildMilestoneFeed();
  late final _journalInjection = _buildJournalInjection();
  late final _growthStore = _buildGrowthStore();
  late final _growthReview = _buildGrowthReview();
  late final _growthService = _buildGrowthService();

  CharacterCard? get activeCharacter => _activeCharacter;
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Token streaming — deliberately the NARROW sense. It drives the send
  /// button, and widening it to cover post-generation was tried and REVERTED:
  /// background evals then held the composer disabled for most of a turn on
  /// slow machines (caught by E2E on the CI runners). The real constraint
  /// lives at the composer instead: its guard must use the SAME predicate as
  /// [sendMessage], or it clears the field for a send the service refuses.
  /// See [isSettlingTurn] and the mirror in `_sendCurrentMessage`.
  bool get isGenerating => _isGenerating;
  bool get isImporting => _isImporting;
  String? get currentSessionId => _currentSessionId;

  double get generationProgress => _generationProgress;
  int get tokensGenerated => _tokensGenerated;
  int get maxTokens => _maxTokens;
  GenerationPhase get generationPhase => _generationPhase;

  /// Seconds elapsed since entering the prefill phase. Returns 0 if not prefilling.
  double get prefillElapsedSeconds => _prefillStartTime != null
      ? DateTime.now().difference(_prefillStartTime!).inMilliseconds / 1000.0
      : 0.0;

  /// Cached KoboldCPP performance data from last /api/extra/perf poll.
  Map<String, dynamic>? get lastPerfData => _lastPerfData;

  /// The active backend's live generation progress (truthful status bar):
  /// Kobold console counts, oMLX admin-stats poll, or LM Studio's runtime
  /// log — null for plain remote APIs, which expose no prefill data. Thin
  /// delegation; source selection lives in LLMProvider.activeLiveProgress.
  LiveGenProgress? get activeLiveProgress =>
      _llmProvider?.activeLiveProgress ?? _koboldService.liveProgress;

  /// Estimated prompt token count for the current generation (for progress display).
  int get prefillPromptTokens => _prefillPromptTokens;
  bool get isGroupMode => _groupManager?.isActive ?? false;
  GroupChat? get activeGroup => _groupManager?.activeGroup;
  bool get observerMode => _groupManager?.observerMode ?? false;
  List<CharacterCard> get groupCharacters =>
      _groupManager?.characters ?? const <CharacterCard>[];

  /// Ordered cast of speakers, group or 1:1+guests. Body in chat_service_accessors.dart.
  List<ChatParticipant> get cast => _castImpl;
  double get tokensPerSecond => _tokensPerSecondImpl;

  int get greetingIndex => _greetingIndex;

  /// Listener wiring lives in [_initImpl] (chat_service_accessors.dart).
  ChatService(
    this._koboldService,
    this._userPersonaService,
    this._storageService,
    this._worldRepository,
  ) {
    _initImpl();
  }

  String get authorNote => _authorNote;
  int get authorNoteStrength => _authorNoteStrength;

  Map<String, int> get lastPromptBudget => _contextBudget.budget;
  Map<String, String> get lastPromptSections => _contextBudget.sections;
  ContextBudgetSource get promptBudgetSource => _contextBudget.source;
  DateTime? get promptBudgetAssembledAt => _contextBudget.assembledAt;
  Future<void> estimateContextBudgetNow() => _estimateContextBudgetNow();
  int get contextSize =>
      _sessionGenSettings.resolveContextSize(_storageService);

  /// Per-session generation parameter overrides. The dialog reads/writes this.
  ChatGenerationSettings get sessionGenSettings => _sessionGenSettings;
  set sessionGenSettings(ChatGenerationSettings value) =>
      _setSessionGenSettingsImpl(value);

  /// Per-chat theme overrides (preset + customized colors/font/background/border).
  ChatThemeOverrides get sessionThemeOverrides => _sessionThemeOverrides;
  set sessionThemeOverrides(ChatThemeOverrides value) =>
      _setSessionThemeOverridesImpl(value);

  String get summary => _summary;
  bool get summaryPaused => _summaryPaused;
  int get summaryLastIndex => _summaryLastIndex;
  bool get isSummaryGenerating => _isSummaryGenerating;
  RelationshipService get relationshipService => _relationshipService;
  TimeService get timeService => _timeService;
  NsfwService get nsfwService => _nsfwService;
  ChaosModeService get chaosModeService => _chaosModeService;
  WebSearchService get webSearchService => _webSearchService;
  bool get webSearchEnabled => _webSearchService.isActive;
  WikiSearchService get wikiSearchService => _wikiSearchService;
  String get wikiBaseUrl => _wikiBaseUrlImpl;
  Future<void> setWikiBaseUrl(String url) => _setWikiBaseUrlImpl(url);
  NeedsSimulation get needsSimulation => _needsSimulation;

  bool get realismEnabled => _realismEnabled;
  String spatialStanceForGroupCharacter(CharacterCard c) =>
      _spatialStanceForGroupCharacterImpl(c);
  bool? withUserForGroupCharacter(CharacterCard c) =>
      _withUserForGroupCharacterImpl(c);
  bool get objectivesActive => _objectivesActiveImpl;
  MemoryService? get memoryService => _memoryService;
  Map<String, dynamic>? get lastRagReceipt => _lastRagReceiptImpl;
  String get standingMoodSummary => standingMoodSummaryImpl;

  bool get isEvaluatingRealism => _isEvaluatingRealism;
  bool get isProcessingGreeting => _isProcessingGreeting;

  // Verifier phase (for overlay header "🕵️ Verifying Realism output" + pass progress, and bubble chip data source).
  // God coordination only; leaf drives via cb thins (no new god void _).
  bool get isVerifyingRealism => _isVerifyingRealism;
  int get verificationPass => _verificationPass;
  int get verificationMaxPasses => _verificationMaxPasses;

  /// Stream text with think blocks stripped (for display) — memoized on
  /// string identity (the overlay + web broadcast read it every notify).
  /// Class member, not extension: FakeChatService overrides it in goldens.
  /// The memo fields stay here; the getter body is in
  /// chat_service_accessors.dart.
  String get realismEvalStreamTextClean => _realismEvalStreamTextCleanImpl;
  String get characterEmotion => _characterEmotion;

  String get emotionIntensity => _emotionIntensity;

  /// Per-session Needs (Sims-style) simulation active. Seeded from the card.
  bool get needsSimEnabled => _needsSimEnabled;

  bool get chaosNsfwEnabled => _chaosModeService.chaosNsfwEnabled;

  int? get regenerableHostBelowGuestsIndex =>
      _regenerableHostBelowGuestsIndexImpl;

  void editMessage(int index, String newText) =>
      _editMessageImpl(index, newText);

  // Growth Rings flag (zeroed on all reset/entry sites). Class-pinned for fakes.
  bool get isGrowthPassRunning => _isGrowthPassRunning;

  /// Active objectives for [character] in the current session; body in chat_service_objectives.dart.
  Future<List<Objective>> getActiveObjectivesFor(CharacterCard character) =>
      _getActiveObjectivesForImpl(character);

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposeCleanupImpl();
    super.dispose();
  }
}
