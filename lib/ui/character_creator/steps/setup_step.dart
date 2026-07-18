// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/optimization_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/backend_chip.dart';
import 'package:front_porch_ai/ui/settings/dialogs/model_search_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/kcpps_selector.dart';

/// Step 0: Backend & Model setup (lifted pure from _buildSetupStep).
class SetupStep extends StatelessWidget {
  final CreatorState state;

  const SetupStep({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final activeBackend = llmProvider.activeBackend;
    final isKobold = activeBackend == BackendType.kobold;
    final isAppleSiliconMac = _isAppleSiliconMac();

    return Center(
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
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your AI backend and model before configuring your character.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              // Backend toggle (uses extracted BackendChip)
              _inputLabel(context, 'Backend', required: false),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: BackendChip(
                      label: 'KoboldCpp (Local)',
                      icon: Icons.computer,
                      isSelected: isKobold,
                      onTap: () async {
                        if (!isKobold) {
                          await llmProvider.setActiveBackend(
                            BackendType.kobold,
                          );
                          // Trigger scan (was never wired) + notify so Kobold model list appears
                          // and the conditional picker UI switches. This was the root of the
                          // "KoboldCpp model picker completely broken" bug.
                          final storage = Provider.of<StorageService>(
                            context,
                            listen: false,
                          );
                          state.scanLocalModels(storage);
                          // Presets are a launch option of the local backend,
                          // so populate them here too for the optional picker.
                          state.scanLocalPresets(storage);
                          state.notify();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BackendChip(
                      label: 'API (Remote)',
                      icon: Icons.cloud,
                      isSelected: activeBackend == BackendType.openRouter,
                      onTap: () async {
                        if (activeBackend != BackendType.openRouter) {
                          await llmProvider.setActiveBackend(
                            BackendType.openRouter,
                          );
                          state.loadAvailableModels(llmProvider);
                        }
                      },
                    ),
                  ),
                  if (isAppleSiliconMac) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: BackendChip(
                        label: 'oMLX',
                        icon: Icons.apple,
                        isSelected: activeBackend == BackendType.omlx,
                        onTap: () async {
                          if (activeBackend != BackendType.omlx) {
                            // setActiveBackend(omlx) configures the live
                            // service onto localhost:8000 synchronously — the
                            // old re-configure + 100ms "settle" delay here
                            // were redundant.
                            await llmProvider.setActiveBackend(
                              BackendType.omlx,
                            );
                            state.loadAvailableModels(llmProvider);
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),

              // Model selection — both Kobold (local) and remote/oMLX now use the *exact same*
              // tappable selector field + searchable dialog (the one the user liked for API/oMLX).
              // This reuses the existing model picker UX for local .gguf files too.
              if (isKobold) ...[
                _inputLabel(context, 'Local Model (.gguf)', required: false),
                const SizedBox(height: 8),
                // Identical styled picker field as remote/oMLX
                InkWell(
                  onTap: () async {
                    final storage = Provider.of<StorageService>(context, listen: false);
                    state.scanLocalModels(storage);
                    final modelManager = Provider.of<ModelManager>(context, listen: false);
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
                          storage.setLastUsedModelPath(f.path);
                          state.notify();
                        },
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerOf(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.borderOf(context),
                      ),
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
                                  color: AppColors.textTertiary(context),
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
                                      ? AppColors.textTertiary(context)
                                      : AppColors.textPrimary(context),
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          color: AppColors.iconSecondary(context),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 16),
                Builder(builder: (ctx) {
                  final k = Provider.of<KoboldService>(ctx);
                  final isTransitioning =
                      k.isStarting || (k.isRunning && !k.modelReady);
                  final dotColor = k.modelReady
                      ? Colors.green.shade300
                      : isTransitioning
                      ? Colors.orange.shade300
                      : Colors.red.shade300;
                  final label = k.modelReady
                      ? 'Ready'
                      : k.isStarting
                      ? 'Starting...'
                      : k.isRunning
                      ? 'Loading model...'
                      : 'Stopped';
                  return Row(
                    children: [
                      _BackendStatusDot(
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
                }),
                const SizedBox(height: 8),
                StatefulBuilder(
                  builder: (context, setLocalState) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.07),
                        ),
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
                                  const Icon(
                                    Icons.tune,
                                    color: Color(0xFF00D4AA),
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
                                    duration:
                                        const Duration(milliseconds: 200),
                                    child: const Icon(
                                      Icons.keyboard_arrow_down,
                                      color: Colors.white54,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          AnimatedCrossFade(
                            firstChild: const SizedBox(height: 0),
                            secondChild:
                                _buildExtraSettingsBody(context, state),
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
                Builder(builder: (ctx) {
                  final k = Provider.of<KoboldService>(ctx);
                  final isAnyRunning = k.isRunning || k.isStarting;
                  final storage = Provider.of<StorageService>(
                    ctx,
                    listen: false,
                  );
                  // A .kcpps preset that owns its own model can launch the
                  // backend even without a picker-selected .gguf.
                  final presetOwnsModel =
                      storage.kcppsHasModel && storage.kcppsModelFileExists;
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
                            ? Colors.redAccent
                            : Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  );
                }),
              ] else ...[
                // API (remote) and oMLX — searchable model picker.
                _inputLabel(
                  context,
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

                    if (context.mounted &&
                        state.availableModels.isNotEmpty) {
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
                          if (s.remoteModelName.isNotEmpty) {
                            state.selectedModelId = s.remoteModelName;
                            state.notify();
                          }
                        }
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerOf(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.borderOf(context),
                      ),
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
                                  color: AppColors.textTertiary(context),
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
                                      ? AppColors.textTertiary(context)
                                      : AppColors.textPrimary(context),
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          color: AppColors.iconSecondary(context),
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
                  color: AppColors.textTertiary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputLabel(
    BuildContext context,
    String text, {
    bool required = false,
  }) {
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary(context),
            fontWeight: FontWeight.w500,
          ),
        ),
        if (required)
          Text(
            ' *',
            style: TextStyle(
              color: AppColors.resolve(
                context,
                Colors.redAccent,
                Colors.red.shade700,
              ),
            ),
          ),
      ],
    );
  }

  /// Check if running on Apple Silicon Mac (arm64 architecture).
  bool _isAppleSiliconMac() {
    if (!Platform.isMacOS) return false;
    // Try to detect arm64 architecture
    try {
      final result = Process.runSync('uname', ['-m']);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim() == 'arm64';
      }
    } catch (_) {}
    // Fallback: if uname fails, assume it's not Apple Silicon
    return false;
  }

  Widget _buildExtraSettingsBody(BuildContext context, CreatorState state) {
    final storage = Provider.of<StorageService>(context, listen: false);
    final hardwareService =
        Provider.of<HardwareService>(context, listen: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KcppsSelector(
            storage: storage,
            localPresets: state.localPresets,
            hint: 'Optional \u2014 select a .kcpps preset',
            onChanged: (val) {
              storage.setActiveKcppsPath(val);
              if (val != null &&
                  storage.kcppsHasModel &&
                  storage.kcppsModelFileExists) {
                state.selectedLocalModelPath = '';
                state.notify();
              }
            },
            onExternalClear: () => storage.setActiveKcppsPath(null),
            onBrowsePicked: (_) {
              if (storage.kcppsHasModel &&
                  storage.kcppsModelFileExists) {
                state.selectedLocalModelPath = '';
                state.notify();
              }
            },
            onModelStatusChanged: (_) => state.notify(),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: hardwareService.isDetecting
                ? const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : hardwareService.hardwareInfo == null
                    ? const Text(
                        'Hardware not detected.',
                        style: TextStyle(color: Colors.redAccent),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow(
                            context,
                            'GPU',
                            hardwareService.hardwareInfo!.gpuName,
                          ),
                          const SizedBox(height: 4),
                          _buildInfoRow(
                            context,
                            'VRAM',
                            '${hardwareService.hardwareInfo!.vramMb} MB${hardwareService.hardwareInfo!.isSharedMemory ? ' (Shared)' : ''}',
                          ),
                        ],
                      ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSettingsTextField(
                  context,
                  label: 'GPU Layers',
                  controller: state.gpuLayersController,
                  isNumber: true,
                  onChanged: (v) {
                    final val = int.tryParse(v);
                    if (val != null) storage.setGpuLayers(val);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSettingsTextField(
                  context,
                  label: 'Context Size',
                  controller: state.contextSizeController,
                  isNumber: true,
                  onChanged: (v) {
                    final val = int.tryParse(v);
                    if (val != null) storage.setContextSize(val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'KV Quantization:',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: storage.kvQuantizationLevel,
                    isExpanded: true,
                    dropdownColor:
                        AppColors.surfaceContainerOf(context),
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 13,
                    ),
                    onChanged: (val) {
                      if (val != null) {
                        storage.setKvQuantizationLevel(val);
                        state.notify();
                      }
                    },
                    items: const [
                      DropdownMenuItem(
                        value: 0,
                        child: Text('0 - None (FP16)'),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Text('1 - 8-Bit Q8'),
                      ),
                      DropdownMenuItem(
                        value: 2,
                        child: Text('2 - 4-Bit Q4'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () =>
                    _applyAutoConfigure(context, state, storage),
                icon: const Icon(
                  Icons.auto_fix_high,
                  color: Colors.amber,
                ),
                label: const Text(
                  'Auto-Configure',
                  style: TextStyle(color: Colors.amber),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTextField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required bool isNumber,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType:
          isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: AppColors.textPrimary(context)),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            TextStyle(color: AppColors.textSecondary(context)),
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  void _applyAutoConfigure(
    BuildContext context,
    CreatorState state,
    StorageService storage,
  ) {
    final hardware =
        Provider.of<HardwareService>(context, listen: false).hardwareInfo;
    if (hardware == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hardware not detected yet.')),
      );
      return;
    }

    int modelSize = 5000;
    if (state.selectedLocalModelPath.isNotEmpty) {
      try {
        final file = File(state.selectedLocalModelPath);
        if (file.existsSync()) {
          modelSize = (file.lengthSync() / (1024 * 1024)).round();
        }
      } catch (_) {}
    }

    final userContext = int.tryParse(state.contextSizeController.text);
    final modelManager =
        Provider.of<ModelManager>(context, listen: false);
    int? kvBytesPerToken;
    if (state.selectedLocalModelPath.isNotEmpty) {
      kvBytesPerToken =
          modelManager.getCachedModelArchitectureInfo(
                    state.selectedLocalModelPath,
                  )?.kvBytesPerToken ??
              modelManager.getCachedKvBytesPerToken(
                state.selectedLocalModelPath,
              );
    }

    final suggestion = OptimizationService.calculateSettings(
      hardware,
      modelSizeMb: modelSize,
      requestedContextSize: userContext,
      kvBytesPerToken: kvBytesPerToken,
      kvQuantizationLevel: storage.kvQuantizationLevel,
    );

    state.gpuLayersController.text = suggestion.gpuLayers.toString();
    state.contextSizeController.text = suggestion.contextSize.toString();
    storage.setGpuLayers(suggestion.gpuLayers);
    storage.setContextSize(suggestion.contextSize);
    state.notify();
  }
}

/// An 8px pulsing status dot that blinks during transitional states.
/// Uses the same animation pattern as LogView (800ms easeInOut opacity pulse).
class _BackendStatusDot extends StatefulWidget {
  final Color color;
  final bool isBlinking;

  const _BackendStatusDot({required this.color, required this.isBlinking});

  @override
  State<_BackendStatusDot> createState() => _BackendStatusDotState();
}

class _BackendStatusDotState extends State<_BackendStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _updateBlinking();
  }

  @override
  void didUpdateWidget(_BackendStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isBlinking != widget.isBlinking) {
      _updateBlinking();
    }
  }

  void _updateBlinking() {
    if (widget.isBlinking) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
      }
    } else {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: _animation.value),
          ),
        );
      },
    );
  }
}
