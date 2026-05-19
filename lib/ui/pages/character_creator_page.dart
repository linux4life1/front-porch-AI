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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:front_porch_ai/services/lore_extraction_service.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/character_gen_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/dialogs/image_crop_dialog.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';

/// Creator mode selection.
enum CreatorMode { automated, guided, quick }

/// Full-page AI-powered character creator wizard.
///
/// Step 0: Backend & Model setup.
/// Step 1: Mode selection (Automated vs Guided).
/// Step 2: Character configuration (mode-specific UI).
/// Step 3: AI generation progress.
/// Step 4: Review and edit the generated card, then save.
class CharacterCreatorPage extends StatefulWidget {
  const CharacterCreatorPage({super.key});

  @override
  State<CharacterCreatorPage> createState() => _CharacterCreatorPageState();
}

class _CharacterCreatorPageState extends State<CharacterCreatorPage> {
  // Step tracking
  int _currentStep = 0; // 0=setup, 1=mode select, 2=config, 3=generating, 4=review
  CreatorMode _creatorMode = CreatorMode.automated;

  // Step 1 — Input controllers
  final _nameController = TextEditingController();
  final _conceptController = TextEditingController();
  final _keywordsController = TextEditingController();
  final _ageController = TextEditingController();
  final _sexController = TextEditingController();
  final _relationshipController = TextEditingController();
  String _artStyle = 'Anime';
  String _greetingLength = 'Medium (2-4 paragraphs)';
  int _altGreetingCount = 2;
  Set<String> _selectedTones = {'Neutral'};
  bool _generateLorebook = true;
  Set<String> _selectedLoreCategories = {};
  String _loreDepth = 'Standard';
  Set<String> _selectedRelationships = {};
  String _customRelationship = '';
  String _selectedArchetype = '';
  bool _nsfwEnabled = false;
  bool _reasoningEnabled = false;
  String _generationDetail = 'Standard';

  // SFW Appearance
  String _race = '';
  final _customRaceController = TextEditingController();
  String _bodyType = '';
  String _hairLength = '';
  String _hairStyle = '';
  String _skinTone = '';
  Set<String> _notableFeatures = {};
  String _absCore = '';
  String _thighs = '';
  String _hips = '';
  String _shoulders = '';
  String _waist = '';

  // NSFW Appearance + Traits
  String _chestSize = '';
  String _buttSize = '';
  String _experience = '';
  String _dominance = '';
  Set<String> _selectedKinks = {};
  final _customKinksController = TextEditingController();
  String _outfitVibe = '';

  // Backstory
  String _backstoryOrigin = '';
  String _backstoryTone = '';
  String _backstoryEra = '';
  final _backstoryNotesController = TextEditingController();
  bool _conceptGenerated = false;

  String _selectedPersonaId = ''; // '' = None (blank slate)

  // ── Quick Mode Controllers ──
  final _quickScenarioController = TextEditingController();
  List<String> _quickSelectedTones = ['Neutral'];
  int _quickGreetingCount = 0;

  // ── Guided Mode Controllers ──
  final _guidedVisionController = TextEditingController();
  final _guidedAppearanceController = TextEditingController();
  final _guidedHairController = TextEditingController();
  final _guidedFeaturesController = TextEditingController();
  final _guidedRaceController = TextEditingController();
  final _guidedPersonalityController = TextEditingController();
  final _guidedSpeechController = TextEditingController();
  final _guidedSecretController = TextEditingController();
  final _guidedOriginController = TextEditingController();
  final _guidedSettingController = TextEditingController();
  final _guidedToneController = TextEditingController();
  final _guidedRelDynamicController = TextEditingController();
  final _guidedRelScenarioController = TextEditingController();
  // Guided NSFW
  final _guidedNsfwBodyController = TextEditingController();
  final _guidedNsfwExpController = TextEditingController();
  final _guidedNsfwDomController = TextEditingController();
  final _guidedNsfwKinksController = TextEditingController();
  final _guidedNsfwClothingController = TextEditingController();
  final _guidedNsfwPersonalityController = TextEditingController();
  bool _isExpandingNarrative = false;

  // Lore Extractors
  final _loreUrlsController = TextEditingController();
  List<PlatformFile> _loreFiles = [];

  /// Show confirmation dialog, then reset all fields if user confirms.
  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 24),
            SizedBox(width: 10),
            Text('Start New Character?', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          'This will clear ALL fields and generated content. This action cannot be undone.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black87,
            ),
            child: const Text('Clear Everything'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _resetAllFields();
    }
  }

  /// Reset every field, controller, selection, and generation state to defaults.
  void _resetAllFields() {
    setState(() {
      // Step & mode
      _currentStep = 0;

      // Basic info controllers
      _nameController.clear();
      _conceptController.clear();
      _keywordsController.clear();
      _ageController.clear();
      _sexController.clear();
      _relationshipController.clear();
      _backstoryNotesController.clear();
      _customRaceController.clear();
      _customKinksController.clear();

      // Guided mode controllers
      _guidedVisionController.clear();
      _guidedAppearanceController.clear();
      _guidedHairController.clear();
      _guidedFeaturesController.clear();
      _guidedRaceController.clear();
      _guidedPersonalityController.clear();
      _guidedSpeechController.clear();
      _guidedSecretController.clear();
      _guidedOriginController.clear();
      _guidedSettingController.clear();
      _guidedToneController.clear();
      _guidedRelDynamicController.clear();
      _guidedRelScenarioController.clear();
      _guidedNsfwBodyController.clear();
      _guidedNsfwExpController.clear();
      _guidedNsfwDomController.clear();
      _guidedNsfwKinksController.clear();
      _guidedNsfwClothingController.clear();
      _guidedNsfwPersonalityController.clear();
      _loreUrlsController.clear();
      _loreFiles.clear();

      // Review controllers
      _descController.clear();
      _personalityController.clear();
      _scenarioController.clear();
      _firstMessageController.clear();
      _exampleDialogueController.clear();
      _systemPromptController.clear();
      _imagePromptController.clear();

      // Chip/toggle selections
      _selectedTones = {'Neutral'};
      _selectedLoreCategories = {};
      _selectedRelationships = {};
      _customRelationship = '';
      _selectedArchetype = '';
      _selectedKinks = {};
      _notableFeatures = {};
      _nsfwEnabled = false;

      // Appearance dropdowns
      _race = '';
      _bodyType = '';
      _hairLength = '';
      _hairStyle = '';
      _skinTone = '';
      _absCore = '';
      _thighs = '';
      _hips = '';
      _shoulders = '';
      _waist = '';

      // NSFW appearance
      _chestSize = '';
      _buttSize = '';
      _experience = '';
      _dominance = '';
      _outfitVibe = '';

      // Backstory
      _backstoryOrigin = '';
      _backstoryTone = '';
      _backstoryEra = '';
      _conceptGenerated = false;

      // Generation config defaults
      _artStyle = 'Anime';
      _greetingLength = 'Medium (2-4 paragraphs)';
      _altGreetingCount = 2;
      _generateLorebook = true;
      _loreDepth = 'Standard';
      _generationDetail = 'Standard';

      // Generation state
      _generationStatus = '';
      _generationPreview = '';
      _isGenerating = false;
      _progress = 0.0;

      // Generated results
      _generatedCard = null;
      _generatedAvatar = null;
      _imagePrompt = null;
      _isGeneratingAvatar = false;
      _lorebookEntryEnabled = {};
      _imagePromptExpanded = false;

      // Persona
      _selectedPersonaId = '';

      // Active gen service
      _activeGenService = null;
    });
  }

  /// Abort an in-progress AI generation. Signals the CharacterGenService
  /// to stop between steps and cancels any in-flight LLM stream.
  void _abortGeneration() {
    _activeGenService?.abort();
    setState(() {
      _isGenerating = false;
      _generationStatus = 'Generation aborted.';
      _generationPreview = '';
      _progress = 0.0;
      _currentStep = 2; // Return to config step
      _activeGenService = null;
    });
  }

  // KoboldCpp local model state
  List<FileSystemEntity> _localModels = [];
  String _selectedLocalModelPath = '';
  bool _isReloadingKobold = false;
  String _koboldStatus = '';

  static const _artStyles = [
    'Anime',
    'Realistic',
    'Painterly',
    'Pixel Art',
    'Comic Book',
    'Watercolor',
    'Fantasy Illustration',
  ];

  static const _greetingLengths = [
    'Short (1-2 paragraphs)',
    'Medium (2-4 paragraphs)',
    'Long (4-6 paragraphs)',
  ];

  static const _greetingTones = [
    'Neutral',
    'Romantic',
    'Spicy/NSFW',
    'Flirty/Playful',
    'Wholesome',
    'Slice of Life',
    'Story/Narrative',
    'Adventure',
    'Combat/Action',
    'Comedy/Humor',
    'Suspense/Thriller',
    'Dark/Mystery',
    'Melancholy',
  ];

  static const _loreCategoryOptions = [
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

  static const _loreDepths = ['Light', 'Standard', 'Deep'];

  static const _relationshipPresets = [
    // SFW
    'Stranger', 'Childhood Friend', 'Rival', 'Best Friend',
    'Mentor', 'Student', 'Roommate', 'Co-worker',
    'Sparring Partner', 'Sibling',
    // Spicy/NSFW
    'Love Interest', 'Secret Admirer', 'Forbidden Romance',
    'FWB', 'Ex-lover', 'Arranged Marriage',
    'Fake Dating', 'Bodyguard',
  ];

  static const _nsfwRelationships = {
    'Love Interest', 'Secret Admirer', 'Forbidden Romance',
    'FWB', 'Ex-lover', 'Arranged Marriage',
    'Fake Dating', 'Bodyguard',
  };

  static const _archetypePresets = {
    'Tsundere': {
      'concept': 'A sharp-tongued person who hides their caring nature behind a cold exterior, denying their feelings while secretly looking out for {{user}}',
      'keywords': 'tsundere, sharp-tongued, secretly caring, stubborn, easily flustered',
    },
    'Yandere': {
      'concept': 'An obsessively devoted person whose love borders on dangerous possessiveness, willing to do anything to keep {{user}} close',
      'keywords': 'yandere, obsessive, possessive, devoted, unstable, sweet on the surface',
    },
    'Kuudere': {
      'concept': 'A stoic and emotionally reserved individual who rarely shows feelings, but whose rare moments of warmth are deeply meaningful',
      'keywords': 'kuudere, stoic, calm, reserved, analytical, quietly caring',
    },
    'Femme Fatale': {
      'concept': 'A dangerously alluring and manipulative figure who uses charm and wit as weapons, always three steps ahead',
      'keywords': 'seductive, cunning, confident, dangerous, mysterious, manipulative',
    },
    'Dark Lord': {
      'concept': 'A powerful and charismatic ruler of dark forces, whose iron will conceals a complex past and a surprising code of honor',
      'keywords': 'commanding, ruthless, charismatic, intelligent, dark humor, powerful',
    },
    'Mentor': {
      'concept': 'A wise and experienced guide who mentors {{user}} through challenges, offering cryptic advice and hard-earned wisdom',
      'keywords': 'wise, patient, cryptic, experienced, protective, tough love',
    },
    'Rival': {
      'concept': 'A fiercely competitive adversary who pushes {{user}} to their limits, respecting strength while refusing to lose',
      'keywords': 'competitive, proud, skilled, determined, begrudging respect, ambitious',
    },
    'Best Friend': {
      'concept': 'A loyal and easygoing companion who always has {{user}}\'s back, bringing laughter and genuine support to every situation',
      'keywords': 'loyal, funny, supportive, easygoing, ride-or-die, honest',
    },
    'The Healer': {
      'concept': 'A gentle and empathetic soul with healing abilities who tends to everyone\'s wounds but their own, carrying quiet burdens',
      'keywords': 'gentle, empathetic, selfless, nurturing, quietly strong, burdened',
    },
    'Rogue': {
      'concept': 'A charming and morally grey trickster who lives by their own rules, stealing hearts as easily as coin purses',
      'keywords': 'charming, witty, roguish, morally grey, quick on their feet, flirtatious',
    },
    'Chosen One': {
      'concept': 'A reluctant hero burdened by an ancient prophecy, thrust into a destiny they never asked for while just wanting a normal life',
      'keywords': 'reluctant, burdened, humble, determined, conflicted, growing into power',
    },
    'The Ex': {
      'concept': 'A former flame who reappears unexpectedly in {{user}}\'s life, carrying unresolved tension, lingering feelings, and unanswered questions',
      'keywords': 'complicated, nostalgic, guarded, magnetic, unresolved, bittersweet',
    },
    'Dandere': {
      'concept': 'A painfully shy and quiet soul who struggles to express themselves, but reveals incredible sweetness and depth once they feel safe enough to open up',
      'keywords': 'dandere, shy, quiet, gentle, sweet, anxious, secretly passionate',
    },
    'Genki': {
      'concept': 'An unstoppable ball of infectious energy and optimism who drags everyone into adventures, refuses to let anyone be sad, and lights up every room',
      'keywords': 'genki, energetic, optimistic, loud, cheerful, stubborn positivity, adventurous',
    },
    'Ojou-sama': {
      'concept': 'A sheltered noble or wealthy heir with an imperious demeanor and signature \"ohoho\" laugh, who secretly yearns for normal friendships and real connections',
      'keywords': 'ojou-sama, elegant, prideful, sheltered, secretly lonely, dramatic, refined',
    },
  };

  // ── Appearance Options (SFW) ──
  static const _bodyTypes = ['Petite', 'Slim', 'Athletic', 'Average', 'Curvy', 'Muscular', 'Plus-size', 'Tall & Lanky'];

  // ── Race / Species Options ──
  static const _raceOptions = [
    'Human', 'Elven', 'Dark Elf', 'Beastkin', 'Demon', 'Angel',
    'Vampire', 'Lycan', 'Dragon-blood', 'Fae', 'Merfolk',
    'Spirit', 'Undead', 'Elemental', 'Android', 'Alien', 'Monster',
  ];
  static const _hairLengths = ['Bald/Shaved', 'Pixie/Short', 'Medium', 'Long', 'Very Long'];
  static const _hairStyles = ['Straight', 'Wavy', 'Curly', 'Braided', 'Ponytail', 'Messy/Wild', 'Twin Tails'];
  static const _skinTones = ['Pale', 'Fair', 'Olive', 'Tan', 'Brown', 'Dark', 'Fantasy'];
  static const _notableFeatureOptions = ['Glasses', 'Freckles', 'Scars', 'Tattoos', 'Piercings', 'Heterochromia', 'Fangs', 'Horns', 'Wings', 'Tail', 'Elf Ears', 'Cat Ears'];
  static const _absCoreOptions = ['Soft', 'Toned', 'Defined', 'Ripped'];
  static const _thighOptions = ['Slim', 'Average', 'Thick', 'Thunder'];
  static const _hipOptions = ['Narrow', 'Average', 'Wide', 'Extra Wide'];
  static const _shoulderOptions = ['Narrow', 'Average', 'Broad', 'V-Shape'];
  static const _waistOptions = ['Wasp', 'Narrow', 'Average', 'Thick'];

  // ── NSFW Options ──
  static const _chestSizes = ['Flat', 'Small', 'Medium', 'Large', 'Huge'];
  static const _buttSizes = ['Flat', 'Small', 'Medium', 'Large', 'Huge'];
  static const _experienceOptions = ['Innocent', 'Virgin', 'Curious', 'Experienced', 'Insatiable'];
  static const _dominanceOptions = ['Submissive', 'Switch', 'Dominant'];
  static const _kinkOptions = ['Praise', 'Degradation', 'Biting/Marking', 'Bondage', 'Exhibitionism', 'Voyeurism', 'Facesitting', 'Smothering', 'Breath Play', 'Breeding', 'Jealousy/Possession'];
  static const _outfitVibes = ['Revealing', 'Lingerie', 'Uniform', 'Leather', 'Barely There'];

  // ── Backstory Options ──
  static const _backstoryOrigins = ['Orphan', 'Noble Birth', 'Self-Made', 'Exile/Outcast', 'Military/Warrior', 'Scholar/Academic', 'Criminal Past', 'Mysterious/Unknown', 'Supernatural Origin', 'Common Folk'];
  static const _backstoryTones = ['Tragic', 'Heroic', 'Comedic', 'Dark/Gritty', 'Wholesome', 'Mysterious', 'Redemptive'];
  static const _backstoryEras = ['Ancient', 'Medieval', 'Victorian', 'Modern', 'Futuristic', 'Timeless/Fantasy'];

  // ── Generation Detail Options ──
  static const _generationDetailOptions = {
    'Brief': '1 short paragraph (80-150 words max)',
    'Standard': '2-3 paragraphs (200-400 words max)',
    'Detailed': '3-4 paragraphs (300-500 words max)',
    'Comprehensive': '4-5 paragraphs (500-700 words max)',
  };

  // Step 2 — Generation state
  String _generationStatus = '';
  String _generationPreview = '';
  bool _isGenerating = false;
  double _progress = 0.0;
  CharacterGenService? _activeGenService;

  // Step 3 — Generated results
  CharacterCard? _generatedCard;
  Uint8List? _generatedAvatar;
  String? _imagePrompt;
  bool _isGeneratingAvatar = false;
  Map<int, bool> _lorebookEntryEnabled = {};
  bool _imagePromptExpanded = false;

  // Step 4 — Realism Engine initial state
  bool _realismStepEnabled = false;
  String _realismTimeOfDay = 'morning';
  int _realismDayCount = 1;
  int _realismShortTermBond = 0;
  int _realismLongTermBond = 0;
  int _realismTrustLevel = 0;
  String _realismEmotion = '';
  String _realismEmotionIntensity = 'mild';
  bool _realismNsfwCooldown = false;
  bool _realismChaosMode = false;
  String _realismCurrentTask = '';

  // Model selector state
  List<RemoteModelInfo> _availableModels = [];
  String _selectedModelId = '';
  bool _isLoadingModels = true;

  // Editable controllers for review step
  final _descController = TextEditingController();
  final _personalityController = TextEditingController();
  final _scenarioController = TextEditingController();
  final _firstMessageController = TextEditingController();
  final _exampleDialogueController = TextEditingController();
  final _systemPromptController = TextEditingController();
  final _imagePromptController = TextEditingController();

  // SharedPreferences keys
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
  static const _prefRelationships = 'chargen_relationships';
  static const _prefCustomRelationship = 'chargen_custom_relationship';
  static const _prefNsfwEnabled = 'chargen_nsfw_enabled';
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

  @override
  void initState() {
    super.initState();
    _loadSavedState();
    _loadAvailableModels();
    // Scan local GGUF models for KoboldCpp
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final llmProvider = Provider.of<LLMProvider>(context, listen: false);
      if (llmProvider.activeBackend == BackendType.kobold) {
        _scanLocalModels();
      }
    });
  }

  Future<void> _loadSavedState() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nameController.text = prefs.getString(_prefName) ?? '';
        _conceptController.text = prefs.getString(_prefConcept) ?? '';
        _keywordsController.text = prefs.getString(_prefKeywords) ?? '';
        _artStyle = prefs.getString(_prefArtStyle) ?? 'Anime';
        _selectedModelId = prefs.getString(_prefModel) ?? '';
        _greetingLength = prefs.getString(_prefGreetingLength) ?? 'Medium (2-4 paragraphs)';
        _altGreetingCount = prefs.getInt(_prefAltCount) ?? 2;
        final savedTones = prefs.getString(_prefTone) ?? 'Neutral';
        _selectedTones = savedTones.split(',').where((t) => t.isNotEmpty).toSet();
        if (_selectedTones.isEmpty) _selectedTones = {'Neutral'};
        _generateLorebook = prefs.getBool(_prefLorebook) ?? true;
        _ageController.text = prefs.getString(_prefAge) ?? '';
        _sexController.text = prefs.getString(_prefSex) ?? '';
        _relationshipController.text = prefs.getString(_prefRelationship) ?? '';
        _selectedPersonaId = prefs.getString(_prefPersona) ?? '';
        _quickScenarioController.text = prefs.getString(_prefQuickScenario) ?? '';

        final savedCategories = prefs.getString(_prefLoreCategories) ?? '';
        _selectedLoreCategories = savedCategories.split(',').where((c) => c.isNotEmpty).toSet();
        _loreDepth = prefs.getString(_prefLoreDepth) ?? 'Standard';
        final savedRelationships = prefs.getString(_prefRelationships) ?? '';
        _selectedRelationships = savedRelationships.split(',').where((r) => r.isNotEmpty).toSet();
        _customRelationship = prefs.getString(_prefCustomRelationship) ?? '';
        _nsfwEnabled = prefs.getBool(_prefNsfwEnabled) ?? false;
        _bodyType = prefs.getString(_prefBodyType) ?? '';
        _race = prefs.getString(_prefRace) ?? '';
        _customRaceController.text = prefs.getString(_prefCustomRace) ?? '';
        _hairLength = prefs.getString(_prefHairLength) ?? '';
        _hairStyle = prefs.getString(_prefHairStyle) ?? '';
        _skinTone = prefs.getString(_prefSkinTone) ?? '';
        final savedFeatures = prefs.getString(_prefNotableFeatures) ?? '';
        _notableFeatures = savedFeatures.split(',').where((f) => f.isNotEmpty).toSet();
        _absCore = prefs.getString(_prefAbsCore) ?? '';
        _thighs = prefs.getString(_prefThighs) ?? '';
        _hips = prefs.getString(_prefHips) ?? '';
        _shoulders = prefs.getString(_prefShoulders) ?? '';
        _waist = prefs.getString(_prefWaist) ?? '';
        _chestSize = prefs.getString(_prefChestSize) ?? '';
        _buttSize = prefs.getString(_prefButtSize) ?? '';
        _experience = prefs.getString(_prefExperience) ?? '';
        _dominance = prefs.getString(_prefDominance) ?? '';
        final savedKinks = prefs.getString(_prefKinks) ?? '';
        _selectedKinks = savedKinks.split(',').where((k) => k.isNotEmpty).toSet();
        _customKinksController.text = prefs.getString(_prefCustomKinks) ?? '';
        _outfitVibe = prefs.getString(_prefOutfitVibe) ?? '';
        _generationDetail = prefs.getString(_prefGenerationDetail) ?? 'Standard';
        _backstoryOrigin = prefs.getString(_prefBackstoryOrigin) ?? '';
        _backstoryTone = prefs.getString(_prefBackstoryTone) ?? '';
        _backstoryEra = prefs.getString(_prefBackstoryEra) ?? '';
        _backstoryNotesController.text = prefs.getString(_prefBackstoryNotes) ?? '';
        _conceptGenerated = prefs.getBool(_prefConceptGenerated) ?? false;

        // Guided mode fields
        final savedMode = prefs.getString(_prefCreatorMode) ?? 'automated';
        _creatorMode = savedMode == 'guided' ? CreatorMode.guided : CreatorMode.automated;
        _guidedVisionController.text = prefs.getString(_prefGuidedVision) ?? '';
        _guidedAppearanceController.text = prefs.getString(_prefGuidedAppearance) ?? '';
        _guidedHairController.text = prefs.getString(_prefGuidedHair) ?? '';
        _guidedFeaturesController.text = prefs.getString(_prefGuidedFeatures) ?? '';
        _guidedRaceController.text = prefs.getString(_prefGuidedRace) ?? '';
        _guidedPersonalityController.text = prefs.getString(_prefGuidedPersonality) ?? '';
        _guidedSpeechController.text = prefs.getString(_prefGuidedSpeech) ?? '';
        _guidedSecretController.text = prefs.getString(_prefGuidedSecret) ?? '';
        _guidedOriginController.text = prefs.getString(_prefGuidedOrigin) ?? '';
        _guidedSettingController.text = prefs.getString(_prefGuidedSetting) ?? '';
        _guidedToneController.text = prefs.getString(_prefGuidedTone) ?? '';
        _guidedRelDynamicController.text = prefs.getString(_prefGuidedRelDynamic) ?? '';
        _guidedRelScenarioController.text = prefs.getString(_prefGuidedRelScenario) ?? '';
        _guidedNsfwBodyController.text = prefs.getString(_prefGuidedNsfwBody) ?? '';
        _guidedNsfwExpController.text = prefs.getString(_prefGuidedNsfwExp) ?? '';
        _guidedNsfwDomController.text = prefs.getString(_prefGuidedNsfwDom) ?? '';
        _guidedNsfwKinksController.text = prefs.getString(_prefGuidedNsfwKinks) ?? '';
        _guidedNsfwClothingController.text = prefs.getString(_prefGuidedNsfwClothing) ?? '';
        _guidedNsfwPersonalityController.text = prefs.getString(_prefGuidedNsfwPersonality) ?? '';
      });
    }
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefName, _nameController.text);
    await prefs.setString(_prefConcept, _conceptController.text);
    await prefs.setString(_prefKeywords, _keywordsController.text);
    await prefs.setString(_prefArtStyle, _artStyle);
    await prefs.setString(_prefModel, _selectedModelId);
    await prefs.setString(_prefGreetingLength, _greetingLength);
    await prefs.setInt(_prefAltCount, _altGreetingCount);
    await prefs.setString(_prefTone, _selectedTones.join(','));
    await prefs.setBool(_prefLorebook, _generateLorebook);
    await prefs.setString(_prefAge, _ageController.text);
    await prefs.setString(_prefSex, _sexController.text);
    await prefs.setString(_prefRelationship, _relationshipController.text);
    await prefs.setString(_prefPersona, _selectedPersonaId);
    await prefs.setString(_prefQuickScenario, _quickScenarioController.text);

    await prefs.setString(_prefLoreCategories, _selectedLoreCategories.join(','));
    await prefs.setString(_prefLoreDepth, _loreDepth);
    await prefs.setString(_prefRelationships, _selectedRelationships.join(','));
    await prefs.setString(_prefCustomRelationship, _customRelationship);
    await prefs.setBool(_prefNsfwEnabled, _nsfwEnabled);
    await prefs.setString(_prefBodyType, _bodyType);
    await prefs.setString(_prefRace, _race);
    await prefs.setString(_prefCustomRace, _customRaceController.text);
    await prefs.setString(_prefHairLength, _hairLength);
    await prefs.setString(_prefHairStyle, _hairStyle);
    await prefs.setString(_prefSkinTone, _skinTone);
    await prefs.setString(_prefNotableFeatures, _notableFeatures.join(','));
    await prefs.setString(_prefAbsCore, _absCore);
    await prefs.setString(_prefThighs, _thighs);
    await prefs.setString(_prefHips, _hips);
    await prefs.setString(_prefShoulders, _shoulders);
    await prefs.setString(_prefWaist, _waist);
    await prefs.setString(_prefChestSize, _chestSize);
    await prefs.setString(_prefButtSize, _buttSize);
    await prefs.setString(_prefExperience, _experience);
    await prefs.setString(_prefDominance, _dominance);
    await prefs.setString(_prefKinks, _selectedKinks.join(','));
    await prefs.setString(_prefCustomKinks, _customKinksController.text);
    await prefs.setString(_prefOutfitVibe, _outfitVibe);
    await prefs.setString(_prefGenerationDetail, _generationDetail);
    await prefs.setString(_prefBackstoryOrigin, _backstoryOrigin);
    await prefs.setString(_prefBackstoryTone, _backstoryTone);
    await prefs.setString(_prefBackstoryEra, _backstoryEra);
    await prefs.setString(_prefBackstoryNotes, _backstoryNotesController.text);
    await prefs.setBool(_prefConceptGenerated, _conceptGenerated);

    // Guided mode fields
    await prefs.setString(_prefCreatorMode, _creatorMode == CreatorMode.guided ? 'guided' : 'automated');
    await prefs.setString(_prefGuidedVision, _guidedVisionController.text);
    await prefs.setString(_prefGuidedAppearance, _guidedAppearanceController.text);
    await prefs.setString(_prefGuidedHair, _guidedHairController.text);
    await prefs.setString(_prefGuidedFeatures, _guidedFeaturesController.text);
    await prefs.setString(_prefGuidedRace, _guidedRaceController.text);
    await prefs.setString(_prefGuidedPersonality, _guidedPersonalityController.text);
    await prefs.setString(_prefGuidedSpeech, _guidedSpeechController.text);
    await prefs.setString(_prefGuidedSecret, _guidedSecretController.text);
    await prefs.setString(_prefGuidedOrigin, _guidedOriginController.text);
    await prefs.setString(_prefGuidedSetting, _guidedSettingController.text);
    await prefs.setString(_prefGuidedTone, _guidedToneController.text);
    await prefs.setString(_prefGuidedRelDynamic, _guidedRelDynamicController.text);
    await prefs.setString(_prefGuidedRelScenario, _guidedRelScenarioController.text);
    await prefs.setString(_prefGuidedNsfwBody, _guidedNsfwBodyController.text);
    await prefs.setString(_prefGuidedNsfwExp, _guidedNsfwExpController.text);
    await prefs.setString(_prefGuidedNsfwDom, _guidedNsfwDomController.text);
    await prefs.setString(_prefGuidedNsfwKinks, _guidedNsfwKinksController.text);
    await prefs.setString(_prefGuidedNsfwClothing, _guidedNsfwClothingController.text);
    await prefs.setString(_prefGuidedNsfwPersonality, _guidedNsfwPersonalityController.text);
  }

  Future<void> _loadAvailableModels() async {
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);

    // If using KoboldCpp backend, no remote model list — just use the local model
    if (llmProvider.activeBackend == BackendType.kobold) {
      if (mounted) {
        setState(() {
          _availableModels = [];
          _isLoadingModels = false;
          _selectedModelId = ''; // Empty = use active service
        });
      }
      return;
    }

    final openRouter = llmProvider.openRouterService;
    try {
      final models = await openRouter.fetchAvailableModels();
      if (mounted) {
        setState(() {
          _availableModels = models;
          _isLoadingModels = false;
          // Default to current model if no saved preference
          if (_selectedModelId.isEmpty) {
            _selectedModelId = openRouter.modelName;
          }
        });
      }
    } catch (e) {
      debugPrint('CharacterCreator: Failed to load models: $e');
      if (mounted) {
        setState(() {
          _isLoadingModels = false;
          _selectedModelId = llmProvider.openRouterService.modelName;
        });
      }
    }
  }

  /// Scan modelsDir for .gguf files (local KoboldCpp models).
  void _scanLocalModels() {
    final storage = Provider.of<StorageService>(context, listen: false);
    final modelsDir = storage.modelsDir;
    if (!modelsDir.existsSync()) {
      setState(() => _localModels = []);
      return;
    }
    try {
      final files = modelsDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.gguf'))
          .toList()
        ..sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      setState(() {
        _localModels = files;
        // Default to last used model if available
        if (_selectedLocalModelPath.isEmpty) {
          _selectedLocalModelPath = storage.lastUsedModelPath ?? '';
        }
      });
    } catch (e) {
      debugPrint('CharacterCreator: Failed to scan models: $e');
      setState(() => _localModels = []);
    }
  }

  /// Stop KoboldCpp and restart with a new model file.
  Future<void> _reloadKoboldWithModel(String modelPath) async {
    if (_isReloadingKobold) return;
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    final kobold = llmProvider.koboldService;

    setState(() {
      _isReloadingKobold = true;
      _koboldStatus = 'Stopping KoboldCpp...';
    });

    try {
      // Stop if running
      if (kobold.isRunning) {
        await kobold.stopKobold();
        await Future.delayed(const Duration(seconds: 1));
      }

      // Find executable
      final binDir = storage.binDir;
      String? execPath;
      if (binDir.existsSync()) {
        for (final f in binDir.listSync()) {
          if (f is File && (f.path.contains('koboldcpp') || f.path.contains('KoboldCpp'))) {
            execPath = f.path;
            break;
          }
        }
      }

      if (execPath == null) {
        setState(() {
          _isReloadingKobold = false;
          _koboldStatus = 'Error: KoboldCpp executable not found';
        });
        return;
      }

      setState(() => _koboldStatus = 'Starting KoboldCpp with new model...');

      await kobold.startKobold(
        execPath,
        modelPath,
        kcppsPath: storage.activeKcppsPath,
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
      setState(() => _koboldStatus = 'Loading model...');
      for (int i = 0; i < 120; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        if (kobold.modelReady) {
          setState(() {
            _isReloadingKobold = false;
            _koboldStatus = 'Model loaded successfully!';
            _selectedLocalModelPath = modelPath;
          });
          return;
        }
        if (kobold.modelLoadingStatus.isNotEmpty) {
          setState(() => _koboldStatus = kobold.modelLoadingStatus);
        }
      }

      setState(() {
        _isReloadingKobold = false;
        _koboldStatus = 'Timeout waiting for model to load';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isReloadingKobold = false;
          _koboldStatus = 'Error: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    // Save state before disposing
    _saveState();
    _nameController.dispose();
    _conceptController.dispose();
    _keywordsController.dispose();
    _ageController.dispose();
    _sexController.dispose();
    _relationshipController.dispose();
    _descController.dispose();
    _personalityController.dispose();
    _scenarioController.dispose();
    _firstMessageController.dispose();
    _exampleDialogueController.dispose();
    _systemPromptController.dispose();
    _quickScenarioController.dispose();
    
    // Guided controllers
    _guidedVisionController.dispose();
    _guidedAppearanceController.dispose();
    _guidedHairController.dispose();
    _guidedFeaturesController.dispose();
    _guidedRaceController.dispose();
    _guidedPersonalityController.dispose();
    _guidedSpeechController.dispose();
    _guidedSecretController.dispose();
    _guidedOriginController.dispose();
    _guidedSettingController.dispose();
    _guidedToneController.dispose();
    _guidedRelDynamicController.dispose();
    _guidedRelScenarioController.dispose();
    _guidedNsfwBodyController.dispose();
    _guidedNsfwExpController.dispose();
    _guidedNsfwDomController.dispose();
    _guidedNsfwKinksController.dispose();
    _guidedNsfwClothingController.dispose();
    _guidedNsfwPersonalityController.dispose();
    _loreUrlsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _isGenerating ? null : () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.amberAccent, size: 22),
            const SizedBox(width: 8),
            const Text('AI Character Creator'),
            const Spacer(),
            // Step indicator
            _buildStepIndicator(),
          ],
        ),
        actions: [
          if (!_isGenerating)
            Tooltip(
              message: 'Start a new character (clears all fields)',
              child: IconButton(
                icon: const Icon(Icons.note_add_outlined, size: 22),
                onPressed: _confirmReset,
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _currentStep == 0
            ? _buildSetupStep()
            : _currentStep == 1
                ? _buildModeSelectStep()
                : _currentStep == 2
                    ? (_creatorMode == CreatorMode.guided
                        ? _buildGuidedConfigStep()
                        : _creatorMode == CreatorMode.quick
                            ? _buildQuickConfigStep()
                            : _buildConfigStep())
                    : _currentStep == 3
                        ? _buildGeneratingStep()
                        : _currentStep == 4
                            ? _buildRealismStep()
                            : _buildReviewStep(),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepDot(0, 'Setup'),
        _stepLine(),
        _stepDot(1, 'Mode'),
        _stepLine(),
        _stepDot(2, 'Configure'),
        _stepLine(),
        _stepDot(3, 'Generate'),
        _stepLine(),
        _stepDot(4, 'Realism'),
        _stepLine(),
        _stepDot(5, 'Review'),
      ],
    );
  }

  Widget _stepDot(int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? Colors.blueAccent : Colors.white12,
            border: isCurrent ? Border.all(color: Colors.white, width: 2) : null,
          ),
          child: Center(
            child: isActive && !isCurrent
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : Text('${step + 1}', style: TextStyle(fontSize: 11, color: isActive ? Colors.white : Colors.white38)),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: isActive ? Colors.white70 : Colors.white30)),
      ],
    );
  }

  Widget _stepLine() {
    return Container(
      width: 32,
      height: 2,
      margin: const EdgeInsets.only(bottom: 14),
      color: Colors.white12,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 0: Backend & Model Setup
  // ═══════════════════════════════════════════════════════════════

  Widget _buildSetupStep() {
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final isKobold = llmProvider.activeBackend == BackendType.kobold;

    return Center(
      key: const ValueKey('setup'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Text(
                'Backend & Model Setup',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose your AI backend and model before configuring your character.',
                style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
              ),
              const SizedBox(height: 32),

              // Backend toggle
              _inputLabel('Backend', required: false),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _backendChip(
                      label: 'KoboldCpp (Local)',
                      icon: Icons.computer,
                      isSelected: isKobold,
                      onTap: () async {
                        if (!isKobold) {
                          await llmProvider.setActiveBackend(BackendType.kobold);
                          _scanLocalModels();
                          setState(() {});
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _backendChip(
                      label: 'API (Remote)',
                      icon: Icons.cloud,
                      isSelected: !isKobold,
                      onTap: () async {
                        if (isKobold) {
                          await llmProvider.setActiveBackend(BackendType.openRouter);
                          _loadAvailableModels();
                          setState(() {});
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Model Selection ──
              if (isKobold) ...[
                _inputLabel('Local Model (.gguf)', required: false),
                const SizedBox(height: 8),
                // KoboldCpp status
                if (llmProvider.koboldService.isRunning)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green)),
                        const SizedBox(width: 8),
                        Text('KoboldCpp is running', style: TextStyle(color: Colors.green.shade300, fontSize: 12)),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red)),
                        const SizedBox(width: 8),
                        const Text('KoboldCpp is not running', style: TextStyle(color: Colors.red, fontSize: 12)),
                      ],
                    ),
                  ),
                // Model list
                Container(
                  constraints: const BoxConstraints(maxHeight: 250),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: _localModels.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.folder_open, color: Colors.white24, size: 32),
                                const SizedBox(height: 8),
                                const Text('No .gguf models found', style: TextStyle(color: Colors.white38)),
                                const SizedBox(height: 4),
                                Text('Place models in: ${Provider.of<StorageService>(context, listen: false).modelsDir.path}',
                                    style: const TextStyle(color: Colors.white24, fontSize: 11)),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: _scanLocalModels,
                                  icon: const Icon(Icons.refresh, size: 14),
                                  label: const Text('Rescan'),
                                  style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _localModels.length,
                          itemBuilder: (context, index) {
                            final file = _localModels[index] as File;
                            final name = p.basename(file.path);
                            final sizeBytes = file.lengthSync();
                            final sizeGB = (sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
                            final isSelected = file.path == _selectedLocalModelPath;
                            return ListTile(
                              dense: true,
                              selected: isSelected,
                              selectedTileColor: Colors.blueAccent.withValues(alpha: 0.15),
                              leading: Icon(
                                isSelected ? Icons.check_circle : Icons.description,
                                size: 18,
                                color: isSelected ? Colors.blueAccent : Colors.white24,
                              ),
                              title: Text(name,
                                  style: TextStyle(color: isSelected ? Colors.blueAccent : Colors.white, fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                              trailing: Text('${sizeGB}GB', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                              onTap: () => setState(() => _selectedLocalModelPath = file.path),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 16),
                // ── Context Size Slider ──
                Builder(builder: (context) {
                  final storage = Provider.of<StorageService>(context);
                  // Power-of-2 steps for context sizes
                  const contextSteps = [2048, 4096, 8192, 16384, 32768, 65536, 131072];
                  // Find closest step index for current value
                  int currentIdx = 0;
                  for (int i = 0; i < contextSteps.length; i++) {
                    if ((contextSteps[i] - storage.contextSize).abs() <
                        (contextSteps[currentIdx] - storage.contextSize).abs()) {
                      currentIdx = i;
                    }
                  }
                  final contextLabel = storage.contextSize >= 1024
                      ? '${(storage.contextSize / 1024).toStringAsFixed(storage.contextSize % 1024 == 0 ? 0 : 1)}K'
                      : '${storage.contextSize}';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.memory, size: 14, color: Colors.white38),
                          const SizedBox(width: 6),
                          Text('Context Size: $contextLabel tokens',
                            style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
                          const Spacer(),
                          Text('${storage.contextSize}',
                            style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      IgnorePointer(
                        ignoring: storage.activeKcppsPath != null && storage.activeKcppsPath!.isNotEmpty,
                        child: Opacity(
                          opacity: storage.activeKcppsPath != null && storage.activeKcppsPath!.isNotEmpty ? 0.5 : 1.0,
                          child: Tooltip(
                            message: storage.activeKcppsPath != null && storage.activeKcppsPath!.isNotEmpty
                                ? 'Context size is controlled by the active .kcpps preset and cannot be edited here.'
                                : '',
                            child: SliderTheme(
                              data: SliderThemeData(
                                activeTrackColor: Colors.blueAccent,
                                inactiveTrackColor: Colors.white10,
                                thumbColor: Colors.blueAccent,
                                overlayColor: Colors.blueAccent.withValues(alpha: 0.2),
                                trackHeight: 4,
                              ),
                              child: Slider(
                                value: currentIdx.toDouble(),
                                min: 0,
                                max: (contextSteps.length - 1).toDouble(),
                                divisions: contextSteps.length - 1,
                                onChanged: (val) {
                                  storage.setContextSize(contextSteps[val.round()]);
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('2K', style: TextStyle(color: Colors.white24, fontSize: 10)),
                          const Text('128K', style: TextStyle(color: Colors.white24, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Larger context uses more VRAM. Match your KoboldCpp --contextsize setting.',
                        style: TextStyle(color: Colors.white24, fontSize: 10),
                      ),
                    ],
                  );
                }),
                const SizedBox(height: 16),
                // Start/Stop button + status
                Row(
                  children: [
                    if (llmProvider.koboldService.isRunning)
                      ElevatedButton.icon(
                        onPressed: _isReloadingKobold
                            ? null
                            : () async {
                                setState(() => _koboldStatus = 'Stopping...');
                                await llmProvider.koboldService.stopKobold();
                                if (mounted) setState(() => _koboldStatus = 'Stopped');
                              },
                        icon: const Icon(Icons.stop, size: 16),
                        label: const Text('Stop KoboldCpp'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: _isReloadingKobold || _selectedLocalModelPath.isEmpty
                            ? null
                            : () => _reloadKoboldWithModel(_selectedLocalModelPath),
                        icon: _isReloadingKobold
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.play_arrow, size: 16),
                        label: Text(_isReloadingKobold ? 'Starting...' : 'Start KoboldCpp'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white10,
                        ),
                      ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _scanLocalModels,
                      icon: const Icon(Icons.folder_open, size: 14),
                      label: const Text('Rescan'),
                      style: TextButton.styleFrom(foregroundColor: Colors.white38),
                    ),
                    const SizedBox(width: 12),
                    if (_koboldStatus.isNotEmpty)
                      Expanded(
                        child: Text(_koboldStatus,
                          style: TextStyle(
                            color: _koboldStatus.contains('Error') ? Colors.red : Colors.white54,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ] else ...[
                // API model picker
                _inputLabel('Generation Model', required: false),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: _isLoadingModels
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            children: [
                              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38)),
                              SizedBox(width: 12),
                              Text('Loading models...', style: TextStyle(color: Colors.white38, fontSize: 13)),
                            ],
                          ),
                        )
                      : InkWell(
                          onTap: () async {
                            final result = await _showModelSearchDialog(
                              title: 'Select Generation Model',
                              currentValue: _selectedModelId,
                            );
                            if (result != null) {
                              setState(() => _selectedModelId = result);
                              _saveState();
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                const Icon(Icons.search, size: 16, color: Colors.white24),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _selectedModelId.isEmpty
                                        ? 'Select a model...'
                                        : (_availableModels.where((m) => m.id == _selectedModelId).firstOrNull?.name ?? _selectedModelId),
                                    style: TextStyle(color: _selectedModelId.isEmpty ? Colors.white38 : Colors.white, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down, color: Colors.white38),
                              ],
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tip: Enable Model Thinking below if using a reasoning model (e.g. Precog, QwQ).',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],

              const SizedBox(height: 24),

              // Reasoning toggle
              _buildReasoningToggle(Colors.blueAccent),

              const SizedBox(height: 32),

              // Next button
              Center(
                child: SizedBox(
                  width: 280,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() => _currentStep = 1),
                    icon: const Icon(Icons.arrow_forward, size: 20),
                    label: const Text('Next: Choose Mode', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backendChip({required String label, required IconData icon, required bool isSelected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent.withValues(alpha: 0.15) : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? Colors.blueAccent : Colors.white12, width: isSelected ? 2 : 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.blueAccent : Colors.white38),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isSelected ? Colors.blueAccent : Colors.white54, fontSize: 13, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 1: Mode Selection
  // ═══════════════════════════════════════════════════════════════

  Widget _buildModeSelectStep() {
    return Center(
      key: const ValueKey('mode-select'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How do you want to create?',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose the creation mode that fits your workflow.',
                style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
              ),
              const SizedBox(height: 32),

              // Automated Mode Card
              _modeCard(
                mode: CreatorMode.automated,
                icon: Icons.auto_awesome,
                iconColor: Colors.amberAccent,
                title: 'Automated Creator',
                subtitle: 'Pick traits from bubbles, let AI fill the gaps',
                description: 'Best when you want to explore and discover. '
                    'Select from archetypes, appearance options, backstory presets, '
                    'and personality keywords. The AI handles the rest.',
                features: const ['Archetype presets', 'Bubble selectors for every trait', 'AI generates description from selections'],
              ),
              const SizedBox(height: 16),

              // Guided Mode Card
              _modeCard(
                mode: CreatorMode.guided,
                icon: Icons.edit_note,
                iconColor: Colors.tealAccent,
                title: 'Guided Creator',
                subtitle: 'Write your vision, AI helps you flesh it out',
                description: 'Best when you already have a character in mind but need help '
                    'getting it on paper. Describe your idea in your own words — '
                    'guided prompts and suggestions help you express your vision.',
                features: const ['Free-form text with guided prompts', 'Suggestion chips for inspiration', '"Help me expand this" AI assist'],
              ),
              const SizedBox(height: 16),

              // Quick Mode Card
              _modeCard(
                mode: CreatorMode.quick,
                icon: Icons.bolt,
                iconColor: Colors.greenAccent,
                title: 'Quick Create',
                subtitle: 'Name it, describe it, done — AI does the rest',
                description: 'Fastest path to a finished character. '
                    'Just give a name and a one-liner. The full AI pipeline '
                    '(interview, lorebook, greetings) runs automatically.',
                features: const ['Name + concept only', 'NSFW toggle', 'Full pipeline in ~2 min'],
              ),

              const SizedBox(height: 32),

              // Navigation
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _currentStep = 0),
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Back', style: TextStyle(fontSize: 14)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white54,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 280,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() => _currentStep = 2),
                        icon: const Icon(Icons.arrow_forward, size: 20),
                        label: Text(
                          _creatorMode == CreatorMode.guided
                              ? 'Next: Guided Setup'
                              : _creatorMode == CreatorMode.quick
                                  ? 'Next: Quick Setup'
                                  : 'Next: Automated Setup',
                          style: const TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _creatorMode == CreatorMode.guided
                              ? const Color(0xFF0D7377)
                              : _creatorMode == CreatorMode.quick
                                  ? const Color(0xFF1B5E20)
                                  : Colors.blueAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeCard({
    required CreatorMode mode,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String description,
    required List<String> features,
  }) {
    final isSelected = _creatorMode == mode;
    Color borderColor;
    if (isSelected) {
      borderColor = mode == CreatorMode.guided
          ? Colors.tealAccent
          : mode == CreatorMode.quick
              ? Colors.greenAccent
              : Colors.amberAccent;
    } else {
      borderColor = Colors.white12;
    }

    return InkWell(
      onTap: () {
        setState(() => _creatorMode = mode);
        _saveState();
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected
              ? (mode == CreatorMode.guided
                  ? Colors.tealAccent.withValues(alpha: 0.06)
                  : mode == CreatorMode.quick
                      ? Colors.greenAccent.withValues(alpha: 0.06)
                      : Colors.amberAccent.withValues(alpha: 0.06))
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.white70,
                      )),
                      const Spacer(),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: borderColor.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('Selected', style: TextStyle(color: borderColor, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: isSelected ? iconColor : Colors.white38, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(description, style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.4)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: features.map((f) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline, size: 12, color: isSelected ? iconColor : Colors.white24),
                        const SizedBox(width: 4),
                        Text(f, style: TextStyle(color: isSelected ? Colors.white54 : Colors.white24, fontSize: 11)),
                      ],
                    )).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 2 (Quick): Quick Create Configuration
  // ═══════════════════════════════════════════════════════════════

  bool _quickNsfwEnabled = false;

  Widget _buildQuickConfigStep() {
    final nameEmpty = _nameController.text.trim().isEmpty;

    return Center(
      key: const ValueKey('quick-config'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bolt, color: Colors.greenAccent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Quick Create', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('Name it, describe it, generate.', style: TextStyle(fontSize: 13, color: Colors.white38)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Name field
              const Text('Character Name', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                onChanged: (_) {
                  setState(() {});
                  _saveState();
                },
                decoration: InputDecoration(
                  hintText: 'Morgana, Kaito, Vex...',
                  hintStyle: const TextStyle(color: Colors.white12, fontSize: 14),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.greenAccent, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 24),

              // Concept field
              const Text('Describe them (optional)', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              const Text(
                'A sentence or two is plenty. Leave it blank and the AI will invent someone.',
                style: TextStyle(color: Colors.white24, fontSize: 11),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _conceptController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 4,
                minLines: 3,
                onChanged: (_) {
                  setState(() {});
                  _saveState();
                },
                decoration: InputDecoration(
                  hintText: 'A gruff dwarven blacksmith who secretly writes poetry...',
                  hintStyle: const TextStyle(color: Colors.white12, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.greenAccent, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 24),

              // Scenario field
              const Text('Scenario / Setting (optional)', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              const Text(
                'Where does the story take place? What\'s the situation? The AI will build on this.',
                style: TextStyle(color: Colors.white24, fontSize: 11),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _quickScenarioController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 3,
                minLines: 2,
                onChanged: (_) {
                  setState(() {});
                  _saveState();
                },
                decoration: InputDecoration(
                  hintText: 'A modern coffee shop where they work as a barista, a fantasy guild hall, a space station...',
                  hintStyle: const TextStyle(color: Colors.white12, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.greenAccent, width: 2)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
              const SizedBox(height: 24),

              // Art style
              const Text('Avatar Art Style', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _artStyles.map((style) {
                  final isSelected = _artStyle == style;
                  return ChoiceChip(
                    label: Text(style),
                    selected: isSelected,
                    onSelected: (_) { setState(() => _artStyle = style); _saveState(); },
                    selectedColor: Colors.greenAccent.shade700,
                    backgroundColor: const Color(0xFF1E293B),
                    labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 13),
                    side: BorderSide(color: isSelected ? Colors.greenAccent.shade700 : Colors.white12),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Greeting tones
              const Text('Greeting Tone', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(
                _quickGreetingCount == 0
                    ? 'Tone for the first message.'
                    : 'Select up to ${_quickGreetingCount + 1} — one per greeting.',
                style: const TextStyle(color: Colors.white24, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _greetingTones.where((tone) => tone != 'Spicy/NSFW' || _quickNsfwEnabled).map((tone) {
                  final isSelected = _quickSelectedTones.contains(tone);
                  final maxTones = _quickGreetingCount + 1;
                  final atLimit = _quickSelectedTones.length >= maxTones && !isSelected;
                  return FilterChip(
                    label: Text(tone),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          if (atLimit) _quickSelectedTones.remove(_quickSelectedTones.last);
                          _quickSelectedTones.add(tone);
                        } else if (_quickSelectedTones.length > 1) {
                          _quickSelectedTones.remove(tone);
                        }
                      });
                      _saveState();
                    },
                    selectedColor: Colors.greenAccent.shade700,
                    backgroundColor: const Color(0xFF1E293B),
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 13),
                    side: BorderSide(color: isSelected ? Colors.greenAccent.shade700 : Colors.white12),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Number of greetings
              const Text('Number of Greetings', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              const Text(
                'How many first messages to generate (1 main + alternates).',
                style: TextStyle(color: Colors.white24, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _quickGreetingCount.toDouble(),
                      min: 0,
                      max: 5,
                      divisions: 5,
                      activeColor: Colors.greenAccent.shade700,
                      inactiveColor: Colors.white12,
                      label: _quickGreetingCount == 0 ? '1 greeting' : '1 + $_quickGreetingCount alt${_quickGreetingCount == 1 ? '' : 's'}',
                      onChanged: (val) {
                        setState(() {
                          _quickGreetingCount = val.round();
                          final maxTones = _quickGreetingCount + 1;
                          while (_quickSelectedTones.length > maxTones) _quickSelectedTones.remove(_quickSelectedTones.last);
                        });
                        _saveState();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      _quickGreetingCount == 0 ? '1 greeting' : '1 + $_quickGreetingCount',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Lore Input
              _buildLoreInputSection(Colors.greenAccent),
              const SizedBox(height: 28),

              // NSFW toggle
              InkWell(
                onTap: () => setState(() => _quickNsfwEnabled = !_quickNsfwEnabled),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _quickNsfwEnabled
                        ? Colors.pinkAccent.withValues(alpha: 0.08)
                        : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _quickNsfwEnabled ? Colors.pinkAccent.withValues(alpha: 0.5) : Colors.white12,
                      width: _quickNsfwEnabled ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        color: _quickNsfwEnabled ? Colors.pinkAccent : Colors.white24,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NSFW Content',
                              style: TextStyle(
                                color: _quickNsfwEnabled ? Colors.pinkAccent.shade100 : Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Enables adult themes in personality, lorebook, and greetings',
                              style: TextStyle(
                                color: _quickNsfwEnabled ? Colors.pinkAccent.withValues(alpha: 0.6) : Colors.white24,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _quickNsfwEnabled,
                        onChanged: (v) => setState(() => _quickNsfwEnabled = v),
                        activeColor: Colors.pinkAccent,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 36),

              // Buttons
              Row(
                children: [
                  SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _currentStep = 1),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: nameEmpty ? null : _startQuickGeneration,
                        icon: const Icon(Icons.bolt, size: 20),
                        label: Text(
                          nameEmpty ? 'Enter a name to continue' : 'Create Character',
                          style: const TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent.shade700,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white10,
                          disabledForegroundColor: Colors.white30,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shared method to extract world lore and respect token budgets.
  Future<String?> _extractWorldLore(LLMProvider provider) async {
    final loreUrls = _loreUrlsController.text.split(',').map((e) => e.trim()).toList();
    if (loreUrls.isEmpty && _loreFiles.isEmpty) return null;

    if (mounted) setState(() => _generationStatus = 'Gathering world lore...');
    String? worldLore = await LoreExtractionService.extractAll(
      urls: loreUrls,
      files: _loreFiles,
      onProgress: (msg) {
        if (mounted) setState(() => _generationStatus = msg);
      },
    );

    if (worldLore.trim().isNotEmpty) {
      final estimatedTokens = worldLore.length ~/ 4;
      
      int freeContextLimit = 30000;
      if (provider.activeBackend == BackendType.kobold && provider.koboldService.isReady) {
         final storage = Provider.of<StorageService>(context, listen: false);
         final koboldContext = storage.contextSize;
         freeContextLimit = koboldContext - 3000; // Leave 3K for generation
      } else {
         freeContextLimit = 120000; 
      }
      
      if (estimatedTokens > freeContextLimit) {
         debugPrint('Lore tokens ($estimatedTokens) exceeds free limit ($freeContextLimit). Truncating.');
         final charLimit = (freeContextLimit * 4).clamp(0, worldLore.length);
         worldLore = worldLore.substring(0, charLimit);
         worldLore += '\n[TRUNCATED DUE TO CONTEXT LIMITS]';
         
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(
             content: Text('World Lore truncated to fit context limits ($estimatedTokens > $freeContextLimit).'),
             backgroundColor: Colors.orange,
             behavior: SnackBarBehavior.floating,
             duration: const Duration(seconds: 5),
           ));
         }
      }
      return worldLore;
    }
    return null;
  }

  /// Generate a character from Quick mode — uses sensible defaults for
  /// everything the user didn't fill in, then routes to the shared pipeline.
  Future<void> _startQuickGeneration() async {
    final name = _nameController.text.trim();
    // Concept is optional in quick mode — if blank, let the LLM invent freely
    final concept = _conceptController.text.trim().isNotEmpty
        ? _conceptController.text.trim()
        : 'Create an interesting, unique character for roleplay.';

    setState(() {
      _currentStep = 3;
      _isGenerating = true;
      _generationStatus = 'Crafting character with AI...';
      _generationPreview = '';
      _progress = 0.0;
      // Sync NSFW state back to main flag so review step shows correctly
      _nsfwEnabled = _quickNsfwEnabled;
    });

    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);

    LLMService llmService;
    if (llmProvider.activeBackend == BackendType.kobold) {
      final kobold = llmProvider.koboldService;
      if (!kobold.isReady) {
        setState(() {
          _generationStatus = 'Error: KoboldCpp is not running. Start it first.';
          _isGenerating = false;
        });
        return;
      }
      llmService = kobold;
    } else if (_selectedModelId.isNotEmpty && _selectedModelId != llmProvider.openRouterService.modelName) {
      llmService = OpenRouterService(
        apiUrl: storage.remoteApiUrl,
        apiKey: storage.remoteApiKey,
        modelName: _selectedModelId,
      );
    } else {
      final active = llmProvider.activeService;
      if (active == null || !active.isReady) {
        setState(() {
          _generationStatus = 'Error: No LLM service available. Configure a model first.';
          _isGenerating = false;
        });
        return;
      }
      llmService = active;
    }

    // Resolve active persona if any
    String userPersonaContext = '';
    if (_selectedPersonaId.isNotEmpty) {
      final personaService = Provider.of<UserPersonaService>(context, listen: false);
      final persona = personaService.personas.where((p) => p.id == _selectedPersonaId).firstOrNull;
      if (persona != null) {
        final parts = <String>[];
        if (persona.name.isNotEmpty) parts.add('Name: ${persona.name}');
          if (persona.persona.isNotEmpty) parts.add('Persona: ${persona.persona}');
        userPersonaContext = parts.join('\n');
      }
    }
    
    // Extract World Lore
    final worldLore = await _extractWorldLore(llmProvider);

    final genService = CharacterGenService(llmService);
    _activeGenService = genService;
    String? genError;

    // Quick mode defaults — everything the wizard normally asks for
    final quickConcept = _quickNsfwEnabled
        ? '$concept. Adult content enabled: include explicit personality traits and sensual details.'
        : concept;

    final card = await genService.generateCharacter(
      name: name,
      concept: quickConcept,
      personalityKeywords: '',
      artStyle: _artStyle,
      greetingLength: 'Medium (2-4 paragraphs)',
      altGreetingCount: _quickGreetingCount,
      greetingTones: _quickSelectedTones,
      generateLorebook: true,
      loreCategories: const [],
      loreDepth: 'Standard',
      descriptionDetail: '2-3 paragraphs',
      age: '',
      sex: '',
      relationship: '',
      scenario: _quickScenarioController.text.trim(),
      backstory: '',
      characterContext: '',
      userPersonaContext: userPersonaContext,
      worldLore: worldLore,
      generateDescription: true,
      nsfwEnabled: _nsfwEnabled,
      reasoningEnabled: _reasoningEnabled,
      imageGenPromptParadigm: storage.imageGenPromptParadigm,
      onProgress: (accumulated) {
        if (mounted) {
          setState(() {
            _generationPreview = accumulated;
            _progress = (accumulated.length / 3000.0).clamp(0.0, 0.95);
          });
        }
      },
      onStatus: (status) {
        if (mounted) setState(() => _generationStatus = status);
      },
      onError: (error) {
        genError = error;
        if (mounted) setState(() => _generationStatus = 'Error: $error');
      },
    );

    if (!mounted) return;
    // If aborted, _abortGeneration already reset state — bail out silently.
    if (genService.isAborted) return;
    if (card == null || genError != null) {
      setState(() {
        _isGenerating = false;
        _generationStatus = genError ?? 'Generation failed. Check your backend connection.';
        _activeGenService = null;
      });
      return;
    }

    // Use the dedicated image prompt generated at the end of the pipeline
    if (genService.generatedImagePrompt != null) {
      _imagePrompt = genService.generatedImagePrompt;
    }

    // Populate review-step controllers so the fields aren't blank
    _lorebookEntryEnabled = {};
    if (card.lorebook != null) {
      for (int i = 0; i < card.lorebook!.entries.length; i++) {
        _lorebookEntryEnabled[i] = true;
      }
    }
    _descController.text = card.description;
    _personalityController.text = card.personality;
    _scenarioController.text = card.scenario;
    _firstMessageController.text = card.firstMessage;
    _exampleDialogueController.text = card.mesExample;
    _systemPromptController.text = card.systemPrompt;

    setState(() {
      _generatedCard = card;
      _currentStep = 4; // Realism Engine step (was Review)
      _isGenerating = false;
      _progress = 1.0;
      _activeGenService = null;
    });

    // Auto-start avatar generation (API backend only)
    final llmProvider2 = Provider.of<LLMProvider>(context, listen: false);
    if (llmProvider2.activeBackend != BackendType.kobold) {
      _generateAvatar();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 2 (Guided): Guided Character Configuration
  // ═══════════════════════════════════════════════════════════════

  static const _guidedVisionPlaceholders = [
    'A tall, slender woman with flowing black hair was dancing in a nightclub when she locked eyes with {{user}}...',
    'A grizzled old blacksmith with one arm, haunted by the war, but still cracks jokes while forging weapons...',
    'Shy bookworm, always has cat hair on her sweater, secretly powerful mage, terrible at eye contact...',
    'Cocky bounty hunter with cybernetic eyes and a debt to the wrong people. Flirts with everyone...',
    'Ancient dragon disguised as a librarian, hoards rare first editions instead of gold...',
  ];

  static const _scenarioSeeds = [
    'Met at a café', 'Childhood friends', 'Mysterious stranger', 'Coworkers',
    'Online match', 'Rescued by them', 'Woke up next to them', 'Battle partners',
    'Neighbors', 'Classmates', 'Summoned them',
  ];

  /// Build a guided text field with suggestion chips that fill the field.
  Widget _guidedField({
    required String label,
    required TextEditingController controller,
    required String hint,
    List<String> suggestions = const [],
    int maxLines = 2,
    int minLines = 1,
    bool isNsfw = false,
    Widget? trailing,
  }) {
    final accentColor = isNsfw ? Colors.pinkAccent : Colors.tealAccent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isNsfw) ...[
                const Icon(Icons.local_fire_department, size: 12, color: Colors.pinkAccent),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(label, style: TextStyle(
                  color: isNsfw ? Colors.pinkAccent.shade100 : Colors.white54,
                  fontSize: 12, fontWeight: FontWeight.w500,
                )),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: maxLines,
            minLines: minLines,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            onChanged: (_) {
              setState(() {});
              _saveState();
            },
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white12, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white12)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white12)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: accentColor)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: suggestions.map((sug) {
                final isInField = controller.text.toLowerCase().contains(sug.toLowerCase());
                return InkWell(
                  onTap: () {
                    if (!isInField) {
                      final current = controller.text.trim();
                      controller.text = current.isEmpty ? sug : '$current, $sug';
                      controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
                      setState(() {});
                      _saveState();
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isInField ? accentColor.withValues(alpha: 0.2) : const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isInField ? accentColor.withValues(alpha: 0.5) : Colors.white10),
                    ),
                    child: Text(sug, style: TextStyle(
                      color: isInField ? accentColor : Colors.white38, fontSize: 11,
                    )),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  /// Collapsible section for guided mode
  Widget _guidedSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
    Color accentColor = Colors.tealAccent,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF162032),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.15)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: accentColor,
          collapsedIconColor: Colors.white24,
          leading: Icon(icon, color: accentColor, size: 18),
          title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, style: const TextStyle(color: Colors.white24, fontSize: 11)),
          children: children,
        ),
      ),
    );
  }

  /// Shared reasoning/thinking toggle for all creation modes.
  Widget _buildReasoningToggle(Color accentColor) {
    return InkWell(
      onTap: () => setState(() => _reasoningEnabled = !_reasoningEnabled),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _reasoningEnabled
              ? accentColor.withValues(alpha: 0.08)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _reasoningEnabled ? accentColor.withValues(alpha: 0.5) : Colors.white12,
            width: _reasoningEnabled ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.psychology,
              color: _reasoningEnabled ? accentColor : Colors.white24,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Model Thinking',
                    style: TextStyle(
                      color: _reasoningEnabled ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Let the model reason before generating. Higher quality, but slower',
                    style: TextStyle(
                      color: _reasoningEnabled ? accentColor.withValues(alpha: 0.6) : Colors.white24,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _reasoningEnabled,
              onChanged: (v) => setState(() => _reasoningEnabled = v),
              activeColor: accentColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoreInputSection(Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('World Lore / Wiki URLs (optional)', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        const Text(
          'Paste one or more wiki/lore URLs separated by commas. You can also attach local files below.',
          style: TextStyle(color: Colors.white24, fontSize: 11),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _loreUrlsController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          maxLines: 4,
          minLines: 2,
          onChanged: (_) => _saveState(),
          decoration: InputDecoration(
            hintText: 'https://wowpedia.fandom.com/wiki/Demon_hunter, https://wowpedia.fandom.com/wiki/Illidan_Stormrage',
            hintStyle: const TextStyle(color: Colors.white12, fontSize: 12),
            filled: true,
            fillColor: const Color(0xFF1E293B),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: accentColor, width: 2)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        const SizedBox(height: 12),
        if (_loreFiles.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: _loreFiles.map((f) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description, size: 14, color: Colors.blueAccent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f.name, style: const TextStyle(color: Colors.white70, fontSize: 12), overflow: TextOverflow.ellipsis)),
                    InkWell(
                      onTap: () {
                        setState(() => _loreFiles.remove(f));
                        _saveState();
                      },
                      child: const Icon(Icons.close, size: 14, color: Colors.white38),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['txt', 'md', 'pdf', 'json', 'csv'],
              allowMultiple: true,
            );
            if (result != null) {
              setState(() {
                for (var newFile in result.files) {
                  if (!_loreFiles.any((f) => f.name == newFile.name)) {
                    _loreFiles.add(newFile);
                  }
                }
              });
              _saveState();
            }
          },
          icon: const Icon(Icons.upload_file, size: 16),
          label: const Text('Attach Lore File (.txt, .md, .pdf)'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white54,
            side: const BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }

  Widget _buildGuidedConfigStep() {
    // Pick a stable placeholder based on name hash
    final placeholderIdx = _nameController.text.hashCode.abs() % _guidedVisionPlaceholders.length;

    return Center(
      key: const ValueKey('guided-config'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Row(
                children: [
                  const Icon(Icons.edit_note, color: Colors.tealAccent, size: 28),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Guided Character Creator',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                        SizedBox(height: 2),
                        Text("Describe your character — we'll help you flesh them out.",
                          style: TextStyle(fontSize: 13, color: Colors.white38)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ══════════════════════════════════════════════
              // Section 1: The Vision (Required)
              // ══════════════════════════════════════════════
              const Text("What's your character like?",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 4),
              const Text("Don't worry about perfect writing — a few sentences, a scene, bullet points, whatever comes naturally.",
                style: TextStyle(fontSize: 12, color: Colors.white38, height: 1.4)),
              const SizedBox(height: 16),

              // Name + randomizer
              Row(
                children: [
                  _inputLabel('Character Name', required: true),
                  const Spacer(),
                  Tooltip(
                    message: 'Generate a random name',
                    child: IconButton(
                      icon: const Icon(Icons.casino, color: Colors.amberAccent, size: 20),
                      onPressed: _randomizeName,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _styledTextField(controller: _nameController, hint: 'e.g. Aria Blackwood, Captain Zara, Luna...', maxLines: 1),
              const SizedBox(height: 16),

              // Age & Sex
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _inputLabel('Age', required: false),
                        const SizedBox(height: 8),
                        _styledTextField(controller: _ageController, hint: 'e.g. 25, Ancient...', maxLines: 1),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _inputLabel('Gender', required: false),
                        const SizedBox(height: 8),
                        _styledTextField(controller: _sexController, hint: 'e.g. Female, Male...', maxLines: 1),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // ══════════════════════════════════════════════
              // Section 2: Appearance (Collapsible)
              // ══════════════════════════════════════════════
              _guidedSection(
                title: 'Appearance',
                subtitle: 'Already described their look above? Skip this.',
                icon: Icons.person_outline,
                children: [
                  _guidedField(
                    label: 'Build / Body Type',
                    controller: _guidedAppearanceController,
                    hint: "Or describe: 'tall and lanky with long legs'",
                    suggestions: const ['Petite', 'Slim', 'Athletic', 'Curvy', 'Muscular', 'Plus-size', 'Tall & Lanky'],
                    maxLines: 2,
                  ),
                  _guidedField(
                    label: 'Hair',
                    controller: _guidedHairController,
                    hint: "e.g. 'waist-length silver hair, usually messy'",
                    suggestions: const ['Short', 'Long', 'Flowing', 'Braided', 'Wild', 'Shaved', 'Pixie'],
                  ),
                  _guidedField(
                    label: 'Distinguishing Features',
                    controller: _guidedFeaturesController,
                    hint: "e.g. 'a jagged scar across her left eye, pointed elf ears'",
                    suggestions: const ['Glasses', 'Scars', 'Tattoos', 'Horns', 'Wings', 'Fangs', 'Cat Ears', 'Freckles'],
                  ),
                  _guidedField(
                    label: 'Race / Species',
                    controller: _guidedRaceController,
                    hint: "e.g. 'half-dragon shapeshifter'",
                    suggestions: const ['Human', 'Elf', 'Demon', 'Vampire', 'Beastkin', 'Android', 'Angel', 'Fae'],
                  ),
                ],
              ),

              // ══════════════════════════════════════════════
              // Section 3: Personality & Vibe (Collapsible)
              // ══════════════════════════════════════════════
              _guidedSection(
                title: 'Personality & Vibe',
                subtitle: "What's it like to spend time with them?",
                icon: Icons.psychology,
                children: [
                  _guidedField(
                    label: 'Personality',
                    controller: _guidedPersonalityController,
                    hint: "What are they like? e.g. 'Sharp wit, never shows vulnerability, but secretly writes poetry'",
                    suggestions: const ['Sarcastic', 'Gentle', 'Intense', 'Playful', 'Cold', 'Chaotic', 'Nurturing', 'Mysterious'],
                    maxLines: 3,
                  ),
                  _guidedField(
                    label: 'How They Talk',
                    controller: _guidedSpeechController,
                    hint: "e.g. 'Formal and old-fashioned' or 'Lots of slang, drops F-bombs'",
                    suggestions: const ['Formal', 'Casual', 'Poetic', 'Blunt', 'Soft-spoken', 'Loud', 'Sarcastic', 'Flirty'],
                  ),
                  _guidedField(
                    label: 'Secret / Hidden Depth',
                    controller: _guidedSecretController,
                    hint: "What's beneath the surface? e.g. 'Seems cold but is terrified of being alone'",
                  ),
                ],
              ),

              // ══════════════════════════════════════════════
              // Section 4: Backstory (Collapsible)
              // ══════════════════════════════════════════════
              _guidedSection(
                title: 'Backstory',
                subtitle: 'Even a sentence helps the AI build a richer history.',
                icon: Icons.auto_stories,
                children: [
                  _guidedField(
                    label: 'Origin / Background',
                    controller: _guidedOriginController,
                    hint: "e.g. 'Grew up on the streets after her parents disappeared'",
                    suggestions: const ['Orphan', 'Nobility', 'Self-made', 'Military', 'Criminal past', 'Mysterious origins', 'Small-town', 'Royalty'],
                    maxLines: 2,
                  ),
                  _guidedField(
                    label: 'Setting / Era',
                    controller: _guidedSettingController,
                    hint: "When and where? e.g. 'Cyberpunk megacity' or 'Medieval fantasy kingdom'",
                    suggestions: const ['Modern', 'Medieval', 'Futuristic', 'Victorian', 'Ancient', 'Post-apocalyptic', 'Urban fantasy'],
                  ),
                  _guidedField(
                    label: 'Tone',
                    controller: _guidedToneController,
                    hint: "Overall feel? e.g. 'Dark and gritty but with moments of warmth'",
                    suggestions: const ['Dark', 'Wholesome', 'Tragic', 'Comedic', 'Mysterious', 'Heroic', 'Bittersweet'],
                  ),
                ],
              ),

              // ══════════════════════════════════════════════
              // Section 5: Relationship (Collapsible)
              // ══════════════════════════════════════════════
              _guidedSection(
                title: 'Relationship to {{user}}',
                subtitle: 'How do they know {{user}}?',
                icon: Icons.favorite_border,
                children: [
                  _guidedField(
                    label: 'Dynamic',
                    controller: _guidedRelDynamicController,
                    hint: "e.g. 'Coworkers who secretly like each other' or 'She's my bodyguard'",
                    suggestions: const ['Strangers', 'Childhood friends', 'Rivals', 'Roommates', 'Love interest', 'Mentor/Student', 'Exes', 'Online friends'],
                    maxLines: 2,
                  ),
                  _guidedField(
                    label: 'Opening Scenario',
                    controller: _guidedRelScenarioController,
                    hint: "Where does the story start? e.g. 'First day at a new school'",
                  ),
                ],
              ),

              // ══════════════════════════════════════════════
              // Section 6: NSFW Details (Gated + Collapsible)
              // ══════════════════════════════════════════════
              // Lore Input
              _buildLoreInputSection(Colors.tealAccent),
              const SizedBox(height: 32),

              // NSFW toggle
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _nsfwEnabled ? Colors.pinkAccent.withValues(alpha: 0.08) : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _nsfwEnabled ? Colors.pinkAccent.withValues(alpha: 0.4) : Colors.white12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.local_fire_department, color: _nsfwEnabled ? Colors.pinkAccent : Colors.white24, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Enable NSFW Options', style: TextStyle(color: _nsfwEnabled ? Colors.pinkAccent.shade100 : Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                          Text('Unlock intimate character details', style: TextStyle(color: _nsfwEnabled ? Colors.pinkAccent.withValues(alpha: 0.5) : Colors.white24, fontSize: 10)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _nsfwEnabled,
                      activeTrackColor: Colors.pinkAccent,
                      onChanged: (val) {
                        setState(() => _nsfwEnabled = val);
                        _saveState();
                      },
                    ),
                  ],
                ),
              ),

              if (_nsfwEnabled)
                _guidedSection(
                  title: 'Intimate Details',
                  subtitle: 'Guided prompts for romantic and sexual traits.',
                  icon: Icons.local_fire_department,
                  accentColor: Colors.pinkAccent,
                  children: [
                    _guidedField(
                      label: 'Body (intimate details)',
                      controller: _guidedNsfwBodyController,
                      hint: "Describe specifics if you want: 'modest chest, wide hips, thick thighs'",
                      suggestions: const ['Flat', 'Small', 'Medium', 'Large', 'Huge'],
                      isNsfw: true,
                    ),
                    _guidedField(
                      label: 'Experience Level',
                      controller: _guidedNsfwExpController,
                      hint: "How experienced are they? e.g. 'First time, nervous but eager'",
                      suggestions: const ['Innocent', 'Virgin', 'Curious', 'Experienced', 'Insatiable'],
                      isNsfw: true,
                    ),
                    _guidedField(
                      label: 'Dominance',
                      controller: _guidedNsfwDomController,
                      hint: "Who takes the lead? e.g. 'Dominant in public, submissive behind closed doors'",
                      suggestions: const ['Submissive', 'Switch', 'Dominant'],
                      isNsfw: true,
                    ),
                    _guidedField(
                      label: 'Turn-ons & Kinks',
                      controller: _guidedNsfwKinksController,
                      hint: "What are they into? e.g. 'Loves being praised, goes weak when you grab her hair'",
                      suggestions: const ['Praise', 'Teasing', 'Biting', 'Bondage', 'Exhibitionism', 'Jealousy', 'Breeding'],
                      maxLines: 2,
                      isNsfw: true,
                    ),
                    _guidedField(
                      label: 'Clothing / Aesthetic',
                      controller: _guidedNsfwClothingController,
                      hint: "What do they wear? e.g. 'Always wears thigh-highs and an oversized shirt at home'",
                      suggestions: const ['Revealing', 'Lingerie', 'Uniform', 'Leather', 'Elegant', 'Barely There'],
                      isNsfw: true,
                    ),
                    _guidedField(
                      label: 'Sexual Personality',
                      controller: _guidedNsfwPersonalityController,
                      hint: "How do they act during intimacy? e.g. 'Giggly and playful, hides her face when embarrassed'",
                      maxLines: 2,
                      isNsfw: true,
                    ),
                  ],
                ),

              // ══════════════════════════════════════════════
              // Character Vision — moved here so sections above feed into it
              // ══════════════════════════════════════════════
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.tealAccent.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.edit_note, color: Colors.tealAccent, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Your Character Vision',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                              SizedBox(height: 2),
                              Text('Write your idea, or let AI generate a description from the details above.',
                                style: TextStyle(fontSize: 11, color: Colors.white38)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _guidedVisionController,
                      maxLines: null,
                      minLines: 6,
                      style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
                      onChanged: (_) { setState(() {}); _saveState(); },
                      decoration: InputDecoration(
                        hintText: _guidedVisionPlaceholders[placeholderIdx],
                        hintStyle: const TextStyle(color: Colors.white12, fontSize: 13),
                        hintMaxLines: 3,
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white12)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white12)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.tealAccent)),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Scenario seed chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _scenarioSeeds.map((seed) {
                        return InkWell(
                          onTap: () {
                            final current = _guidedVisionController.text.trim();
                            _guidedVisionController.text = current.isEmpty ? seed : '$current. $seed';
                            _guidedVisionController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _guidedVisionController.text.length));
                            setState(() {});
                            _saveState();
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Text(seed, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    // Generate Character Description button
                    Row(
                      children: [
                        const Spacer(),
                        if (_isExpandingNarrative)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent)),
                                SizedBox(width: 8),
                                Text('Generating description...', style: TextStyle(color: Colors.tealAccent, fontSize: 12)),
                              ],
                            ),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: _nameController.text.trim().isEmpty ? null : _expandNarrative,
                            icon: const Icon(Icons.auto_fix_high, size: 16),
                            label: const Text('Generate Character Description', style: TextStyle(fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0D7377),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.white10,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ══════════════════════════════════════════════
              // Section 7: Output Settings (Always Visible)
              // ══════════════════════════════════════════════
              _guidedSection(
                title: 'Output Settings',
                subtitle: 'Greeting style, art style, lorebook, and detail level.',
                icon: Icons.tune,
                children: [
                  // Persona selector
                  _inputLabel('{{user}} Persona for Greetings', required: false),
                  const SizedBox(height: 4),
                  const Text('Select a persona to tailor greetings, or "None" for public cards.',
                    style: TextStyle(color: Colors.white24, fontSize: 11)),
                  const SizedBox(height: 8),
                  Builder(builder: (context) {
                    final personaService = Provider.of<UserPersonaService>(context);
                    final personas = personaService.personas;
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedPersonaId,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          items: [
                            const DropdownMenuItem(value: '', child: Row(children: [
                              Icon(Icons.person_off, size: 16, color: Colors.white38),
                              SizedBox(width: 8),
                              Text('None (Blank Slate)', style: TextStyle(color: Colors.white54)),
                            ])),
                            ...personas.map((p) => DropdownMenuItem(value: p.id, child: Row(children: [
                              const Icon(Icons.person, size: 16, color: Colors.blueAccent),
                              const SizedBox(width: 8),
                              Flexible(child: Text(p.displayLabel, overflow: TextOverflow.ellipsis)),
                            ]))),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedPersonaId = value ?? '');
                            _saveState();
                          },
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),

                  // Greeting tones
                  _inputLabel('Greeting Tones', required: false),
                  const SizedBox(height: 4),
                  Text(
                    _altGreetingCount == 0
                        ? 'Tone for the first message.'
                        : 'Select up to ${_altGreetingCount + 1} — one per greeting.',
                    style: const TextStyle(color: Colors.white24, fontSize: 11)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _greetingTones.where((tone) => tone != 'Spicy/NSFW' || _nsfwEnabled).map((tone) {
                      final isSelected = _selectedTones.contains(tone);
                      final maxTones = _altGreetingCount + 1;
                      final atLimit = _selectedTones.length >= maxTones && !isSelected;
                      return FilterChip(
                        label: Text(tone),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              if (atLimit) _selectedTones.remove(_selectedTones.last);
                              _selectedTones.add(tone);
                            } else if (_selectedTones.length > 1) {
                              _selectedTones.remove(tone);
                            }
                          });
                          _saveState();
                        },
                        selectedColor: Colors.blueAccent,
                        backgroundColor: const Color(0xFF1E293B),
                        checkmarkColor: Colors.white,
                        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 13),
                        side: BorderSide(color: isSelected ? Colors.blueAccent : Colors.white12),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Greeting length + alt count
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _inputLabel('First Message Length', required: false),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _greetingLength,
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF1E293B),
                                  style: const TextStyle(color: Colors.white, fontSize: 13),
                                  items: _greetingLengths.map((len) => DropdownMenuItem(value: len, child: Text(len))).toList(),
                                  onChanged: (value) { if (value != null) { setState(() => _greetingLength = value); _saveState(); } },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _inputLabel('Alternate Greetings', required: false),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Slider(
                                    value: _altGreetingCount.toDouble(), min: 0, max: 5, divisions: 5,
                                    activeColor: Colors.blueAccent, inactiveColor: Colors.white12,
                                    label: '$_altGreetingCount',
                                    onChanged: (val) {
                                      setState(() {
                                        _altGreetingCount = val.round();
                                        final maxTones = _altGreetingCount + 1;
                                        while (_selectedTones.length > maxTones) _selectedTones.remove(_selectedTones.last);
                                      });
                                      _saveState();
                                    },
                                  ),
                                ),
                                SizedBox(width: 24, child: Text('$_altGreetingCount', style: const TextStyle(color: Colors.white70, fontSize: 13))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Art style
                  _inputLabel('Avatar Art Style', required: false),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _artStyles.map((style) {
                      final isSelected = _artStyle == style;
                      return ChoiceChip(
                        label: Text(style),
                        selected: isSelected,
                        onSelected: (_) => setState(() => _artStyle = style),
                        selectedColor: Colors.blueAccent,
                        backgroundColor: const Color(0xFF1E293B),
                        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 13),
                        side: BorderSide(color: isSelected ? Colors.blueAccent : Colors.white12),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Description detail
                  _inputLabel('Description Detail', required: false),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _generationDetailOptions.keys.map((label) {
                      final isSelected = _generationDetail == label;
                      return ChoiceChip(
                        label: Text(label),
                        selected: isSelected,
                        onSelected: (_) { setState(() => _generationDetail = label); _saveState(); },
                        selectedColor: Colors.blueAccent,
                        backgroundColor: const Color(0xFF1E293B),
                        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 13),
                        side: BorderSide(color: isSelected ? Colors.blueAccent : Colors.white12),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Lorebook
                  Row(
                    children: [
                      const Icon(Icons.menu_book, color: Colors.blueAccent, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Auto-generate World Lore',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))),
                      Switch(value: _generateLorebook, activeTrackColor: Colors.blueAccent,
                        onChanged: (val) { setState(() => _generateLorebook = val); _saveState(); }),
                    ],
                  ),
                  if (_generateLorebook) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Depth:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(width: 4),
                        const Tooltip(
                          message: 'Controls how many consecutive generation steps the Lore Engine processes. Deep = more expansive lore structure but longer wait time.',
                          child: Icon(Icons.info_outline, size: 14, color: Colors.white38),
                        ),
                        const SizedBox(width: 8),
                        ..._loreDepths.map((depth) {
                          final isSelected = _loreDepth == depth;
                          final count = depth == 'Light' ? '3-4' : depth == 'Deep' ? '10-15' : '5-8';
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('$depth ($count)', style: const TextStyle(fontSize: 11)),
                              selected: isSelected,
                              onSelected: (_) { setState(() => _loreDepth = depth); _saveState(); },
                              selectedColor: Colors.blueAccent,
                              backgroundColor: const Color(0xFF1E293B),
                              labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white54),
                              side: BorderSide(color: isSelected ? Colors.blueAccent : Colors.white12),
                              visualDensity: VisualDensity.compact,
                            ),
                          );
                        }),
                      ],
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 24),

              // ── Validation hint ──
              if (_guidedVisionController.text.trim().isNotEmpty &&
                  _guidedVisionController.text.trim().length < 20)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: Colors.amberAccent, size: 16),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('Tip: The more detail you provide, the better the AI can capture your vision.',
                          style: TextStyle(color: Colors.amberAccent, fontSize: 12)),
                      ),
                    ],
                  ),
                ),

              // ── Back + Generate buttons ──
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _currentStep = 1),
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Back', style: TextStyle(fontSize: 14)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white54,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 240,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _nameController.text.trim().isEmpty ||
                            _guidedVisionController.text.trim().length < 10
                            ? null
                            : _startGuidedGeneration,
                        icon: const Icon(Icons.auto_awesome, size: 20),
                        label: const Text('Generate Character', style: TextStyle(fontSize: 16)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D7377),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white10,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 2 (Automated): Character Configuration
  // ═══════════════════════════════════════════════════════════════

  /// Helper: single-select chip row
  Widget _singleSelectChipRow(String label, String current, List<String> options, void Function(String) onChanged, {bool isNsfw = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isNsfw) ...[
                const Icon(Icons.local_fire_department, size: 12, color: Colors.pinkAccent),
                const SizedBox(width: 4),
              ],
              Text(label, style: TextStyle(color: isNsfw ? Colors.pinkAccent.shade100 : Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: options.map((opt) {
              final isSelected = current == opt;
              final accentColor = isNsfw ? Colors.pinkAccent : Colors.blueAccent;
              return ChoiceChip(
                label: Text(opt, style: const TextStyle(fontSize: 11)),
                selected: isSelected,
                onSelected: (_) {
                  onChanged(isSelected ? '' : opt);
                  _saveState();
                },
                selectedColor: accentColor.withValues(alpha: 0.3),
                backgroundColor: const Color(0xFF1E293B),
                labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white54),
                side: BorderSide(color: isSelected ? accentColor : Colors.white10),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// Helper: multi-select chip row
  Widget _multiSelectChipRow(String label, Set<String> selected, List<String> options, void Function(Set<String>) onChanged, {bool isNsfw = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isNsfw) ...[
                const Icon(Icons.local_fire_department, size: 12, color: Colors.pinkAccent),
                const SizedBox(width: 4),
              ],
              Text(label, style: TextStyle(color: isNsfw ? Colors.pinkAccent.shade100 : Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: options.map((opt) {
              final isSelected = selected.contains(opt);
              final accentColor = isNsfw ? Colors.pinkAccent : Colors.blueAccent;
              return FilterChip(
                label: Text(opt, style: const TextStyle(fontSize: 11)),
                selected: isSelected,
                onSelected: (val) {
                  final newSet = Set<String>.from(selected);
                  if (val) { newSet.add(opt); } else { newSet.remove(opt); }
                  onChanged(newSet);
                  _saveState();
                },
                selectedColor: accentColor.withValues(alpha: 0.3),
                backgroundColor: const Color(0xFF1E293B),
                checkmarkColor: accentColor,
                labelStyle: TextStyle(color: isSelected ? accentColor : Colors.white38),
                side: BorderSide(color: isSelected ? accentColor : Colors.white10),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
  Widget _buildConfigStep() {
    return Center(
      key: const ValueKey('config'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Text(
                'Bring Your Character to Life',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Give us a name and a concept — the AI will do the rest. '
                'It will generate a complete character card with personality, backstory, '
                'dialogue examples, and a custom avatar.',
                style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
              ),
              const SizedBox(height: 24),

              // ── NSFW Toggle ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _nsfwEnabled ? Colors.pinkAccent.withValues(alpha: 0.08) : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _nsfwEnabled ? Colors.pinkAccent.withValues(alpha: 0.4) : Colors.white12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.local_fire_department, color: _nsfwEnabled ? Colors.pinkAccent : Colors.white24, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Enable NSFW Options', style: TextStyle(color: _nsfwEnabled ? Colors.pinkAccent.shade100 : Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                          Text('Unlock spicy appearance & relationship options', style: TextStyle(color: _nsfwEnabled ? Colors.pinkAccent.withValues(alpha: 0.5) : Colors.white24, fontSize: 10)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _nsfwEnabled,
                      activeTrackColor: Colors.pinkAccent,
                      onChanged: (val) {
                        setState(() => _nsfwEnabled = val);
                        _saveState();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Archetype Quick Start ──
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF162032),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bolt, color: Colors.amberAccent, size: 18),
                        const SizedBox(width: 6),
                        const Text('Quick Start — Archetype Presets', style: TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text('Tap to auto-fill concept & personality', style: TextStyle(color: Colors.white24, fontSize: 11)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _archetypePresets.entries.map((entry) {
                        final isSelected = _selectedArchetype == entry.key;
                        return ChoiceChip(
                          label: Text(entry.key, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.white70)),
                          avatar: Icon(isSelected ? Icons.check : Icons.auto_awesome, size: 14, color: isSelected ? Colors.white : Colors.amberAccent),
                          selected: isSelected,
                          selectedColor: Colors.amberAccent.withValues(alpha: 0.3),
                          backgroundColor: const Color(0xFF1E293B),
                          side: BorderSide(color: isSelected ? Colors.amberAccent : Colors.white12),
                          checkmarkColor: Colors.amberAccent,
                          showCheckmark: false,
                          onSelected: (_) {
                            setState(() {
                              if (isSelected) {
                                _selectedArchetype = '';
                              } else {
                                _selectedArchetype = entry.key;
                                _conceptController.text = entry.value['concept'] ?? '';
                                _keywordsController.text = entry.value['keywords'] ?? '';
                                if (_nameController.text.isEmpty) {
                                  _nameController.text = entry.key;
                                }
                              }
                            });
                            _saveState();
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Name with Randomize ──
              Row(
                children: [
                  _inputLabel('Character Name', required: true),
                  const Spacer(),
                  Tooltip(
                    message: 'Generate a random character name',
                    child: IconButton(
                      icon: const Icon(Icons.casino, color: Colors.amberAccent, size: 20),
                      onPressed: _randomizeName,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _styledTextField(
                controller: _nameController,
                hint: 'e.g. Aria Blackwood, Captain Zara, Luna...',
                maxLines: 1,
              ),
              const SizedBox(height: 16),

              // ── Age & Sex row (compact) ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _inputLabel('Age', required: false),
                        const SizedBox(height: 8),
                        _styledTextField(
                          controller: _ageController,
                          hint: 'e.g. 25, Ancient...',
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _inputLabel('Gender', required: false),
                        const SizedBox(height: 8),
                        _styledTextField(
                          controller: _sexController,
                          hint: 'e.g. Female, Male...',
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Appearance Builder ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF162032),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_outline, color: Colors.blueAccent, size: 18),
                        const SizedBox(width: 8),
                        const Text('Character Appearance', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        const Text('All optional', style: TextStyle(color: Colors.white24, fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _singleSelectChipRow('Race / Species', _race, _raceOptions, (v) => setState(() => _race = v)),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Text('Custom: ', style: TextStyle(color: Colors.white38, fontSize: 12)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _customRaceController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'e.g. Kitsune, Arachnid, Void-born...',
                                hintStyle: const TextStyle(color: Colors.white12, fontSize: 12),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                filled: true,
                                fillColor: const Color(0xFF1E293B),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.white12)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.white12)),
                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.blueAccent)),
                              ),
                              onChanged: (_) {
                                // Clear chip selection if typing custom
                                if (_customRaceController.text.trim().isNotEmpty && _race.isNotEmpty) {
                                  setState(() => _race = '');
                                }
                                _saveState();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    _singleSelectChipRow('Body Type', _bodyType, _bodyTypes, (v) => setState(() => _bodyType = v)),
                    _singleSelectChipRow('Hair Length', _hairLength, _hairLengths, (v) => setState(() => _hairLength = v)),
                    _singleSelectChipRow('Hair Style', _hairStyle, _hairStyles, (v) => setState(() => _hairStyle = v)),
                    _singleSelectChipRow('Skin Tone', _skinTone, _skinTones, (v) => setState(() => _skinTone = v)),
                    _multiSelectChipRow('Notable Features', _notableFeatures, _notableFeatureOptions, (v) => setState(() => _notableFeatures = v)),
                    const Divider(color: Colors.white10, height: 16),
                    _singleSelectChipRow('Abs / Core', _absCore, _absCoreOptions, (v) => setState(() => _absCore = v)),
                    _singleSelectChipRow('Thighs', _thighs, _thighOptions, (v) => setState(() => _thighs = v)),
                    _singleSelectChipRow('Hips', _hips, _hipOptions, (v) => setState(() => _hips = v)),
                    _singleSelectChipRow('Shoulders', _shoulders, _shoulderOptions, (v) => setState(() => _shoulders = v)),
                    _singleSelectChipRow('Waist', _waist, _waistOptions, (v) => setState(() => _waist = v)),
                    // NSFW body details
                    if (_nsfwEnabled) ...[
                      const Divider(color: Colors.pinkAccent, height: 24),
                      _singleSelectChipRow('Chest Size', _chestSize, _chestSizes, (v) => setState(() => _chestSize = v), isNsfw: true),
                      _singleSelectChipRow('Butt Size', _buttSize, _buttSizes, (v) => setState(() => _buttSize = v), isNsfw: true),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Relationship Presets (multi-select, NSFW gated) ──
              _inputLabel('Relationship to {{user}}', required: false),
              const SizedBox(height: 4),
              const Text('Select one or more dynamics', style: TextStyle(color: Colors.white24, fontSize: 11)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _relationshipPresets.where((rel) {
                  // Hide NSFW chips if toggle is off
                  if (!_nsfwEnabled && _nsfwRelationships.contains(rel)) return false;
                  return true;
                }).map((rel) {
                  final isSelected = _selectedRelationships.contains(rel);
                  final isNsfw = _nsfwRelationships.contains(rel);
                  return FilterChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isNsfw) ...[
                          Icon(Icons.local_fire_department, size: 12, color: isSelected ? Colors.white : Colors.pinkAccent.shade100),
                          const SizedBox(width: 4),
                        ],
                        Text(rel),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedRelationships.add(rel);
                        } else {
                          _selectedRelationships.remove(rel);
                        }
                      });
                      _saveState();
                    },
                    selectedColor: isNsfw ? Colors.pinkAccent.withValues(alpha: 0.3) : Colors.blueAccent,
                    backgroundColor: const Color(0xFF1E293B),
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 12,
                    ),
                    side: BorderSide(
                      color: isSelected
                          ? (isNsfw ? Colors.pinkAccent : Colors.blueAccent)
                          : Colors.white12,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              _styledTextField(
                controller: _relationshipController,
                hint: 'Or type a custom relationship...',
                maxLines: 1,
              ),
              const SizedBox(height: 24),

              // ── NSFW Traits Section ──
              if (_nsfwEnabled) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.pinkAccent.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_fire_department, color: Colors.pinkAccent, size: 18),
                          const SizedBox(width: 8),
                          const Text('Sexual Traits', style: TextStyle(color: Colors.pinkAccent, fontSize: 14, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          const Text('All optional', style: TextStyle(color: Colors.white24, fontSize: 10)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _singleSelectChipRow('Experience', _experience, _experienceOptions, (v) => setState(() => _experience = v), isNsfw: true),
                      _singleSelectChipRow('Dominance', _dominance, _dominanceOptions, (v) => setState(() => _dominance = v), isNsfw: true),
                      _multiSelectChipRow('Kinks', _selectedKinks, _kinkOptions, (v) => setState(() => _selectedKinks = v), isNsfw: true),
                      // Custom kinks
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.local_fire_department, size: 12, color: Colors.pinkAccent),
                                const SizedBox(width: 4),
                                Text('Custom Kinks', style: TextStyle(color: Colors.pinkAccent.shade100, fontSize: 12, fontWeight: FontWeight.w500)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            _styledTextField(
                              controller: _customKinksController,
                              hint: 'e.g. foot worship, roleplay, praise kink...',
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      _singleSelectChipRow('Outfit Vibe', _outfitVibe, _outfitVibes, (v) => setState(() => _outfitVibe = v), isNsfw: true),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              const SizedBox(height: 24),

              // Personality keywords
              _inputLabel('Personality Keywords', required: false),
              const SizedBox(height: 8),
              _styledTextField(
                controller: _keywordsController,
                hint: 'e.g. witty, secretive, bookish, brave, loyal...',
                maxLines: 1,
              ),
              const SizedBox(height: 24),

              // ── Backstory ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF162032),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_stories, color: Colors.blueAccent, size: 18),
                        const SizedBox(width: 8),
                        const Text('Backstory', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        const Text('All optional', style: TextStyle(color: Colors.white24, fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _singleSelectChipRow('Origin', _backstoryOrigin, _backstoryOrigins, (v) => setState(() => _backstoryOrigin = v)),
                    _singleSelectChipRow('Tone', _backstoryTone, _backstoryTones, (v) => setState(() => _backstoryTone = v)),
                    _singleSelectChipRow('Era', _backstoryEra, _backstoryEras, (v) => setState(() => _backstoryEra = v)),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Custom Backstory Notes', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 6),
                          _styledTextField(
                            controller: _backstoryNotesController,
                            hint: 'e.g. Was betrayed by their order, seeks revenge...',
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Description detail level
              _inputLabel('Description Detail', required: false),
              const SizedBox(height: 4),
              const Text('Controls how detailed the character description will be', style: TextStyle(color: Colors.white24, fontSize: 11)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _generationDetailOptions.keys.map((label) {
                  final isSelected = _generationDetail == label;
                  return ChoiceChip(
                    label: Text(label),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => _generationDetail = label);
                      _saveState();
                    },
                    selectedColor: Colors.blueAccent,
                    backgroundColor: const Color(0xFF1E293B),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 13,
                    ),
                    side: BorderSide(
                      color: isSelected ? Colors.blueAccent : Colors.white12,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // ── Description (generated via magic wand) ──
              Row(
                children: [
                  _inputLabel('Description', required: true),
                  const Spacer(),
                  if (_isRandomizing)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                              value: _conceptGenProgress > 0 ? _conceptGenProgress : null,
                              strokeWidth: 2,
                              color: Colors.amberAccent,
                            ),
                          ),
                          if (_conceptGenProgress > 0) ...[
                            const SizedBox(width: 6),
                            Text('${(_conceptGenProgress * 100).toInt()}%', style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
                          ],
                        ],
                      ),
                    )
                  else
                    Tooltip(
                      message: 'Generate a description using all your selections',
                      child: IconButton(
                        icon: const Icon(Icons.auto_fix_high, color: Colors.amberAccent, size: 20),
                        onPressed: _randomizeConcept,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // Description field — locked until magic wand is run
              Stack(
                children: [
                  _styledTextField(
                    controller: _conceptController,
                    hint: _conceptGenerated
                        ? 'Edit the generated description...'
                        : 'Tap ✨ above to generate a description from your selections',
                    maxLines: null,
                    minLines: 4,
                    readOnly: !_conceptGenerated,
                    enabled: _conceptGenerated,
                  ),
                  if (!_conceptGenerated && !_isRandomizing)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _randomizeConcept,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.2)),
                          ),
                          child: const Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.auto_fix_high, color: Colors.amberAccent, size: 18),
                                SizedBox(width: 8),
                                Text('Tap to generate description', style: TextStyle(color: Colors.amberAccent, fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Lorebook Section (enhanced) ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF162032),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.menu_book, color: Colors.blueAccent, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Auto-generate World Lore',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                        Switch(
                          value: _generateLorebook,
                          activeTrackColor: Colors.blueAccent,
                          onChanged: (val) {
                            setState(() => _generateLorebook = val);
                            _saveState();
                          },
                        ),
                      ],
                    ),
                    if (_generateLorebook) ...[
                      const SizedBox(height: 12),
                      // Depth selector
                      Row(
                        children: [
                          const Text('Depth:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                          const SizedBox(width: 4),
                          const Tooltip(
                            message: 'Controls how many consecutive generation steps the Lore Engine processes. Deep = more expansive lore structure but longer wait time.',
                            child: Icon(Icons.info_outline, size: 14, color: Colors.white38),
                          ),
                          const SizedBox(width: 8),
                          ..._loreDepths.map((depth) {
                            final isSelected = _loreDepth == depth;
                            final count = depth == 'Light' ? '3-4' : depth == 'Deep' ? '10-15' : '5-8';
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text('$depth ($count)', style: const TextStyle(fontSize: 11)),
                                selected: isSelected,
                                onSelected: (_) {
                                  setState(() => _loreDepth = depth);
                                  _saveState();
                                },
                                selectedColor: Colors.blueAccent,
                                backgroundColor: const Color(0xFF1E293B),
                                labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.white54),
                                side: BorderSide(color: isSelected ? Colors.blueAccent : Colors.white12),
                                visualDensity: VisualDensity.compact,
                              ),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('Focus areas (optional):', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _loreCategoryOptions.map((cat) {
                          final isSelected = _selectedLoreCategories.contains(cat);
                          return FilterChip(
                            label: Text(cat, style: const TextStyle(fontSize: 11)),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedLoreCategories.add(cat);
                                } else {
                                  _selectedLoreCategories.remove(cat);
                                }
                              });
                              _saveState();
                            },
                            selectedColor: Colors.blueAccent.withValues(alpha: 0.3),
                            backgroundColor: const Color(0xFF1E293B),
                            checkmarkColor: Colors.blueAccent,
                            labelStyle: TextStyle(color: isSelected ? Colors.blueAccent : Colors.white38),
                            side: BorderSide(color: isSelected ? Colors.blueAccent : Colors.white12),
                            visualDensity: VisualDensity.compact,
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Persona selector (directly above tones)
              _inputLabel('{{user}} Persona for Greetings', required: false),
              const SizedBox(height: 4),
              const Text(
                'Select a persona to tailor greetings, or "None" for public cards.',
                style: TextStyle(color: Colors.white24, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final personaService = Provider.of<UserPersonaService>(context);
                final personas = personaService.personas;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedPersonaId,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Row(
                            children: [
                              Icon(Icons.person_off, size: 16, color: Colors.white38),
                              SizedBox(width: 8),
                              Text('None (Blank Slate)', style: TextStyle(color: Colors.white54)),
                            ],
                          ),
                        ),
                        ...personas.map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Row(
                            children: [
                              const Icon(Icons.person, size: 16, color: Colors.blueAccent),
                              const SizedBox(width: 8),
                              Flexible(child: Text(p.displayLabel, overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        )),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedPersonaId = value ?? '');
                        _saveState();
                      },
                    ),
                  ),
                );
              }),
              const SizedBox(height: 24),

              // Greeting tone (multi-select, capped to total greeting count)
              _inputLabel('Greeting Tones', required: false),
              const SizedBox(height: 4),
              Text(
                _altGreetingCount == 0
                    ? 'Tone for the first message.'
                    : 'Select up to ${_altGreetingCount + 1} — one per greeting (first message + $_altGreetingCount alternate${_altGreetingCount == 1 ? '' : 's'}).',
                style: const TextStyle(color: Colors.white24, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _greetingTones.where((tone) => tone != 'Spicy/NSFW' || _nsfwEnabled).map((tone) {
                  final isSelected = _selectedTones.contains(tone);
                  final maxTones = _altGreetingCount + 1;
                  final atLimit = _selectedTones.length >= maxTones && !isSelected;
                  return FilterChip(
                    label: Text(tone),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          if (atLimit) {
                            // At limit — swap: remove the last tone and add this one
                            _selectedTones.remove(_selectedTones.last);
                          }
                          _selectedTones.add(tone);
                        } else if (_selectedTones.length > 1) {
                          _selectedTones.remove(tone);
                        }
                      });
                      _saveState();
                    },
                    selectedColor: Colors.blueAccent,
                    backgroundColor: const Color(0xFF1E293B),
                    checkmarkColor: Colors.white,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 13,
                    ),
                    side: BorderSide(
                      color: isSelected ? Colors.blueAccent : Colors.white12,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // First message length + Alt greeting count — side by side
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // First message length
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _inputLabel('First Message Length', required: false),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _greetingLength,
                              isExpanded: true,
                              dropdownColor: const Color(0xFF1E293B),
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              items: _greetingLengths.map((len) => DropdownMenuItem(
                                value: len,
                                child: Text(len),
                              )).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _greetingLength = value);
                                  _saveState();
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Number of alternate greetings
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _inputLabel('Alternate Greetings', required: false),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _altGreetingCount.toDouble(),
                                min: 0,
                                max: 5,
                                divisions: 5,
                                activeColor: Colors.blueAccent,
                                inactiveColor: Colors.white12,
                                label: '$_altGreetingCount',
                                onChanged: (val) {
                                  setState(() {
                                    _altGreetingCount = val.round();
                                    // Trim excess tones if count decreased
                                    final maxTones = _altGreetingCount + 1;
                                    while (_selectedTones.length > maxTones) {
                                      _selectedTones.remove(_selectedTones.last);
                                    }
                                  });
                                  _saveState();
                                },
                              ),
                            ),
                            SizedBox(
                              width: 24,
                              child: Text('$_altGreetingCount', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Art style (last option)
              _inputLabel('Avatar Art Style', required: false),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _artStyles.map((style) {
                  final isSelected = _artStyle == style;
                  return ChoiceChip(
                    label: Text(style),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _artStyle = style),
                    selectedColor: Colors.blueAccent,
                    backgroundColor: const Color(0xFF1E293B),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 13,
                    ),
                    side: BorderSide(
                      color: isSelected ? Colors.blueAccent : Colors.white12,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),

              // Lore Input
              _buildLoreInputSection(Colors.blueAccent),
              const SizedBox(height: 32),
              const SizedBox(height: 32),

              // Back + Generate buttons
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _currentStep = 1),
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Back', style: TextStyle(fontSize: 14)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white54,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 240,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _nameController.text.trim().isEmpty || _conceptController.text.trim().isEmpty || !_conceptGenerated
                            ? null
                            : _startGeneration,
                        icon: const Icon(Icons.auto_awesome, size: 20),
                        label: const Text('Generate Character', style: TextStyle(fontSize: 16)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white10,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputLabel(String text, {bool required = false}) {
    return Row(
      children: [
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        if (required) const Text(' *', style: TextStyle(color: Colors.redAccent)),
      ],
    );
  }




  /// Show a searchable model picker dialog. Returns the selected model ID or null.
  Future<String?> _showModelSearchDialog({
    required String title,
    required String? currentValue,
    bool showSameAsGenerator = false,
  }) async {
    String searchQuery = '';
    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = _availableModels.where((m) {
              if (searchQuery.isEmpty) return true;
              final q = searchQuery.toLowerCase();
              return m.name.toLowerCase().contains(q) || m.id.toLowerCase().contains(q);
            }).toList();

            return Dialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500, maxHeight: 500),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                      child: Row(
                        children: [
                          Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    // Search bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        autofocus: true,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search models...',
                          hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                          prefixIcon: const Icon(Icons.search, color: Colors.white24, size: 20),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (v) => setDialogState(() => searchQuery = v),
                      ),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    // Model list
                    Flexible(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: [
                          if (showSameAsGenerator)
                            _modelListTile(
                              name: 'Same as generator',
                              id: '',
                              isSelected: currentValue == null || currentValue.isEmpty,
                              isThinking: false,
                              onTap: () => Navigator.pop(context, ''),
                            ),
                          ...filtered.map((m) {
                            final isThinking = m.name.toLowerCase().contains('think') ||
                                m.id.toLowerCase().contains('thinking') ||
                                m.id.toLowerCase().contains('reasoner');
                            return _modelListTile(
                              name: m.name.isNotEmpty ? m.name : m.id,
                              id: m.id,
                              isSelected: m.id == currentValue,
                              isThinking: isThinking,
                              onTap: () => Navigator.pop(context, m.id),
                            );
                          }),
                          if (filtered.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: Text('No models found', style: TextStyle(color: Colors.white38))),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _modelListTile({
    required String name,
    required String id,
    required bool isSelected,
    required bool isThinking,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: Colors.blueAccent.withValues(alpha: 0.15),
      leading: isThinking
          ? const Icon(Icons.psychology, size: 18, color: Colors.deepPurpleAccent)
          : (id.isEmpty ? const Icon(Icons.link, size: 18, color: Colors.white24) : null),
      title: Text(
        name,
        style: TextStyle(
          color: isSelected ? Colors.blueAccent : (isThinking ? Colors.deepPurple.shade200 : Colors.white),
          fontSize: 13,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isSelected ? const Icon(Icons.check, size: 16, color: Colors.blueAccent) : null,
      onTap: onTap,
    );
  }

  Widget _styledTextField({
    required TextEditingController controller,
    required String hint,
    int? maxLines = 1,
    int? minLines,
    bool readOnly = false,
    bool enabled = true,
  }) {
    return AppTextField(
      controller: controller,
      readOnly: readOnly,
      enabled: enabled,
      maxLines: maxLines,
      minLines: minLines,
      style: TextStyle(color: enabled ? Colors.white : Colors.white38, fontSize: 14),
      onChanged: (_) {
        setState(() {}); // Rebuild to update button state
        _saveState(); // Auto-save on change
      },
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blueAccent),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 2: Generation Progress
  // ═══════════════════════════════════════════════════════════════

  Widget _buildGeneratingStep() {
    return Center(
      key: const ValueKey('generating'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            children: [
              const SizedBox(height: 32),
              // Animated icon
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(seconds: 2),
                builder: (_, value, child) => Transform.rotate(
                  angle: value * 6.28,
                  child: child,
                ),
                onEnd: () {}, // Continuous animation via key
                child: const Icon(Icons.auto_awesome, size: 64, color: Colors.amberAccent),
              ),
              const SizedBox(height: 24),
              Text(
                _generationStatus.isEmpty ? 'Generating character...' : _generationStatus,
                style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation(Colors.blueAccent),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 24),
              // Abort button
              if (_isGenerating)
                SizedBox(
                  width: 200,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _abortGeneration,
                    icon: const Icon(Icons.stop_circle_outlined, size: 20),
                    label: const Text('Abort Generation', style: TextStyle(fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              // Live preview of generation
              if (_generationPreview.isNotEmpty)
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 400),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _generationPreview,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 4: Realism Engine
  // ═══════════════════════════════════════════════════════════════

  Widget _buildRealismStep() {
    // If we got here due to a generation error, show the error state
    if (_generatedCard == null) {
      return Center(
        key: const ValueKey('realism-error'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text(
              'Generation failed. The LLM did not produce valid output.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => setState(() {
                _currentStep = 2;
                _generationPreview = '';
              }),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            ),
          ],
        ),
      );
    }

    return Center(
      key: const ValueKey('realism'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Realism Engine',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              const Text(
                'Set the initial state for the Realism Engine when a new conversation starts. '
                'These values will seed the relationship, emotion, and time-of-day systems.',
                style: TextStyle(fontSize: 14, color: Colors.white54, height: 1.5),
              ),
              const SizedBox(height: 32),

              RealismFormSection(
                enabled: _realismStepEnabled,
                onEnabledChanged: (v) => setState(() => _realismStepEnabled = v),
                timeOfDay: _realismTimeOfDay,
                onTimeOfDayChanged: (v) => setState(() => _realismTimeOfDay = v),
                dayCount: _realismDayCount,
                onDayCountChanged: (v) => setState(() => _realismDayCount = v),
                shortTermBond: _realismShortTermBond,
                onShortTermBondChanged: (v) => setState(() => _realismShortTermBond = v),
                longTermBond: _realismLongTermBond,
                onLongTermBondChanged: (v) => setState(() => _realismLongTermBond = v),
                trustLevel: _realismTrustLevel,
                onTrustLevelChanged: (v) => setState(() => _realismTrustLevel = v),
                emotion: _realismEmotion,
                onEmotionChanged: (v) => setState(() => _realismEmotion = v),
                emotionIntensity: _realismEmotionIntensity,
                onEmotionIntensityChanged: (v) => setState(() => _realismEmotionIntensity = v),
                nsfwCooldownEnabled: _realismNsfwCooldown,
                onNsfwCooldownChanged: (v) => setState(() => _realismNsfwCooldown = v),
                chaosModeEnabled: _realismChaosMode,
                onChaosModeChanged: (v) => setState(() => _realismChaosMode = v),
                currentTask: _realismCurrentTask,
                onCurrentTaskChanged: (v) => setState(() => _realismCurrentTask = v),
              ),

              // Navigation
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() => _currentStep = 3),
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('Back', style: TextStyle(fontSize: 14)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white54,
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 280,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () => setState(() => _currentStep = 5),
                          icon: const Icon(Icons.arrow_forward, size: 20),
                          label: const Text('Next: Review & Save', style: TextStyle(fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 5: Review & Edit
  // ═══════════════════════════════════════════════════════════════


  Widget _buildReviewStep() {
    if (_generatedCard == null) {
      return Center(
        key: const ValueKey('review-error'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text(
              'Generation failed. The LLM did not produce valid output.',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => setState(() {
                _currentStep = 2;
                _generationPreview = '';
              }),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      key: const ValueKey('review'),
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column — Avatar + quick info
          SizedBox(
            width: 280,
            child: Column(
              children: [
                // Avatar
                Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: const Color(0xFF1E293B),
                    border: Border.all(color: Colors.white12),
                    image: _generatedAvatar != null
                        ? DecorationImage(
                            image: MemoryImage(_generatedAvatar!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _generatedAvatar == null
                      ? Center(
                          child: _isGeneratingAvatar
                              ? const Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(color: Colors.blueAccent),
                                    SizedBox(height: 12),
                                    Text('Generating avatar...', style: TextStyle(color: Colors.white38, fontSize: 12)),
                                  ],
                                )
                              : Provider.of<LLMProvider>(context, listen: false).activeBackend == BackendType.kobold
                                  ? Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.content_copy, size: 32, color: Colors.white24),
                                          const SizedBox(height: 8),
                                          const Text('Avatar generation unavailable with KoboldCpp',
                                            style: TextStyle(color: Colors.white38, fontSize: 12),
                                            textAlign: TextAlign.center),
                                          const SizedBox(height: 8),
                                          const Text('Copy the image prompt below to generate locally',
                                            style: TextStyle(color: Colors.white24, fontSize: 11),
                                            textAlign: TextAlign.center),
                                        ],
                                      ),
                                    )
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.image_outlined, size: 48, color: Colors.white24),
                                        const SizedBox(height: 8),
                                        TextButton.icon(
                                          onPressed: _generateAvatar,
                                          icon: const Icon(Icons.auto_awesome, size: 16),
                                          label: const Text('Generate Avatar'),
                                        ),
                                      ],
                                    ),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                if (_generatedAvatar != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _isGeneratingAvatar ? null : _generateAvatar,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text(_isGeneratingAvatar ? 'Generating...' : 'Regenerate'),
                        style: TextButton.styleFrom(foregroundColor: Colors.blueAccent),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _isGeneratingAvatar ? null : () async {
                          final cropped = await ImageCropDialog.show(
                            context,
                            imageBytes: _generatedAvatar!,
                          );
                          if (cropped != null && mounted) {
                            setState(() => _generatedAvatar = cropped);
                          }
                        },
                        icon: const Icon(Icons.crop, size: 16),
                        label: const Text('Crop'),
                        style: TextButton.styleFrom(foregroundColor: Colors.orangeAccent),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                // Editable image prompt — collapsible
                Row(
                  children: [
                    const Text('Image Prompt', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.white38, size: 16),
                      onPressed: () {
                        if (_imagePromptController.text.isNotEmpty) {
                          Clipboard.setData(ClipboardData(text: _imagePromptController.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Image prompt copied to clipboard'), duration: Duration(seconds: 2)),
                          );
                        }
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Copy prompt to clipboard',
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        _imagePromptExpanded ? Icons.expand_less : Icons.expand_more,
                        color: Colors.white38,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _imagePromptExpanded = !_imagePromptExpanded),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: _imagePromptExpanded ? 'Collapse' : 'Expand',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _imagePromptController,
                  maxLines: _imagePromptExpanded ? null : 2,
                  minLines: _imagePromptExpanded ? 6 : 2,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Describe the character portrait...',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white12),
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
                const SizedBox(height: 16),
                // Character name
                Text(
                  _generatedCard!.name,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // Tags
                if (_generatedCard!.tags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: _generatedCard!.tags.map((tag) => Chip(
                      label: Text(tag, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                      backgroundColor: const Color(0xFF374151),
                      side: BorderSide.none,
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
                const SizedBox(height: 24),
                // Action buttons
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saveCharacter,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Character'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _confirmReset,
                    icon: const Icon(Icons.note_add_outlined, size: 18),
                    label: const Text('New Character'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),

          // Right column — Editable fields
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Review & Edit',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                const Text(
                  'The AI generated the following character card. Feel free to edit any field before saving.',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
                const SizedBox(height: 24),
                _editableField('Description', _descController, maxLines: 6),
                _editableField('Personality', _personalityController, maxLines: 4),
                _editableField('Scenario', _scenarioController, maxLines: 3),
                _editableField('First Message', _firstMessageController, maxLines: 6),
                _editableField('Example Dialogue', _exampleDialogueController, maxLines: 6),

                // ── Lorebook Preview & Cherry-pick ──
                if (_generatedCard!.lorebook != null && _generatedCard!.lorebook!.entries.isNotEmpty) ...[
                  const Divider(color: Colors.white12, height: 32),
                  Row(
                    children: [
                      const Icon(Icons.menu_book, color: Colors.blueAccent, size: 18),
                      const SizedBox(width: 8),
                      const Text('World Lore Entries', style: TextStyle(color: Colors.blueAccent, fontSize: 15, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('${_lorebookEntryEnabled.values.where((v) => v).length}/${_generatedCard!.lorebook!.entries.length} enabled',
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Uncheck entries you don\'t want included in the saved character.',
                    style: TextStyle(color: Colors.white24, fontSize: 11)),
                  const SizedBox(height: 12),
                  ...List.generate(_generatedCard!.lorebook!.entries.length, (i) {
                    final entry = _generatedCard!.lorebook!.entries[i];
                    final enabled = _lorebookEntryEnabled[i] ?? true;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: enabled ? const Color(0xFF1E293B) : const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: enabled ? Colors.blueAccent.withValues(alpha: 0.3) : Colors.white10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: enabled,
                            activeColor: Colors.blueAccent,
                            onChanged: (val) => setState(() => _lorebookEntryEnabled[i] = val ?? true),
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Opacity(
                              opacity: enabled ? 1.0 : 0.4,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(entry.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 2),
                                  Text('Keys: ${entry.key}', style: const TextStyle(color: Colors.blueAccent, fontSize: 11)),
                                  const SizedBox(height: 4),
                                  Text(entry.content, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _editableField(String label, TextEditingController controller, {int maxLines = 3}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          AppTextField(
            controller: controller,
            maxLines: maxLines,
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.blueAccent),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  Logic
  // ═══════════════════════════════════════════════════════════════

  bool _isRandomizing = false;
  double _conceptGenProgress = 0.0;

  /// "Help me expand this" — uses the LLM to rewrite rough user notes into richer prose.
  Future<void> _expandNarrative() async {
    if (_isExpandingNarrative) return;
    setState(() => _isExpandingNarrative = true);

    try {
      final llmService = _getActiveLlmService();
      if (llmService == null) { setState(() => _isExpandingNarrative = false); return; }

      // ── Gather all filled-in fields ──
      final details = <String>[];
      final name = _nameController.text.trim();
      if (name.isNotEmpty) details.add('Name: $name');
      if (_ageController.text.trim().isNotEmpty) details.add('Age: ${_ageController.text.trim()}');
      if (_sexController.text.trim().isNotEmpty) details.add('Sex: ${_sexController.text.trim()}');
      if (_guidedAppearanceController.text.trim().isNotEmpty) details.add('Build/Body: ${_guidedAppearanceController.text.trim()}');
      if (_guidedHairController.text.trim().isNotEmpty) details.add('Hair: ${_guidedHairController.text.trim()}');
      if (_guidedFeaturesController.text.trim().isNotEmpty) details.add('Features: ${_guidedFeaturesController.text.trim()}');
      if (_guidedRaceController.text.trim().isNotEmpty) details.add('Race/Species: ${_guidedRaceController.text.trim()}');
      if (_guidedPersonalityController.text.trim().isNotEmpty) details.add('Personality: ${_guidedPersonalityController.text.trim()}');
      if (_guidedSpeechController.text.trim().isNotEmpty) details.add('Speech style: ${_guidedSpeechController.text.trim()}');
      if (_guidedSecretController.text.trim().isNotEmpty) details.add('Hidden depth: ${_guidedSecretController.text.trim()}');
      if (_guidedOriginController.text.trim().isNotEmpty) details.add('Background: ${_guidedOriginController.text.trim()}');
      if (_guidedSettingController.text.trim().isNotEmpty) details.add('Setting: ${_guidedSettingController.text.trim()}');
      if (_guidedToneController.text.trim().isNotEmpty) details.add('Tone: ${_guidedToneController.text.trim()}');
      if (_guidedRelDynamicController.text.trim().isNotEmpty) details.add('Relationship to {{user}}: ${_guidedRelDynamicController.text.trim()}');
      if (_guidedRelScenarioController.text.trim().isNotEmpty) details.add('Opening scenario: ${_guidedRelScenarioController.text.trim()}');
      if (_nsfwEnabled) {
        if (_guidedNsfwBodyController.text.trim().isNotEmpty) details.add('Intimate body: ${_guidedNsfwBodyController.text.trim()}');
        if (_guidedNsfwExpController.text.trim().isNotEmpty) details.add('Experience: ${_guidedNsfwExpController.text.trim()}');
        if (_guidedNsfwDomController.text.trim().isNotEmpty) details.add('Dominance: ${_guidedNsfwDomController.text.trim()}');
        if (_guidedNsfwKinksController.text.trim().isNotEmpty) details.add('Kinks: ${_guidedNsfwKinksController.text.trim()}');
        if (_guidedNsfwClothingController.text.trim().isNotEmpty) details.add('Clothing: ${_guidedNsfwClothingController.text.trim()}');
        if (_guidedNsfwPersonalityController.text.trim().isNotEmpty) details.add('Sexual personality: ${_guidedNsfwPersonalityController.text.trim()}');
      }

      final userVision = _guidedVisionController.text.trim();
      if (details.length <= 1 && userVision.isEmpty) {
        // Nothing to work with
        setState(() => _isExpandingNarrative = false);
        return;
      }

      final detailsBlock = details.join('\n');
      final visionBlock = userVision.isNotEmpty
          ? '\n\nUser\'s additional notes/vision:\n"$userVision"'
          : '';

      String accumulated = '';
      await for (final token in llmService.generateStream(GenerationParams(
        prompt: 'A user is creating a roleplay character using a guided form. They filled in '
            'various fields with details about the character. Generate a vivid, cohesive character '
            'description that weaves ALL of these details together into 2-3 flowing paragraphs. '
            'PRESERVE the user\'s creative intent — do not override their ideas with generic tropes. '
            'If they provided NSFW details, include them tastefully in the description.\n\n'
            'Character details from form:\n$detailsBlock$visionBlock\n\n'
            'Output ONLY a JSON object with exactly one key: "expanded". The value should be '
            'the complete character description in third person. No markdown, no explanation, just the JSON:',
        maxLength: 1024,
        minLength: 64,
        temperature: 1.0,
        repeatPenalty: 1.1,
        minP: 0.05,
        reasoningEnabled: false,
        stopSequences: ['<END>'],
      ))) {
        accumulated += token;
      }

      final result = _extractChargenValue(accumulated, 'expanded');
      if (result != null && mounted) {
        // Show a dialog letting the user accept/reject the expanded version
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.auto_fix_high, color: Colors.tealAccent, size: 22),
                SizedBox(width: 8),
                Text('Generated Description', style: TextStyle(color: Colors.white, fontSize: 18)),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('AI generated this description from your details:', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
                      ),
                      child: SelectableText(
                        result,
                        style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('This will replace the current vision text. You can edit it after.', style: TextStyle(color: Colors.white24, fontSize: 11)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Discard', style: TextStyle(color: Colors.white38)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D7377)),
                child: const Text('Use This'),
              ),
            ],
          ),
        );

        if (accepted == true && mounted) {
          setState(() {
            _guidedVisionController.text = result;
          });
          _saveState();
        }
      }
    } catch (e) {
      debugPrint('CharacterCreator: Expand narrative failed: $e');
    }

    if (mounted) setState(() => _isExpandingNarrative = false);
  }

  /// Start generation from guided mode — assembles all guided fields into a narrative concept.
  Future<void> _startGuidedGeneration() async {
    final name = _nameController.text.trim();
    final vision = _guidedVisionController.text.trim();

    if (name.isEmpty || vision.length < 10) return;

    setState(() {
      _currentStep = 3;
      _isGenerating = true;
      _generationStatus = 'Crafting character with AI...';
      _generationPreview = '';
      _progress = 0.0;
    });

    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);

    // Resolve LLM service — same logic as automated mode
    LLMService llmService;
    if (llmProvider.activeBackend == BackendType.kobold) {
      final kobold = llmProvider.koboldService;
      if (!kobold.isReady) {
        setState(() { _generationStatus = 'Error: KoboldCpp is not running. Start it first.'; _isGenerating = false; });
        return;
      }
      llmService = kobold;
    } else if (_selectedModelId.isNotEmpty && _selectedModelId != llmProvider.openRouterService.modelName) {
      llmService = OpenRouterService(apiUrl: storage.remoteApiUrl, apiKey: storage.remoteApiKey, modelName: _selectedModelId);
    } else {
      final active = llmProvider.activeService;
      if (active == null || !active.isReady) {
        setState(() { _generationStatus = 'Error: No LLM service available. Configure a model first.'; _isGenerating = false; });
        return;
      }
      llmService = active;
    }

    // Resolve persona context
    String userPersonaContext = '';
    if (_selectedPersonaId.isNotEmpty) {
      final personaService = Provider.of<UserPersonaService>(context, listen: false);
      final selectedPersona = personaService.personas.where((p) => p.id == _selectedPersonaId).firstOrNull;
      if (selectedPersona != null) {
        final parts = <String>[];
        if (selectedPersona.name.isNotEmpty) parts.add('Name: ${selectedPersona.name}');
        if (selectedPersona.persona.isNotEmpty) parts.add('Persona: ${selectedPersona.persona}');
        userPersonaContext = parts.join('\n');
      }
    }

    // ── Assemble guided narrative ──
    final conceptParts = <String>[vision];
    if (_guidedAppearanceController.text.trim().isNotEmpty) {
      conceptParts.add('Physical build: ${_guidedAppearanceController.text.trim()}');
    }
    if (_guidedHairController.text.trim().isNotEmpty) {
      conceptParts.add('Hair: ${_guidedHairController.text.trim()}');
    }
    if (_guidedFeaturesController.text.trim().isNotEmpty) {
      conceptParts.add('Distinguishing features: ${_guidedFeaturesController.text.trim()}');
    }
    if (_guidedRaceController.text.trim().isNotEmpty) {
      conceptParts.add('Race/Species: ${_guidedRaceController.text.trim()}');
    }
    if (_guidedPersonalityController.text.trim().isNotEmpty) {
      conceptParts.add('Personality: ${_guidedPersonalityController.text.trim()}');
    }
    if (_guidedSpeechController.text.trim().isNotEmpty) {
      conceptParts.add('Speech style: ${_guidedSpeechController.text.trim()}');
    }
    if (_guidedSecretController.text.trim().isNotEmpty) {
      conceptParts.add('Hidden depth: ${_guidedSecretController.text.trim()}');
    }
    if (_guidedOriginController.text.trim().isNotEmpty) {
      conceptParts.add('Background: ${_guidedOriginController.text.trim()}');
    }
    if (_guidedSettingController.text.trim().isNotEmpty) {
      conceptParts.add('Setting: ${_guidedSettingController.text.trim()}');
    }
    if (_guidedToneController.text.trim().isNotEmpty) {
      conceptParts.add('Tone: ${_guidedToneController.text.trim()}');
    }
    if (_guidedRelDynamicController.text.trim().isNotEmpty) {
      conceptParts.add('Relationship to {{user}}: ${_guidedRelDynamicController.text.trim()}');
    }
    if (_guidedRelScenarioController.text.trim().isNotEmpty) {
      conceptParts.add('Opening scenario: ${_guidedRelScenarioController.text.trim()}');
    }

    // NSFW parts
    if (_nsfwEnabled) {
      if (_guidedNsfwBodyController.text.trim().isNotEmpty) conceptParts.add('Intimate body details: ${_guidedNsfwBodyController.text.trim()}');
      if (_guidedNsfwExpController.text.trim().isNotEmpty) conceptParts.add('Sexual experience: ${_guidedNsfwExpController.text.trim()}');
      if (_guidedNsfwDomController.text.trim().isNotEmpty) conceptParts.add('Dominance: ${_guidedNsfwDomController.text.trim()}');
      if (_guidedNsfwKinksController.text.trim().isNotEmpty) conceptParts.add('Turn-ons/kinks: ${_guidedNsfwKinksController.text.trim()}');
      if (_guidedNsfwClothingController.text.trim().isNotEmpty) conceptParts.add('Clothing aesthetic: ${_guidedNsfwClothingController.text.trim()}');
      if (_guidedNsfwPersonalityController.text.trim().isNotEmpty) conceptParts.add('Sexual personality: ${_guidedNsfwPersonalityController.text.trim()}');
    }

    final enrichedConcept = conceptParts.join('. ');
    final personalityKeywords = _guidedPersonalityController.text.trim();

    // ── Build character context for the generator ──
    final contextParts = <String>[];
    if (_ageController.text.trim().isNotEmpty) contextParts.add('Age: ${_ageController.text.trim()}');
    if (_sexController.text.trim().isNotEmpty) contextParts.add('Sex: ${_sexController.text.trim()}');
    if (_guidedAppearanceController.text.trim().isNotEmpty) contextParts.add('Appearance: ${_guidedAppearanceController.text.trim()}');
    if (_guidedHairController.text.trim().isNotEmpty) contextParts.add('Hair: ${_guidedHairController.text.trim()}');
    if (_guidedFeaturesController.text.trim().isNotEmpty) contextParts.add('Features: ${_guidedFeaturesController.text.trim()}');
    if (_guidedRaceController.text.trim().isNotEmpty) contextParts.add('Race/Species: ${_guidedRaceController.text.trim()}');
    if (_guidedRelDynamicController.text.trim().isNotEmpty) contextParts.add('Relationship to {{user}}: ${_guidedRelDynamicController.text.trim()}');
    if (_guidedOriginController.text.trim().isNotEmpty) contextParts.add('Backstory: ${_guidedOriginController.text.trim()}');
    if (_guidedSettingController.text.trim().isNotEmpty) contextParts.add('Setting: ${_guidedSettingController.text.trim()}');
    if (_guidedToneController.text.trim().isNotEmpty) contextParts.add('Tone: ${_guidedToneController.text.trim()}');
    if (_nsfwEnabled) {
      final nsfwContext = <String>[];
      if (_guidedNsfwExpController.text.trim().isNotEmpty) nsfwContext.add('Experience: ${_guidedNsfwExpController.text.trim()}');
      if (_guidedNsfwDomController.text.trim().isNotEmpty) nsfwContext.add('Dominance: ${_guidedNsfwDomController.text.trim()}');
      if (_guidedNsfwKinksController.text.trim().isNotEmpty) nsfwContext.add('Kinks: ${_guidedNsfwKinksController.text.trim()}');
      if (nsfwContext.isNotEmpty) contextParts.add(nsfwContext.join(', '));
    }

    final genService = CharacterGenService(llmService);
    _activeGenService = genService;


    final card = await genService.generateCharacter(
      name: name,
      concept: enrichedConcept,
      personalityKeywords: personalityKeywords,
      artStyle: _artStyle,
      greetingLength: _greetingLength,
      altGreetingCount: _altGreetingCount,
      greetingTones: _selectedTones.toList(),
      generateLorebook: _generateLorebook,
      loreCategories: _selectedLoreCategories.toList(),
      loreDepth: _loreDepth,
      descriptionDetail: _generationDetailOptions[_generationDetail] ?? '2-3 paragraphs',
      age: _ageController.text.trim(),
      sex: _sexController.text.trim(),
      relationship: _guidedRelDynamicController.text.trim(),
      backstory: [
        if (_guidedOriginController.text.trim().isNotEmpty) _guidedOriginController.text.trim(),
        if (_guidedToneController.text.trim().isNotEmpty) '${_guidedToneController.text.trim()} tone',
        if (_guidedSettingController.text.trim().isNotEmpty) '${_guidedSettingController.text.trim()} setting',
      ].join(', '),
      characterContext: contextParts.join('\n'),
      userPersonaContext: userPersonaContext,
      generateDescription: true,
      nsfwEnabled: _nsfwEnabled,
      reasoningEnabled: _reasoningEnabled,
      imageGenPromptParadigm: storage.imageGenPromptParadigm,
      onProgress: (accumulated) {
        if (mounted) {
          setState(() {
            _generationPreview = accumulated;
            _progress = (accumulated.length / 3000.0).clamp(0.0, 0.95);
          });
        }
      },
      onStatus: (status) { if (mounted) setState(() => _generationStatus = status); },
      onError: (error) { if (mounted) setState(() => _generationStatus = 'Error: $error'); },
    );

    // Fetch the dedicated image prompt
    _imagePrompt = genService.generatedImagePrompt;

    // If aborted, _abortGeneration already reset state — bail out silently.
    if (genService.isAborted) return;

    if (card != null) {
      _generatedCard = card;
      _lorebookEntryEnabled = {};
      if (card.lorebook != null) {
        for (int i = 0; i < card.lorebook!.entries.length; i++) {
          _lorebookEntryEnabled[i] = true;
        }
      }
      _descController.text = card.description;
      _personalityController.text = card.personality;
      _scenarioController.text = card.scenario;
      _firstMessageController.text = card.firstMessage;
      _exampleDialogueController.text = card.mesExample;
      _systemPromptController.text = card.systemPrompt;

      setState(() { _currentStep = 4; _isGenerating = false; _progress = 1.0; _activeGenService = null; }); // → Realism step

      if (llmProvider.activeBackend != BackendType.kobold) {
        _generateAvatar();
      }
    } else {
      setState(() { _currentStep = 4; _isGenerating = false; _generatedCard = null; _activeGenService = null; }); // → Realism step (error)
    }
  }

  /// Randomize just the character name
  Future<void> _randomizeName() async {
    if (_isRandomizing) return;
    setState(() => _isRandomizing = true);

    try {
      final llmService = _getActiveLlmService();
      if (llmService == null) return;

      final archetypeHint = _selectedArchetype.isNotEmpty
          ? ' The name should suit a "$_selectedArchetype" character.'
          : '';

      String accumulated = '';
      await for (final token in llmService.generateStream(GenerationParams(
        prompt: 'Generate ONE unique, creative character name for a roleplay character.$archetypeHint Output ONLY a JSON object with exactly one key: "name". No markdown, no explanation, just the JSON:',
        maxLength: 128,
        minLength: 16,
        temperature: 1.2,
        repeatPenalty: 1.1,
        minP: 0.05,
        reasoningEnabled: false,
        stopSequences: ['<END>'],
      ))) {
        accumulated += token;
      }

      final nameResult = _extractChargenValue(accumulated, 'name');
      if (nameResult != null) {
        setState(() {
          _nameController.text = nameResult;
        });
        _saveState();
      }
    } catch (e) {
      debugPrint('CharacterCreator: Randomize name failed: $e');
    }

    if (mounted) setState(() => _isRandomizing = false);
  }

  /// Randomize a concept/description using all selected toggles as context
  Future<void> _randomizeConcept() async {
    if (_isRandomizing) return;
    setState(() {
      _isRandomizing = true;
      _conceptGenProgress = 0.0;
    });

    try {
      final llmService = _getActiveLlmService();
      if (llmService == null) return;

      // Build context from all selections
      final contextParts = <String>[];
      if (_selectedArchetype.isNotEmpty) contextParts.add('Archetype: $_selectedArchetype');
      if (_nameController.text.trim().isNotEmpty) contextParts.add('Name: ${_nameController.text.trim()}');
      if (_keywordsController.text.trim().isNotEmpty) contextParts.add('Personality: ${_keywordsController.text.trim()}');
      if (_ageController.text.trim().isNotEmpty) contextParts.add('Age: ${_ageController.text.trim()}');
      if (_sexController.text.trim().isNotEmpty) contextParts.add('Sex: ${_sexController.text.trim()}');
      final effectiveRace = _customRaceController.text.trim().isNotEmpty ? _customRaceController.text.trim() : _race;
      if (effectiveRace.isNotEmpty) contextParts.add('Race/species: $effectiveRace');
      if (_bodyType.isNotEmpty) contextParts.add('Body type: $_bodyType');
      if (_hairLength.isNotEmpty || _hairStyle.isNotEmpty) {
        contextParts.add('Hair: ${[if (_hairLength.isNotEmpty) _hairLength, if (_hairStyle.isNotEmpty) _hairStyle].join(", ")}');
      }
      if (_skinTone.isNotEmpty) contextParts.add('Skin tone: $_skinTone');
      if (_notableFeatures.isNotEmpty) contextParts.add('Notable features: ${_notableFeatures.join(", ")}');
      if (_selectedRelationships.isNotEmpty) contextParts.add('Relationship to user: ${_selectedRelationships.join(", ")}');
      if (_backstoryOrigin.isNotEmpty) contextParts.add('Backstory origin: $_backstoryOrigin');
      if (_backstoryTone.isNotEmpty) contextParts.add('Backstory tone: $_backstoryTone');
      if (_backstoryEra.isNotEmpty) contextParts.add('Era/setting: $_backstoryEra');
      if (_backstoryNotesController.text.trim().isNotEmpty) contextParts.add('Backstory notes: ${_backstoryNotesController.text.trim()}');
      if (_nsfwEnabled) {
        if (_experience.isNotEmpty) contextParts.add('Experience: $_experience');
        if (_dominance.isNotEmpty) contextParts.add('Dominance: $_dominance');
        if (_selectedKinks.isNotEmpty) contextParts.add('Kinks: ${_selectedKinks.join(", ")}');
        if (_outfitVibe.isNotEmpty) contextParts.add('Outfit vibe: $_outfitVibe');
      }

      final contextStr = contextParts.isNotEmpty
          ? ' Use these character details as inspiration: ${contextParts.join("; ")}.'
          : '';

      final descLength = _generationDetailOptions[_generationDetail] ?? '2-3 paragraphs';
      final maxTokensForDesc = const {'Brief': 256, 'Standard': 512, 'Detailed': 1024, 'Comprehensive': 2048}[_generationDetail] ?? 512;

      String accumulated = '';
      int tokenCount = 0;
      await for (final token in llmService.generateStream(GenerationParams(
        prompt: 'Generate a creative character description ($descLength) for a roleplay character.$contextStr Write in third person. Include physical appearance, personality hints, and backstory elements. Output ONLY a JSON object with exactly one key: "concept". Be vivid and detailed. No markdown, no explanation, just the JSON:',
        maxLength: maxTokensForDesc,
        minLength: 32,
        temperature: 1.2,
        repeatPenalty: 1.1,
        minP: 0.05,
        reasoningEnabled: false,
        stopSequences: ['<END>'],
      ))) {
        accumulated += token;
        tokenCount++;
        if (mounted) {
          setState(() => _conceptGenProgress = (tokenCount / maxTokensForDesc).clamp(0.0, 0.95));
        }
      }

      final conceptResult = _extractChargenValue(accumulated, 'concept');
      if (conceptResult != null) {
        setState(() {
          _conceptController.text = conceptResult;
          _conceptGenerated = true;
        });
        _saveState();
      }
    } catch (e) {
      debugPrint('CharacterCreator: Randomize concept failed: $e');
    }

    if (mounted) setState(() => _isRandomizing = false);
  }

  /// Robust extractor for chargen JSON values from LLM output.
  /// Handles markdown fences, literal newlines, unescaped quotes, and
  /// falls back to regex extraction if JSON.decode fails.
  String? _extractChargenValue(String raw, String key) {
    // Step 1: Strip thinking blocks
    String cleaned = raw.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '',
    ).replaceAll(
      RegExp(r'<think>[\s\S]*$', caseSensitive: false), '',
    ).trim();

    // Step 2: Strip markdown code fences (common with local models)
    cleaned = cleaned
        .replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^```\s*$', multiLine: true), '')
        .trim();

    debugPrint('CharacterCreator: Raw $key output (${cleaned.length} chars): ${cleaned.length > 200 ? '${cleaned.substring(0, 200)}...' : cleaned}');

    // Step 3: Extract JSON object
    final jsonStart = cleaned.indexOf('{');
    final jsonEnd = cleaned.lastIndexOf('}');
    if (jsonStart < 0 || jsonEnd <= jsonStart) {
      debugPrint('CharacterCreator: No JSON object found in $key output');
      return null;
    }
    String jsonStr = cleaned.substring(jsonStart, jsonEnd + 1);

    // Step 4: Try direct JSON parse
    try {
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final value = data[key]?.toString();
      if (value != null && value.isNotEmpty) {
        debugPrint('CharacterCreator: Direct JSON parse succeeded for $key');
        return value;
      }
    } catch (_) {
      debugPrint('CharacterCreator: Direct JSON parse failed for $key, trying fixes...');
    }

    // Step 5: Fix literal newlines inside JSON strings and retry
    try {
      String fixed = jsonStr;
      // Escape literal newlines that are inside JSON string values
      // (between unescaped quotes) — these break json.decode
      fixed = fixed.replaceAll('\r\n', '\\n').replaceAll('\r', '\\n');
      // Replace literal newlines with \n but only inside strings
      final sb = StringBuffer();
      bool inString = false;
      bool escaped = false;
      for (int i = 0; i < fixed.length; i++) {
        final ch = fixed[i];
        if (escaped) {
          sb.write(ch);
          escaped = false;
          continue;
        }
        if (ch == '\\') {
          sb.write(ch);
          escaped = true;
          continue;
        }
        if (ch == '"') {
          inString = !inString;
          sb.write(ch);
          continue;
        }
        if (ch == '\n' && inString) {
          sb.write('\\n');
          continue;
        }
        sb.write(ch);
      }
      fixed = sb.toString();
      // Also fix trailing commas
      fixed = fixed.replaceAll(RegExp(r',\s*}'), '}').replaceAll(RegExp(r',\s*]'), ']');

      final data = json.decode(fixed) as Map<String, dynamic>;
      final value = data[key]?.toString();
      if (value != null && value.isNotEmpty) {
        debugPrint('CharacterCreator: Fixed JSON parse succeeded for $key');
        return value;
      }
    } catch (_) {
      debugPrint('CharacterCreator: Fixed JSON parse also failed for $key, trying regex...');
    }

    // Step 6: Regex fallback — extract value after "key": "
    try {
      final pattern = RegExp('"$key"\\s*:\\s*"', caseSensitive: false);
      final match = pattern.firstMatch(jsonStr);
      if (match != null) {
        final valueStart = match.end;
        // Walk forward to find the closing quote (not escaped)
        bool esc = false;
        for (int i = valueStart; i < jsonStr.length; i++) {
          final ch = jsonStr[i];
          if (esc) { esc = false; continue; }
          if (ch == '\\') { esc = true; continue; }
          if (ch == '"') {
            // Found the end of the value
            final value = jsonStr.substring(valueStart, i)
                .replaceAll('\\n', '\n')
                .replaceAll('\\t', '\t')
                .replaceAll('\\"', '"');
            if (value.isNotEmpty) {
              debugPrint('CharacterCreator: Regex extraction succeeded for $key');
              return value;
            }
            break;
          }
        }
        // If no closing quote found, just grab everything after the key to the end
        final rawValue = jsonStr.substring(valueStart).replaceAll(RegExp(r'"\s*}?\s*$'), '');
        if (rawValue.isNotEmpty) {
          debugPrint('CharacterCreator: Regex extraction (no closing quote) for $key');
          return rawValue.replaceAll('\\n', '\n').replaceAll('\\t', '\t').replaceAll('\\"', '"');
        }
      }
    } catch (_) {}

    debugPrint('CharacterCreator: All parse strategies failed for $key');
    return null;
  }

  /// Helper: resolve the active LLM service for randomization
  LLMService? _getActiveLlmService() {
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);

    LLMService? llmService;
    if (llmProvider.activeBackend == BackendType.kobold) {
      final kobold = llmProvider.koboldService;
      if (kobold.isReady) llmService = kobold;
    } else {
      if (_selectedModelId.isNotEmpty && _selectedModelId != llmProvider.openRouterService.modelName) {
        llmService = OpenRouterService(
          apiUrl: storage.remoteApiUrl,
          apiKey: storage.remoteApiKey,
          modelName: _selectedModelId,
        );
      } else {
        llmService = llmProvider.activeService;
      }
    }

    if (llmService == null || !llmService.isReady) {
      setState(() => _isRandomizing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No LLM available — configure a model first'), backgroundColor: Color(0xFF2A2A2A), behavior: SnackBarBehavior.floating),
        );
      }
      return null;
    }
    return llmService;
  }

  Future<void> _startGeneration() async {
    final name = _nameController.text.trim();
    final concept = _conceptController.text.trim();
    final keywords = _keywordsController.text.trim();

    if (name.isEmpty || concept.isEmpty) return;

    setState(() {
      _currentStep = 3;
      _isGenerating = true;
      _generationStatus = 'Crafting character with AI...';
      _generationPreview = '';
      _progress = 0.0;
    });

    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);

    // Create LLM service based on active backend
    LLMService llmService;
    if (llmProvider.activeBackend == BackendType.kobold) {
      // KoboldCpp — use local backend directly
      final kobold = llmProvider.koboldService;
      if (!kobold.isReady) {
        setState(() {
          _generationStatus = 'Error: KoboldCpp is not running. Start it first.';
          _isGenerating = false;
        });
        return;
      }
      llmService = kobold;
    } else if (_selectedModelId.isNotEmpty && _selectedModelId != llmProvider.openRouterService.modelName) {
      final tempService = OpenRouterService(
        apiUrl: storage.remoteApiUrl,
        apiKey: storage.remoteApiKey,
        modelName: _selectedModelId,
      );
      llmService = tempService;
    } else {
      final active = llmProvider.activeService;
      if (active == null || !active.isReady) {
        setState(() {
          _generationStatus = 'Error: No LLM service available. Configure a model first.';
          _isGenerating = false;
        });
        return;
      }
      llmService = active;
    }

    debugPrint('CharacterGen: Using backend: ${llmService.runtimeType} (${llmProvider.activeBackend == BackendType.kobold ? "KoboldCpp" : _selectedModelId.isNotEmpty ? _selectedModelId : "default API model"})');

    // Resolve selected persona context
    String userPersonaContext = '';
    if (_selectedPersonaId.isNotEmpty) {
      final personaService = Provider.of<UserPersonaService>(context, listen: false);
      final selectedPersona = personaService.personas
          .where((p) => p.id == _selectedPersonaId)
          .firstOrNull;
      if (selectedPersona != null) {
        final parts = <String>[];
        if (selectedPersona.name.isNotEmpty) parts.add('Name: ${selectedPersona.name}');
        if (selectedPersona.persona.isNotEmpty) parts.add('Persona: ${selectedPersona.persona}');
        userPersonaContext = parts.join('\n');
      }
    }

    // Extract World Lore
    final worldLore = await _extractWorldLore(llmProvider);
    
    final genService = CharacterGenService(llmService);
    _activeGenService = genService;


    // Build appearance + NSFW context
    final appearanceParts = <String>[];
    final effectiveRace = _customRaceController.text.trim().isNotEmpty ? _customRaceController.text.trim() : _race;
    if (effectiveRace.isNotEmpty) appearanceParts.add('$effectiveRace race/species');
    if (_bodyType.isNotEmpty) appearanceParts.add('$_bodyType build');
    if (_hairLength.isNotEmpty) appearanceParts.add('$_hairLength hair');
    if (_hairStyle.isNotEmpty) appearanceParts.add('$_hairStyle hair style');
    if (_skinTone.isNotEmpty) appearanceParts.add('$_skinTone skin');
    if (_notableFeatures.isNotEmpty) appearanceParts.addAll(_notableFeatures);
    if (_absCore.isNotEmpty) appearanceParts.add('$_absCore abs');
    if (_thighs.isNotEmpty) appearanceParts.add('$_thighs thighs');
    if (_hips.isNotEmpty) appearanceParts.add('$_hips hips');
    if (_shoulders.isNotEmpty) appearanceParts.add('$_shoulders shoulders');
    if (_waist.isNotEmpty) appearanceParts.add('$_waist waist');
    if (_nsfwEnabled) {
      if (_chestSize.isNotEmpty) appearanceParts.add('$_chestSize chest');
      if (_buttSize.isNotEmpty) appearanceParts.add('$_buttSize butt');
    }

    final nsfwParts = <String>[];
    if (_nsfwEnabled) {
      if (_experience.isNotEmpty) nsfwParts.add('Sexual experience: $_experience');
      if (_dominance.isNotEmpty) nsfwParts.add('Dominance: $_dominance');
      if (_selectedKinks.isNotEmpty) nsfwParts.add('Kinks: ${_selectedKinks.join(", ")}');
      if (_customKinksController.text.trim().isNotEmpty) nsfwParts.add('Also into: ${_customKinksController.text.trim()}');
      if (_outfitVibe.isNotEmpty) nsfwParts.add('Typical outfit vibe: $_outfitVibe');
    }

    String enrichedConcept = concept;
    if (appearanceParts.isNotEmpty) {
      enrichedConcept += '. Physical appearance: ${appearanceParts.join(", ")}';
    }
    if (nsfwParts.isNotEmpty) {
      enrichedConcept += '. ${nsfwParts.join(". ")}';
    }

    final card = await genService.generateCharacter(
      name: name,
      concept: enrichedConcept,
      personalityKeywords: keywords,
      artStyle: _artStyle,
      greetingLength: _greetingLength,
      altGreetingCount: _altGreetingCount,
      greetingTones: _selectedTones.toList(),
      generateLorebook: _generateLorebook,
      loreCategories: _selectedLoreCategories.toList(),
      loreDepth: _loreDepth,
      descriptionDetail: _generationDetailOptions[_generationDetail] ?? '2-3 paragraphs',
      age: _ageController.text.trim(),
      sex: _sexController.text.trim(),
      worldLore: worldLore,
      relationship: [
        ..._selectedRelationships,
        if (_relationshipController.text.trim().isNotEmpty) _relationshipController.text.trim(),
      ].join(', '),
      backstory: [
        if (_backstoryOrigin.isNotEmpty) _backstoryOrigin,
        if (_backstoryTone.isNotEmpty) '${_backstoryTone} tone',
        if (_backstoryEra.isNotEmpty) '${_backstoryEra} era',
        if (_backstoryNotesController.text.trim().isNotEmpty) _backstoryNotesController.text.trim(),
      ].join(', '),
      characterContext: [
        if (effectiveRace.isNotEmpty) 'Race/Species: $effectiveRace',
        if (_ageController.text.trim().isNotEmpty) 'Age: ${_ageController.text.trim()}',
        if (_sexController.text.trim().isNotEmpty) 'Sex: ${_sexController.text.trim()}',
        if (appearanceParts.isNotEmpty) 'Appearance: ${appearanceParts.join(", ")}',
        if (_selectedRelationships.isNotEmpty || _relationshipController.text.trim().isNotEmpty)
          'Relationship to {{user}}: ${[..._selectedRelationships, if (_relationshipController.text.trim().isNotEmpty) _relationshipController.text.trim()].join(", ")}',
        if (_backstoryOrigin.isNotEmpty) 'Backstory origin: $_backstoryOrigin',
        if (_backstoryTone.isNotEmpty) 'Story tone: $_backstoryTone',
        if (_backstoryEra.isNotEmpty) 'Era/setting: $_backstoryEra',
        if (_backstoryNotesController.text.trim().isNotEmpty) 'Backstory: ${_backstoryNotesController.text.trim()}',
        if (_nsfwEnabled && nsfwParts.isNotEmpty) nsfwParts.join(', '),
      ].join('\n'),
      userPersonaContext: userPersonaContext,
      nsfwEnabled: _nsfwEnabled,
      reasoningEnabled: _reasoningEnabled,
      imageGenPromptParadigm: storage.imageGenPromptParadigm,
      onProgress: (accumulated) {

        if (mounted) {
          setState(() {
            _generationPreview = accumulated;
            _progress = (accumulated.length / 3000.0).clamp(0.0, 0.95);
          });
        }
      },
      onStatus: (status) {
        if (mounted) {
          setState(() {
            _generationStatus = status;
          });
        }
      },
      onError: (error) {

        if (mounted) {
          setState(() {
            _generationStatus = 'Error: $error';
          });
        }
      },
    );

    // Fetch the dedicated image prompt before moving to review
    _imagePrompt = genService.generatedImagePrompt;

    // If aborted, _abortGeneration already reset state — bail out silently.
    if (genService.isAborted) return;

    if (card != null) {
      // Inject user-authored description (from magic wand)
      card.description = enrichedConcept;

      _generatedCard = card;
      // Initialize lorebook entry enabled map — all enabled by default
      _lorebookEntryEnabled = {};
      if (card.lorebook != null) {
        for (int i = 0; i < card.lorebook!.entries.length; i++) {
          _lorebookEntryEnabled[i] = true;
        }
      }
      _descController.text = card.description;
      _personalityController.text = card.personality;
      _scenarioController.text = card.scenario;
      _firstMessageController.text = card.firstMessage;
      _exampleDialogueController.text = card.mesExample;
      _systemPromptController.text = card.systemPrompt;

      setState(() {
        _currentStep = 4; // → Realism Engine step
        _isGenerating = false;
        _progress = 1.0;
        _activeGenService = null;
      });

      // Auto-start avatar generation (API backend only — KoboldCpp has no image API)
      if (llmProvider.activeBackend != BackendType.kobold) {
        _generateAvatar();
      }
    } else {
      setState(() {
        _currentStep = 4; // → Realism step (error state)
        _isGenerating = false;
        _generatedCard = null;
        _activeGenService = null;
      });
    }
  }

  Future<void> _generateAvatar() async {
    if (_isGeneratingAvatar) return;

    final imageGenService = Provider.of<ImageGenService>(context, listen: false);

    // Determine prompt for avatar
    String prompt = _imagePromptController.text.trim();
    if (prompt.isEmpty) {
      if (_imagePrompt != null && _imagePrompt!.isNotEmpty) {
        // Strip character name from the LLM-generated prompt
        String cleanPrompt = _imagePrompt!;
        final charName = _nameController.text.trim();
        if (charName.isNotEmpty) {
          cleanPrompt = cleanPrompt.replaceAll(RegExp(RegExp.escape(charName), caseSensitive: false), '').trim();
          for (final part in charName.split(RegExp(r'\s+'))) {
            if (part.length > 2) {
              cleanPrompt = cleanPrompt.replaceAll(RegExp('\\b${RegExp.escape(part)}\\b', caseSensitive: false), '').trim();
            }
          }
          cleanPrompt = cleanPrompt.replaceAll(RegExp(r',\s*,'), ',').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
          if (cleanPrompt.startsWith(',')) cleanPrompt = cleanPrompt.substring(1).trim();
        }
        // Append art style as a tag, not a sentence
        prompt = '$cleanPrompt, $_artStyle style';
      } else {
        // Fallback: build visual tags from known character details
        final tags = <String>['character portrait', '$_artStyle style'];
        final sex = _sexController.text.trim();
        final age = _ageController.text.trim();
        if (sex.isNotEmpty) tags.add(sex.toLowerCase());
        if (age.isNotEmpty) tags.add('$age years old');
        // Pull visual details from guided appearance fields if available
        if (_guidedAppearanceController.text.trim().isNotEmpty) tags.add(_guidedAppearanceController.text.trim());
        if (_guidedHairController.text.trim().isNotEmpty) tags.add(_guidedHairController.text.trim());
        if (_guidedFeaturesController.text.trim().isNotEmpty) tags.add(_guidedFeaturesController.text.trim());
        if (_guidedRaceController.text.trim().isNotEmpty) tags.add(_guidedRaceController.text.trim());
        // If no guided fields, extract a brief snippet from description (first 150 chars max)
        if (tags.length <= 4 && _descController.text.trim().isNotEmpty) {
          final descSnippet = _descController.text.trim();
          tags.add(descSnippet.length > 150 ? '${descSnippet.substring(0, 150)}' : descSnippet);
        }
        prompt = tags.join(', ');
      }
      _imagePromptController.text = prompt;
    }

    setState(() => _isGeneratingAvatar = true);

    try {
      final imageBytes = await imageGenService.generateImage(
        prompt: prompt,
        size: '512x512',
        isPortrait: true,
      );

      if (mounted && imageBytes != null) {
        setState(() {
          _generatedAvatar = imageBytes;
          _isGeneratingAvatar = false;
        });
      } else {
        if (mounted) {
          setState(() => _isGeneratingAvatar = false);
        }
      }
    } catch (e) {
      debugPrint('CharacterCreator: Avatar gen failed: $e');
      if (mounted) {
        setState(() => _isGeneratingAvatar = false);
      }
    }
  }

  Future<void> _saveCharacter() async {
    if (_generatedCard == null) return;

    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);

    try {
      // Update card with edited fields
      final card = _generatedCard!;
      card.description = _descController.text;
      card.personality = _personalityController.text;
      card.scenario = _scenarioController.text;
      card.firstMessage = _firstMessageController.text;
      card.mesExample = _exampleDialogueController.text;
      card.systemPrompt = _systemPromptController.text;

      // Build V2.5 extensions from Realism Engine step
      if (_realismStepEnabled) {
        card.frontPorchExtensions = FrontPorchExtensions(
          realismEnabled: _realismStepEnabled,
          shortTermBond: _realismShortTermBond,
          longTermBond: _realismLongTermBond,
          trustLevel: _realismTrustLevel,
          dayCount: _realismDayCount,
          timeOfDay: _realismTimeOfDay,
          characterEmotion: _realismEmotion,
          emotionIntensity: _realismEmotionIntensity,
          nsfwCooldownEnabled: _realismNsfwCooldown,
          chaosModeEnabled: _realismChaosMode,
          currentTask: _realismCurrentTask,
        );
      }

      // Filter lorebook entries — remove unchecked ones
      if (card.lorebook != null && _lorebookEntryEnabled.isNotEmpty) {
        final filtered = <LorebookEntry>[];
        for (int i = 0; i < card.lorebook!.entries.length; i++) {
          if (_lorebookEntryEnabled[i] ?? true) {
            filtered.add(card.lorebook!.entries[i]);
          }
        }
        card.lorebook = Lorebook(entries: filtered);
      }

      // Save avatar image
      if (_generatedAvatar != null) {
        final charDir = storage.charactersDir;
        if (!charDir.existsSync()) charDir.createSync(recursive: true);

        final epoch = DateTime.now().millisecondsSinceEpoch;
        final safeName = card.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
        final imagePath = p.join(charDir.path, '${safeName}_$epoch.png');

        // Write the raw image — V2 embedding is handled by the repo
        await File(imagePath).writeAsBytes(_generatedAvatar!);
        card.imagePath = imagePath;
      }

      // Add to repository
      debugPrint('AG_DEBUG: Saving character "${card.name}" to DB...');
      await repo.addCharacter(card);
      debugPrint('AG_DEBUG: Character saved! dbId=${card.dbId}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                const SizedBox(width: 8),
                Text('${card.name} created successfully!'),
              ],
            ),
            backgroundColor: const Color(0xFF2A2A2A),
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Clear saved form data since character was created
        final prefs = await SharedPreferences.getInstance();
        for (final key in [_prefName, _prefConcept, _prefKeywords, _prefArtStyle]) {
          await prefs.remove(key);
        }
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e, stackTrace) {
      debugPrint('AG_DEBUG: ERROR saving character: $e');
      debugPrint('AG_DEBUG: Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save character: $e'),
            backgroundColor: Colors.red.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
