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

import 'dart:io';
import 'package:path/path.dart' as path_lib;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Barrel imports
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

// Not in barrels (internal or low-frequency)
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/optimization_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class ModelSettingsDialog extends StatefulWidget {
  const ModelSettingsDialog({super.key});

  @override
  State<ModelSettingsDialog> createState() => _ModelSettingsDialogState();
}

class _ModelSettingsDialogState extends State<ModelSettingsDialog> {
  // Local backend fields
  final _gpuLayersController = TextEditingController(text: '0');
  final _contextSizeController = TextEditingController(text: '');
  bool _useVulkan = false;
  bool _useCublas = false;
  bool _useMetal = false;
  bool _useRocm = false;
  String? _selectedModelPath;

  // Remote API fields
  final _apiUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelNameController = TextEditingController();
  String? _connectionStatus;
  bool _isTesting = false;

  // Preset fields
  List<File> _localPresets = [];

  @override
  void initState() {
    super.initState();
    final storage = Provider.of<StorageService>(context, listen: false);
    // Local settings
    _useCublas = storage.useCublas == true;
    _useVulkan = storage.useVulkan == true;
    _useMetal = storage.useMetal == true;
    _useRocm = storage.useRocm == true;
    _selectedModelPath = storage.lastUsedModelPath;
    _gpuLayersController.text = storage.gpuLayers.toString();
    _contextSizeController.text = storage.contextSize.toString();
    // Remote settings
    _apiUrlController.text = storage.remoteApiUrl;
    _apiKeyController.text = storage.remoteApiKey;
    _modelNameController.text = storage.remoteModelName;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scanLocalPresets();
    });
  }

  void _scanLocalPresets() {
    final storage = Provider.of<StorageService>(context, listen: false);
    setState(() {
      _localPresets = scanKcppsPresets(storage.binDir);
    });
  }

  /// Check whether a .kcpps preset is currently active.
  bool _isPresetActive(BuildContext ctx) {
    final storage = Provider.of<StorageService>(ctx, listen: false);
    return storage.activeKcppsPath != null &&
        storage.activeKcppsPath!.isNotEmpty;
  }

  @override
  void dispose() {
    _gpuLayersController.dispose();
    _contextSizeController.dispose();
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    _modelNameController.dispose();
    super.dispose();
  }

  void _applyAutoConfiguration() {
    final hardware = Provider.of<HardwareService>(
      context,
      listen: false,
    ).hardwareInfo;
    if (hardware == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hardware not detected yet.')),
      );
      return;
    }

    int modelSize = 5000;
    if (_selectedModelPath != null) {
      try {
        final file = File(_selectedModelPath!);
        if (file.existsSync()) {
          modelSize = (file.lengthSync() / (1024 * 1024)).round();
        }
      } catch (e) {
        // ignore
      }
    }

    final storage = Provider.of<StorageService>(context, listen: false);

    // Respect whatever the user currently has in the context field (critical for
    // the new accurate KoboldLayerSolver). Also try to get real kvBytesPerToken
    // for the selected model so the solver can be precise.
    final userContext = int.tryParse(_contextSizeController.text);
    int? kvBytesPerToken;
    if (_selectedModelPath != null) {
      final modelManager = Provider.of<ModelManager>(context, listen: false);
      kvBytesPerToken =
          modelManager
              .getCachedModelArchitectureInfo(_selectedModelPath!)
              ?.kvBytesPerToken ??
          modelManager.getCachedKvBytesPerToken(_selectedModelPath!);
    }

    final suggestion = OptimizationService.calculateSettings(
      hardware,
      modelSizeMb: modelSize,
      requestedContextSize: userContext,
      kvBytesPerToken: kvBytesPerToken,
      kvQuantizationLevel: storage.kvQuantizationLevel,
    );

    setState(() {
      _gpuLayersController.text = suggestion.gpuLayers.toString();
      _contextSizeController.text = suggestion.contextSize.toString();

      if (Platform.isMacOS) {
        _useMetal = true;
        _useVulkan = false;
        _useCublas = false;
        _useRocm = false;
      } else if (hardware.vendor == 'Nvidia') {
        _useCublas = true;
        _useVulkan = false;
        _useMetal = false;
        _useRocm = false;
      } else if (hardware.vendor == 'AMD' &&
          Platform.isLinux &&
          hardware.hasRocm) {
        _useRocm = true;
        _useVulkan = false;
        _useCublas = false;
        _useMetal = false;
      } else {
        _useVulkan = suggestion.useVulkan;
        _useCublas = false;
        _useMetal = false;
        _useRocm = false;
      }
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(suggestion.reasoning)));
  }

  Future<void> _restartBackend() async {
    final koboldService = Provider.of<KoboldService>(context, listen: false);
    final backendManager = Provider.of<BackendManager>(context, listen: false);

    if (backendManager.backendPath == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Backend not found.')));
      return;
    }

    final storage = Provider.of<StorageService>(context, listen: false);

    // Case A — preset owns a valid model file: skip model-path checks.
    // Case B — no preset / preset has no model / model file missing: user must pick one.
    final presetOwnsModel =
        storage.kcppsHasModel && storage.kcppsModelFileExists;

    if (!presetOwnsModel) {
      if (_selectedModelPath == null ||
          !File(_selectedModelPath!).existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Valid model not selected.')),
        );
        return;
      }
    }

    // Validate preset file exists if one is active
    if (storage.activeKcppsPath != null &&
        storage.activeKcppsPath!.isNotEmpty) {
      if (!File(storage.activeKcppsPath!).existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Selected preset not found. It may have been deleted or moved.\n'
              'Clearing the preset and falling back to app settings.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        storage.setActiveKcppsPath(null);
        if (_selectedModelPath != null) {
          storage.setModelPreset(_selectedModelPath!, '');
        }
        return;
      }
    }

    // When the preset owns the model, pass empty string — KoboldCPP reads
    // it from the .kcpps config. Otherwise pass the Flutter-selected path.
    final effectiveModel = presetOwnsModel ? '' : _selectedModelPath!;

    storage.setLastUsedModelPath(_selectedModelPath);
    storage.setGpuLayers(int.tryParse(_gpuLayersController.text) ?? 0);
    storage.setContextSize(int.tryParse(_contextSizeController.text) ?? 8192);
    storage.setUseCublas(_useCublas);
    storage.setUseVulkan(_useVulkan);
    storage.setUseMetal(_useMetal);
    storage.setUseRocm(_useRocm);

    // Await the full stop so the process tree is terminated and the port is
    // released before we start a new instance. Without this, Windows can
    // leave the old koboldcpp.exe alive → zombie processes accumulate.
    if (koboldService.isRunning) {
      await koboldService.stopKobold();
    }

    // Give the OS a moment to fully release the port after process termination.
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    koboldService.startKobold(
      backendManager.backendPath!,
      effectiveModel,
      kcppsPath: storage.activeKcppsPath,
      gpuLayers: int.tryParse(_gpuLayersController.text) ?? 0,
      contextSize: int.tryParse(_contextSizeController.text) ?? 8192,
      useVulkan: _useVulkan,
      useCublas: _useCublas,
      useMetal: _useMetal,
      useRocm: _useRocm,
    );
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Restarting backend with new settings...')),
    );
  }

  void _saveRemoteSettings() {
    final storage = Provider.of<StorageService>(context, listen: false);
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    // Never overwrite the user's remote API URL when oMLX is active (it uses a fixed localhost URL)
    if (llmProvider.activeBackend != BackendType.omlx) {
      storage.setRemoteApiUrl(_apiUrlController.text.trim());
    }
    storage.setRemoteApiKey(_apiKeyController.text.trim());
    storage.setRemoteModelName(_modelNameController.text.trim());
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('API settings saved.')));
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _connectionStatus = null;
    });
    _saveRemoteSettings();
    final openRouter = Provider.of<OpenRouterService>(context, listen: false);
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    // Force oMLX localhost URL when oMLX backend is active (ignores whatever is in the URL field)
    final apiUrl = llmProvider.activeBackend == BackendType.omlx
        ? 'http://localhost:8000/v1'
        : _apiUrlController.text.trim();
    // Ensure the service has the latest config
    openRouter.configure(
      apiUrl: apiUrl,
      apiKey: _apiKeyController.text.trim(),
      modelName: _modelNameController.text.trim(),
    );
    final result = await openRouter.testConnection();
    if (mounted) {
      setState(() {
        _isTesting = false;
        _connectionStatus = result;
      });
    }
  }

  Future<void> _showModelPicker() async {
    // Ensure the service has the latest config before fetching.
    // Force localhost:8000/v1 when oMLX backend is selected (model picker is used for oMLX too).
    final openRouter = Provider.of<OpenRouterService>(context, listen: false);
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final apiUrl = llmProvider.activeBackend == BackendType.omlx
        ? 'http://localhost:8000/v1'
        : _apiUrlController.text.trim();
    openRouter.configure(
      apiUrl: apiUrl,
      apiKey: _apiKeyController.text.trim(),
      modelName: _modelNameController.text.trim(),
    );

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    List<RemoteModelInfo> models;
    try {
      models = await openRouter.fetchAvailableModels();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // dismiss loading
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to fetch models: $e')));
      }
      return;
    }

    if (!mounted) return;
    Navigator.pop(context); // dismiss loading

    if (models.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No models available. Check your API URL and key.'),
        ),
      );
      return;
    }

    // Show the model picker dialog
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtered = searchQuery.isEmpty
                ? models
                : models
                      .where(
                        (m) => m.id.toLowerCase().contains(
                          searchQuery.toLowerCase(),
                        ),
                      )
                      .toList();

            return AlertDialog(
              backgroundColor: AppColors.cardOf(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Model',
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search models...',
                      hintStyle: TextStyle(
                        color: AppColors.textTertiary(context),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: AppColors.iconSecondary(context),
                        size: 18,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceContainerOf(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      isDense: true,
                    ),
                    onChanged: (val) => setDialogState(() => searchQuery = val),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                height: 400,
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No models match "$searchQuery"',
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (ctx, index) {
                          final model = filtered[index];
                          final isSelected =
                              model.id == _modelNameController.text;
                          return ListTile(
                            dense: true,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            title: Text(
                              model.id,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.blueAccent
                                    : AppColors.textPrimary(context),
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Row(
                              children: [
                                if (model.isFree)
                                  Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'FREE',
                                      style: TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                Flexible(
                                  child: Text(
                                    model.pricingLabel,
                                    style: TextStyle(
                                      color: AppColors.textTertiary(context),
                                      fontSize: 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            trailing: isSelected
                                ? const Icon(
                                    Icons.check_circle,
                                    color: Colors.blueAccent,
                                    size: 18,
                                  )
                                : null,
                            onTap: () => Navigator.pop(ctx, model.id),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textSecondary(context)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        _modelNameController.text = selected;
      });
      _saveRemoteSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final llmProvider = Provider.of<LLMProvider>(context);
    final backend = llmProvider.activeBackend;

    return Dialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Model Settings',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: AppColors.textSecondary(context),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Backend toggle
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildToggleButton(
                      label: 'Local',
                      icon: Icons.computer,
                      isSelected: backend == BackendType.kobold,
                      onTap: () =>
                          llmProvider.setActiveBackend(BackendType.kobold),
                    ),
                  ),
                  Expanded(
                    child: _buildToggleButton(
                      label: 'Pseudo-Remote',
                      icon: Icons.laptop,
                      isSelected: backend == BackendType.pseudoRemote,
                      onTap: () => llmProvider.setActiveBackend(
                        BackendType.pseudoRemote,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _buildToggleButton(
                      label: 'Remote API',
                      icon: Icons.cloud,
                      isSelected: backend == BackendType.openRouter,
                      onTap: () =>
                          llmProvider.setActiveBackend(BackendType.openRouter),
                    ),
                  ),
                  if (Platform.isMacOS)
                    Expanded(
                      child: _buildToggleButton(
                        label: 'oMLX',
                        icon: Icons.apple,
                        isSelected: backend == BackendType.omlx,
                        onTap: () =>
                            llmProvider.setActiveBackend(BackendType.omlx),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Content area
            Flexible(
              child: SingleChildScrollView(
                child: backend == BackendType.kobold
                    ? _buildLocalSettings()
                    : backend == BackendType.pseudoRemote
                    ? _buildPseudoRemoteSettings()
                    : _buildRemoteSettings(isOmLx: backend == BackendType.omlx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? Colors.white
                  : AppColors.textSecondary(context),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : AppColors.textSecondary(context),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalSettings() {
    final storage = Provider.of<StorageService>(context);
    final modelManager = Provider.of<ModelManager>(context);
    final hardwareService = Provider.of<HardwareService>(context);
    final koboldService = Provider.of<KoboldService>(context);

    // Auto-select first model if none selected and models exist.
    // Skip when a kcpps preset with a valid model is active (use "Managed by kcpps")
    if (_selectedModelPath == null &&
        modelManager.models.isNotEmpty &&
        !(storage.kcppsHasModel && storage.kcppsModelFileExists)) {
      _selectedModelPath = modelManager.models.first.path;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ModelSelector(
          models: modelManager.models,
          selectedModelPath: _selectedModelPath,
          showManagedByKcpps:
              storage.kcppsHasModel && storage.kcppsModelFileExists,
          onChanged: (val) {
            if (val == null) {
              setState(() {
                _selectedModelPath = null;
              });
            } else {
              setState(() {
                _selectedModelPath = val;
              });
              storage.setLastUsedModelPath(val);
              final savedPreset = storage.modelPresetMap[val];
              if (savedPreset != null &&
                  savedPreset.isNotEmpty &&
                  File(savedPreset).existsSync()) {
                storage.setActiveKcppsPath(savedPreset);
              } else {
                storage.setActiveKcppsPath(null);
              }
              _applyAutoConfiguration();
            }
          },
        ),

        const SizedBox(height: 16),

        // Preset selection
        Consumer<StorageService>(
          builder: (context, storage, _) {
            final isPresetActive =
                storage.activeKcppsPath != null &&
                storage.activeKcppsPath!.isNotEmpty;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configuration Preset',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                const SizedBox(height: 8),
                KcppsSelector(
                  storage: storage,
                  localPresets: _localPresets,
                  hint: 'None (Use App Settings)',
                  onChanged: (val) {
                    storage.setActiveKcppsPath(val);
                    if (_selectedModelPath != null && val != null) {
                      storage.setModelPreset(_selectedModelPath!, val);
                    } else if (_selectedModelPath != null && val == null) {
                      storage.setModelPreset(_selectedModelPath!, '');
                    }
                    if (val != null &&
                        storage.kcppsHasModel &&
                        storage.kcppsModelFileExists) {
                      setState(() {
                        _selectedModelPath = null;
                      });
                    }
                  },
                  onExternalClear: () {
                    storage.setActiveKcppsPath(null);
                    if (_selectedModelPath != null) {
                      storage.setModelPreset(_selectedModelPath!, '');
                    }
                  },
                  onBrowsePicked: (path) {
                    if (_selectedModelPath != null) {
                      storage.setModelPreset(_selectedModelPath!, path);
                    }
                    _scanLocalPresets();
                    if (storage.kcppsHasModel && storage.kcppsModelFileExists) {
                      setState(() {
                        _selectedModelPath = null;
                      });
                    }
                  },
                  onModelStatusChanged: (_) {
                    setState(() {});
                  },
                ),
                const SizedBox(height: 16),

                // When a preset is active, show a clear label instead of just fading
                // the fields. Users need to know these controls are overridden.
                if (isPresetActive)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.3),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.amber,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Controlled by preset: ${path_lib.basename(storage.activeKcppsPath!)}',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                IgnorePointer(
                  ignoring: isPresetActive,
                  child: Opacity(
                    opacity: isPresetActive ? 0.4 : 1.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Hardware Info
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerOf(context),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: hardwareService.isDetecting
                              ? const Center(child: CircularProgressIndicator())
                              : hardwareService.hardwareInfo == null
                              ? const Text(
                                  'Hardware not detected.',
                                  style: TextStyle(color: Colors.redAccent),
                                )
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildInfoRow(
                                      'GPU',
                                      hardwareService.hardwareInfo!.gpuName,
                                    ),
                                    _buildInfoRow(
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
                              child: _buildTextField(
                                label: 'GPU Layers',
                                controller: _gpuLayersController,
                                isNumber: true,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: IgnorePointer(
                                ignoring: _isPresetActive(context),
                                child: Opacity(
                                  opacity: _isPresetActive(context) ? 0.5 : 1.0,
                                  child: _isPresetActive(context)
                                      ? Tooltip(
                                          message:
                                              'Context size is controlled by the active .kcpps preset and cannot be edited here.',
                                          child: _buildTextField(
                                            label: 'Context Size',
                                            controller: _contextSizeController,
                                            isNumber: true,
                                          ),
                                        )
                                      : _buildTextField(
                                          label: 'Context Size',
                                          controller: _contextSizeController,
                                          isNumber: true,
                                        ),
                                ),
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
                                  value: Provider.of<StorageService>(
                                    context,
                                  ).kvQuantizationLevel,
                                  isExpanded: true,
                                  dropdownColor: AppColors.surfaceContainerOf(
                                    context,
                                  ),
                                  style: TextStyle(
                                    color: AppColors.textPrimary(context),
                                    fontSize: 13,
                                  ),
                                  onChanged: (val) {
                                    if (val != null) {
                                      Provider.of<StorageService>(
                                        context,
                                        listen: false,
                                      ).setKvQuantizationLevel(val);
                                      setState(() {});
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
                            const SizedBox(width: 8),
                            Tooltip(
                              message:
                                  'Quantizes the context window to save significant VRAM with minimal quality loss. Note: KoboldCPP dynamically disables Context Shifting when this is active.',
                              child: Icon(
                                Icons.info_outline,
                                size: 16,
                                color: AppColors.iconSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                IgnorePointer(
                  ignoring: isPresetActive,
                  child: Opacity(
                    opacity: isPresetActive ? 0.4 : 1.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              onPressed: _applyAutoConfiguration,
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
                  ),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _restartBackend,
            icon: const Icon(Icons.refresh),
            label: Text(
              _isPresetActive(context)
                  ? (koboldService.isRunning
                        ? 'Restart with Preset'
                        : 'Start with Preset')
                  : (koboldService.isRunning
                        ? 'Restart Backend'
                        : 'Start Backend'),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRemoteSettings({bool isOmLx = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isOmLx) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.apple, color: Colors.blueAccent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'oMLX mode on Apple Silicon. URL fixed to http://localhost:8000/v1. oMLX must be running (`omlx serve`). Model name below is used for generation.',
                    style: TextStyle(fontSize: 11, color: Colors.blueAccent),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!isOmLx)
          _buildTextField(label: 'API URL', controller: _apiUrlController),
        if (!isOmLx) const SizedBox(height: 12),
        if (!isOmLx)
          _buildTextField(
            label: 'API Key',
            controller: _apiKeyController,
            isObscured: true,
          ),
        if (!isOmLx) const SizedBox(height: 12),
        // Model selector — tappable chip that opens a model picker dialog
        InkWell(
          onTap: () => _showModelPicker(),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(8),
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
                        _modelNameController.text.isEmpty
                            ? 'Tap to select a model...'
                            : _modelNameController.text,
                        style: TextStyle(
                          color: _modelNameController.text.isEmpty
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
        const SizedBox(height: 16),

        // Connection status
        if (_connectionStatus != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: _connectionStatus!.contains('successful')
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _connectionStatus!.contains('successful')
                    ? Colors.greenAccent.withValues(alpha: 0.3)
                    : Colors.redAccent.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              _connectionStatus!,
              style: TextStyle(
                color: _connectionStatus!.contains('successful')
                    ? Colors.greenAccent
                    : Colors.redAccent,
                fontSize: 13,
              ),
            ),
          ),

        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isTesting ? null : _testConnection,
                icon: _isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saveRemoteSettings,
                icon: const Icon(Icons.save),
                label: const Text('Save'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary(context),
                  side: BorderSide(color: AppColors.borderOf(context)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPseudoRemoteSettings() {
    final pseudoRemote = Provider.of<PseudoRemoteService>(context);
    final llmProvider = Provider.of<LLMProvider>(context);
    final anyRunning = llmProvider.hasAnyManagedProcessRunning;
    final storage = Provider.of<StorageService>(context);
    final modelManager = Provider.of<ModelManager>(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Configuration Preset (.kcpps)',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 8),
        KcppsSelector(
          storage: storage,
          localPresets: _localPresets,
          hint: 'Required — select a .kcpps preset',
          onChanged: (val) {
            storage.setActiveKcppsPath(val);
            if (val != null &&
                storage.kcppsHasModel &&
                storage.kcppsModelFileExists) {
              setState(() {
                _selectedModelPath = null;
              });
            }
          },
          onExternalClear: () {
            storage.setActiveKcppsPath(null);
          },
          onBrowsePicked: (_) {
            if (storage.kcppsHasModel && storage.kcppsModelFileExists) {
              setState(() {
                _selectedModelPath = null;
              });
            }
          },
          onModelStatusChanged: (_) {
            setState(() {});
          },
        ),
        const SizedBox(height: 16),

        ModelSelector(
          models: modelManager.models,
          selectedModelPath: _selectedModelPath,
          showManagedByKcpps:
              storage.kcppsHasModel && storage.kcppsModelFileExists,
          onChanged: (val) {
            if (val == null) {
              setState(() {
                _selectedModelPath = null;
              });
            } else {
              setState(() {
                _selectedModelPath = val;
              });
              storage.setLastUsedModelPath(val);
              final savedPreset = storage.modelPresetMap[val];
              if (savedPreset != null &&
                  savedPreset.isNotEmpty &&
                  File(savedPreset).existsSync()) {
                storage.setActiveKcppsPath(savedPreset);
              } else {
                storage.setActiveKcppsPath(null);
              }
              _applyAutoConfiguration();
            }
          },
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: anyRunning
                ? () => _stopManagedBackend(context)
                : (storage.activeKcppsPath == null ||
                      storage.activeKcppsPath!.isEmpty ||
                      !(storage.kcppsHasModel &&
                              storage.kcppsModelFileExists) &&
                          _selectedModelPath == null)
                ? null
                : () => _startPseudoRemote(context),
            icon: Icon(anyRunning ? Icons.stop : Icons.play_arrow),
            label: Text(anyRunning ? 'Stop Backend' : 'Start Pseudo-Remote'),
            style: ElevatedButton.styleFrom(
              backgroundColor: anyRunning
                  ? Colors.redAccent
                  : Colors.greenAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Process Logs',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 8),
        LogView(logs: pseudoRemote.logs),
      ],
    );
  }

  void _stopManagedBackend(BuildContext context) {
    Provider.of<LLMProvider>(context, listen: false).stopAllManagedProcesses();
  }

  Future<void> _startPseudoRemote(BuildContext context) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final backendManager = Provider.of<BackendManager>(context, listen: false);
    final pseudoRemote = Provider.of<PseudoRemoteService>(
      context,
      listen: false,
    );

    if (backendManager.backendPath == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Backend not found.')));
      return;
    }
    if (storage.activeKcppsPath == null || storage.activeKcppsPath!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a .kcpps preset first.')),
      );
      return;
    }

    // If the preset has no valid model, the user must have selected one manually
    final overrideModel =
        (storage.kcppsHasModel && storage.kcppsModelFileExists)
        ? null
        : _selectedModelPath;

    await pseudoRemote.start(
      executablePath: backendManager.backendPath!,
      kcppsPath: storage.activeKcppsPath!,
      modelPath: overrideModel,
    );
  }

  Widget _buildInfoRow(String label, String value) {
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

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool isNumber = false,
    bool isObscured = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      obscureText: isObscured,
      style: TextStyle(color: AppColors.textPrimary(context)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary(context)),
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
