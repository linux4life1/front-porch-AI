// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/steps.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Studio wizard: wiki → lorebook cards → a real World in the library.
class WorldFromWikiPage extends StatefulWidget {
  const WorldFromWikiPage({super.key});

  @override
  State<WorldFromWikiPage> createState() => _WorldFromWikiPageState();
}

class _WorldFromWikiPageState extends State<WorldFromWikiPage> {
  late final CreatorState creatorState = CreatorState();
  late final WorldFromWikiState worldState = WorldFromWikiState();

  void _tick() {
    if (mounted) setState(() {});
  }

  void _onCreator() {
    _tick();
    if (!mounted || worldState.currentStep != 0) return;
    final llm = Provider.of<LLMProvider>(context, listen: false);
    worldState.refreshToolsGate(llm: llm, creator: creatorState);
  }

  @override
  void initState() {
    super.initState();
    creatorState.loadSavedState();
    creatorState.addListener(_onCreator);
    worldState.addListener(_tick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final storage = Provider.of<StorageService>(context, listen: false);
        creatorState.scanLocalModels(storage);
        creatorState.scanLocalPresets(storage);
        creatorState.initLocalSettingsControllers(storage);
        final modelManager = Provider.of<ModelManager>(context, listen: false);
        modelManager.refreshModels();
        if (creatorState.selectedLocalModelPath.isEmpty &&
            storage.lastUsedModelPath != null &&
            storage.lastUsedModelPath!.isNotEmpty) {
          creatorState.selectedLocalModelPath = storage.lastUsedModelPath!;
        }
        final llm = Provider.of<LLMProvider>(context, listen: false);
        if (!llm.hasManagedProcess) {
          creatorState.loadAvailableModels(llm);
        }
        final saved = storage.webSearchSettings.savedWikiUrls;
        if (worldState.wikiUrl.isEmpty && saved.isNotEmpty) {
          worldState.wikiUrl = saved.first;
        }
        worldState.refreshToolsGate(llm: llm, creator: creatorState);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    creatorState.removeListener(_onCreator);
    worldState.removeListener(_tick);
    creatorState.disposeControllers();
    worldState.disposeControllers();
    super.dispose();
  }

  Future<void> _saveAndFinish() async {
    final repo = Provider.of<WorldRepository>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await worldState.save(repo);
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${worldState.nameController.text.trim()} saved to Worlds.',
          ),
        ),
      );
      navigator.pop();
    }
  }

  Widget _stepDot(BuildContext context, int step, String label) {
    final isActive = worldState.currentStep >= step;
    final isCurrent = worldState.currentStep == step;
    final dotColor = isActive
        ? AppColors.porchAmberOf(context)
        : AppColors.surfaceContainerOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            border: Border.all(
              color: isCurrent
                  ? AppColors.textPrimary(context)
                  : AppColors.borderOf(context).withValues(alpha: 0.3),
              width: isCurrent ? 2 : 1,
            ),
          ),
          child: Center(
            child: isActive && !isCurrent
                ? Icon(Icons.check, size: 14, color: AppColors.onChaosAccent)
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      color: isActive
                          ? AppColors.onChaosAccent
                          : AppColors.textTertiary(context),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive
                ? AppColors.textSecondary(context)
                : AppColors.textTertiary(context),
          ),
        ),
      ],
    );
  }

  Widget _stepLine(BuildContext context) {
    return Container(
      width: 20,
      height: 2,
      margin: const EdgeInsets.only(bottom: 14),
      color: AppColors.borderOf(context).withValues(alpha: 0.35),
    );
  }

  Widget _nav() {
    final step = worldState.currentStep;
    final busy = worldState.busy;
    String nextLabel;
    VoidCallback? onNext;
    switch (step) {
      case 0:
        nextLabel = 'Next: Book';
        onNext = worldState.toolsAdvertised
            ? () {
                worldState.currentStep = 1;
                worldState.notify();
              }
            : null;
      case 1:
        nextLabel = worldState.lorebooksOn ? 'Scout wiki' : 'Next: Preview';
        onNext = busy
            ? null
            : () {
                if (!worldState.lorebooksOn) {
                  worldState.currentStep = 4;
                  worldState.notify();
                  return;
                }
                worldState.scout(
                  llm: Provider.of<LLMProvider>(context, listen: false),
                  creator: creatorState,
                );
              };
      case 2:
        nextLabel = 'Write ${worldState.signed.length} cards';
        onNext = busy || worldState.signed.isEmpty
            ? null
            : () {
                worldState.write(
                  llm: Provider.of<LLMProvider>(context, listen: false),
                  creator: creatorState,
                );
              };
      case 3:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (worldState.writing)
                ElevatedButton.icon(
                  key: const Key('world-from-wiki-stop-nav'),
                  onPressed: worldState.abortWrite,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('Stop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.porchAmberOf(context),
                    foregroundColor: AppColors.onChaosAccent,
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: () {
                    worldState.currentStep = 2;
                    worldState.notify();
                  },
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back'),
                ),
            ],
          ),
        );
      default:
        nextLabel = 'Save World';
        onNext = busy ? null : _saveAndFinish;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (step > 0 && step != 3)
            OutlinedButton.icon(
              onPressed: busy
                  ? null
                  : () {
                      worldState.currentStep = step - 1;
                      worldState.notify();
                    },
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back'),
            ),
          if (step > 0 && step != 3) const SizedBox(width: 16),
          SizedBox(
            width: 280,
            height: 48,
            child: ElevatedButton.icon(
              key: const Key('world-from-wiki-next'),
              onPressed: onNext,
              icon: Icon(step >= 4 ? Icons.check : Icons.arrow_forward),
              label: Text(nextLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.porchAmberOf(context),
                foregroundColor: AppColors.onChaosAccent,
              ),
            ),
          ),
        ],
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
          icon: Icon(worldState.writing ? Icons.stop : Icons.arrow_back),
          tooltip: worldState.writing ? 'Stop' : 'Back',
          onPressed: worldState.writing
              ? worldState.abortWrite
              : () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Icon(
              Icons.menu_book_outlined,
              color: AppColors.porchAmberOf(context),
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              'World from Wiki',
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            const Spacer(),
            _stepDot(context, 0, 'Setup'),
            _stepLine(context),
            _stepDot(context, 1, 'Book'),
            _stepLine(context),
            _stepDot(context, 2, 'Review'),
            _stepLine(context),
            _stepDot(context, 3, 'Write'),
            _stepLine(context),
            _stepDot(context, 4, 'Preview'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (worldState.currentStep == 0 && !worldState.toolsAdvertised)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Text(
                kWorldFromWikiToolsCopy,
                key: const Key('world-from-wiki-tools-copy'),
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  height: 1.4,
                ),
              ),
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: worldState.currentStep == 0
                  ? SetupStep(state: creatorState)
                  : worldState.currentStep == 1
                  ? WorldFromWikiBookStep(state: worldState)
                  : worldState.currentStep == 2
                  ? WorldFromWikiReviewStep(state: worldState)
                  : worldState.currentStep == 3
                  ? WorldFromWikiWriteStep(state: worldState)
                  : WorldFromWikiPreviewStep(state: worldState),
            ),
          ),
          _nav(),
        ],
      ),
    );
  }
}
