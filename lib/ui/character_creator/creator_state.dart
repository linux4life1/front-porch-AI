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

/// Creator mode selection.
enum CreatorMode { automated, guided, quick }

/// ChangeNotifier lifting all shared state for the AI character creator wizard.
/// Pure mechanical lift from the original god page per Stage 4 plan.
/// Owns all form fields, controllers, prefs keys, load/save/reset, step index,
/// generation state, and orchestration methods. UI steps are pure presentation.
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

  // Load / Save / Reset (pure lift, adapted for notifier)
  Future<void> loadSavedState() async {
    final prefs = await SharedPreferences.getInstance();
    nameController.text = prefs.getString(_prefName) ?? '';
    conceptController.text = prefs.getString(_prefConcept) ?? '';
    keywordsController.text = prefs.getString(_prefKeywords) ?? '';
    artStyle = prefs.getString(_prefArtStyle) ?? 'Anime';
    selectedModelId = prefs.getString(_prefModel) ?? '';
    greetingLength =
        prefs.getString(_prefGreetingLength) ?? 'Medium (2-4 paragraphs)';
    altGreetingCount = prefs.getInt(_prefAltCount) ?? 2;
    final savedTones = prefs.getString(_prefTone) ?? 'Neutral';
    selectedTones = savedTones.split(',').where((t) => t.isNotEmpty).toSet();
    if (selectedTones.isEmpty) selectedTones = {'Neutral'};
    generateLorebook = prefs.getBool(_prefLorebook) ?? true;
    ageController.text = prefs.getString(_prefAge) ?? '';
    sexController.text = prefs.getString(_prefSex) ?? '';
    relationshipController.text = prefs.getString(_prefRelationship) ?? '';
    selectedPersonaId = prefs.getString(_prefPersona) ?? '';
    quickScenarioController.text = prefs.getString(_prefQuickScenario) ?? '';

    final savedCategories = prefs.getString(_prefLoreCategories) ?? '';
    selectedLoreCategories = savedCategories
        .split(',')
        .where((c) => c.isNotEmpty)
        .toSet();
    loreDepth = prefs.getString(_prefLoreDepth) ?? 'Standard';
    includeDynamicMacros = prefs.getBool(_prefDynamicMacros) ?? false;
    narrativePerspective =
        prefs.getString(_prefNarrativePerspective) ?? 'first';
    if (narrativePerspective != 'first' && narrativePerspective != 'third') {
      narrativePerspective = 'first';
    }
    narrativeTense = prefs.getString(_prefNarrativeTense) ?? 'present';
    if (narrativeTense != 'present' && narrativeTense != 'past') {
      narrativeTense = 'present';
    }
    final savedRelationships = prefs.getString(_prefRelationships) ?? '';
    selectedRelationships = savedRelationships
        .split(',')
        .where((r) => r.isNotEmpty)
        .toSet();
    customRelationship = prefs.getString(_prefCustomRelationship) ?? '';
    nsfwEnabled = prefs.getBool(_prefNsfwEnabled) ?? false;
    realismVerificationEnabled =
        prefs.getBool(_prefRealismVerificationEnabled) ?? false;
    realismVerificationMaxReprocesses =
        prefs.getInt(_prefRealismVerificationMax) ?? 1;
    realismVerificationStrictness =
        prefs.getInt(_prefRealismVerificationStrict) ?? 3;
    realismNeedsDirectorAuthority =
        prefs.getBool(_prefRealismNeedsDirectorAuthority) ?? false;
    bodyType = prefs.getString(_prefBodyType) ?? '';
    race = prefs.getString(_prefRace) ?? '';
    customRaceController.text = prefs.getString(_prefCustomRace) ?? '';
    hairLength = prefs.getString(_prefHairLength) ?? '';
    hairStyle = prefs.getString(_prefHairStyle) ?? '';
    skinTone = prefs.getString(_prefSkinTone) ?? '';
    final savedFeatures = prefs.getString(_prefNotableFeatures) ?? '';
    notableFeatures = savedFeatures
        .split(',')
        .where((f) => f.isNotEmpty)
        .toSet();
    absCore = prefs.getString(_prefAbsCore) ?? '';
    thighs = prefs.getString(_prefThighs) ?? '';
    hips = prefs.getString(_prefHips) ?? '';
    shoulders = prefs.getString(_prefShoulders) ?? '';
    waist = prefs.getString(_prefWaist) ?? '';
    chestSize = prefs.getString(_prefChestSize) ?? '';
    buttSize = prefs.getString(_prefButtSize) ?? '';
    experience = prefs.getString(_prefExperience) ?? '';
    dominance = prefs.getString(_prefDominance) ?? '';
    final savedKinks = prefs.getString(_prefKinks) ?? '';
    selectedKinks = savedKinks.split(',').where((k) => k.isNotEmpty).toSet();
    customKinksController.text = prefs.getString(_prefCustomKinks) ?? '';
    outfitVibe = prefs.getString(_prefOutfitVibe) ?? '';
    generationDetail = prefs.getString(_prefGenerationDetail) ?? 'Standard';
    backstoryOrigin = prefs.getString(_prefBackstoryOrigin) ?? '';
    backstoryTone = prefs.getString(_prefBackstoryTone) ?? '';
    backstoryEra = prefs.getString(_prefBackstoryEra) ?? '';
    backstoryNotesController.text = prefs.getString(_prefBackstoryNotes) ?? '';
    conceptGenerated = prefs.getBool(_prefConceptGenerated) ?? false;

    // Stored as the enum's own name so every mode round-trips. Quick Create
    // used to collapse to 'automated' on BOTH sides of this pair, so picking
    // it and reopening the wizard silently put the user back on the automated
    // form. Unknown/legacy values still fall back to automated.
    final savedMode = prefs.getString(_prefCreatorMode) ?? 'automated';
    _creatorMode = switch (savedMode) {
      'guided' => CreatorMode.guided,
      'quick' => CreatorMode.quick,
      _ => CreatorMode.automated,
    };
    guidedVisionController.text = prefs.getString(_prefGuidedVision) ?? '';
    guidedAppearanceController.text =
        prefs.getString(_prefGuidedAppearance) ?? '';
    guidedHairController.text = prefs.getString(_prefGuidedHair) ?? '';
    guidedFeaturesController.text = prefs.getString(_prefGuidedFeatures) ?? '';
    guidedRaceController.text = prefs.getString(_prefGuidedRace) ?? '';
    guidedPersonalityController.text =
        prefs.getString(_prefGuidedPersonality) ?? '';
    guidedSpeechController.text = prefs.getString(_prefGuidedSpeech) ?? '';
    guidedSecretController.text = prefs.getString(_prefGuidedSecret) ?? '';
    guidedOriginController.text = prefs.getString(_prefGuidedOrigin) ?? '';
    guidedSettingController.text = prefs.getString(_prefGuidedSetting) ?? '';
    guidedToneController.text = prefs.getString(_prefGuidedTone) ?? '';
    guidedRelDynamicController.text =
        prefs.getString(_prefGuidedRelDynamic) ?? '';
    guidedRelScenarioController.text =
        prefs.getString(_prefGuidedRelScenario) ?? '';
    guidedNsfwBodyController.text = prefs.getString(_prefGuidedNsfwBody) ?? '';
    guidedNsfwExpController.text = prefs.getString(_prefGuidedNsfwExp) ?? '';
    guidedNsfwDomController.text = prefs.getString(_prefGuidedNsfwDom) ?? '';
    guidedNsfwKinksController.text =
        prefs.getString(_prefGuidedNsfwKinks) ?? '';
    guidedNsfwClothingController.text =
        prefs.getString(_prefGuidedNsfwClothing) ?? '';
    guidedNsfwPersonalityController.text =
        prefs.getString(_prefGuidedNsfwPersonality) ?? '';

    notifyListeners();
  }

  Future<void> saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefName, nameController.text);
    await prefs.setString(_prefConcept, conceptController.text);
    await prefs.setString(_prefKeywords, keywordsController.text);
    await prefs.setString(_prefArtStyle, artStyle);
    await prefs.setString(_prefModel, selectedModelId);
    await prefs.setString(_prefGreetingLength, greetingLength);
    await prefs.setInt(_prefAltCount, altGreetingCount);
    await prefs.setString(_prefTone, selectedTones.join(','));
    await prefs.setBool(_prefLorebook, generateLorebook);
    await prefs.setString(_prefAge, ageController.text);
    await prefs.setString(_prefSex, sexController.text);
    await prefs.setString(_prefRelationship, relationshipController.text);
    await prefs.setString(_prefPersona, selectedPersonaId);
    await prefs.setString(_prefQuickScenario, quickScenarioController.text);
    await prefs.setString(
      _prefLoreCategories,
      selectedLoreCategories.join(','),
    );
    await prefs.setString(_prefLoreDepth, loreDepth);
    await prefs.setBool(_prefDynamicMacros, includeDynamicMacros);
    await prefs.setString(_prefNarrativePerspective, narrativePerspective);
    await prefs.setString(_prefNarrativeTense, narrativeTense);
    await prefs.setString(_prefRelationships, selectedRelationships.join(','));
    await prefs.setString(_prefCustomRelationship, customRelationship);
    await prefs.setBool(_prefNsfwEnabled, nsfwEnabled);
    await prefs.setBool(
      _prefRealismVerificationEnabled,
      realismVerificationEnabled,
    );
    await prefs.setInt(
      _prefRealismVerificationMax,
      realismVerificationMaxReprocesses,
    );
    await prefs.setInt(
      _prefRealismVerificationStrict,
      realismVerificationStrictness,
    );
    await prefs.setBool(
      _prefRealismNeedsDirectorAuthority,
      realismNeedsDirectorAuthority,
    );
    await prefs.setString(_prefBodyType, bodyType);
    await prefs.setString(_prefRace, race);
    await prefs.setString(_prefCustomRace, customRaceController.text);
    await prefs.setString(_prefHairLength, hairLength);
    await prefs.setString(_prefHairStyle, hairStyle);
    await prefs.setString(_prefSkinTone, skinTone);
    await prefs.setString(_prefNotableFeatures, notableFeatures.join(','));
    await prefs.setString(_prefAbsCore, absCore);
    await prefs.setString(_prefThighs, thighs);
    await prefs.setString(_prefHips, hips);
    await prefs.setString(_prefShoulders, shoulders);
    await prefs.setString(_prefWaist, waist);
    await prefs.setString(_prefChestSize, chestSize);
    await prefs.setString(_prefButtSize, buttSize);
    await prefs.setString(_prefExperience, experience);
    await prefs.setString(_prefDominance, dominance);
    await prefs.setString(_prefKinks, selectedKinks.join(','));
    await prefs.setString(_prefCustomKinks, customKinksController.text);
    await prefs.setString(_prefOutfitVibe, outfitVibe);
    await prefs.setString(_prefGenerationDetail, generationDetail);
    await prefs.setString(_prefBackstoryOrigin, backstoryOrigin);
    await prefs.setString(_prefBackstoryTone, backstoryTone);
    await prefs.setString(_prefBackstoryEra, backstoryEra);
    await prefs.setString(_prefBackstoryNotes, backstoryNotesController.text);
    await prefs.setBool(_prefConceptGenerated, conceptGenerated);
    await prefs.setString(_prefCreatorMode, _creatorMode.name);
    await prefs.setString(_prefGuidedVision, guidedVisionController.text);
    await prefs.setString(
      _prefGuidedAppearance,
      guidedAppearanceController.text,
    );
    await prefs.setString(_prefGuidedHair, guidedHairController.text);
    await prefs.setString(_prefGuidedFeatures, guidedFeaturesController.text);
    await prefs.setString(_prefGuidedRace, guidedRaceController.text);
    await prefs.setString(
      _prefGuidedPersonality,
      guidedPersonalityController.text,
    );
    await prefs.setString(_prefGuidedSpeech, guidedSpeechController.text);
    await prefs.setString(_prefGuidedSecret, guidedSecretController.text);
    await prefs.setString(_prefGuidedOrigin, guidedOriginController.text);
    await prefs.setString(_prefGuidedSetting, guidedSettingController.text);
    await prefs.setString(_prefGuidedTone, guidedToneController.text);
    await prefs.setString(
      _prefGuidedRelDynamic,
      guidedRelDynamicController.text,
    );
    await prefs.setString(
      _prefGuidedRelScenario,
      guidedRelScenarioController.text,
    );
    await prefs.setString(_prefGuidedNsfwBody, guidedNsfwBodyController.text);
    await prefs.setString(_prefGuidedNsfwExp, guidedNsfwExpController.text);
    await prefs.setString(_prefGuidedNsfwDom, guidedNsfwDomController.text);
    await prefs.setString(_prefGuidedNsfwKinks, guidedNsfwKinksController.text);
    await prefs.setString(
      _prefGuidedNsfwClothing,
      guidedNsfwClothingController.text,
    );
    await prefs.setString(
      _prefGuidedNsfwPersonality,
      guidedNsfwPersonalityController.text,
    );
  }

  void resetAllFields() {
    // Step & mode
    _currentStep = 0;
    _creatorMode = CreatorMode.automated;

    // Basic info controllers
    nameController.clear();
    conceptController.clear();
    keywordsController.clear();
    ageController.clear();
    sexController.clear();
    relationshipController.clear();
    backstoryNotesController.clear();
    customRaceController.clear();
    customKinksController.clear();

    // Guided mode controllers
    guidedVisionController.clear();
    guidedAppearanceController.clear();
    guidedHairController.clear();
    guidedFeaturesController.clear();
    guidedRaceController.clear();
    guidedPersonalityController.clear();
    guidedSpeechController.clear();
    guidedSecretController.clear();
    guidedOriginController.clear();
    guidedSettingController.clear();
    guidedToneController.clear();
    guidedRelDynamicController.clear();
    guidedRelScenarioController.clear();
    guidedNsfwBodyController.clear();
    guidedNsfwExpController.clear();
    guidedNsfwDomController.clear();
    guidedNsfwKinksController.clear();
    guidedNsfwClothingController.clear();
    guidedNsfwPersonalityController.clear();
    loreUrlsController.clear();
    loreFiles.clear();

    // Review controllers
    descController.clear();
    personalityController.clear();
    scenarioController.clear();
    firstMessageController.clear();
    exampleDialogueController.clear();
    systemPromptController.clear();

    // Chip/toggle selections
    selectedTones = {'Neutral'};
    selectedLoreCategories = {};
    selectedRelationships = {};
    customRelationship = '';
    selectedArchetype = '';
    selectedKinks = {};
    notableFeatures = {};
    nsfwEnabled = false;
    realismVerificationEnabled = false;
    realismVerificationMaxReprocesses = 1;
    realismVerificationStrictness = 3;
    realismNeedsDirectorAuthority = false;

    // Appearance dropdowns
    race = '';
    bodyType = '';
    hairLength = '';
    hairStyle = '';
    skinTone = '';
    absCore = '';
    thighs = '';
    hips = '';
    shoulders = '';
    waist = '';

    // NSFW appearance
    chestSize = '';
    buttSize = '';
    experience = '';
    dominance = '';
    outfitVibe = '';

    // Backstory
    backstoryOrigin = '';
    backstoryTone = '';
    backstoryEra = '';
    conceptGenerated = false;

    // Generation config defaults
    artStyle = 'Anime';
    greetingLength = 'Medium (2-4 paragraphs)';
    altGreetingCount = 2;
    generateLorebook = true;
    loreDepth = 'Standard';
    includeDynamicMacros = false;
    narrativePerspective = 'first';
    narrativeTense = 'present';
    generationDetail = 'Standard';

    // Generation state
    generationStatus = '';
    generationPreview = '';
    isGenerating = false;
    progress = 0.0;

    // Generated results
    generatedCard = null;
    imagePrompt = null;
    lorebookEntryEnabled = {};

    // Persona
    selectedPersonaId = '';

    // Active gen service
    activeGenService = null;

    // Model state reset (light)
    selectedLocalModelPath = '';
    koboldStatus = '';
    selectedModelId = '';

    notifyListeners();
  }

  void abortGeneration() {
    activeGenService?.abort();
    isGenerating = false;
    generationStatus = 'Generation aborted.';
    generationPreview = '';
    progress = 0.0;
    _currentStep = 2; // Return to config step
    activeGenService = null;
    notifyListeners();
  }

  // Model loading / scanning (signatures adapted to accept services; callers pass from UI context)
  Future<void> loadAvailableModels(LLMProvider llmProvider) async {
    if (llmProvider.hasManagedProcess) {
      availableModels = [];
      isLoadingModels = false;
      selectedModelId = '';
      notifyListeners();
      return;
    }
    final openRouter = llmProvider.openRouterService;
    try {
      final models = await openRouter.fetchAvailableModels();
      availableModels = models;
      isLoadingModels = false;
      if (selectedModelId.isEmpty) {
        selectedModelId = openRouter.modelName;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('CreatorState: Failed to load models: $e');
      isLoadingModels = false;
      selectedModelId = llmProvider.openRouterService.modelName;
      notifyListeners();
    }
  }

  void scanLocalModels(StorageService storage) {
    final modelsDir = storage.modelsDir;
    if (!modelsDir.existsSync()) {
      localModels = [];
      notifyListeners();
      return;
    }
    try {
      final files =
          modelsDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.gguf'))
              .toList()
            ..sort(
              (a, b) => p
                  .basename(a.path)
                  .toLowerCase()
                  .compareTo(p.basename(b.path).toLowerCase()),
            );
      localModels = files;
      if (selectedLocalModelPath.isEmpty) {
        selectedLocalModelPath = storage.lastUsedModelPath ?? '';
      }
      notifyListeners();
    } catch (e) {
      debugPrint('CreatorState: Failed to scan models: $e');
      localModels = [];
      notifyListeners();
    }
  }

  void scanLocalPresets(StorageService storage) {
    localPresets = scanKcppsPresets(storage.binDir);
    notifyListeners();
  }

  void initLocalSettingsControllers(StorageService storage) {
    gpuLayersController.text = storage.gpuLayers.toString();
    contextSizeController.text = storage.contextSize.toString();
  }

  // Note: reloadKoboldWithModel lifted with service params (callers in steps
  // pass providers/storage from their context). It already launches a .kcpps
  // preset when one is active, so preset launching needs no separate path.
  Future<void> reloadKoboldWithModel(
    String modelPath,
    LLMProvider llmProvider,
    StorageService storage,
    BackendManager backendManager,
  ) async {
    if (isReloadingKobold) return;
    final kobold = llmProvider.koboldService;

    isReloadingKobold = true;
    koboldStatus = 'Stopping KoboldCpp...';
    notifyListeners();

    try {
      // Stop if running
      if (kobold.isRunning) {
        await kobold.stopKobold();
        await Future.delayed(const Duration(seconds: 1));
      }

      // Use BackendManager to find the executable (same pattern as model_settings_dialog & settings_page)
      if (backendManager.backendPath == null) {
        isReloadingKobold = false;
        koboldStatus = 'Error: Backend executable not found';
        notifyListeners();
        return;
      }
      final execPath = backendManager.backendPath!;

      koboldStatus = 'Starting KoboldCpp with new model...';
      notifyListeners();

      // If the .kcpps preset owns the model, let it handle model loading
      final hasValidKcppsModel =
          storage.kcppsHasModel && storage.kcppsModelFileExists;
      final effectiveModel = hasValidKcppsModel ? '' : modelPath;

      await kobold.startKobold(
        execPath,
        effectiveModel,
        kcppsPath: storage.activeKcppsPath,
        mmprojPath: modelPath.isNotEmpty
            ? storage.mmprojForModel(modelPath)
            : null,
        port: 5001,
        gpuLayers: storage.gpuLayers,
        contextSize: storage.contextSize,
        useVulkan: storage.useVulkan ?? false,
        useCublas: storage.useCublas ?? false,
        useMetal: storage.useMetal ?? false,
        useRocm: storage.useRocm ?? false,
      );

      // Save as last used model
      await storage.setLastUsedModelPath(modelPath);

      // Poll for model readiness
      koboldStatus = 'Loading model...';
      notifyListeners();
      for (int i = 0; i < 120; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (kobold.modelReady) {
          isReloadingKobold = false;
          koboldStatus = 'Model loaded successfully!';
          selectedLocalModelPath = modelPath;
          notifyListeners();
          return;
        }
        if (kobold.modelLoadingStatus.isNotEmpty) {
          koboldStatus = kobold.modelLoadingStatus;
          notifyListeners();
        }
      }

      isReloadingKobold = false;
      koboldStatus = 'Timeout waiting for model to load';
      notifyListeners();
    } catch (e) {
      isReloadingKobold = false;
      koboldStatus = 'Error: $e';
      notifyListeners();
    }
  }

  /// The real generation + save engine lives in `creator_state_engine.dart`
  /// (a CreatorState extension) to keep this file focused on state and honor
  /// the per-file size cap. The shell calls `generateFromMode(...)` and
  /// `saveCharacter(...)` from there.

  /// Allow direct step assignment from the engine extension (which only sees
  /// public members) without firing a listener per intermediate change.
  void setStep(int value) {
    _currentStep = value;
  }

  /// Clear the core saved-form prefs after a character is successfully created,
  /// so the next visit starts fresh. Mirrors the original review-step save.
  Future<void> clearSavedFormPrefsAfterSave() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [_prefName, _prefConcept, _prefKeywords, _prefArtStyle]) {
      await prefs.remove(key);
    }
  }

  // Public notify for step widgets (avoids protected member warnings when called from outside)
  void notify() => notifyListeners();

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

// Helper for kcpps scan (lifted if not in utils; assume or duplicate minimal)
List<File> scanKcppsPresets(Directory binDir) {
  if (!binDir.existsSync()) return [];
  try {
    return binDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.kcpps'))
        .toList();
  } catch (_) {
    return [];
  }
}
