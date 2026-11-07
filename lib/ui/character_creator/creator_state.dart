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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/creator_greetings.dart';
import 'package:front_porch_ai/ui/character_creator/creator_interview.dart';
import 'package:front_porch_ai/ui/character_creator/creator_profile.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.models.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.prefs.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state/creator_form_reset.dart';
import 'package:front_porch_ai/ui/character_creator/creator_templates.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Creator mode selection.
enum CreatorMode { automated, guided, quick }

/// Shared state for the AI character creator wizard: form fields,
/// controllers, prefs, load/save/reset, step index, and generation.
class CreatorState extends ChangeNotifier {
  // Step tracking (0=setup, 1=mode, 2=config, 3=generating, 4=profile,
  // 5=greetings, 6=realism, 7=review)
  int _currentStep = 0;
  int get currentStep => _currentStep;
  set currentStep(int value) {
    _currentStep = value;
    notifyListeners();
  }

  CreatorMode _creatorMode = CreatorMode.automated;
  CreatorMode get creatorMode => _creatorMode;
  set creatorMode(CreatorMode value) {
    _creatorMode = value;
    notifyListeners();
  }

  // Step 0/1 — Input controllers and selections (lifted verbatim)
  final nameController = TextEditingController();
  final conceptController = TextEditingController();
  final keywordsController = TextEditingController();
  final ageController = TextEditingController();
  final sexController = TextEditingController();
  final relationshipController = TextEditingController();
  String artStyle = 'Anime';
  String greetingLength = 'Medium (2-4 paragraphs)';
  int altGreetingCount = 2;
  Set<String> selectedTones = {'Neutral'};
  bool generateLorebook = true;
  Set<String> selectedLoreCategories = {};
  String loreDepth = 'Standard';
  bool includeDynamicMacros = false;

  /// Greeting + example-dialog voice. `'first'`/`'third'` and
  /// `'present'`/`'past'`. Default first + present is the historical path.
  String narrativePerspective = 'first';
  String narrativeTense = 'present';
  Set<String> selectedRelationships = {};
  String customRelationship = '';
  String selectedArchetype = '';
  bool nsfwEnabled = false;
  bool reasoningEnabled = false;
  String generationDetail = 'Standard';

  // Realism Verification (Director/Verifier) — threaded per plan for creator wizard consistency (stub realism_step now wires).
  bool realismVerificationEnabled = false;
  int realismVerificationMaxReprocesses = 1;
  int realismVerificationStrictness = 3;
  bool realismNeedsDirectorAuthority = false;

  // SFW Appearance
  String race = '';
  final customRaceController = TextEditingController();
  String bodyType = '';
  String hairLength = '';
  String hairStyle = '';
  String skinTone = '';
  Set<String> notableFeatures = {};
  String absCore = '';
  String thighs = '';
  String hips = '';
  String shoulders = '';
  String waist = '';

  // NSFW Appearance + Traits
  String chestSize = '';
  String buttSize = '';
  String experience = '';
  String dominance = '';
  Set<String> selectedKinks = {};
  final customKinksController = TextEditingController();
  String outfitVibe = '';

  // Backstory
  String backstoryOrigin = '';
  String backstoryTone = '';
  String backstoryEra = '';
  final backstoryNotesController = TextEditingController();
  bool conceptGenerated = false;

  String selectedPersonaId = ''; // '' = None (blank slate)

  // ── Quick Mode Controllers ──
  final quickScenarioController = TextEditingController();
  List<String> quickSelectedTones = ['Neutral'];
  int quickGreetingCount = 0;

  // ── Guided Mode Controllers ──
  final guidedVisionController = TextEditingController();
  final guidedAppearanceController = TextEditingController();
  final guidedHairController = TextEditingController();
  final guidedFeaturesController = TextEditingController();
  final guidedRaceController = TextEditingController();
  final guidedPersonalityController = TextEditingController();
  final guidedSpeechController = TextEditingController();
  final guidedSecretController = TextEditingController();
  final guidedOriginController = TextEditingController();
  final guidedSettingController = TextEditingController();
  final guidedToneController = TextEditingController();
  final guidedRelDynamicController = TextEditingController();
  final guidedRelScenarioController = TextEditingController();
  final guidedNsfwBodyController = TextEditingController();
  final guidedNsfwExpController = TextEditingController();
  final guidedNsfwDomController = TextEditingController();
  final guidedNsfwKinksController = TextEditingController();
  final guidedNsfwClothingController = TextEditingController();
  final guidedNsfwPersonalityController = TextEditingController();

  // Lore (for automated/guided)
  final loreUrlsController = TextEditingController();
  List<PlatformFile> loreFiles = [];

  /// The profile boxes (the Profile step and Review share them). Replaced by
  /// styled boxes made with their text when a profile arrives
  /// ([adoptProfileBoxes]), like the greeting boxes.
  TextEditingController descController = TextEditingController();
  TextEditingController personalityController = TextEditingController();
  TextEditingController scenarioController = TextEditingController();

  /// Replaced by [newGreetingBox] when a generated card's greetings arrive,
  /// like the alternates.
  TextEditingController firstMessageController = TextEditingController();
  final exampleDialogueController = TextEditingController();
  final systemPromptController = TextEditingController();
  List<TextEditingController> altGreetingControllers = [];
  List<GreetingRealismSeed?> greetingSeeds = [];
  final greetings = CreatorGreetings();
  final profile = CreatorProfile();
  final review = CreatorReview();
  final interview = CreatorInterview();

  /// The Mode step's templates and the form's `Started from` mark.
  late final templates = CreatorTemplates(notifyListeners, save: saveState);

  /// A generated greeting's box: the character editor's, with spell check
  /// and macro, "dialogue" and *action* colouring. Made with its text, so
  /// no spell-check pass is queued until someone types.
  TextEditingController newGreetingBox([String text = '']) =>
      StyledTextController(text: text, preset: StyledTextPreset.studioProse);

  /// A generated profile: its three boxes become styled boxes made with
  /// their text (never at construction: the spell-check timer). The old
  /// boxes may still be on screen this frame.
  void adoptProfileBoxes(String description, String personality, String scen) {
    final old = [descController, personalityController, scenarioController];
    descController = newGreetingBox(description);
    personalityController = newGreetingBox(personality);
    scenarioController = newGreetingBox(scen);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }

  // Generation state (lifted)
  String generationStatus = '';
  String generationPreview = '';
  bool isGenerating = false;
  double progress = 0.0;
  CharacterCard? generatedCard;
  String? imagePrompt;

  /// First-save picture (a persona's); null writes a placeholder.
  String? portraitSourcePath;
  Map<int, bool> lorebookEntryEnabled = {};

  // Quick-mode NSFW flag (synced into [nsfwEnabled] when generation starts).
  bool quickNsfwEnabled = false;

  // Async flags for AI-assisted helpers (magic-wand description, name/concept
  // randomizers, guided narrative expansion) — drive spinners in the steps.
  bool isExpandingNarrative = false;
  bool isRandomizing = false;
  double conceptGenProgress = 0.0;

  // Transient error surfaced by a step (e.g. "no LLM available"). The step
  // shows a SnackBar then clears it. Lives here because the engine has no
  // BuildContext of its own.
  String? engineError;

  // Realism Engine seed values — written into the saved card's
  // FrontPorchExtensions when [realismStepEnabled] is true. The Realism step
  // edits these; save consumes them. (Verification fields already exist above.)
  // Not saved with the draft: each visit opens it on Porch Life's "Start
  // every new chat with Realism"; Clear Everything goes back to it.
  bool realismStepEnabled = false;
  bool porchLifeRealism = false;
  int realismShortTermBond = 0;
  int realismLongTermBond = 0;
  int realismTrustLevel = 0;
  int realismDayCount = 1;
  String realismTimeOfDay = 'morning';
  // Story Calendar authoring (story-calendar.md §3a): null start date =
  // "the day the chat starts"; null time = period default.
  String? realismStoryStartDate;
  String? realismStoryStartTime;
  String realismEmotion = 'neutral';
  String realismEmotionIntensity = 'moderate';
  bool realismAfterglow = true; // the card's switch: how new chats start it
  bool realismChaosMode = false;
  // Same AND-gate as the manual creator: false on the card is a veto.
  bool realismNeedsSim = true;
  bool realismPocketsEnabled = true;
  bool realismEnjoysLowHygiene = false;

  /// Long-term ambitions authored in the creator's realism step (approved
  /// sketch §4). Card-resident like the rest of this state.
  List<String> realismAmbitions = const [];
  List<String> realismPlanLines = const [];

  /// The opening task (saved as `currentTask`), from the facts pass.
  String realismCurrentTask = '';
  String realismOccupation = '';
  String realismOccupationBrief = '';
  String realismBirthday = '';
  String realismHours = '';
  List<int>? realismWorkDays;

  /// Likes & Dislikes and the 18+ pair — same card-resident identity lists,
  /// authored in the same step.
  List<String> realismLikes = const [];
  List<String> realismDislikes = const [];
  List<String> realismIntimateInto = const [];
  List<String> realismIntimateNotInto = const [];

  /// Recovery profile from the realism step (Afterglow PR 2); notify-only.
  RecoveryProfile realismRecovery = const RecoveryProfile();

  /// Starting Pockets & Wardrobe as chip text (`sundress (rain-soaked)`).
  /// Notify-only like the identity lists above — saveState() persists none of
  /// them, and a half-persisted wardrobe would be worse than none.
  List<String> realismWorn = const [];
  List<String> realismCarrying = const [];

  // Needs simulation tuning — custom per-character baselines (0-100 starting
  // levels). Mirrors the character editor so AI-created characters can ship
  // the same setup; written into FrontPorchExtensions on save.
  int needsBaselineHunger = 80;
  int needsBaselineBladder = 80;
  int needsBaselineEnergy = 80;
  int needsBaselineSocial = 80;
  int needsBaselineFun = 80;
  int needsBaselineHygiene = 80;
  int needsBaselineComfort = 80;
  String needsPace = 'normal';
  List<String> needsOff = const [];

  // Model / backend state (lifted)
  String selectedModelId = '';
  List availableModels = [];
  bool isLoadingModels = false;
  List<FileSystemEntity> localModels = [];
  String selectedLocalModelPath = '';
  bool isReloadingKobold = false;
  String koboldStatus = '';
  List<File> localPresets = [];
  bool extraSettingsExpanded = false;
  final gpuLayersController = TextEditingController();
  final contextSizeController = TextEditingController();
  CharacterGenService? activeGenService;

  /// Makes each run's service. A test swaps in one with no retry waits.
  CharacterGenService Function(LLMService llm) newGenService =
      CharacterGenService.new;

  // Options (lifted statics)
  static const generationDetailOptions = {
    'Brief': '1 short paragraph (80-150 words max)',
    'Standard': '2-3 paragraphs (200-400 words max)',
    'Detailed': '3-4 paragraphs (300-500 words max)',
    'Comprehensive': '4-5 paragraphs (500-700 words max)',
  };

  static const loreCategoryOptions = [
    'Locations',
    'NPCs/Allies',
    'Factions/Organizations',
    'Culture/Customs',
    'Abilities/Magic',
    'Flora/Fauna',
    'Items/Equipment',
    'History/Events',
    'Secrets/Hidden Lore',
  ];

  static const loreDepths = ['Light', 'Standard', 'Deep'];

  static const relationshipPresets = [
    // SFW
    'Stranger', 'Childhood Friend', 'Rival', 'Best Friend',
    'Mentor', 'Student', 'Roommate', 'Co-worker',
    'Sparring Partner', 'Sibling',
    // Spicy/NSFW
    'Love Interest', 'Secret Admirer', 'Forbidden Romance',
    'FWB', 'Ex-lover', 'Arranged Marriage',
    'Fake Dating', 'Bodyguard',
  ];

  static const nsfwRelationships = {
    'Love Interest',
    'Secret Admirer',
    'Forbidden Romance',
    'FWB',
    'Ex-lover',
    'Arranged Marriage',
    'Fake Dating',
    'Bodyguard',
  };

  /// The real generation + save engine lives in `creator_state_engine.dart`
  /// (a CreatorState extension) to keep this file focused on state and honor
  /// the per-file size cap. The shell calls `generateFromMode(...)` and
  /// `saveCharacter(...)` from there.

  /// Allow direct step assignment from the engine extension (which only sees
  /// public members) without firing a listener per intermediate change.
  void setStep(int value) {
    _currentStep = value;
  }

  // Public notify for step widgets (avoids protected member warnings when called from outside)
  void notify() => notifyListeners();

  /// How long typing must pause before [scheduleSave] saves.
  static const saveDelay = Duration(milliseconds: 500);
  Timer? _saveTimer;

  /// Prefs I/O and its one-at-a-time save queue.
  final _prefs = CreatorFormPrefs();
  late final _models = CreatorBackendModels(this);

  /// False for a session seeded from a persona: it never loads or writes the
  /// saved draft, so the user's own unfinished character is left alone.
  bool persistDraft = true;

  /// Class door — `_CountingCreatorState` in the debounce test `@override`s
  /// this. An extension member is statically dispatched and cannot be.
  /// Drops a pending [scheduleSave]: this save already includes that text.
  Future<void> saveState() {
    _saveTimer?.cancel();
    if (!persistDraft) return Future<void>.value();
    return _prefs.save(this);
  }

  /// The typing door: one save once the user pauses, not one per keystroke
  /// (#371). Callers still [notify] at once; only the save waits.
  void scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, saveState);
  }

  Future<void> loadSavedState() async {
    await _prefs.load(this, applyMode: (mode) => _creatorMode = mode);
    notifyListeners();
  }

  void resetAllFields() {
    _currentStep = 0;
    _creatorMode = CreatorMode.automated;
    clearCreatorForm(this);
    notifyListeners();
  }

  /// Clear the core saved-form prefs after a character is successfully created,
  /// so the next visit starts fresh. Mirrors the original review-step save.
  Future<void> clearSavedFormPrefsAfterSave() =>
      persistDraft ? _prefs.clearAfterSave() : Future<void>.value();

  void abortGeneration() => _models.abortGeneration();

  Future<void> loadAvailableModels(LLMProvider llmProvider) =>
      _models.loadAvailableModels(llmProvider);

  void scanLocalModels(StorageService storage) =>
      _models.scanLocalModels(storage);

  void scanLocalPresets(StorageService storage) =>
      _models.scanLocalPresets(storage);

  void initLocalSettingsControllers(StorageService storage) =>
      _models.initLocalSettingsControllers(storage);

  /// The Realism step starts at `realismDefault`, not the permission.
  void seedRealismFromPorchLife(StorageService storage) {
    porchLifeRealism = storage.realismSettings.realismDefault;
    realismStepEnabled = porchLifeRealism;
    notifyListeners();
  }

  Future<void> reloadKoboldWithModel(
    String modelPath,
    LLMProvider llmProvider,
    StorageService storage,
    BackendManager backendManager,
  ) => _models.reloadKoboldWithModel(
    modelPath,
    llmProvider,
    storage,
    backendManager,
  );

  // Dispose for controllers (called by shell)
  void disposeControllers() {
    // Keep what was typed in the last half second before leaving.
    if (_saveTimer?.isActive ?? false) saveState();
    // A greeting still being written must not land in a disposed box.
    greetings.dispose();
    profile.dispose();
    review.dispose();
    interview.dispose();
    nameController.dispose();
    conceptController.dispose();
    keywordsController.dispose();
    ageController.dispose();
    sexController.dispose();
    relationshipController.dispose();
    descController.dispose();
    personalityController.dispose();
    scenarioController.dispose();
    firstMessageController.dispose();
    exampleDialogueController.dispose();
    systemPromptController.dispose();
    for (final c in altGreetingControllers) {
      c.dispose();
    }
    quickScenarioController.dispose();
    guidedVisionController.dispose();
    guidedAppearanceController.dispose();
    guidedHairController.dispose();
    guidedFeaturesController.dispose();
    guidedRaceController.dispose();
    guidedPersonalityController.dispose();
    guidedSpeechController.dispose();
    guidedSecretController.dispose();
    guidedOriginController.dispose();
    guidedSettingController.dispose();
    guidedToneController.dispose();
    guidedRelDynamicController.dispose();
    guidedRelScenarioController.dispose();
    guidedNsfwBodyController.dispose();
    guidedNsfwExpController.dispose();
    guidedNsfwDomController.dispose();
    guidedNsfwKinksController.dispose();
    guidedNsfwClothingController.dispose();
    guidedNsfwPersonalityController.dispose();
    gpuLayersController.dispose();
    contextSizeController.dispose();
    loreUrlsController.dispose();
    customRaceController.dispose();
    customKinksController.dispose();
    backstoryNotesController.dispose();
  }

  @override
  void dispose() {
    disposeControllers();
    super.dispose();
  }
}
