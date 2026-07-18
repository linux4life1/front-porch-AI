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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state_engine.dart';
import 'package:front_porch_ai/ui/character_creator/steps/setup_step.dart';
import 'package:front_porch_ai/ui/character_creator/steps/mode_select_step.dart';
import 'package:front_porch_ai/ui/character_creator/steps/quick_config_step.dart';
import 'package:front_porch_ai/ui/character_creator/steps/guided_config_step.dart';
import 'package:front_porch_ai/ui/character_creator/steps/automated_config_step.dart';
import 'package:front_porch_ai/ui/character_creator/steps/generating_step.dart';
import 'package:front_porch_ai/ui/character_creator/steps/realism_step.dart';
import 'package:front_porch_ai/ui/character_creator/steps/review_step.dart';

/// Thin shell for the AI character creator wizard (~200 LOC per Stage 4 plan).
/// Delegates all state (60+ fields, prefs, load/save, step, gen) to CreatorState (ChangeNotifier).
/// Step content via extracted widgets in steps/ (review_step largest, extracted early).
/// Reusable widgets in widgets/ (backend_chip, mode_card, styled_text_field auto-save).
/// UI consistency (non-negotiable): exact top-bar horizontal step dots+labels+lines in AppBar (driven by simple currentStep),
/// AnimatedSwitcher for step content, _buildNavButtons at bottom of flow.
/// No side menus/tab bars/free-jumping. AppColors exclusively (resolve, *Of helpers, withValues). const where possible.
/// All old god content deleted as part of extraction (deletion part of task).
class CharacterCreatorPage extends StatefulWidget {
  const CharacterCreatorPage({super.key});

  @override
  State<CharacterCreatorPage> createState() => _CharacterCreatorPageState();
}

class _CharacterCreatorPageState extends State<CharacterCreatorPage> {
  late final CreatorState creatorState = CreatorState();

  void _onCreatorStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    creatorState.loadSavedState();
    creatorState.addListener(_onCreatorStateChanged);

    // Ensure local models are scanned for the KoboldCpp picker in Setup (was never called before).
    // Also refresh the app-wide ModelManager so the picker has data on entry.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final storage = Provider.of<StorageService>(context, listen: false);
        creatorState.scanLocalModels(storage);
        creatorState.scanLocalPresets(storage);
        creatorState.initLocalSettingsControllers(storage);
        final modelManager = Provider.of<ModelManager>(context, listen: false);
        modelManager.refreshModels();
        // If a last used local model exists, preselect it for the picker UI.
        if (creatorState.selectedLocalModelPath.isEmpty &&
            storage.lastUsedModelPath != null &&
            storage.lastUsedModelPath!.isNotEmpty) {
          creatorState.selectedLocalModelPath = storage.lastUsedModelPath!;
          creatorState.notify();
        }

        // Also eagerly load remote models (for API / oMLX pickers) so the list isn't empty on entry.
        final llm = Provider.of<LLMProvider>(context, listen: false);
        if (!llm.hasManagedProcess) {
          // Fire and forget; loadAvailableModels does its own notify + sets initial selection.
          creatorState.loadAvailableModels(llm);
        }
      } catch (_) {
        // Providers may not be ready in some edge cases; non-fatal.
      }
    });
  }

  @override
  void dispose() {
    creatorState.removeListener(_onCreatorStateChanged);
    creatorState.disposeControllers();
    super.dispose();
  }

  /// Show confirmation dialog, then reset all fields if user confirms.
  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(ctx),
        title: Text(
          'Start Over?',
          style: TextStyle(color: AppColors.textPrimary(ctx)),
        ),
        content: Text(
          'This will clear every field and generated data. This cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.resolve(
                ctx,
                Colors.orangeAccent,
                Colors.orange.shade700,
              ),
            ),
            child: const Text('Clear Everything'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      creatorState.resetAllFields();
    }
  }

  /// Persist the finished character, then show a result SnackBar and close the
  /// wizard on success. The engine returns the outcome (it has no context); the
  /// page owns the messaging and navigation.
  Future<void> _saveAndFinish() async {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final name = creatorState.generatedCard?.name ?? 'Character';

    final ok = await creatorState.saveCharacter(repo: repo, storage: storage);
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$name created successfully!',
            style: TextStyle(color: AppColors.textPrimary(context)),
          ),
          backgroundColor: AppColors.surfaceContainerOf(context),
          behavior: SnackBarBehavior.floating,
        ),
      );
      navigator.pop();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            creatorState.engineError ?? 'Failed to save character.',
            style: TextStyle(color: AppColors.textPrimary(context)),
          ),
          backgroundColor: AppColors.resolve(
            context,
            Colors.red.shade800,
            Colors.red.shade700,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // Step indicator (exact pattern from create_character_page.dart: horizontal dots + labels + connecting lines in AppBar, driven by creatorState.currentStep int).
  Widget _buildStepIndicator(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepDot(context, 0, 'Setup'),
        _stepLine(context),
        _stepDot(context, 1, 'Mode'),
        _stepLine(context),
        _stepDot(context, 2, 'Configure'),
        _stepLine(context),
        _stepDot(context, 3, 'Generate'),
        _stepLine(context),
        _stepDot(context, 4, 'Realism'),
        _stepLine(context),
        _stepDot(context, 5, 'Review'),
      ],
    );
  }

  Widget _stepDot(BuildContext context, int step, String label) {
    final isActive = creatorState.currentStep >= step;
    final isCurrent = creatorState.currentStep == step;
    final dotColor = isActive
        ? AppColors.porchAmberOf(context)
        : AppColors.surfaceContainerOf(context);
    final borderColor = isCurrent
        ? AppColors.textPrimary(context)
        : AppColors.borderOf(context);
    final numberOrCheckColor = isActive
        ? AppColors.onChaosAccent
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

  Widget _stepLine(BuildContext context) {
    return Container(
      width: 24,
      height: 2,
      margin: const EdgeInsets.only(bottom: 14),
      color: AppColors.borderOf(context).withValues(alpha: 0.35),
    );
  }

  // _buildNavButtons at the bottom of each step (per wizard flow; modeled exactly on create_character_page.dart).
  Widget _buildNavButtons({
    required int currentStep,
    String? nextLabel,
    VoidCallback? onNext,
    bool showBack = true,
  }) {
    final labels = ['Mode', 'Configure', 'Generate', 'Realism', 'Review'];
    final nextText =
        nextLabel ??
        (currentStep < labels.length
            ? 'Next: ${labels[currentStep]}'
            : 'Save & Finish');

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
                  onPressed: () => creatorState.currentStep = currentStep - 1,
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
                      if (currentStep == 2) {
                        creatorState.generateFromMode(
                          llmProvider: Provider.of<LLMProvider>(
                            context,
                            listen: false,
                          ),
                          storage: Provider.of<StorageService>(
                            context,
                            listen: false,
                          ),
                          personaService: Provider.of<UserPersonaService>(
                            context,
                            listen: false,
                          ),
                          imageService: Provider.of<ImageGenService>(
                            context,
                            listen: false,
                          ),
                        );
                        return;
                      }
                      if (currentStep == 5) {
                        _saveAndFinish();
                        return;
                      }
                      creatorState.currentStep = currentStep + 1;
                    },
                icon: Icon(
                  currentStep >= 5 ? Icons.check : Icons.arrow_forward,
                  size: 20,
                ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: creatorState.isGenerating
              ? null
              : () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Icon(
              Icons.auto_awesome,
              color: AppColors.resolve(
                context,
                Colors.amberAccent,
                Colors.amber.shade700,
              ),
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              'AI Character Creator',
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            const Spacer(),
            _buildStepIndicator(context),
          ],
        ),
        actions: [
          if (!creatorState.isGenerating)
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
      body: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: creatorState.currentStep == 0
                  ? SetupStep(state: creatorState)
                  : creatorState.currentStep == 1
                  ? ModeSelectStep(state: creatorState)
                  : creatorState.currentStep == 2
                  ? (creatorState.creatorMode == CreatorMode.guided
                        ? GuidedConfigStep(state: creatorState)
                        : creatorState.creatorMode == CreatorMode.quick
                        ? QuickConfigStep(state: creatorState)
                        : AutomatedConfigStep(state: creatorState))
                  : creatorState.currentStep == 3
                  ? GeneratingStep(state: creatorState)
                  : creatorState.currentStep == 4
                  ? RealismStep(state: creatorState)
                  : ReviewStep(state: creatorState),
            ),
          ),
          _buildNavButtons(currentStep: creatorState.currentStep),
        ],
      ),
    );
  }
}

// (End of thin shell. Stage 4 god-file modularization complete: creator_state.dart + 8 steps/ + 3 widgets/. All prior ~8500 LOC god content in this file deleted. 0 new private methods in shell. AppColors + UI wizard consistency + flutter_lints + Provider/ChangeNotifier preserved. Tree runnable after gates.)
