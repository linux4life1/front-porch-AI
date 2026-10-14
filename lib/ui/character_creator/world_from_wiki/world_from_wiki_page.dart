// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/steps.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// Studio wizard: wiki → lorebook cards → a real World in the library.
class WorldFromWikiPage extends StatefulWidget {
  const WorldFromWikiPage({super.key});

  @override
  State<WorldFromWikiPage> createState() => _WorldFromWikiPageState();
}

class _WorldFromWikiPageState extends State<WorldFromWikiPage> {
  late final CreatorState creatorState = CreatorState();
  late final WorldFromWikiState worldState = WorldFromWikiState();
  late final ChatService _chat;
  late final LLMProvider _llm;

  void _tick() {
    if (mounted) setState(() {});
  }

  /// Chat's tool check moved (started, answered) or the backend changed.
  void _readToolsGate() {
    if (!mounted || worldState.currentStep != 0) return;
    worldState.refreshToolsGate(chat: _chat, llm: _llm, creator: creatorState);
  }

  void _onToolCheck() => _readToolsGate();

  void _onCreator() {
    _tick();
    _readToolsGate();
  }

  @override
  void initState() {
    super.initState();
    _chat = Provider.of<ChatService>(context, listen: false);
    _llm = Provider.of<LLMProvider>(context, listen: false);
    creatorState.loadSavedState();
    creatorState.addListener(_onCreator);
    worldState.addListener(_tick);
    _chat.addListener(_onToolCheck);
    _llm.addListener(_onToolCheck);
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
            storage.backendSettings.lastUsedModelPath != null &&
            storage.backendSettings.lastUsedModelPath!.isNotEmpty) {
          creatorState.selectedLocalModelPath =
              storage.backendSettings.lastUsedModelPath!;
        }
        final llm = Provider.of<LLMProvider>(context, listen: false);
        if (!llm.hasManagedProcess) {
          creatorState.loadAvailableModels(llm);
        }
        final saved = storage.webSearchSettings.savedWikiUrls;
        if (worldState.wikiUrl.isEmpty && saved.isNotEmpty) {
          worldState.wikiUrl = saved.first;
        }
      } catch (_) {}
      _readToolsGate();
    });
  }

  @override
  void dispose() {
    _chat.removeListener(_onToolCheck);
    _llm.removeListener(_onToolCheck);
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

  Widget _nav() {
    final step = worldState.currentStep;
    final busy = worldState.busy;
    String nextLabel;
    VoidCallback? onNext;
    switch (step) {
      case 0:
        nextLabel = 'Next: Book';
        onNext = worldState.toolsReady
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
        // Writing: Stop in `bad` (the spec's outlined action); stopped: Back.
        return Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 24),
          child: Center(
            child: worldState.writing
                ? SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      key: const Key('world-from-wiki-stop-nav'),
                      onPressed: worldState.abortWrite,
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text(
                        'Stop',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: StudioColors.badOf(context),
                        side: BorderSide(
                          color: StudioColors.badOf(context),
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  )
                : CreatorNavBar(
                    busy: false,
                    showBack: true,
                    onBack: () {
                      worldState.currentStep = 2;
                      worldState.notify();
                    },
                    onNext: null,
                    nextLabel: '',
                    showNext: false,
                  ),
          ),
        );
      default:
        nextLabel = 'Save World';
        onNext = busy ? null : _saveAndFinish;
    }
    return CreatorNavBar(
      busy: busy,
      showBack: step > 0,
      onBack: () {
        worldState.currentStep = step - 1;
        worldState.notify();
      },
      onNext: onNext,
      nextLabel: nextLabel,
      isLast: step >= 4,
      nextKey: const Key('world-from-wiki-next'),
    );
  }

  /// Why Next is locked, in plain words, and the pill's "ask again" when the
  /// model is running but nothing has asked it yet.
  Widget _toolsBanner(BuildContext context) {
    final gate = worldState.toolsGate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        children: [
          if (gate == WorldToolsGate.checking) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: StudioColors.amberOf(context),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              worldFromWikiToolsCopy(gate) ?? '',
              key: const Key('world-from-wiki-tools-copy'),
              style: TextStyle(
                color: StudioColors.proseOf(context),
                height: 1.4,
              ),
            ),
          ),
          if (worldFromWikiToolsCanRetest(gate))
            TextButton(
              key: const Key('world-from-wiki-tools-retest'),
              onPressed: () => worldState.retestTools(
                chat: _chat,
                llm: _llm,
                creator: creatorState,
              ),
              child: const Text('Check now'),
            ),
        ],
      ),
    );
  }

  static const _stepLabels = ['Setup', 'Book', 'Review', 'Write', 'Preview'];

  @override
  Widget build(BuildContext context) =>
      CreatorTheme(child: Builder(builder: _scaffold));

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: StudioColors.bgOf(context),
      appBar: AppBar(
        toolbarHeight: 56,
        backgroundColor: StudioColors.sideOf(context),
        shape: Border(bottom: BorderSide(color: StudioColors.lineOf(context))),
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          spacing: 14,
          children: [
            SizedBox.square(
              dimension: 40,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(worldState.writing ? Icons.stop : Icons.arrow_back),
                tooltip: worldState.writing ? 'Stop' : 'Back',
                color: StudioColors.proseOf(context),
                onPressed: worldState.writing
                    ? worldState.abortWrite
                    : () => Navigator.of(context).pop(),
              ),
            ),
            Icon(
              Icons.menu_book_outlined,
              color: StudioColors.amberOf(context),
              size: 22,
            ),
            Text(
              'World from Wiki',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: StudioColors.inkOf(context),
              ),
            ),
            const Spacer(),
            CreatorStepIndicator(
              labels: _stepLabels,
              current: worldState.currentStep,
            ),
          ],
        ),
        actions: const [SizedBox(width: 16)],
      ),
      body: Column(
        children: [
          if (worldState.currentStep == 0 && !worldState.toolsReady)
            _toolsBanner(context),
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
