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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart' show Pockets;
import 'package:front_porch_ai/ui/avatar_creation/avatar_generation_panel.dart';
import 'package:front_porch_ai/ui/dialogs/lorebook_entry_dialog.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/providers/app_state.dart';

part 'create_character_page.save.dart';
part 'create_character_page.step_lorebook.dart';
part 'create_character_page.step_portrait.dart';
part 'create_character_page.step_realism.dart';
part 'create_character_page.step_review.dart';
part 'create_character_page.steps_core.dart';

/// Manual character creator — 7-step wizard.
///
/// Step 0: Identity (name, tags)
/// Step 1: Personality (description, personality, scenario, advanced prompts)
/// Step 2: Dialogue (first message, alt greetings, example dialogues)
/// Step 3: Lorebook (CRUD)
/// Step 4: Porch Life + Realism Engine (wardrobe, time, chaos, engine seeds)
/// Step 5: Review & Create (the card is SAVED advancing out of here)
/// Step 6: Portrait & Avatars — the shared AvatarGenerationPanel (phase #12);
///         post-save by design, so a failed generation can't lose the writing.
class CreateCharacterPage extends StatefulWidget {
  const CreateCharacterPage({super.key});

  @override
  State<CreateCharacterPage> createState() => _CreateCharacterPageState();
}

class _CreateCharacterPageState extends State<CreateCharacterPage> {
  /// Re-exposes the protected [setState] for the `part of` extensions
  /// (`create_character_page.*.dart`). Same bridge as settings_page,
  /// chat_page and the group wizard.
  void rebuildState(VoidCallback fn) => setState(fn);

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
  // AND-gated at chat start (card && Porch Life global). Default true so
  // a new card does not silently veto Needs — the form used to hide this
  // toggle unless the engine was on, so every manual create baked false.
  bool _realismNeedsSim = true;
  bool _realismEnjoysLowHygiene = false;

  /// Long-term ambitions (approved sketch §4) — a list, not newline text.
  List<String> _realismAmbitions = const [];
  List<String> _realismPlanLines = const [];
  String _realismOccupation = '';
  String _realismHours = '';
  List<String> _realismLikes = const [];
  List<String> _realismDislikes = const [];
  List<String> _realismIntimateInto = const [];
  List<String> _realismIntimateNotInto = const [];

  /// Starting Pockets & Wardrobe as chip text (`sundress (rain-soaked)`).
  /// [Pockets] owns the conversion to and from the card's `{name, state}` map.
  List<String> _realismWorn = const [];
  List<String> _realismCarrying = const [];
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
        _stepDot(4, 'Porch Life'),
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
      'Porch Life',
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


}
