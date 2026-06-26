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

// Shared, timer-free service doubles for provider-backed widget goldens.
//
// The real services are unsuitable for static pixel goldens: a real LLMProvider
// builds a KoboldService whose readiness probe schedules a recurring timer, so
// `pumpAndSettle` never returns. These doubles construct nothing and implement
// only the surface the widgets actually read (everything else throws via
// noSuchMethod), following the established `_Fake*` pattern in `test/ui/`.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' show Objective;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_generation_settings.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/models/chat_participant.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/chat/chaos_mode_service.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/folder_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/models/world.dart' as world_model;
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/stt_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/tts_voice_info.dart';
import 'package:front_porch_ai/services/update_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';

/// A timer-free, IO-free [LLMProvider] double. Exposes the backend-type surface
/// screens read (e.g. ReviewAvatarPanel checks `activeBackend`) without
/// constructing any backend service.
class FakeLLMProvider extends ChangeNotifier implements LLMProvider {
  FakeLLMProvider({this.activeBackend = BackendType.kobold});

  @override
  final BackendType activeBackend;

  @override
  bool get isLocal => activeBackend == BackendType.kobold;

  @override
  bool get hasManagedProcess =>
      activeBackend == BackendType.kobold ||
      activeBackend == BackendType.pseudoRemote;

  @override
  bool get hasAnyManagedProcessRunning => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// A `ChatService` double for sidebar/chat/overlay goldens. `ChatService` is a
/// large god class, so this implements only the surface a rendered widget reads
/// and grows as new surfaces are covered; everything else throws via
/// noSuchMethod. Sub-services (e.g. [timeService]) are seeded deterministically.
class FakeChatService extends ChangeNotifier implements ChatService {
  FakeChatService({
    this.realismEnabled = true,
    this.isGenerating = false,
    this.authorNote = '',
    this.authorNoteStrength = 3,
    this.summary = '',
    this.summaryLastIndex = 0,
    this.summaryPaused = false,
    this.isSummaryGenerating = false,
    this.needsSimEnabled = true,
    this.characterEmotion = 'neutral',
    this.emotionIntensity = 'moderate',
    this.characterEvolutionCount = 0,
    this.activeCharacter,
    List<ChatMessage> messages = const [],
    // Generation status bar surface.
    this.generationPhase = GenerationPhase.idle,
    this.generationProgress = 0.0,
    this.tokensGenerated = 0,
    this.maxTokens = 0,
    this.tokensPerSecond = 0.0,
    this.prefillElapsedSeconds = 0.0,
    this.prefillPromptTokens = 0,
    this.lastPerfData,
    // Realism-processing overlay surface.
    this.isVerifyingRealism = false,
    this.verificationPass = 0,
    this.verificationMaxPasses = 1,
    this.isEvaluatingRealism = false,
    this.isProcessingGreeting = false,
    String timeOfDay = 'evening',
    int dayCount = 3,
    int startDayOfWeek = 1,
    int shortTermBond = 120,
    int longTermBond = 60,
    int trustLevel = 40,
    Map<String, int> needs = const {
      'hunger': 70,
      'bladder': 55,
      'energy': 80,
      'social': 45,
      'fun': 65,
      'hygiene': 75,
      'comfort': 60,
    },
  }) : _messages = messages {
    _time = TimeService(
      onNotify: () {},
      onSaveChat: () async {},
      onSetPendingRealismMetadata: (_, _) {},
      onNudgePatchLastMessageRealismState: (_, _) {},
    )..loadTimeScalars(
        timeOfDay: timeOfDay,
        dayCount: dayCount,
        startDayOfWeek: startDayOfWeek,
        passageOfTimeEnabled: true,
      );
    _nsfw = NsfwService(
      getGroupInt: (_, _) => 0,
      getGroupValue: (_, _) => null,
      setGroupValue: (_, _, _) {},
    );
    _chaos = ChaosModeService(
      onNotify: () {},
      onSaveChat: () async {},
      onSetPendingRealismMetadata: (_, _) {},
    );
    _needs = NeedsSimulation(
      onNotify: () {},
      onSaveChat: () async {},
      getTimeOfDay: () => timeOfDay,
      getRealismEnabled: () => realismEnabled,
      getArousalLevel: () => 0,
      getNsfwCooldownEnabled: () => false,
      getCooldownTurnsRemaining: () => 0,
      getObserverMode: () => false,
      getCurrentSpeakerIdForRealism: () => '',
      getIsGroupNonObserverMode: () => false,
      getGroupNeeds: (_) => {},
      setGroupNeeds: (_, _) {},
      getEnjoysLowHygiene: () => false,
      getNeedsSimEnabled: () => needsSimEnabled,
      setArousalLevel: (_) {},
    )..restoreFromSnapshot(needs);
    _relationship = RelationshipService(
      onNotify: () {},
      onSaveChat: () async {},
      getIsGroupActive: () => false,
      getObserverMode: () => false,
      getGroupCharacterCount: () => 0,
      getShouldTrackInterCharacterRelationships: () => false,
      getCurrentSpeakerIdForRealism: () => '',
      getCurrentGroupMemberIds: () => <String>{},
      getOtherGroupMemberIds: (_) => const [],
      getOtherGroupMemberIdToLowerName: (_) => const {},
      getRecentExchangeLowerText: () => '',
      getMessageCount: () => 0,
      getIsGroupRealismActive: () => false,
      getGroupAffectionScore: (_, {int defaultValue = 0}) => defaultValue,
      setGroupAffectionScore: (_, _) {},
      getGroupLongTermScore: (_, {int defaultValue = 0}) => defaultValue,
      setGroupLongTermScore: (_, _) {},
      getGroupTrustLevel: (_, {int defaultValue = 0}) => defaultValue,
      setGroupTrustLevel: (_, _) {},
      getGroupFixation: (_, {String defaultValue = ''}) => defaultValue,
      setGroupFixation: (_, _) {},
      getGroupFixationLifespan: (_, {int defaultValue = 0}) => defaultValue,
      setGroupFixationLifespan: (_, _) {},
      getGroupRelationshipTier: (_, {int defaultValue = 0}) => defaultValue,
      setGroupRelationshipTier: (_, _) {},
      getGroupLongTermTier: (_, {int defaultValue = 0}) => defaultValue,
      setGroupLongTermTier: (_, _) {},
      getGroupSpatialStance: (_, {String defaultValue = ''}) => defaultValue,
      setGroupSpatialStance: (_, _) {},
      getGroupInterCharacterRelationships: (_) => <String, int>{},
      setGroupInterCharacterRelationships: (_, _) {},
    )..loadScalars(
        affectionScore: shortTermBond,
        longTermScore: longTermBond,
        trustLevel: trustLevel,
      );
  }

  final List<ChatMessage> _messages;
  late final TimeService _time;
  late final NsfwService _nsfw;
  late final ChaosModeService _chaos;
  late final NeedsSimulation _needs;
  late final RelationshipService _relationship;

  @override
  final bool realismEnabled;
  @override
  final bool isGenerating;
  @override
  final String authorNote;
  @override
  final int authorNoteStrength;
  @override
  final String summary;
  @override
  final int summaryLastIndex;
  @override
  final bool summaryPaused;
  @override
  final bool isSummaryGenerating;
  @override
  final bool needsSimEnabled;
  @override
  final String characterEmotion;
  @override
  final String emotionIntensity;
  @override
  final int characterEvolutionCount;
  @override
  final CharacterCard? activeCharacter;

  // Generation status bar surface.
  @override
  final GenerationPhase generationPhase;
  @override
  final double generationProgress;
  @override
  final int tokensGenerated;
  @override
  final int maxTokens;
  @override
  final double tokensPerSecond;
  @override
  final double prefillElapsedSeconds;
  @override
  final int prefillPromptTokens;
  @override
  final Map<String, dynamic>? lastPerfData;

  // Realism-processing overlay surface.
  @override
  final bool isVerifyingRealism;
  @override
  final int verificationPass;
  @override
  final int verificationMaxPasses;
  @override
  final bool isEvaluatingRealism;
  @override
  final bool isProcessingGreeting;

  // RealismProcessingOverlay reads this at build time; empty = "initializing" branch.
  @override
  String get realismEvalStreamTextClean => '';

  @override
  TimeService get timeService => _time;
  @override
  NsfwService get nsfwService => _nsfw;
  @override
  ChaosModeService get chaosModeService => _chaos;
  @override
  NeedsSimulation get needsSimulation => _needs;
  @override
  RelationshipService get relationshipService => _relationship;

  // 1:1 mode by default (no active group) for the simple sidebar sections.
  @override
  GroupChat? get activeGroup => null;
  @override
  bool get chaosNsfwEnabled => _chaos.chaosNsfwEnabled;

  // Unified-cast surface (empty / 1:1 defaults for the simple test doubles).
  @override
  List<ChatParticipant> get cast => const [];
  @override
  bool get observerMode => false;
  @override
  List<Objective> getObjectivesForGroupCharacter(CharacterCard character) =>
      const [];
  // getArousalForGroupCharacter is an extension on ChatService (resolves on the
  // static type), so it needs no fake override.

  // Objective surface — empty by default (renders the "propose an objective" UI).
  @override
  Objective? get primaryObjective => null;
  @override
  List<Objective> get secondaryObjectives => const [];
  @override
  bool get isCheckingCompletion => false;

  // Context viewer surface.
  @override
  Map<String, int> get lastPromptBudget => const {};
  @override
  int get contextSize => 8192;

  @override
  Future<List<Objective>> getActiveObjectivesFor(CharacterCard _) async =>
      const [];

  // ChatSettingsDialog reads sessionGenSettings in didChangeDependencies then
  // calls resolveBannedPhrases(storage). Pre-populate bannedPhrases so the
  // resolve short-circuits before touching StorageService.realismSettings.
  @override
  ChatGenerationSettings get sessionGenSettings =>
      ChatGenerationSettings(bannedPhrases: const <String>[]);
  @override
  set sessionGenSettings(ChatGenerationSettings _) {}

  // Message bubble surface.
  @override
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  // Mutates the seeded message in place so facade edit paths (e.g. inserting a
  // generated image into the last message) are observable in unit tests.
  @override
  void editMessage(int index, String newText) {
    if (index >= 0 && index < _messages.length) _messages[index].text = newText;
  }
  @override
  bool get isGroupMode => false;
  @override
  List<CharacterCard> get groupCharacters => const [];
  @override
  int get greetingIndex => 0;
  @override
  bool get isGeneratingActions => false;
  @override
  List<String> get suggestedActions => const [];

  // Scene-guest "regenerate the buried host" affordance. These unit goldens never
  // set up a host buried under Lite-NPC replies, so null = MessageBubble shows no
  // buried-host regen button (matching the pre-scene-guest render). Without this
  // stub the real getter call hits noSuchMethod and throws at build time, which
  // is what was making the MessageBubble goldens fail on CI.
  @override
  int? get regenerableHostBelowGuestsIndex => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Timer-free [TtsService] double. Exposes the getters that widget build trees
/// read at build time (MessageBubble, TTS settings dialogs, voice browsing).
class FakeTtsService extends ChangeNotifier implements TtsService {
  @override
  bool get isSpeaking => false;
  @override
  bool get isGenerating => false;
  @override
  String? get currentMessageId => null;
  @override
  double get generationProgress => 0.0;
  @override
  List<TtsVoiceInfo> get activeVoices => const [];
  @override
  double get modelDownloadProgress => 0.0;
  @override
  bool get isDownloadingModel => false;
  @override
  String? get lastError => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [SttService] double that avoids the real constructor's platform-channel
/// [AudioRecorder] (which throws MissingPluginException in headless tests).
/// Defaults to unavailable; [transcribeAudioFile] returns a canned value so
/// VoiceFacade's transcribe path is exercisable without Whisper.
class FakeSttService extends ChangeNotifier implements SttService {
  FakeSttService({this.available = false, this.transcript});

  final bool available;
  final String? transcript;

  @override
  bool get isAvailable => available;
  @override
  Future<String?> transcribeAudioFile(String audioPath) async => transcript;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Empty [UserPersonaService] double. [MessageBubble] uses a
/// `Consumer<UserPersonaService>` to filter personas by sender name; an empty
/// list renders the section as a no-op. [UserPersonaPage] reads [persona] when
/// `personas` is non-empty — returning a default here so seeded variants work.
class FakeUserPersonaService extends ChangeNotifier
    implements UserPersonaService {
  @override
  List<UserPersona> get personas => const [];
  @override
  UserPersona get persona => UserPersona(id: 'default');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Seeded [CharacterRepository] double. Holds a fixed in-memory character
/// list; `loadCharacters` is a no-op. Used by home-page component goldens.
class FakeCharacterRepository extends ChangeNotifier
    implements CharacterRepository {
  FakeCharacterRepository([List<CharacterCard> characters = const []])
    : _characters = List.unmodifiable(characters);

  final List<CharacterCard> _characters;

  @override
  List<CharacterCard> get characters => _characters;
  @override
  bool get isLoading => false;
  @override
  List<String> get allTags => const [];
  @override
  Future<void> loadCharacters() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Empty [FolderService] double. All folder-related lookups return empty
/// collections so [CharacterCardGrid] renders the unfolderd character list.
class FakeFolderService extends ChangeNotifier implements FolderService {
  @override
  List<CharacterFolder> get folders => const [];
  @override
  List<String> getCharactersInFolder(String folderId) => const [];
  @override
  List<String> getCharactersInFolderRecursive(String folderId) => const [];
  @override
  List<CharacterFolder> getSubfolders(String? parentId) => const [];
  @override
  Set<String> getUnfolderedCharacterPaths() => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Empty [GroupChatRepository] double. Returns no groups so the grid renders
/// only character cards (no group tiles).
class FakeGroupChatRepository extends ChangeNotifier
    implements GroupChatRepository {
  @override
  List<GroupChat> get groups => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal [AppState] double. [Sidebar] reads only [selectedIndex] at build
/// time; [setIndex] is a no-op (navigation callbacks are never invoked in a
/// static golden).
class FakeAppState extends ChangeNotifier implements AppState {
  FakeAppState({this.selectedIndex = 0});

  @override
  final int selectedIndex;

  @override
  void setIndex(int index) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Empty [WorldRepository] double. Returns no worlds; [WorldManagementPage]
/// renders the empty-state message ("No worlds yet").
class FakeWorldRepository extends ChangeNotifier implements WorldRepository {
  FakeWorldRepository([List<world_model.World> worlds = const []])
    : _worlds = worlds;

  final List<world_model.World> _worlds;

  @override
  List<world_model.World> get worlds => List.unmodifiable(_worlds);
  @override
  bool get isLoading => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Minimal [UpdateService] double. [Sidebar]'s `Consumer<UpdateService>`
/// reads [currentVersion], [displayCurrentVersion], and [updateAvailable]
/// at build time. [UpdateDialog]'s Consumer additionally reads
/// [downloadComplete], [downloading], [displayLatestVersion],
/// [releaseNotes], and [downloadProgress]. No HTTP, timers, or file-system.
class FakeUpdateService extends ChangeNotifier implements UpdateService {
  FakeUpdateService({
    this.updateAvailable = false,
    this.downloadComplete = false,
    this.downloading = false,
    this.latestVersion = '0.9.1',
    this.releaseNotes = '',
    this.downloadProgress = 0.0,
  });

  @override
  String get currentVersion => '0.9.0';
  @override
  String get displayCurrentVersion => 'v0.9.0';
  @override
  final bool updateAvailable;
  @override
  final bool downloadComplete;
  @override
  final bool downloading;
  @override
  final String latestVersion;
  @override
  String get displayLatestVersion => 'v$latestVersion';
  @override
  final String releaseNotes;
  @override
  final double downloadProgress;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
