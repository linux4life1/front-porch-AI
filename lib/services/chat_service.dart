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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/storage/settings/appearance_settings.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/chat_bindings.dart';
import 'package:front_porch_ai/services/chat/chat_lifetime.dart';
import 'package:front_porch_ai/services/chat/chat_wiring.dart';
import 'package:front_porch_ai/services/chat/doors/actions/actions_door.dart';
import 'package:front_porch_ai/services/chat/doors/cast/cast_door.dart';
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/transfer/transfer.dart';
import 'package:front_porch_ai/services/chat/doors/controls/controls_door.dart';
import 'package:front_porch_ai/services/chat/doors/objectives/objectives_door.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edits_door.dart';
import 'package:front_porch_ai/services/chat/doors/entry/entry_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/doors/turn/send_spine.dart';
import 'package:front_porch_ai/services/chat/doors/turn/turn_engine.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/database/database.dart' hide AvatarImage, World;
import 'package:front_porch_ai/services/live_gen_progress.dart';

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
export 'chat/doors/turn/prompt_api.dart';
export 'chat/doors/turn/turn_api.dart';
export 'chat/doors/turn/send_api.dart';

/// The one chat notifier Provider, the web facades and the UI see: a
/// constructor, a getter per door, and the forwarders the golden fakes
/// override. Every door is built by [ChatWiring]; old names reach a door
/// through the `*_api.dart` bridges exported above.
class ChatService extends ChangeNotifier {
  final KoboldService _koboldService;
  final UserPersonaService _userPersonaService;
  final StorageService _storageService;
  final WorldRepository _worldRepository;

  /// The services main.dart hands this chat after it is built.
  final _bound = BoundServices();
  late final _life = ChatLifetime(_koboldService);

  /// The open chat every door reads (messages, session id, character,
  /// group). Its session id setter tells KoboldCpp which chat is open.
  late final _session = ChatSessionState(onChatOpened: _life.chatOpened);
  late final _wiring = ChatWiring(
    kobold: _koboldService,
    personas: _userPersonaService,
    storage: _storageService,
    worlds: _worldRepository,
    bound: _bound,
    session: _session,
    life: _life,
    service: this,
    notify: notifyListeners,
  );

  /// Listeners on the services around this chat, init and dispose.
  late final _bindings = ChatBindings(
    kobold: _koboldService,
    storage: _storageService,
    bound: _bound,
    life: _life,
    wiring: _wiring,
    notify: notifyListeners,
  );

  MediaDoor get mediaDoor => _wiring.mediaDoor;

  /// Roster, Scene Guests, greetings, Away, idle turns (cast_api.dart).
  CastDoor get castDoor => _wiring.castDoor;
  ActionsDoor get actionsDoor => _wiring.actionsDoor;
  List<String> get suggestedActions => actionsDoor.suggestedActions;
  bool get isGeneratingActions => actionsDoor.isGeneratingActions;

  /// Quests and the goal check; the members below forward so fakes pin them.
  ObjectivesDoor get objectivesDoor => _wiring.objectivesDoor;
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
  ControlsDoor get controlsDoor => _wiring.controlsDoor;

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
  RealismGraph get realism => _wiring.realism;

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
  String characterIdFor(CharacterCard c) => _session.characterIdFor(c);

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
  /// That predicate is `sendBusyReason` (one body, on [sendSpine]), which
  /// reads this same flag; the composer (`sendComposerMessage`) and the web
  /// relay ask it before they let go of the text. See [isSettlingTurn].
  bool get isGenerating => turnEngine.progress.isGenerating;
  bool get isImporting => chatImporter.isImporting;

  /// The import and export doors; their old names live in transfer_api.dart.
  ChatImporter get chatImporter => _wiring.chatImporter;
  ChatPackager get chatPackager => _wiring.chatPackager;

  /// A reply, its post-gen settle, an import or narration is running: the
  /// window cast edits (Away / Back) refuse. Class member so fakes pin it.
  bool get isTurnBusy => turnEngine.isTurnBusy;
  String? get currentSessionId => _session.currentSessionId;

  /// The user's turn: `sendMessage` and its guard (the one predicate the
  /// composer reads, `sendBusyReason`), the hand-off to [turnEngine], Try
  /// again, the "Did time pass?" gate, the group speaker pick, the Chance
  /// Time reveal, the recap controls and the idle turn's staging; old names
  /// in send_api.dart.
  SendSpine get sendSpine => _wiring.sendSpine;

  /// One generation: stream, progress, post-generation passes, the stops;
  /// old names in turn_api.dart. The status members around it forward so
  /// fakes pin them.
  TurnEngine get turnEngine => _wiring.turnEngine;
  double get generationProgress => turnEngine.progress.generationProgress;
  int get tokensGenerated => turnEngine.progress.tokensGenerated;
  int get maxTokens => turnEngine.progress.maxTokens;
  GenerationPhase get generationPhase => turnEngine.progress.generationPhase;

  /// Seconds elapsed since entering the prefill phase. Returns 0 if not prefilling.
  double get prefillElapsedSeconds => turnEngine.progress.prefillElapsedSeconds;

  /// Cached KoboldCPP performance data from last /api/extra/perf poll.
  Map<String, dynamic>? get lastPerfData => turnEngine.progress.lastPerfData;

  /// The active backend's live generation progress (truthful status bar):
  /// Kobold console counts, oMLX admin-stats poll, or LM Studio's runtime
  /// log — null for plain remote APIs, which expose no prefill data. Thin
  /// delegation; source selection lives in LLMProvider.activeLiveProgress.
  LiveGenProgress? get activeLiveProgress =>
      _bound.llmProvider?.activeLiveProgress ?? _koboldService.liveProgress;

  /// Estimated prompt token count for the current generation (for progress display).
  int get prefillPromptTokens => turnEngine.progress.prefillPromptTokens;

  /// Kobold's tokenizer and perf poll are measured. oMLX and remote hosts
  /// are not — the status bar must not print a chars/4 guess as tokens.
  bool get prefillMetricsAreMeasured => _bound.llmProvider?.isLocal ?? true;

  /// Opening a 1:1 or a group, the group roster and its per-member reads
  /// and switches; old names in entry_api.dart. Fakes pin the members below.
  EntryDoor get entryDoor => _wiring.entryDoor;
  bool get isGroupMode => _session.groupManager?.isActive ?? false;
  GroupChat? get activeGroup => _session.groupManager?.activeGroup;
  bool get observerMode => _session.groupManager?.observerMode ?? false;
  List<CharacterCard> get groupCharacters =>
      _session.groupManager?.characters ?? const <CharacterCard>[];

  /// Ordered cast of speakers, group or 1:1+guests (body in
  /// [CastDoor.participants]).
  List<ChatParticipant> get cast => castDoor.participants;
  double get tokensPerSecond => turnEngine.progress.tokensPerSecond;

  int get greetingIndex => castDoor.greetings.greetingIndex;

  /// Listener wiring lives in [ChatBindings.init].
  ChatService(
    this._koboldService,
    this._userPersonaService,
    this._storageService,
    this._worldRepository,
  ) {
    _bindings.init();
  }

  /// The open chat's row: load, save, fork, new chat, history window and
  /// today line; old names in session_api.dart. Fakes pin the members below.
  SessionStore get sessionStore => _wiring.sessionStore;
  String get authorNote => sessionStore.authorNote;
  int get authorNoteStrength => sessionStore.authorNoteStrength;
  int get historyBasePosition => sessionStore.history.basePosition;
  String? get todaySentence => sessionStore.today.todaySentence;
  String? get todayLine => sessionStore.today.todayLine;
  void setTodaySentence(String? v) => sessionStore.today.setTodaySentence(v);
  void abandonToday() => sessionStore.today.abandonToday();

  /// The reply's prompt and request: blocks, plan, history window, RAG,
  /// the Context Viewer budget and the prompt source; old names in
  /// prompt_api.dart. Fakes pin the Context Viewer forwarders below.
  PromptAssembler get promptAssembler => _wiring.promptAssembler;
  Map<String, int> get lastPromptBudget => promptAssembler.budget.budget;
  Map<String, String> get lastPromptSections => promptAssembler.budget.sections;
  ContextBudgetSource get promptBudgetSource => promptAssembler.budget.source;
  DateTime? get promptBudgetAssembledAt => promptAssembler.budget.assembledAt;
  int get promptDroppedMessages => promptAssembler.budget.droppedMessages;
  Future<void> estimateContextBudgetNow() =>
      promptAssembler.budget.estimateNow();
  int get contextSize => promptAssembler.contextSize;

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
  bool get realismEnabled => _realismEnabled;

  /// The one name for the Realism gate in this library: Porch Life allows
  /// it AND the chat's own switch (test/hygiene/realism_gate_ratchet_test).
  bool get _realismEnabled => controlsDoor.realismEnabled;
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

  // Pockets & Wardrobe per-chat switches
  // (docs/design/pockets-wardrobe-chat-toggle.md). Forwarders, not
  // extensions: the golden fakes answer these for the sidebar widget tests.
  /// This 1:1 chat's stored Pockets switch (the checkbox reads it; the gate
  /// is [pocketsEnabledFor]).
  bool get pocketsChatSwitch => controlsDoor.pocketsChatSwitch;

  /// The member's stored per-chat switch in a group, the 1:1 one outside.
  bool pocketsSwitchFor(String memberId) =>
      controlsDoor.pocketsSwitchFor(memberId);
  Future<void> setPocketsEnabled(bool on) => controlsDoor.setPocketsEnabled(on);
  Future<void> setMemberPocketsEnabled(String memberId, bool on) =>
      controlsDoor.setMemberPocketsEnabled(memberId, on);
  MemoryService? get memoryService => _bound.memory;

  /// Reads the public [messages], so a fake is never probed for privates.
  Map<String, dynamic>? get lastRagReceipt => lastRagReceiptIn(messages);
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

  /// A group member's Pockets default for the group's NEW chats (the card
  /// flag on their member copy — the sidebar flips the live per-chat
  /// switch, this sets what a fresh chat starts with).
  Future<void> setMemberPocketsDefault(CharacterCard member, bool on) =>
      entryDoor.members.setMemberPocketsDefault(member, on);

  bool get chaosNsfwEnabled => realism.chaos.chaosNsfwEnabled;

  /// Edit, delete, regen, swipes, Reprocess, impersonate; old names in
  /// edits_api.dart. The two members below forward so fakes pin them.
  EditsDoor get editsDoor => _wiring.editsDoor;
  int? get regenerableHostBelowGuestsIndex =>
      editsDoor.regen.hostBelowGuestsIndex;
  void editMessage(int index, String newText) =>
      editsDoor.editor.edit(index, newText);

  // Growth Rings flag (zeroed on all reset/entry sites). Class-pinned for fakes.
  bool get isGrowthPassRunning => realism.growthPassRunning;

  /// Active objectives for [character] in the current session.
  Future<List<Objective>> getActiveObjectivesFor(CharacterCard character) =>
      objectivesDoor.getActiveObjectivesFor(character);

  /// The app's appearance choices, read live by the Ambient Stage
  /// (`sceneTokensFor`) so the chat page and the web chat state agree.
  AppearanceSettings get appearance => _storageService.appearance;

  /// The coarse absence phrase gated by the welcome-back-banner setting:
  /// the ONE gate the desktop banner and the web facade both read.
  String? get absenceBannerPhrase =>
      _storageService.realismSettings.absenceBannerEnabled
      ? sessionStore.absencePhrase
      : null;

  Future<void> commitChatLorebookEdit() async {
    notifyListeners();
    await sessionStore.save();
  }

  /// Point this chat — and the MemoryService it owns — at [db], at startup
  /// and after a swap (body in [ChatBindings.updateDatabase]).
  void updateDatabase(AppDatabase db) => _bindings.updateDatabase(db);

  /// Alias of [updateDatabase] so startup wiring and post-swap rebinding can
  /// never drift apart.
  void setDatabase(AppDatabase db) => updateDatabase(db);

  /// The services main.dart wires after construction (the LLM provider and
  /// the character library also get this chat's listeners).
  void setCharacterRepository(CharacterRepository repo) =>
      _bindings.setCharacterRepository(repo);
  void setLLMProvider(LLMProvider provider) =>
      _bindings.setLLMProvider(provider);
  void setTtsService(TtsService service) => _bound.tts = service;
  void setMemoryService(MemoryService service) => _bound.memory = service;
  void setImageGenService(ImageGenService service) => _bound.imageGen = service;

  /// The desktop's chat page opened or closed; a "Did time pass?" question
  /// needs one open (or a web client), and KoboldCpp's cache follows it.
  void chatScreenOpened() => _life.screenOpened(_session.currentSessionId);
  void chatScreenClosed() => _life.screenClosed();

  /// Test-only overrides for driving the real LLM paths (realism evals +
  /// chat generation) with canned responses without a full LLMProvider.
  @visibleForTesting
  LLMService? get testLlmServiceOverride => _bound.testMouth;
  @visibleForTesting
  set testLlmServiceOverride(LLMService? v) => _bound.testMouth = v;
  @visibleForTesting
  bool get testIsLocalOverride => _bound.testIsLocal;
  @visibleForTesting
  set testIsLocalOverride(bool v) => _bound.testIsLocal = v;
  @visibleForTesting
  LLMService? get testWorkerLlmServiceOverride => _bound.testWorker;
  @visibleForTesting
  set testWorkerLlmServiceOverride(LLMService? v) => _bound.testWorker = v;

  @override
  void notifyListeners() {
    if (_life.disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _bindings.dispose();
    super.dispose();
  }
}
