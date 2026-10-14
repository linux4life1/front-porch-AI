// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/setup_backend_picker.dart';
import 'package:front_porch_ai/ui/settings/dialogs/model_search_dialog.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

import 'package:front_porch_ai/ui/character_creator/steps/setup_step_fields.dart';
import 'package:front_porch_ai/ui/character_creator/steps/setup_step_status_dot.dart';

/// Step 0: Backend & Model setup (lifted pure from _buildSetupStep).
class SetupStep extends StatelessWidget {
  final CreatorState state;

  const SetupStep({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final activeBackend = llmProvider.activeBackend;
    final isKobold = activeBackend == BackendType.kobold;

    return Align(
      alignment: Alignment.topCenter,
      key: const ValueKey('setup'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Backend & Model Setup',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: StudioColors.inkOf(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose your AI backend and model before configuring your character.',
                style: TextStyle(
                  fontSize: 14,
                  color: StudioColors.mutedOf(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),

              SetupBackendPicker(state: state),
              const SizedBox(height: 24),

              // Model selection — both Kobold (local) and remote/oMLX now use the *exact same*
              // tappable selector field + searchable dialog (the one the user liked for API/oMLX).
              // This reuses the existing model picker UX for local .gguf files too.
              if (isKobold) ...[
                const SetupInputLabel('Local Model (.gguf)', required: false),
                const SizedBox(height: 8),
                // Identical styled picker field as remote/oMLX
                InkWell(
                  onTap: () async {
                    final storage = Provider.of<StorageService>(
                      context,
                      listen: false,
                    );
                    state.scanLocalModels(storage);
                    final modelManager = Provider.of<ModelManager>(
                      context,
                      listen: false,
                    );
                    await modelManager.refreshModels();

                    final models = modelManager.models.isNotEmpty
                        ? modelManager.models
                        : state.localModels;

                    if (context.mounted) {
                      // Always open the searchable picker (even if currently empty) so the user
                      // sees the familiar search UI and can understand the state.
                      showGenericModelSearchDialog<FileSystemEntity>(
                        context,
                        models,
                        title: 'Select Local Model',
                        getTitle: (f) => p.basename(f.path),
                        getSubtitle: (f) => f.path,
                        onSelected: (f) {
                          state.selectedLocalModelPath = f.path;
                          // Like the other pickers: the model brings its
                          // own preset or none, so a preset that owns a
                          // different model does not load that one instead.
                          selectKoboldModel(storage, f.path);
                          state.notify();
                        },
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: StudioColors.bgOf(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: StudioColors.lineOf(context)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Model',
                                style: TextStyle(
                                  color: StudioColors.mutedOf(context),
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                state.selectedLocalModelPath.isEmpty
                                    ? 'Tap to select a model...'
                                    : p.basename(state.selectedLocalModelPath),
                                style: TextStyle(
                                  color: state.selectedLocalModelPath.isEmpty
                                      ? StudioColors.mutedOf(context)
                                      : StudioColors.inkOf(context),
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          color: StudioColors.mutedOf(context),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 16),
                Builder(
                  builder: (ctx) {
                    final phase = Provider.of<KoboldService>(ctx).phase;
                    final isTransitioning =
                        phase == KoboldPhase.starting ||
                        phase == KoboldPhase.loading;
                    final dotColor = switch (phase) {
                      KoboldPhase.ready => StudioColors.tealOf(ctx),
                      KoboldPhase.unloaded => StudioColors.faintOf(ctx),
                      KoboldPhase.starting ||
                      KoboldPhase.loading => StudioColors.honeyOf(ctx),
                      KoboldPhase.stopped => StudioColors.badOf(ctx),
                    };
                    final label = switch (phase) {
                      KoboldPhase.ready => 'Ready',
                      // It loads again with the next request.
                      KoboldPhase.unloaded => 'Unloaded while idle',
                      KoboldPhase.starting => 'Starting...',
                      KoboldPhase.loading => 'Loading model...',
                      KoboldPhase.stopped => 'Stopped',
                    };
                    return Row(
                      children: [
                        BackendStatusDot(
                          color: dotColor,
                          isBlinking: isTransitioning,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: TextStyle(color: dotColor, fontSize: 12),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                StatefulBuilder(
                  builder: (context, setLocalState) {
                    return Container(
                      decoration: BoxDecoration(
                        color: StudioColors.cardOf(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: StudioColors.lineOf(context)),
                      ),
                      child: Column(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              state.extraSettingsExpanded =
                                  !state.extraSettingsExpanded;
                              setLocalState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.tune,
                                    color: StudioColors.amberOf(context),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 10),
                                  const Text(
                                    'Extra Settings',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const Spacer(),
                                  AnimatedRotation(
                                    turns: state.extraSettingsExpanded
                                        ? 0.5
                                        : 0,
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      Icons.keyboard_arrow_down,
                                      color: StudioColors.mutedOf(context),
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          AnimatedCrossFade(
                            firstChild: const SizedBox(height: 0),
                            secondChild: SetupExtraSettingsBody(state: state),
                            crossFadeState: state.extraSettingsExpanded
                                ? CrossFadeState.showSecond
                                : CrossFadeState.showFirst,
                            duration: const Duration(milliseconds: 220),
                            sizeCurve: Curves.easeInOut,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (ctx) {
                    final k = Provider.of<KoboldService>(ctx);
                    final isAnyRunning = k.isRunning || k.isStarting;
                    final storage = Provider.of<StorageService>(
                      ctx,
                      listen: false,
                    );
                    // A .kcpps preset that owns its own model can launch the
                    // backend even without a picker-selected .gguf.
                    final presetOwnsModel =
                        storage.backendSettings.kcppsHasModel &&
                        storage.backendSettings.kcppsModelFileExists;
                    final canStart =
                        state.selectedLocalModelPath.isNotEmpty ||
                        presetOwnsModel;
                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isAnyRunning
                            ? () {
                                if (k.isRunning || k.isStarting) {
                                  k.stopKobold();
                                }
                              }
                            : !canStart
                            ? null
                            : () {
                                final llm = Provider.of<LLMProvider>(
                                  ctx,
                                  listen: false,
                                );
                                final backendManager =
                                    Provider.of<BackendManager>(
                                      ctx,
                                      listen: false,
                                    );
                                state.reloadKoboldWithModel(
                                  state.selectedLocalModelPath,
                                  llm,
                                  storage,
                                  backendManager,
                                );
                              },
                        icon: Icon(
                          isAnyRunning ? Icons.stop : Icons.play_arrow,
                        ),
                        label: Text(
                          isAnyRunning ? 'Stop Backend' : 'Start Backend',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isAnyRunning
                              ? StudioColors.badOf(ctx)
                              : StudioColors.amberOf(ctx),
                          foregroundColor: StudioColors.amberInkOf(ctx),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    );
                  },
                ),
              ] else ...[
                // API (remote) and oMLX — searchable model picker.
                SetupInputLabel(
                  activeBackend == BackendType.omlx
                      ? 'oMLX Model'
                      : 'Remote Model',
                  required: false,
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final llm = Provider.of<LLMProvider>(
                      context,
                      listen: false,
                    );
                    final storage = Provider.of<StorageService>(
                      context,
                      listen: false,
                    );

                    if (state.availableModels.isEmpty) {
                      await state.loadAvailableModels(llm);
                    }

                    if (context.mounted && state.availableModels.isNotEmpty) {
                      showModelSearchDialog(
                        context,
                        storage,
                        state.availableModels.cast<RemoteModelInfo>(),
                      );
                      Future.delayed(const Duration(milliseconds: 350), () {
                        if (context.mounted) {
                          final s = Provider.of<StorageService>(
                            context,
                            listen: false,
                          );
                          if (s.backendSettings.remoteModelName.isNotEmpty) {
                            state.selectedModelId =
                                s.backendSettings.remoteModelName;
                            state.notify();
                          }
                        }
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: StudioColors.bgOf(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: StudioColors.lineOf(context)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Model',
                                style: TextStyle(
                                  color: StudioColors.mutedOf(context),
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                state.selectedModelId.isEmpty
                                    ? 'Tap to select a model...'
                                    : state.selectedModelId,
                                style: TextStyle(
                                  color: state.selectedModelId.isEmpty
                                      ? StudioColors.mutedOf(context)
                                      : StudioColors.inkOf(context),
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          color: StudioColors.mutedOf(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              Text(
                'The selected backend and model will be used for all AI generation in this wizard.',
                style: TextStyle(
                  fontSize: 12,
                  color: StudioColors.mutedOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
