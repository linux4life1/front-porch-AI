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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/ui/avatar_creation/avatar_generation_panel.dart';
import 'package:front_porch_ai/ui/dialogs/lorebook_entry_dialog.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/providers/app_state.dart';

/// Manual character creator — 7-step wizard.
///
/// Step 0: Identity (name, tags)
/// Step 1: Personality (description, personality, scenario, advanced prompts)
/// Step 2: Dialogue (first message, alt greetings, example dialogues)
/// Step 3: Lorebook (CRUD)
/// Step 4: Realism Engine (initial state)
/// Step 5: Review & Create (the card is SAVED advancing out of here)
/// Step 6: Portrait & Avatars — the shared AvatarGenerationPanel (phase #12);
///         post-save by design, so a failed generation can't lose the writing.
class CreateCharacterPage extends StatefulWidget {
  const CreateCharacterPage({super.key});

  @override
  State<CreateCharacterPage> createState() => _CreateCharacterPageState();
}

class _CreateCharacterPageState extends State<CreateCharacterPage> {
  int _currentStep = 0;

  // ── Identity (Step 0) ──
  final _nameController = TextEditingController();
  final List<String> _tags = [];
  final _tagController = TextEditingController();

  // ── Portrait & Avatars (Step 6) ──
  /// The persisted card, set when Review's "Create Character" advances into
  /// the final step. The panel needs a saved card before any image lands.
  CharacterCard? _savedCard;

  /// The panel is mid-generation — Done is locked so leaving can't silently
  /// drop work the engine is still finishing.
  bool _panelBusy = false;

  // ── Personality (Step 1) ──
  final _descriptionController = StyledTextController(preset: StyledTextPreset.macros);
  final _personalityController = StyledTextController(preset: StyledTextPreset.macros);
  final _scenarioController = StyledTextController(preset: StyledTextPreset.macros);
  final _systemPromptController = StyledTextController(preset: StyledTextPreset.macros);
  final _postHistoryController = StyledTextController(preset: StyledTextPreset.macros);

  // ── Dialogue (Step 2) ──
  final _firstMessageController = StyledTextController(preset: StyledTextPreset.prose);
  final _exampleDialogueController = StyledTextController(preset: StyledTextPreset.prose);
  final List<StyledTextController> _altGreetingControllers = [];

  // ── Lorebook (Step 3) ──
  final List<LorebookEntry> _lorebookEntries = [];

  // ── Realism Engine (Step 4) ──
  bool _realismEnabled = false;
  String _realismTimeOfDay = 'morning';
  int _realismDayCount = 1;
  // Story Calendar authoring (story-calendar.md §3a): null start date =
  // "the day the chat starts"; null time = period default.
  String? _realismStoryStartDate;
  String? _realismStoryStartTime;
  int _realismShortTermBond = 0;
  int _realismLongTermBond = 0;
  int _realismTrustLevel = 0;
  String _realismEmotion = '';
  String _realismEmotionIntensity = 'mild';
  bool _realismNsfwCooldown = false;
  bool _realismChaosMode = false;
  bool _realismNeedsSim = false;
  bool _realismEnjoysLowHygiene = false;
  String _realismCurrentTask = '';
  bool _realismVerificationEnabled = false;
  int _realismVerificationMaxReprocesses = 1;
  int _realismVerificationStrictness = 3;
  bool _realismNeedsDirectorAuthority = false;

  // ── Needs Simulation baselines (0-100) ──
  int _needsBaselineHunger = 80;
  int _needsBaselineBladder = 80;
  int _needsBaselineEnergy = 80;
  int _needsBaselineSocial = 80;
  int _needsBaselineFun = 80;
  int _needsBaselineHygiene = 80;
  int _needsBaselineComfort = 80;

  int _needsDecayHunger = 5;
  int _needsDecayBladder = 5;
  int _needsDecayEnergy = 5;
  int _needsDecaySocial = 5;
  int _needsDecayFun = 5;
  int _needsDecayHygiene = 5;
  int _needsDecayComfort = 5;

  // ── Token counter ──
  final ValueNotifier<int> _tokenNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    // Listen to all text controllers for token counting
    for (final c in _allControllers) {
      c.addListener(_updateTokenEstimate);
    }
  }

  List<TextEditingController> get _allControllers => [
    _nameController,
    _descriptionController,
    _personalityController,
    _scenarioController,
    _systemPromptController,
    _postHistoryController,
    _firstMessageController,
    _exampleDialogueController,
    ..._altGreetingControllers,
  ];

  void _updateTokenEstimate() {
    int total = 0;
    for (final c in _allControllers) {
      // Rough estimate: ~4 chars per token
      total += (c.text.length / 4).ceil();
    }
    // Add lorebook entries
    for (final entry in _lorebookEntries) {
      total +=
          ((entry.name.length + entry.key.length + entry.content.length) / 4)
              .ceil();
    }
    if (mounted) {
      _tokenNotifier.value = total;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tagController.dispose();
    _descriptionController.dispose();
    _personalityController.dispose();
    _scenarioController.dispose();
    _systemPromptController.dispose();
    _postHistoryController.dispose();
    _firstMessageController.dispose();
    _exampleDialogueController.dispose();
    for (final c in _altGreetingControllers) {
      c.dispose();
    }
    _tokenNotifier.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              Provider.of<AppState>(context, listen: false).setIndex(0),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.person_add,
              color: AppColors.formMasterAccent,
              size: 22,
            ),
            const SizedBox(width: 8),
            const Text('Create Character'),
            const Spacer(),
            _buildStepIndicator(),
          ],
        ),
      ),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _currentStep == 0
                ? _buildIdentityStep()
                : _currentStep == 1
                ? _buildPersonalityStep()
                : _currentStep == 2
                ? _buildDialogueStep()
                : _currentStep == 3
                ? _buildLorebookStep()
                : _currentStep == 4
                ? _buildRealismStep()
                : _currentStep == 5
                ? _buildReviewStep()
                : _buildPortraitAvatarsStep(),
          ),
          // Floating token counter
          Positioned(
            right: 24,
            bottom: 24,
            child: ValueListenableBuilder<int>(
              valueListenable: _tokenNotifier,
              builder: (context, tokens, child) =>
                  _buildTokenBadge(tokens),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP INDICATOR
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStepIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepDot(0, 'Identity'),
        _stepLine(),
        _stepDot(1, 'Personality'),
        _stepLine(),
        _stepDot(2, 'Dialogue'),
        _stepLine(),
        _stepDot(3, 'Lorebook'),
        _stepLine(),
        _stepDot(4, 'Realism'),
        _stepLine(),
        _stepDot(5, 'Review'),
        _stepLine(),
        _stepDot(6, 'Portrait & Avatars'),
      ],
    );
  }

  Widget _stepDot(int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;

    final dotColor = isActive
        ? AppColors.porchAmberOf(context)
        : AppColors.surfaceContainerOf(context);

    final borderColor = isCurrent
        ? AppColors.textPrimary(context)
        : AppColors.borderOf(context);

    final numberOrCheckColor = isActive
        ? AppColors.resolve(context, Colors.white, Colors.white)
        : AppColors.textTertiary(context);

    final labelColor = isActive
        ? AppColors.textSecondary(context)
        : AppColors.textTertiary(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            border: isCurrent
                ? Border.all(color: borderColor, width: 2)
                : Border.all(
                    color: AppColors.borderOf(context).withValues(alpha: 0.3),
                  ),
          ),
          child: Center(
            child: isActive && !isCurrent
                ? Icon(Icons.check, size: 14, color: numberOrCheckColor)
                : Text(
                    '${step + 1}',
                    style: TextStyle(fontSize: 11, color: numberOrCheckColor),
                  ),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: labelColor)),
      ],
    );
  }

  Widget _stepLine() {
    return Container(
      width: 24,
      height: 2,
      margin: const EdgeInsets.only(bottom: 14),
      color: AppColors.borderOf(context).withValues(alpha: 0.35),
    );
  }

  Widget _buildTokenBadge(int estimatedTokens) {
    final color = estimatedTokens > 4000
        ? Colors.redAccent
        : estimatedTokens > 2000
        ? Colors.orangeAccent
        : AppColors.formMasterAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.token, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '~$estimatedTokens tokens',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  NAVIGATION BUTTONS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildNavButtons({
    required int currentStep,
    String? nextLabel,
    VoidCallback? onNext,
    bool showBack = true,
  }) {
    final labels = [
      'Personality',
      'Dialogue',
      'Lorebook',
      'Realism Engine',
      'Review & Create',
    ];
    final nextText =
        nextLabel ??
        (currentStep < labels.length ? 'Next: ${labels[currentStep]}' : 'Save');

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showBack && currentStep > 0)
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _currentStep = currentStep - 1),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back', style: TextStyle(fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary(context),
                    side: BorderSide(color: AppColors.borderOf(context)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            if (showBack && currentStep > 0) const SizedBox(width: 16),
            SizedBox(
              width: 280,
              height: 52,
              child: ElevatedButton.icon(
                onPressed:
                    onNext ??
                    () {
                      // Validate on step 0 (name required)
                      if (currentStep == 0) {
                        if (_nameController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Character name is required'),
                              backgroundColor: Colors.redAccent,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                      }
                      setState(() => _currentStep = currentStep + 1);
                    },
                icon: const Icon(Icons.arrow_forward, size: 20),
                label: Text(nextText, style: const TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.porchAmberOf(context),
                  foregroundColor: AppColors.onChaosAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 0: IDENTITY
  // ═══════════════════════════════════════════════════════════════

  Widget _buildIdentityStep() {
    return Center(
      key: const ValueKey('identity'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Character Identity',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Set your character\'s name and tags. Portrait and avatars '
                'come in the final step, after your writing is safely saved.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              // Name field
              _inputLabel('Character Name', required: true),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 16,
                ),
                decoration: _inputDecoration('Enter character name'),
              ),
              const SizedBox(height: 24),

              // Tags
              _inputLabel('Tags', required: false),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._tags.map(
                    (tag) => Chip(
                      label: Text(
                        tag,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 12,
                        ),
                      ),
                      backgroundColor: AppColors.surfaceContainerOf(context),
                      side: BorderSide.none,
                      deleteIcon: Icon(
                        Icons.close,
                        size: 14,
                        color: AppColors.iconSecondary(context),
                      ),
                      onDeleted: () => setState(() => _tags.remove(tag)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tagController,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontSize: 14,
                      ),
                      decoration: _inputDecoration('Add a tag...'),
                      onSubmitted: _addTag,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => _addTag(_tagController.text),
                    icon: const Icon(
                      Icons.add_circle,
                      color: AppColors.formMasterAccent,
                    ),
                    tooltip: 'Add tag',
                  ),
                ],
              ),

              _buildNavButtons(currentStep: 0),
            ],
          ),
        ),
      ),
    );
  }

  void _addTag(String value) {
    final tag = value.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() => _tags.add(tag));
      _tagController.clear();
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 1: PERSONALITY
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPersonalityStep() {
    return Center(
      key: const ValueKey('personality'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Personality & World',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Define who your character is and the world they inhabit.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              _expandableField(
                'Description',
                _descriptionController,
                hint: 'Physical appearance, backstory, key traits...',
                maxLines: 4,
              ),
              const SizedBox(height: 20),

              _expandableField(
                'Personality',
                _personalityController,
                hint: 'How they act, speak, think...',
                maxLines: 3,
              ),
              const SizedBox(height: 20),

              _expandableField(
                'Scenario',
                _scenarioController,
                hint: 'The setting, situation, or context...',
                maxLines: 3,
              ),
              const SizedBox(height: 24),

              // Advanced Prompts (collapsed)
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Row(
                    children: [
                      Icon(
                        Icons.settings_suggest,
                        size: 18,
                        color: Colors.white38,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Advanced Prompts (optional)',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                    ],
                  ),
                  children: [
                    const SizedBox(height: 8),
                    _expandableField(
                      'System Prompt',
                      _systemPromptController,
                      hint:
                          'Instructions for the AI about how to play this character...',
                      maxLines: 4,
                    ),
                    const SizedBox(height: 16),
                    _expandableField(
                      'Post-History Instructions',
                      _postHistoryController,
                      hint:
                          'Injected after chat history, before AI response...',
                      maxLines: 3,
                    ),
                  ],
                ),
              ),

              _buildNavButtons(currentStep: 1),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 2: DIALOGUE
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDialogueStep() {
    return Center(
      key: const ValueKey('dialogue'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dialogue & Greetings',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Configure the character\'s opening message and example dialogue.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white54,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              _expandableField(
                'First Message',
                _firstMessageController,
                hint:
                    'The character\'s opening message when a conversation starts...',
                maxLines: 6,
              ),
              const SizedBox(height: 24),

              // Alternate Greetings
              Row(
                children: [
                  _inputLabel('Alternate Greetings', required: false),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        final ctrl = StyledTextController(preset: StyledTextPreset.prose);
                        ctrl.addListener(_updateTokenEstimate);
                        _altGreetingControllers.add(ctrl);
                      });
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Greeting'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.formMasterAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._altGreetingControllers.asMap().entries.map((entry) {
                final idx = entry.key;
                final ctrl = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _expandableField(
                          'Greeting ${idx + 1}',
                          ctrl,
                          hint: 'Alternative opening message...',
                          maxLines: 4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _altGreetingControllers[idx].dispose();
                            _altGreetingControllers.removeAt(idx);
                          });
                        },
                        icon: const Icon(
                          Icons.remove_circle_outline,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        tooltip: 'Remove greeting',
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 20),

              _expandableField(
                'Example Dialogue',
                _exampleDialogueController,
                hint: '<START>\n{{user}}: Hello!\n{{char}}: *smiles warmly*',
                maxLines: 6,
              ),

              _buildNavButtons(currentStep: 2),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 3: LOREBOOK
  // ═══════════════════════════════════════════════════════════════

  Widget _buildLorebookStep() {
    return Center(
      key: const ValueKey('lorebook'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lorebook',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Add world lore entries that inject context into conversations when keywords are detected.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white54,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _addLorebookEntry,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Entry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.formMasterAccent,
                      foregroundColor: AppColors.onChaosAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              if (_lorebookEntries.isEmpty)
                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No lorebook entries yet',
                          style: TextStyle(color: Colors.white38, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Add entries to inject context-aware world lore into conversations.',
                          style: TextStyle(color: Colors.white24, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ..._lorebookEntries.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final lore = entry.value;
                  return _buildLorebookEntryCard(idx, lore);
                }),

              _buildNavButtons(currentStep: 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLorebookEntryCard(int index, LorebookEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          width: 1.5,
          color: entry.constant
              ? Colors.amberAccent.withValues(alpha: 0.3)
              : entry.enabled
              ? AppColors.formMasterAccent.withValues(alpha: 0.2)
              : AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.menu_book,
                size: 14,
                color: entry.constant
                    ? Colors.amberAccent
                    : entry.enabled
                    ? AppColors.formMasterAccent
                    : Colors.white38,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.displayName,
                  style: TextStyle(
                    color: entry.enabled
                        ? Colors.white
                        : Colors.white38,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (entry.constant)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Always Active',
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (!entry.constant)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.formMasterAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Depth ${entry.stickyDepth}',
                    style: const TextStyle(
                      color: AppColors.formMasterAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Tooltip(
                message: entry.enabled
                    ? 'Disable — entry won\'t be matched'
                    : 'Enable — entry will match on its keys',
                child: Switch(
                  value: entry.enabled,
                  onChanged: (val) {
                    setState(() {
                      entry.enabled = val;
                      _updateTokenEstimate();
                    });
                  },
                  activeTrackColor: AppColors.formMasterAccent.withValues(
                    alpha: 0.5,
                  ),
                  activeThumbColor: AppColors.formMasterAccent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              IconButton(
                onPressed: () => _editLorebookEntry(index),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: Colors.white38,
                ),
                tooltip: 'Edit entry',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
              IconButton(
                onPressed: () => _deleteLorebookEntry(index),
                icon: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: Colors.redAccent,
                ),
                tooltip: 'Delete entry',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
          if (entry.key.isNotEmpty && !entry.constant) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 3,
              children: entry.keys
                  .map(
                    (k) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        k.trim(),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addLorebookEntry() async {
    final result = await showLorebookEntryDialog(context: context);
    if (result != null) {
      setState(() {
        _lorebookEntries.add(result);
        _updateTokenEstimate();
      });
    }
  }

  Future<void> _editLorebookEntry(int index) async {
    final entry = _lorebookEntries[index];
    final result = await showLorebookEntryDialog(
      context: context,
      existing: entry,
      showEnabled: true,
    );
    if (result != null) {
      setState(() {
        _lorebookEntries[index] = result;
        _updateTokenEstimate();
      });
    }
  }

  void _deleteLorebookEntry(int index) {
    setState(() {
      _lorebookEntries.removeAt(index);
      _updateTokenEstimate();
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 4: REALISM ENGINE
  // ═══════════════════════════════════════════════════════════════

  Widget _buildRealismStep() {
    return Center(
      key: const ValueKey('realism'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Realism Engine',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Set the initial state for the Realism Engine when a new conversation starts. '
                'These values will seed the relationship, emotion, and time-of-day systems.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              RealismFormSection(
                enabled: _realismEnabled,
                onEnabledChanged: (v) => setState(() => _realismEnabled = v),
                timeOfDay: _realismTimeOfDay,
                onTimeOfDayChanged: (v) =>
                    setState(() => _realismTimeOfDay = v),
                dayCount: _realismDayCount,
                onDayCountChanged: (v) => setState(() => _realismDayCount = v),
                storyStartDate: _realismStoryStartDate,
                onStoryStartDateChanged: (v) =>
                    setState(() => _realismStoryStartDate = v),
                storyStartTime: _realismStoryStartTime,
                onStoryStartTimeChanged: (v) =>
                    setState(() => _realismStoryStartTime = v),
                shortTermBond: _realismShortTermBond,
                onShortTermBondChanged: (v) =>
                    setState(() => _realismShortTermBond = v),
                longTermBond: _realismLongTermBond,
                onLongTermBondChanged: (v) =>
                    setState(() => _realismLongTermBond = v),
                trustLevel: _realismTrustLevel,
                onTrustLevelChanged: (v) =>
                    setState(() => _realismTrustLevel = v),
                emotion: _realismEmotion,
                onEmotionChanged: (v) => setState(() => _realismEmotion = v),
                emotionIntensity: _realismEmotionIntensity,
                onEmotionIntensityChanged: (v) =>
                    setState(() => _realismEmotionIntensity = v),
                nsfwCooldownEnabled: _realismNsfwCooldown,
                onNsfwCooldownChanged: (v) =>
                    setState(() => _realismNsfwCooldown = v),
                chaosModeEnabled: _realismChaosMode,
                onChaosModeChanged: (v) =>
                    setState(() => _realismChaosMode = v),
                currentTask: _realismCurrentTask,
                onCurrentTaskChanged: (v) =>
                    setState(() => _realismCurrentTask = v),
                realismVerificationEnabled: _realismVerificationEnabled,
                onRealismVerificationChanged: (v) =>
                    setState(() => _realismVerificationEnabled = v),
                realismVerificationMaxReprocesses:
                    _realismVerificationMaxReprocesses,
                onRealismVerificationMaxReprocessesChanged: (v) =>
                    setState(() => _realismVerificationMaxReprocesses = v),
                realismVerificationStrictness: _realismVerificationStrictness,
                onRealismVerificationStrictnessChanged: (v) =>
                    setState(() => _realismVerificationStrictness = v),
                needsFormSection: NeedsFormSection(
                  enabled: _realismNeedsSim,
                  onEnabledChanged: (v) => setState(() => _realismNeedsSim = v),
                  enjoysLowHygiene: _realismEnjoysLowHygiene,
                  onEnjoysLowHygieneChanged: (v) =>
                      setState(() => _realismEnjoysLowHygiene = v),
                  needsSimStrength: 1, // default, not editable in creator
                  baselineHunger: _needsBaselineHunger,
                  onBaselineHungerChanged: (v) =>
                      setState(() => _needsBaselineHunger = v),
                  baselineBladder: _needsBaselineBladder,
                  onBaselineBladderChanged: (v) =>
                      setState(() => _needsBaselineBladder = v),
                  baselineEnergy: _needsBaselineEnergy,
                  onBaselineEnergyChanged: (v) =>
                      setState(() => _needsBaselineEnergy = v),
                  baselineSocial: _needsBaselineSocial,
                  onBaselineSocialChanged: (v) =>
                      setState(() => _needsBaselineSocial = v),
                  baselineFun: _needsBaselineFun,
                  onBaselineFunChanged: (v) =>
                      setState(() => _needsBaselineFun = v),
                  baselineHygiene: _needsBaselineHygiene,
                  onBaselineHygieneChanged: (v) =>
                      setState(() => _needsBaselineHygiene = v),
                  baselineComfort: _needsBaselineComfort,
                  onBaselineComfortChanged: (v) =>
                      setState(() => _needsBaselineComfort = v),
                  decayHunger: _needsDecayHunger,
                  onDecayHungerChanged: (v) =>
                      setState(() => _needsDecayHunger = v),
                  decayBladder: _needsDecayBladder,
                  onDecayBladderChanged: (v) =>
                      setState(() => _needsDecayBladder = v),
                  decayEnergy: _needsDecayEnergy,
                  onDecayEnergyChanged: (v) =>
                      setState(() => _needsDecayEnergy = v),
                  decaySocial: _needsDecaySocial,
                  onDecaySocialChanged: (v) =>
                      setState(() => _needsDecaySocial = v),
                  decayFun: _needsDecayFun,
                  onDecayFunChanged: (v) => setState(() => _needsDecayFun = v),
                  decayHygiene: _needsDecayHygiene,
                  onDecayHygieneChanged: (v) =>
                      setState(() => _needsDecayHygiene = v),
                  decayComfort: _needsDecayComfort,
                  onDecayComfortChanged: (v) =>
                      setState(() => _needsDecayComfort = v),
                ),
              ),

              _buildNavButtons(currentStep: 4),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 5: REVIEW & CREATE
  // ═══════════════════════════════════════════════════════════════

  Widget _buildReviewStep() {
    return SingleChildScrollView(
      key: const ValueKey('review'),
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column — quick info (the portrait is made in the NEXT step,
          // after the card is safely saved).
          SizedBox(
            width: 280,
            child: Column(
              children: [
                Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: AppColors.cardOf(context),
                    border: Border.all(color: AppColors.borderOf(context)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person,
                        size: 64,
                        color: AppColors.textTertiary(context),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Portrait comes next,\nonce the card is saved',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Name
                Text(
                  _nameController.text.isEmpty
                      ? 'Unnamed'
                      : _nameController.text,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // Tags
                if (_tags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: _tags
                        .map(
                          (tag) => Chip(
                            label: Text(
                              tag,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                            backgroundColor: AppColors.surfaceContainerOf(
                              context,
                            ),
                            side: BorderSide.none,
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
                const SizedBox(height: 16),
                // Realism Engine summary
                if (_realismEnabled)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.formMasterAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.formMasterAccent.withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.psychology,
                              size: 14,
                              color: AppColors.formMasterAccent,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Realism Engine',
                              style: TextStyle(
                                color: AppColors.formMasterAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Day $_realismDayCount · ${_realismTimeOfDay.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ')}',
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 11,
                          ),
                        ),
                        if (_realismEmotion.isNotEmpty)
                          Text(
                            'Emotion: $_realismEmotion ($_realismEmotionIntensity)',
                            style: TextStyle(
                              color: AppColors.textTertiary(context),
                              fontSize: 11,
                            ),
                          ),
                        Text(
                          'Bond: $_realismShortTermBond / $_realismLongTermBond · Trust: $_realismTrustLevel',
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                // Create button — saves the card, then advances into the
                // Portrait & Avatars step (generation is post-save by design).
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _createAndAdvance,
                    icon: const Icon(Icons.check),
                    label: const Text('Create Character'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.formMasterAccent,
                      foregroundColor: AppColors.onChaosAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _currentStep = 0),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Back to Edit'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary(context),
                      side: BorderSide(color: AppColors.borderOf(context)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 32),

          // Right column — editable fields review
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Review & Edit',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Review your character card. All fields are still editable before saving.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                _reviewField(
                  'Description',
                  _descriptionController,
                  maxLines: 4,
                ),
                _reviewField(
                  'Personality',
                  _personalityController,
                  maxLines: 3,
                ),
                _reviewField('Scenario', _scenarioController, maxLines: 3),
                _reviewField(
                  'First Message',
                  _firstMessageController,
                  maxLines: 5,
                ),
                if (_exampleDialogueController.text.isNotEmpty)
                  _reviewField(
                    'Example Dialogue',
                    _exampleDialogueController,
                    maxLines: 4,
                  ),
                if (_systemPromptController.text.isNotEmpty)
                  _reviewField(
                    'System Prompt',
                    _systemPromptController,
                    maxLines: 3,
                  ),
                if (_postHistoryController.text.isNotEmpty)
                  _reviewField(
                    'Post-History Instructions',
                    _postHistoryController,
                    maxLines: 3,
                  ),

                // Alt greetings
                ..._altGreetingControllers.asMap().entries.map((entry) {
                  return _reviewField(
                    'Alt Greeting ${entry.key + 1}',
                    entry.value,
                    maxLines: 3,
                  );
                }),

                // Lorebook
                if (_lorebookEntries.isNotEmpty) ...[
                  Divider(color: AppColors.borderOf(context), height: 32),
                  Row(
                    children: [
                      const Icon(
                        Icons.menu_book,
                        color: AppColors.formMasterAccent,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Lorebook Entries',
                        style: TextStyle(
                          color: AppColors.formMasterAccent,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_lorebookEntries.length} entries',
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ..._lorebookEntries.map(
                    (entry) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.cardOf(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.formMasterAccent.withValues(
                            alpha: 0.2,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.displayName,
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (entry.key.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Keys: ${entry.key}',
                              style: const TextStyle(
                                color: AppColors.formMasterAccent,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          if (entry.content.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              entry.content,
                              style: TextStyle(
                                color: AppColors.textSecondary(context),
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewField(
    String label,
    TextEditingController controller, {
    int maxLines = 3,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.formMasterAccent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          AppTextField(
            controller: controller,
            maxLines: maxLines,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
              height: 1.5,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.formMasterAccent),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP 6: PORTRAIT & AVATARS (post-save, the shared panel)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPortraitAvatarsStep() {
    final card = _savedCard;
    if (card == null) return const SizedBox.shrink(); // unreachable guard
    return Center(
      key: const ValueKey('portrait-avatars'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Portrait & Avatars',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 10),
              // The saved chip — nothing below can lose the writing.
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.logReady.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.logReady.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    '✓ ${card.name} is saved — everything below is optional '
                    'and can\'t lose your writing',
                    style: const TextStyle(
                      color: AppColors.logReady,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              AvatarGenerationPanel(
                key: ValueKey(card.dbId),
                card: card,
                ensureCardSaved: () async => card,
                initialPrompt: _portraitPromptSeed(card.name),
                onBusyChanged: (busy) {
                  if (mounted) setState(() => _panelBusy = busy);
                },
              ),
              const SizedBox(height: 24),
              Center(
                child: SizedBox(
                  width: 280,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _panelBusy ? null : _finishAndClose,
                    icon: const Icon(Icons.check, size: 20),
                    label: const Text('Done', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.porchAmberOf(context),
                      foregroundColor: AppColors.onChaosAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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

  /// Portrait-prompt seed from the wizard's own fields: the description (the
  /// manual creator's appearance lives there), macros resolved to the name.
  String _portraitPromptSeed(String name) {
    var seed = _descriptionController.text
        .replaceAll('{{char}}', name)
        .replaceAll('{{user}}', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (seed.length > 400) seed = seed.substring(0, 400);
    if (seed.isEmpty) seed = 'character portrait of $name';
    return seed;
  }

  // ═══════════════════════════════════════════════════════════════
  //  SAVE
  // ═══════════════════════════════════════════════════════════════

  /// Review's "Create Character": persist the card (always-embedded V2 PNG —
  /// placeholder image for now, the portrait lands in the next step), then
  /// advance into Portrait & Avatars holding the saved card.
  Future<void> _createAndAdvance() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Character name is required'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);

    try {
      // Always build extensions — even when realism is disabled — so that
      // any configured values survive a round-trip through PNG save/load.
      // The realismEnabled flag controls whether the engine *uses* them at
      // runtime, not whether they are persisted.
      final fpExt = FrontPorchExtensions(
        realismEnabled: _realismEnabled,
        shortTermBond: _realismShortTermBond,
        longTermBond: _realismLongTermBond,
        trustLevel: _realismTrustLevel,
        dayCount: _realismDayCount,
        timeOfDay: _realismTimeOfDay,
        storyStartDate: _realismStoryStartDate,
        storyStartTime: _realismStoryStartTime,
        characterEmotion: _realismEmotion,
        emotionIntensity: _realismEmotionIntensity,
        nsfwCooldownEnabled: _realismNsfwCooldown,
        passageOfTimeEnabled: true, // default on; user can toggle later
        chaosModeEnabled: _realismChaosMode,
        needsSimEnabled: _realismNeedsSim,
        enjoysLowHygiene: _realismEnjoysLowHygiene,
        currentTask: _realismCurrentTask,
        realismVerificationEnabled: _realismVerificationEnabled,
        realismVerificationMaxReprocesses: _realismVerificationMaxReprocesses,
        realismVerificationStrictness: _realismVerificationStrictness,
        realismNeedsDirectorAuthority: _realismNeedsDirectorAuthority,
        needsBaselineHunger: _needsBaselineHunger,
        needsBaselineBladder: _needsBaselineBladder,
        needsBaselineEnergy: _needsBaselineEnergy,
        needsBaselineSocial: _needsBaselineSocial,
        needsBaselineFun: _needsBaselineFun,
        needsBaselineHygiene: _needsBaselineHygiene,
        needsBaselineComfort: _needsBaselineComfort,
        needsDecayHunger: _needsDecayHunger,
        needsDecayBladder: _needsDecayBladder,
        needsDecayEnergy: _needsDecayEnergy,
        needsDecaySocial: _needsDecaySocial,
        needsDecayFun: _needsDecayFun,
        needsDecayHygiene: _needsDecayHygiene,
        needsDecayComfort: _needsDecayComfort,
      );

      fpExt.ensureStableId();

      final card = CharacterCard(
        name: name,
        description: _descriptionController.text,
        personality: _personalityController.text,
        scenario: _scenarioController.text,
        firstMessage: _firstMessageController.text,
        mesExample: _exampleDialogueController.text,
        systemPrompt: _systemPromptController.text,
        postHistoryInstructions: _postHistoryController.text,
        alternateGreetings: _altGreetingControllers
            .map((c) => c.text)
            .where((t) => t.trim().isNotEmpty)
            .toList(),
        tags: List.from(_tags),
        lorebook: _lorebookEntries.isNotEmpty
            ? Lorebook(entries: List.from(_lorebookEntries))
            : null,
        frontPorchExtensions: fpExt,
      );

      // Determine PNG path — always write a PNG so card data (including
      // Realism Engine extensions) can be embedded and survive app restarts.
      // Placeholder image for now: the Portrait & Avatars step overwrites the
      // pixels in place (same basename — folders key members on it).
      final charDir = storage.charactersDir;
      if (!charDir.existsSync()) charDir.createSync(recursive: true);
      final epoch = DateTime.now().millisecondsSinceEpoch;
      final safeName = name
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(' ', '_');
      final imagePath = p.join(charDir.path, '${safeName}_$epoch.png');
      card.imagePath = imagePath;
      final v2Service = V2CardService();
      await v2Service.saveCardAsPng(card, imagePath, null);
      debugPrint(
        '[CreateCharacter] Saved PNG with extensions: '
        'realism=${fpExt.realismEnabled}, bond=${fpExt.shortTermBond}, '
        'trust=${fpExt.trustLevel}, emotion=${fpExt.characterEmotion}',
      );

      // Add to repository
      await repo.addCharacter(card);

      if (mounted) {
        setState(() {
          // p12 flow: advance to the Portrait & Avatars step (6) instead of
          // resetting to step 0. The old reset block (including Rawhide's
          // _realismStoryStartDate/_realismStoryStartTime resets) is obsolete
          // here — the wizard continues to the avatar panel and then closes, so
          // there is nothing to reset for a fresh start in this path.
          _savedCard = card;
          _currentStep = 6;
        });
      }
    } catch (e) {
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

  /// Final step's "Done": back to home and reset the wizard for a fresh run.
  void _finishAndClose() {
    final name = _savedCard?.name ?? 'Character';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle,
              color: AppColors.logReady,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text('$name created successfully!'),
          ],
        ),
        backgroundColor: AppColors.surfaceContainerOf(context),
        behavior: SnackBarBehavior.floating,
      ),
    );
    // CreateCharacterPage lives as a tab in MainLayout (not pushed as a
    // route), so Navigator.pop() would pop the entire scaffold → black
    // screen. Instead navigate back to the home tab and reset the form.
    Provider.of<AppState>(context, listen: false).setIndex(0);
    setState(() {
      _currentStep = 0;
      _savedCard = null;
      _panelBusy = false;
      _nameController.clear();
      _descriptionController.clear();
      _personalityController.clear();
      _scenarioController.clear();
      _firstMessageController.clear();
      _exampleDialogueController.clear();
      _systemPromptController.clear();
      _postHistoryController.clear();
      for (final c in _altGreetingControllers) {
        c.dispose();
      }
      _altGreetingControllers.clear();
      _lorebookEntries.clear();
      _tags.clear();
      _realismEnabled = false;
      _realismTimeOfDay = 'morning';
      _realismDayCount = 1;
      _realismShortTermBond = 0;
      _realismLongTermBond = 0;
      _realismTrustLevel = 0;
      _realismEmotion = '';
      _realismEmotionIntensity = 'mild';
      _realismNsfwCooldown = false;
      _realismChaosMode = false;
      _realismCurrentTask = '';
      _realismVerificationEnabled = false;
      _realismVerificationMaxReprocesses = 1;
      _realismVerificationStrictness = 3;
      _realismNeedsDirectorAuthority = false;
      _tokenNotifier.value = 0;
    });
  }

  // ═══════════════════════════════════════════════════════════════
  //  SHARED HELPERS
  // ═══════════════════════════════════════════════════════════════

  Widget _inputLabel(String text, {bool required = false}) {
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            color: AppColors.textPrimary(context),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (required)
          const Text(' *', style: TextStyle(color: Colors.redAccent)),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: AppColors.textTertiary(context),
        fontSize: 14,
      ),
      filled: true,
      fillColor: AppColors.surfaceContainerOf(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.borderOf(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.porchAmberOf(context)),
      ),
      contentPadding: const EdgeInsets.all(14),
    );
  }

  Widget _expandableField(
    String label,
    TextEditingController controller, {
    String hint = '',
    int maxLines = 3,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _inputLabel(label),
            const Spacer(),
            IconButton(
              onPressed: () => showExpandedEditorDialog(
                context: context,
                title: label,
                controller: controller,
              ),
              icon: const Icon(
                Icons.open_in_full,
                size: 16,
                color: Colors.white38,
              ),
              tooltip: 'Expand editor',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 6),
        AppTextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            height: 1.5,
          ),
          spellCheckConfiguration: AppTextField.platformSpellCheck(),
          decoration: _inputDecoration(hint),
        ),
      ],
    );
  }

}
