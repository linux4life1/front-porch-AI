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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

part 'creator_state.prefs.dart';
part 'creator_state.models.dart';

/// Creator mode selection.
enum CreatorMode { automated, guided, quick }

/// Shared state for the AI character creator wizard: form fields,
/// controllers, prefs, load/save/reset, step index, and generation.
class CreatorState extends ChangeNotifier {
  // Step tracking (0=setup, 1=mode, 2=config, 3=generating, 4=realism, 5=review)
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

  // Review editable controllers (lifted)
  final descController = TextEditingController();
  final personalityController = TextEditingController();
  final scenarioController = TextEditingController();
  final firstMessageController = TextEditingController();
  final exampleDialogueController = TextEditingController();
  final systemPromptController = TextEditingController();
  List<TextEditingController> altGreetingControllers = [];
  List<GreetingRealismSeed?> greetingSeeds = [];

  // SharedPreferences keys (all lifted)
  static const _prefName = 'chargen_name';
  static const _prefConcept = 'chargen_concept';
  static const _prefKeywords = 'chargen_keywords';
  static const _prefArtStyle = 'chargen_art_style';
  static const _prefModel = 'chargen_model';
  static const _prefGreetingLength = 'chargen_greeting_length';
  static const _prefAltCount = 'chargen_alt_count';
  static const _prefTone = 'chargen_tone';
  static const _prefLorebook = 'chargen_lorebook';
  static const _prefAge = 'chargen_age';
  static const _prefSex = 'chargen_sex';
  static const _prefRelationship = 'chargen_relationship';
  static const _prefPersona = 'chargen_persona';
  static const _prefQuickScenario = 'chargen_quick_scenario';
  static const _prefLoreCategories = 'chargen_lore_categories';
  static const _prefLoreDepth = 'chargen_lore_depth';
  static const _prefDynamicMacros = 'chargen_dynamic_macros';
  static const _prefNarrativePerspective = 'chargen_narrative_perspective';
  static const _prefNarrativeTense = 'chargen_narrative_tense';
  static const _prefRelationships = 'chargen_relationships';
  static const _prefCustomRelationship = 'chargen_custom_relationship';
  static const _prefNsfwEnabled = 'chargen_nsfw_enabled';
  static const _prefRealismVerificationEnabled =
      'chargen_realism_verification_enabled';
  static const _prefRealismVerificationMax = 'chargen_realism_verification_max';
  static const _prefRealismVerificationStrict =
      'chargen_realism_verification_strict';
  static const _prefRealismNeedsDirectorAuthority =
      'chargen_realism_needs_director_authority';
  static const _prefBodyType = 'chargen_body_type';
  static const _prefRace = 'chargen_race';
  static const _prefCustomRace = 'chargen_custom_race';
  static const _prefHairLength = 'chargen_hair_length';
  static const _prefHairStyle = 'chargen_hair_style';
  static const _prefSkinTone = 'chargen_skin_tone';
  static const _prefNotableFeatures = 'chargen_notable_features';
  static const _prefAbsCore = 'chargen_abs_core';
  static const _prefThighs = 'chargen_thighs';
  static const _prefHips = 'chargen_hips';
  static const _prefShoulders = 'chargen_shoulders';
  static const _prefWaist = 'chargen_waist';
  static const _prefChestSize = 'chargen_chest_size';
  static const _prefButtSize = 'chargen_butt_size';
  static const _prefExperience = 'chargen_experience';
  static const _prefDominance = 'chargen_dominance';
  static const _prefKinks = 'chargen_kinks';
  static const _prefCustomKinks = 'chargen_custom_kinks';
  static const _prefOutfitVibe = 'chargen_outfit_vibe';
  static const _prefGenerationDetail = 'chargen_generation_detail';
  static const _prefBackstoryOrigin = 'chargen_backstory_origin';
  static const _prefBackstoryTone = 'chargen_backstory_tone';
  static const _prefBackstoryEra = 'chargen_backstory_era';
  static const _prefBackstoryNotes = 'chargen_backstory_notes';
  static const _prefConceptGenerated = 'chargen_concept_generated';
  static const _prefCreatorMode = 'chargen_creator_mode';
  static const _prefGuidedVision = 'chargen_guided_vision';
  static const _prefGuidedAppearance = 'chargen_guided_appearance';
  static const _prefGuidedHair = 'chargen_guided_hair';
  static const _prefGuidedFeatures = 'chargen_guided_features';
  static const _prefGuidedRace = 'chargen_guided_race';
  static const _prefGuidedPersonality = 'chargen_guided_personality';
  static const _prefGuidedSpeech = 'chargen_guided_speech';
  static const _prefGuidedSecret = 'chargen_guided_secret';
  static const _prefGuidedOrigin = 'chargen_guided_origin';
  static const _prefGuidedSetting = 'chargen_guided_setting';
  static const _prefGuidedTone = 'chargen_guided_tone';
  static const _prefGuidedRelDynamic = 'chargen_guided_rel_dynamic';
  static const _prefGuidedRelScenario = 'chargen_guided_rel_scenario';
  static const _prefGuidedNsfwBody = 'chargen_guided_nsfw_body';
  static const _prefGuidedNsfwExp = 'chargen_guided_nsfw_exp';
  static const _prefGuidedNsfwDom = 'chargen_guided_nsfw_dom';
  static const _prefGuidedNsfwKinks = 'chargen_guided_nsfw_kinks';
  static const _prefGuidedNsfwClothing = 'chargen_guided_nsfw_clothing';
  static const _prefGuidedNsfwPersonality = 'chargen_guided_nsfw_personality';

  // Generation state (lifted)
  String generationStatus = '';
  String generationPreview = '';
  bool isGenerating = false;
  double progress = 0.0;
  CharacterCard? generatedCard;
  String? imagePrompt;
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
  bool realismStepEnabled = false;
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
  bool realismNsfwCooldown = false;
  bool realismChaosMode = false;
  // Same AND-gate as the manual creator: false on the card is a veto.
  bool realismNeedsSim = true;
  bool realismEnjoysLowHygiene = false;

  /// Long-term ambitions authored in the creator's realism step (approved
  /// sketch §4). Card-resident like the rest of this state.
  List<String> realismAmbitions = const [];
  List<String> realismPlanLines = const [];
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

  /// Starting Pockets & Wardrobe as chip text (`sundress (rain-soaked)`).
  /// Notify-only like the identity lists above — saveState() persists none of
  /// them, and a half-persisted wardrobe would be worse than none.
  List<String> realismWorn = const [];
  List<String> realismCarrying = const [];

  // Needs simulation tuning — custom per-character baselines (0-100 starting
  // levels) and decay rates (drop per tick). Mirrors the character editor so
  // AI-created characters can ship the same custom needs setup; written into
  // FrontPorchExtensions on save. Defaults match create_character_page.
  int needsBaselineHunger = 80;
  int needsBaselineBladder = 80;
  int needsBaselineEnergy = 80;
  int needsBaselineSocial = 80;
  int needsBaselineFun = 80;
  int needsBaselineHygiene = 80;
  int needsBaselineComfort = 80;
  int needsDecayHunger = 5;
  int needsDecayBladder = 5;
  int needsDecayEnergy = 5;
  int needsDecaySocial = 5;
  int needsDecayFun = 5;
  int needsDecayHygiene = 5;
  int needsDecayComfort = 5;

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

  /// Class door — `_CountingCreatorState` in the debounce test `@override`s
  /// this. An extension member is statically dispatched and cannot be.
  Future<void> saveState() => _saveStateImpl();

  // Dispose for controllers (called by shell)
  void disposeControllers() {
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
