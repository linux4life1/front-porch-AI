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
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/storage/settings/appearance_settings.dart';
import 'package:front_porch_ai/services/tool_choice_style_probe.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/chat_defaults.dart';
import 'package:front_porch_ai/services/chat/llm_lanes.dart';
import 'package:front_porch_ai/services/chat/doors/actions/actions_door.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_api.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/transfer/transfer.dart';
import 'package:front_porch_ai/services/chat/doors/coalesced_notify.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_api.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edits_api.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edits_door.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_api.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_api.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/group_turn_manager.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/services/expression_classifier.dart';
import 'package:front_porch_ai/services/live_gen_progress.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';

export 'chat/realism_snapshot.dart'
    show kSpatialStancePreTurn, kWithUserPreTurn;
export 'chat/doors/actions/actions_api.dart';
export 'chat/doors/cast/cast_api.dart';
export 'chat/doors/media/media_api.dart';
export 'chat/doors/transfer/transfer_api.dart';
export 'chat/doors/objectives/objectives_api.dart';
export 'chat/doors/edits/edits_api.dart';
export 'chat/doors/session/session_api.dart';
export 'chat/doors/entry/entry_api.dart';
export 'chat/doors/realism/realism_api.dart';
export 'chat/planner_today_fate.dart';
export 'chat/chat_defaults.dart';
export 'chat/doors/controls/controls_api.dart';

part 'chat/chat_service_history.dart';
part 'chat/chat_service_reprocess.dart';
part 'chat/chat_service_generation.dart';
part 'chat/chat_service_generation_entry.dart';
part 'chat/chat_service_generation_blocks.dart';
part 'chat/chat_service_generation_plan.dart';
part 'chat/chat_service_generation_plan_register.dart';
part 'chat/chat_service_generation_rag.dart';
part 'chat/chat_service_generation_request.dart';
part 'chat/chat_service_generation_stream.dart';
part 'chat/chat_service_generation_stream_accessors.dart';
part 'chat/chat_service_generation_postgen.dart';
part 'chat/chat_service_generation_postgen_engine.dart';
part 'chat/chat_service_idle_autonomous.dart';
part 'chat/chat_service_prompt_blocks.dart';
part 'chat/chat_service_context_budget.dart';
part 'chat/chat_service_send.dart';
part 'chat/chat_service_send_handoff.dart';
part 'chat/chat_service_turn_flow.dart';
part 'chat/chat_service_message_ops.dart';
part 'chat/chat_service_accessors.dart';
part 'chat/chat_service_fields.dart';

class ChatService extends ChangeNotifier with ChatServiceFieldBag {
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

  late final MediaDoor mediaDoor = _buildMediaDoor();

  /// Roster, Scene Guests, greetings, Away, idle turns (cast_api.dart).
  late final CastDoor castDoor = _buildCastDoor();
  late final ActionsDoor actionsDoor = _buildActionsDoor();
  List<String> get suggestedActions => actionsDoor.suggestedActions;
  bool get isGeneratingActions => actionsDoor.isGeneratingActions;

  /// Quests and the goal check; the members below forward so fakes pin them.
  late final ObjectivesDoor objectivesDoor = _buildObjectivesDoor();
  Objective? get primaryObjective => objectivesDoor.primaryObjective;
  List<Objective> get secondaryObjectives => objectivesDoor.secondaryObjectives;
  ObjectiveTally get objectiveTally => objectivesDoor.objectiveTally;
  bool get isCheckingCompletion => objectivesDoor.isCheckingCompletion;
  void skipObjectiveCheck() => objectivesDoor.completion.skip();

  /// Web-facade fakes override this; body in [MediaDoor].
  Future<void> addGeneratedImageMessage(
    String path,
    String prompt, {
    String? senderName,
    String? characterId,
  }) => mediaDoor.addGeneratedImageMessage(
    path,
    prompt,
    senderName: senderName,
    characterId: characterId,
  );

  /// The chat's switches and gates: Realism, Needs, Objectives, Afterglow,
  /// Chaos, the call, the clock, One-Shot, Chance Time; old names in
  /// controls_api.dart. Fakes pin the forwarders below.
  late final ControlsDoor controlsDoor = _buildControlsDoor();

  /// The mouth and worker lanes and the studio wizards' tool check.
  late final LlmLanes _lanes = _buildLanes();

  /// Fake-pinned (widget fakes override; extension members can't be).
  /// Ending a call also releases any parked call-model swap.
  bool get callMode => controlsDoor.callMode;
  set callMode(bool value) => controlsDoor.setCallMode(value);

  List<Objective> getObjectivesForGroupCharacter(CharacterCard character) =>
      objectivesDoor.getObjectivesForGroupCharacter(character);

  /// The Realism Engine and everything hanging off it: the clock, Needs,
  /// feelings, mood, Afterglow, Pockets, the judges and their transport, the
  /// prompt injections, the Journal, Growth Rings, lore and places. The
  /// getters below forward into it; fakes override them.
  late final RealismGraph realism = _buildRealismGraph();

  Biome get activeChatBiome => realism.weather.activeChatBiome;

  /// Today's story weather, or null when off (body in [ChatWeather]).
  DailyWeather? get currentWeather => realism.weather.currentWeather;

  /// Tomorrow's forecast under the same gate (body in [ChatWeather]).
  DailyWeather? get upcomingWeather => realism.weather.upcomingWeather;

  /// The current DAY-PART's weather (body in [ChatWeather]).
  SegmentWeather? get currentSegmentWeather =>
      realism.weather.currentSegmentWeather;

  /// Sidebar/web read surface (Living Time §6); body on the graph.
  List<({String text, int progress})> ambitionsFor(CharacterCard card) =>
      realism.ambitionsFor(card);

  /// Pockets' one read (off hides, never erases); body in
  /// [PocketsLedger.pocketsFor]. Class member: FakeChatService overrides it.
  Pockets? pocketsFor(String characterId) =>
      realism.pocketsLedger.pocketsFor(characterId);

  /// The one Pockets switch, for UI gating: unlike a null [pocketsFor] it
  /// tells "off" (no panel) from "no record yet". A class member: fakes
  /// override only those (as an extension it turned a golden red, bcea783).
  bool get pocketsFeatureEnabled =>
      _storageService.realismSettings.pocketsEnabled;

  /// The stable id for a card, exposed so UI can look a record up without
  /// reaching for a private. Same resolver every Pockets surface uses.
  String characterIdFor(CharacterCard c) => _getCharacterIdFromCard(c);

  JournalReview get journalReview => realism.journalReview;

  /// Journal UI door — class member so FakeChatService can override it.
  JournalStore get journalStore => realism.journalStore;
  MilestoneFeed get milestoneFeed => realism.milestoneFeed;

  CharacterCard? get activeCharacter => _session.activeCharacter;
  List<ChatMessage> get messages => List.unmodifiable(_session.messages);

  /// Token streaming — deliberately the NARROW sense. It drives the send
  /// button, and widening it to cover post-generation was tried and REVERTED:
  /// background evals then held the composer disabled for most of a turn on
  /// slow machines (caught by E2E on the CI runners). The real constraint
  /// lives at the composer instead: its guard must use the SAME predicate as
  /// [sendMessage], or it clears the field for a send the service refuses.
  /// See [isSettlingTurn] and the mirror in `_sendCurrentMessage`.
  bool get isGenerating => _isGenerating;
  bool get isImporting => chatImporter.isImporting;

  /// The import and export doors; their old names live in transfer_api.dart.
  late final ChatImporter chatImporter = _buildChatImporter();
  late final ChatPackager chatPackager = _buildChatPackager();

  /// A reply, its post-gen settle, an import or narration is running: the
  /// window cast edits (Away / Back) refuse. Class member so fakes pin it.
  bool get isTurnBusy => _isTurnBusy;
  String? get currentSessionId => _session.currentSessionId;

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

  /// Kobold's tokenizer and perf poll are measured. oMLX and remote hosts
  /// are not — the status bar must not print a chars/4 guess as tokens.
  bool get prefillMetricsAreMeasured =>
      _llmProvider == null || _llmProvider!.isLocal;

  /// Opening a 1:1 or a group, the group roster and its per-member reads
  /// and switches; old names in entry_api.dart. Fakes pin the members below.
  late final EntryDoor entryDoor = _buildEntryDoor();
  bool get isGroupMode => _session.groupManager?.isActive ?? false;
  GroupChat? get activeGroup => _session.groupManager?.activeGroup;
  bool get observerMode => _session.groupManager?.observerMode ?? false;
  List<CharacterCard> get groupCharacters =>
      _session.groupManager?.characters ?? const <CharacterCard>[];

  /// Ordered cast of speakers, group or 1:1+guests. Body in chat_service_idle_autonomous.dart.
  List<ChatParticipant> get cast => _castImpl;
  double get tokensPerSecond => _tokensPerSecondImpl;

  int get greetingIndex => castDoor.greetings.greetingIndex;

  /// Listener wiring lives in [_initImpl] (chat_service_accessors.dart).
  ChatService(
    this._koboldService,
    this._userPersonaService,
    this._storageService,
    this._worldRepository,
  ) {
    _initImpl();
  }

  /// The open chat's row: load, save, fork, new chat, history window and
  /// today line; old names in session_api.dart. Fakes pin the members below.
  late final SessionStore sessionStore = _buildSessionStore();
  String get authorNote => sessionStore.authorNote;
  int get authorNoteStrength => sessionStore.authorNoteStrength;
  int get historyBasePosition => sessionStore.history.basePosition;
  String? get todaySentence => sessionStore.today.todaySentence;
  String? get todayLine => sessionStore.today.todayLine;
  void setTodaySentence(String? v) => sessionStore.today.setTodaySentence(v);
  void abandonToday() => sessionStore.today.abandonToday();

  Map<String, int> get lastPromptBudget => _contextBudget.budget;
  Map<String, String> get lastPromptSections => _contextBudget.sections;
  ContextBudgetSource get promptBudgetSource => _contextBudget.source;
  DateTime? get promptBudgetAssembledAt => _contextBudget.assembledAt;
  int get promptDroppedMessages => _contextBudget.droppedMessages;
  Future<void> estimateContextBudgetNow() => _estimateContextBudgetNow();
  int get contextSize =>
      sessionStore.genSettings.resolveContextSize(_storageService);

  /// Per-session generation parameter overrides. The dialog reads/writes this.
  ChatGenerationSettings get sessionGenSettings => sessionStore.genSettings;
  set sessionGenSettings(ChatGenerationSettings value) =>
      sessionStore.setGenSettings(value);

  /// Per-chat theme overrides (preset + customized colors/font/background/border).
  ChatThemeOverrides get sessionThemeOverrides => sessionStore.themeOverrides;
  set sessionThemeOverrides(ChatThemeOverrides value) =>
      sessionStore.setThemeOverrides(value);
  void refreshActiveCharacterCard(CharacterCard card) =>
      entryDoor.refreshActiveCharacterCard(card);

  String get summary => sessionStore.summary;
  bool get summaryPaused => sessionStore.summaryPaused;
  int get summaryLastIndex => sessionStore.summaryLastIndex;
  bool get isSummaryGenerating => sessionStore.isSummaryGenerating;
  RelationshipService get relationshipService => realism.relationship;
  TimeService get timeService => realism.time;
  NsfwService get nsfwService => realism.nsfw;
  ChaosModeService get chaosModeService => realism.chaos;
  WebSearchService get webSearchService => mediaDoor.webSearchService;
  bool get webSearchEnabled => mediaDoor.webSearchService.isActive;
  WikiSearchService get wikiSearchService => mediaDoor.wikiSearchService;
  String get wikiBaseUrl => mediaDoor.wikiBaseUrl;
  Future<void> setWikiBaseUrl(String url) => mediaDoor.setWikiBaseUrl(url);
  NeedsSimulation get needsSimulation => realism.needs;
  Future<void> setNeedsSimEnabled(bool on) =>
      controlsDoor.setNeedsSimEnabled(on);
  bool get realismEnabled => controlsDoor.realismEnabled;
  bool get realismChatSwitch => controlsDoor.realismChatSwitch;
  bool get realismAllowed => _storageService.realismSettings.realismAllowed;
  String spatialStanceForGroupCharacter(CharacterCard c) =>
      entryDoor.reads.spatialStanceForGroupCharacter(c);
  bool? withUserForGroupCharacter(CharacterCard c) =>
      entryDoor.reads.withUserForGroupCharacter(c);
  bool get objectivesActive => controlsDoor.objectivesActive;
  bool get afterglowChatSwitch => controlsDoor.afterglowChatSwitch;
  Future<void> setAfterglowEnabled(bool on) =>
      controlsDoor.setAfterglowEnabled(on);
  MemoryService? get memoryService => _memoryService;
  Map<String, dynamic>? get lastRagReceipt => _lastRagReceiptImpl;
  String get standingMoodSummary => realism.standingMood.summary;

  bool get isEvaluatingRealism => realism.evalStatus.evaluating;
  bool get isProcessingGreeting => castDoor.baseline.isProcessingGreeting;

  // Verifier phase: the overlay header, pass progress, and the bubble chip.
  bool get isVerifyingRealism => realism.evalStatus.verifying;
  int get verificationPass => realism.evalStatus.verificationPass;
  int get verificationMaxPasses => realism.evalStatus.verificationMaxPasses;

  /// Stream text with think blocks stripped (for display), memoized on the
  /// graph's eval status. Class member: FakeChatService overrides it.
  String get realismEvalStreamTextClean => realism.evalStatus.streamTextClean;
  String get characterEmotion => realism.registers.emotion;
  String get emotionIntensity => realism.registers.intensity;
  String get emotionCause => realism.registers.cause;
  int get emotionHeldTurns => realism.registers.heldTurns;
  String get moodLine => realism.mood.displayLine;

  /// The chat's Needs switch; [needsActive] is the gate Needs run behind.
  bool get needsSimEnabled => controlsDoor.needsSimEnabled;
  bool get needsActive => realism.needsPass.active;

  /// Writes Porch Life Passage of Time — the live clock gate. Class-pinned
  /// so goldens/fakes can override.
  Future<void> setPassageOfTimeEnabled(bool enabled) =>
      controlsDoor.setPassageOfTimeEnabled(enabled);

  /// A group member's own Afterglow switch (body in [GroupMemberSettings]).
  Future<void> setMemberAfterglowEnabled(CharacterCard member, bool on) =>
      entryDoor.members.setMemberAfterglowEnabled(member, on);

  bool get chaosNsfwEnabled => realism.chaos.chaosNsfwEnabled;

  /// Edit, delete, regen, swipes, Reprocess, impersonate; old names in
  /// edits_api.dart. The two members below forward so fakes pin them.
  late final EditsDoor editsDoor = _buildEditsDoor();
  int? get regenerableHostBelowGuestsIndex =>
      editsDoor.regen.hostBelowGuestsIndex;
  void editMessage(int index, String newText) =>
      editsDoor.editor.edit(index, newText);

  // Growth Rings flag (zeroed on all reset/entry sites). Class-pinned for fakes.
  bool get isGrowthPassRunning => realism.growthPassRunning;

  /// Active objectives for [character] in the current session.
  Future<List<Objective>> getActiveObjectivesFor(CharacterCard character) =>
      objectivesDoor.getActiveObjectivesFor(character);

  late final _doorNotify = CoalescedNotify(notifyListeners);

  /// Re-emits a door's changes as this service's, once per microtask.
  void _forwardDoorNotify(ChangeNotifier door) =>
      door.addListener(_doorNotify.call);

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
