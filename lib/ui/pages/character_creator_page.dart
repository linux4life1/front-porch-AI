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
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/steps/steps.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/services.dart';

/// AI character creator wizard. Delegates state to [CreatorState].
/// Top-bar [CreatorStepIndicator], [AnimatedSwitcher] for step content,
/// [CreatorNavBar] at the bottom. No side menus, tab bars, or free-jumping.
/// Wrapped in [CreatorTheme] so every Material widget inside follows the
/// studio palette (docs/design/creator-ui-spec.md).
class CharacterCreatorPage extends StatefulWidget {
  const CharacterCreatorPage({super.key, this.seed});

  /// "Make a Character" → AI Assist: starts Quick mode from a persona.
  final PersonaCharacterSeed? seed;

  @override
  State<CharacterCreatorPage> createState() => _CharacterCreatorPageState();
}

class _CharacterCreatorPageState extends State<CharacterCreatorPage> {
  late final CreatorState creatorState = CreatorState();

  /// Set once Save has written the card, so this page stops counting as
  /// unsaved while it asks about the tab it is about to switch away from.
  bool _saved = false;

  void _onCreatorStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    if (seed != null) {
      creatorState.applyPersonaSeed(seed);
    } else {
      creatorState.loadSavedState();
    }
    creatorState.addListener(_onCreatorStateChanged);

    // Ensure local models are scanned for the KoboldCpp picker in Setup (was never called before).
    // Also refresh the app-wide ModelManager so the picker has data on entry.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final storage = Provider.of<StorageService>(context, listen: false);
        creatorState.seedRealismFromPorchLife(storage);
        // The templates folder; the Mode step lists it (built-ins until then).
        creatorState.templates.library = ChargenTemplateLibrary.under(
          storage.rootPath,
        );
        creatorState.templates.refresh();
        creatorState.scanLocalModels(storage);
        creatorState.scanLocalPresets(storage);
        creatorState.initLocalSettingsControllers(storage);
        final modelManager = Provider.of<ModelManager>(context, listen: false);
        modelManager.refreshModels();
        // If a last used local model exists, preselect it for the picker UI.
        if (creatorState.selectedLocalModelPath.isEmpty &&
            storage.backendSettings.lastUsedModelPath != null &&
            storage.backendSettings.lastUsedModelPath!.isNotEmpty) {
          creatorState.selectedLocalModelPath =
              storage.backendSettings.lastUsedModelPath!;
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
        title: Row(
          spacing: 10,
          children: [
            Icon(
              Icons.note_add_outlined,
              size: 22,
              color: StudioColors.amberOf(ctx),
            ),
            const Text('Start Over?'),
          ],
        ),
        content: const Text(
          'This will clear every field and generated data. This cannot be undone.',
        ),
        actions: [
          SizedBox(
            height: 44,
            child: TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                foregroundColor: StudioColors.proseOf(ctx),
              ),
              child: const Text('Cancel'),
            ),
          ),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: StudioColors.badOf(ctx),
                foregroundColor: StudioColors.amberInkOf(ctx),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Clear Everything',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
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
  ///
  /// The wizard is pushed over whichever page the sidebar was showing, so a
  /// bare pop lands there (User Personas, Settings...). Like the manual
  /// creator's Done, it switches the main screen to Home first, where the new
  /// character now sits.
  Future<void> _saveAndFinish() async {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    final appState = Provider.of<AppState>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final name = creatorState.generatedCard?.name ?? 'Character';

    final ok = await creatorState.saveCharacter(repo: repo, storage: storage);
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(characterCreatedSnackBar(context, name));
      _saved = true;
      // Already on Home: leave it as it is (a second setIndex(0) would
      // read as a Home re-tap and close the open folder). The tab underneath
      // may hold its own unsaved draft; keeping it skips the switch.
      if (appState.selectedIndex != 0 &&
          await UnsavedChanges.instance.confirmLeave(context)) {
        appState.setIndex(0);
      }
      navigator.pop();
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            creatorState.engineError ?? 'Failed to save character.',
            // Amber ink reads on `bad` in both themes: dark on dark mode's
            // bright red, near-white on light mode's deep red.
            style: TextStyle(color: StudioColors.amberInkOf(context)),
          ),
          backgroundColor: StudioColors.badOf(context),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static const _stepLabels = [
    'Setup',
    'Mode',
    'Configure',
    'Generate',
    'Profile',
    'Greetings',
    'Realism',
    'Review',
  ];

  /// The last step's index; its Next is "Save & Finish".
  static const _lastStep = 7;

  /// Next on the current step: Configure starts the generation (it stops on
  /// Profile), Profile writes the rest (once), the last step saves, every
  /// other step moves one on.
  void _next() {
    final step = creatorState.currentStep;
    if (step == 4 && !creatorState.profile.completed) {
      creatorState.continueGeneration(
        llmProvider: Provider.of<LLMProvider>(context, listen: false),
      );
      return;
    }
    if (step == 2) {
      creatorState.generateFromMode(
        llmProvider: Provider.of<LLMProvider>(context, listen: false),
        storage: Provider.of<StorageService>(context, listen: false),
        personaService: Provider.of<UserPersonaService>(context, listen: false),
      );
      return;
    }
    if (step == _lastStep) {
      _saveAndFinish();
      return;
    }
    creatorState.currentStep = step + 1;
  }

  Widget _navBar() {
    final step = creatorState.currentStep;
    // Same lock the AppBar's back arrow and reset action already take. Without
    // it, Back → Generate started a SECOND generation over the first (only the
    // newest one is reachable from Abort, and whichever finished last stomped
    // the card + review fields), and Next jumped to the Realism step, which
    // reports "Generation failed" for a null card while the first is still
    // streaming. Abort Generation on the step itself remains the way out.
    // A greeting being written (or the outfit being re-read), and a
    // profile rewrite or facts re-read, hold them the same way; that card's
    // Stop is the way out. The Review rewrites lock only their own card
    // (the spec's "States"). The AppBar keeps today's lock: leaving or
    // starting over stops the write instead.
    final busy =
        creatorState.isGenerating ||
        creatorState.greetings.busy ||
        creatorState.profile.busy;
    return CreatorNavBar(
      busy: busy,
      showBack: step > 0,
      onBack: () => creatorState.currentStep = step - 1,
      onNext: _next,
      nextLabel: step < _lastStep
          ? 'Next: ${_stepLabels[step + 1]}'
          : 'Save & Finish',
      isLast: step >= _lastStep,
    );
  }

  Widget _stepBody() => switch (creatorState.currentStep) {
    0 => SetupStep(state: creatorState),
    1 => ModeSelectStep(state: creatorState),
    2 => switch (creatorState.creatorMode) {
      CreatorMode.guided => GuidedConfigStep(state: creatorState),
      CreatorMode.quick => QuickConfigStep(state: creatorState),
      _ => AutomatedConfigStep(state: creatorState),
    },
    3 => GeneratingStep(state: creatorState),
    4 => ProfileStep(state: creatorState),
    5 => GreetingsStep(state: creatorState),
    6 => RealismStep(state: creatorState),
    _ => ReviewStep(state: creatorState),
  };

  /// The typed inputs are kept in preferences; a generated character is
  /// not, until Save.
  @override
  Widget build(BuildContext context) => UnsavedChangesGuard(
    isDirty: () => !_saved && creatorState.generatedCard != null,
    child: CreatorTheme(child: Builder(builder: _scaffold)),
  );

  Widget _scaffold(BuildContext context) {
    final line = StudioColors.lineOf(context);
    return Scaffold(
      backgroundColor: StudioColors.bgOf(context),
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: StudioColors.sideOf(context),
        shape: Border(bottom: BorderSide(color: line)),
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          spacing: 14,
          children: [
            SizedBox.square(
              dimension: 40,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.arrow_back),
                color: StudioColors.proseOf(context),
                onPressed: creatorState.isGenerating
                    ? null
                    : () => Navigator.of(context).maybePop(),
              ),
            ),
            Icon(
              Icons.auto_awesome,
              color: StudioColors.amberOf(context),
              size: 22,
            ),
            Text(
              'AI Character Creator',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: StudioColors.inkOf(context),
              ),
            ),
            const Spacer(),
            CreatorStepIndicator(
              labels: _stepLabels,
              current: creatorState.currentStep,
            ),
          ],
        ),
        actions: [
          if (!creatorState.isGenerating)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Tooltip(
                message: 'Start a new character (clears all fields)',
                child: SizedBox.square(
                  dimension: 40,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.note_add_outlined, size: 22),
                    color: StudioColors.proseOf(context),
                    onPressed: _confirmReset,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _stepBody(),
            ),
          ),
          _navBar(),
        ],
      ),
    );
  }
}
