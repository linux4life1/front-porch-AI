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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/pages/home/enhance/enhance_review_body.dart';
import 'package:front_porch_ai/ui/pages/home/enhance/wizard/wizard.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The AI Enhance wizard — the same top-bar step-dot chrome and linear
/// progression as the AI character creator (the mandated "Create X" pattern),
/// reworked from the old dialog chain so the feature EXPLAINS itself:
///
///   About → Model → Chat → Interview → Review → Chats
///
/// Step 0 teaches what Enhance is and how it works (nobody should have to
/// "just know"); the last step offers to bring the base character's chats
/// along onto the freshly saved "(Enhanced)" copy via the `.fpchat`
/// round-trip ([ChatServiceEnhanceChats.copyChatsForEnhance]). Nothing is
/// written anywhere until the Review step's Save.
class EnhanceWizardPage extends StatefulWidget {
  const EnhanceWizardPage({super.key, required this.character});

  final CharacterCard character;

  @override
  State<EnhanceWizardPage> createState() => _EnhanceWizardPageState();
}

class _EnhanceWizardPageState extends State<EnhanceWizardPage> {
  static const _stepLabels = [
    'About', 'Model', 'Chat', 'Interview', 'Review', 'Chats', //
  ];

  int _currentStep = 0;

  // About + Chat steps — the character's existing 1:1 chats.
  List<Map<String, dynamic>>? _sessions; // null = still loading
  String? _sessionId;

  // Model step — hosts the creator wizard's REAL SetupStep.
  late final CreatorState creatorState = CreatorState();
  String _modelId = '';

  // Interview step — field checklist + the grounded pipeline run.
  EnhanceSelection _selection = const EnhanceSelection(porchLife: true);
  late bool _nsfw =
      widget.character.frontPorchExtensions?.nsfwCooldownEnabled ?? false;
  EnhanceContext? _chatContext;
  bool _running = false;
  bool _cancelRequested = false;
  String _statusText = '';
  String _previewText = '';
  String? _runError;
  CharacterGenService? _gen;
  CharacterCard? _enhanced;
  EnhanceSelection? _ranSelection;

  // Review step.
  final _reviewKey = GlobalKey<EnhanceReviewBodyState>();
  bool _saving = false;
  CharacterCard? _savedCopy;

  // Chats step — bring the base character's chats along.
  bool _copying = false;
  int _copyDone = 0;
  int _copyTotal = 0;
  int? _copiedCount;
  String? _copyError;

  bool get _navLocked => _running || _saving || _copying;

  void _onCreatorStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // Same init recipe as CharacterCreatorPage/the old EnhanceSetupPage:
    // restore saved backend/model choices (shared prefs with the creator —
    // one consistent answer to "which model does AI generation use"), then
    // scan pickers.
    creatorState.loadSavedState();
    creatorState.addListener(_onCreatorStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final storage = Provider.of<StorageService>(context, listen: false);
        creatorState.scanLocalModels(storage);
        creatorState.scanLocalPresets(storage);
        creatorState.initLocalSettingsControllers(storage);
        Provider.of<ModelManager>(context, listen: false).refreshModels();
        if (creatorState.selectedLocalModelPath.isEmpty &&
            storage.backendSettings.lastUsedModelPath != null &&
            storage.backendSettings.lastUsedModelPath!.isNotEmpty) {
          creatorState.selectedLocalModelPath =
              storage.backendSettings.lastUsedModelPath!;
          creatorState.notify();
        }
        final llm = Provider.of<LLMProvider>(context, listen: false);
        if (!llm.hasManagedProcess) {
          creatorState.loadAvailableModels(llm);
        }
      } catch (_) {
        // Providers may not be ready in some edge cases; non-fatal.
      }
      // getSessionsForId resolves by imagePath basename — passing the dbId
      // UUID silently returns [] (the documented identity gotcha). 1:1 only.
      final chat = Provider.of<ChatService>(context, listen: false);
      chat.getSessionsForId(widget.character.stableGroupId).then((s) {
        if (!mounted) return;
        setState(() {
          _sessions = s;
          if (s.length == 1) _sessionId = s.first['id'] as String;
        });
      });
    });
  }

  @override
  void dispose() {
    // Leaving mid-interview must not leave a generation running on the
    // shared backend.
    _gen?.abort();
    creatorState.removeListener(_onCreatorStateChanged);
    creatorState.disposeControllers();
    super.dispose();
  }

  /// Load the chat's grounding material (transcript, recap, memory cards)
  /// so the Interview step can warn about a too-short chat, then advance.
  Future<void> _loadChatContextAndAdvance() async {
    final db = liveDatabase(context);
    final ctx = await buildEnhanceContext(
      db: db,
      card: widget.character,
      sessionId: _sessionId!,
    );
    if (!mounted) return;
    setState(() {
      _chatContext = ctx;
      _currentStep = 3;
    });
  }

  Future<void> _runInterview() async {
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    // Same resolver the creator wizard uses; the backend can have gone away
    // between the Model step and here (e.g. Kobold crashed).
    final llm = llmProvider.serviceForModel(_modelId);
    if (llm == null) {
      setState(() {
        _runError =
            'The AI backend isn\'t running any more. Go back to the Model '
            'step and get one ready, then try again.';
      });
      return;
    }
    final ctx = _chatContext!;
    final grounding = buildChatExcerptBlock(
      turns: ctx.turns,
      recap: ctx.recap,
      memoryCards: ctx.memoryCards,
      maxChars: enhanceGroundingCharBudget(
        isLocalKobold:
            llmProvider.activeBackend == BackendType.kobold &&
            llmProvider.koboldService.isReady,
        contextSize: storage.backendSettings.promptContext(
          storage.backendSettings.contextSize,
        ),
      ),
    );
    final gen = CharacterGenService(llm);
    final selection = _selection;
    String? errorMessage;
    setState(() {
      _running = true;
      _cancelRequested = false;
      _runError = null;
      _statusText = 'Getting ready...';
      _previewText = '';
      _gen = gen;
    });
    final voice = readNarrativeVoice(widget.character);
    final enhanced = await gen.enhanceCharacter(
      source: widget.character,
      selection: selection,
      chatGrounding: grounding,
      nsfwEnabled: _nsfw,
      narrativePerspective: voice.perspective,
      narrativeTense: voice.tense,
      sex: voice.sex,
      // A home-screen action must not kill evals a background chat may have
      // in flight on the shared backend (Scene Guest precedent).
      abortInFlight: false,
      onStatus: (s) {
        if (mounted) setState(() => _statusText = s);
      },
      onProgress: (p) {
        if (mounted) setState(() => _previewText = p);
      },
      onError: (e) => errorMessage = e,
    );
    if (!mounted) return;
    _gen = null;
    setState(() {
      _running = false;
      if (_cancelRequested) return; // back to the checklist, no error
      if (enhanced == null) {
        _runError = errorMessage == null
            ? 'The AI didn\'t produce a usable result. This usually means '
                  'the model struggled with the task — try again, or try a '
                  'different model.'
            : 'The AI ran into a problem: $errorMessage';
      } else {
        _enhanced = enhanced;
        _ranSelection = selection;
        _currentStep = 4;
      }
    });
  }

  void _cancelInterview() {
    _cancelRequested = true;
    _gen?.abort();
  }

  Future<void> _saveReview() async {
    setState(() => _saving = true);
    final copy = await _reviewKey.currentState?.save();
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (copy != null) {
        _savedCopy = copy;
        _currentStep = 5;
      }
    });
  }

  Future<void> _copyChats() async {
    final chat = Provider.of<ChatService>(context, listen: false);
    setState(() {
      _copying = true;
      _copyError = null;
      _copyDone = 0;
      _copyTotal = _sessions?.length ?? 0;
    });
    try {
      final copied = await chat.copyChatsForEnhance(
        from: widget.character,
        to: _savedCopy!,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _copyDone = done;
              _copyTotal = total;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _copying = false;
        _copiedCount = copied;
      });
    } on ChatImportBusy {
      if (!mounted) return;
      setState(() {
        _copying = false;
        _copyError =
            'A reply is still being written in the open chat. Let it finish, '
            'then try again.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _copying = false;
        _copyError = 'Could not copy the chats: $e';
      });
    }
  }

  void _finish() {
    // Capture before pop — after the route leaves, this context is
    // deactivating (same order the creator's _saveAndFinish uses).
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    if (_savedCopy != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('"${_savedCopy!.name}" added to your library.')),
      );
    }
  }

  Widget _buildInterviewStep() {
    if (_running) {
      return EnhanceInterviewProgress(
        characterName: widget.character.name,
        statusText: _statusText,
        previewText: _previewText,
      );
    }
    return EnhanceInterviewChecklist(
      selection: _selection,
      onSelectionChanged: (s) => setState(() => _selection = s),
      nsfw: _nsfw,
      onNsfwChanged: (v) => setState(() => _nsfw = v),
      userTurnCount: _chatContext?.userTurnCount,
      runError: _runError,
    );
  }

  // Bottom nav — per-step labels/gating. While the interview runs, the only
  // control is Cancel; after the Review save there is no way back (the copy
  // exists).
  Widget _buildNavButtons(bool backendReady) {
    if (_running) return EnhanceWizardCancelBar(onCancel: _cancelInterview);

    final (
      String nextLabel,
      IconData nextIcon,
      VoidCallback? onNext,
    ) = switch (_currentStep) {
      0 => (
        'Next: Model',
        Icons.arrow_forward,
        (_sessions?.isNotEmpty ?? false)
            ? () => setState(() => _currentStep = 1)
            : null,
      ),
      1 => (
        backendReady ? 'Next: Chat' : 'Waiting for a ready backend...',
        Icons.arrow_forward,
        backendReady
            ? () => setState(() {
                _modelId = creatorState.selectedModelId;
                _currentStep = 2;
              })
            : null,
      ),
      2 => (
        'Next: Interview',
        Icons.arrow_forward,
        _sessionId != null ? _loadChatContextAndAdvance : null,
      ),
      3 => (
        'Start the Interview',
        Icons.auto_awesome,
        _selection.anySelected ? _runInterview : null,
      ),
      4 => (
        'Save as New Character',
        Icons.save_alt,
        _saving ? null : _saveReview,
      ),
      _ => ('Finish', Icons.check, _copying ? null : _finish),
    };
    final showBack = _currentStep > 0 && _currentStep < 5 && !_saving;

    return EnhanceWizardNavBar(
      showBack: showBack,
      onBack: () => setState(() => _currentStep--),
      saving: _saving,
      nextLabel: nextLabel,
      nextIcon: nextIcon,
      onNext: onNext,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch the pieces whose changes flip Model-step readiness (Kobold
    // finishing its model load, a backend switch) so Next updates live.
    final llmProvider = context.watch<LLMProvider>();
    context.watch<KoboldService>();
    final backendReady =
        llmProvider.serviceForModel(creatorState.selectedModelId) != null;

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimary(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _navLocked ? null : _finish,
        ),
        title: Row(
          children: [
            Icon(
              Icons.auto_awesome,
              color: AppColors.porchAmberOf(context),
              size: 22,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'AI Enhance ${widget.character.name}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textPrimary(context)),
              ),
            ),
            const Spacer(),
            EnhanceStepIndicator(
              labels: _stepLabels,
              currentStep: _currentStep,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              // Keyed per step: an unkeyed switcher would update a step that
              // shares a runtimeType with the last one in place — no
              // transition, and one step's scroll offset bleeding into the
              // next.
              child: KeyedSubtree(
                key: ValueKey<int>(_currentStep),
                child: switch (_currentStep) {
                  0 => EnhanceAboutStep(
                    characterName: widget.character.name,
                    sessions: _sessions,
                  ),
                  1 => EnhanceModelStep(creatorState: creatorState),
                  2 => EnhanceChatPickStep(
                    characterName: widget.character.name,
                    sessions: _sessions,
                    selectedSessionId: _sessionId,
                    onSelectSession: (id) => setState(() => _sessionId = id),
                  ),
                  3 => _buildInterviewStep(),
                  4 => EnhanceReviewBody(
                    key: _reviewKey,
                    original: widget.character,
                    enhanced: _enhanced!,
                    selection: _ranSelection!,
                    showIntimate: _nsfw,
                  ),
                  _ => EnhanceChatsCopyStep(
                    characterName: widget.character.name,
                    savedCopyName: _savedCopy?.name,
                    chatCount: _sessions?.length ?? 0,
                    copying: _copying,
                    copyDone: _copyDone,
                    copyTotal: _copyTotal,
                    copiedCount: _copiedCount,
                    copyError: _copyError,
                    onCopy: _copyChats,
                  ),
                },
              ),
            ),
          ),
          _buildNavButtons(backendReady),
        ],
      ),
    );
  }
}
