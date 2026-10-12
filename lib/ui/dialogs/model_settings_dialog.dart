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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Barrel imports
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

// Not in barrels (internal or low-frequency)
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/backend.dart';
import 'package:front_porch_ai/ui/dialogs/model_settings/model_settings.dart';
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';
import 'package:front_porch_ai/utils/utils.dart';

class ModelSettingsDialog extends StatefulWidget {
  const ModelSettingsDialog({super.key});

  @override
  State<ModelSettingsDialog> createState() => _ModelSettingsDialogState();
}

class _ModelSettingsDialogState extends State<ModelSettingsDialog> {
  // Local backend fields
  final _gpuLayersController = TextEditingController(text: '0');
  final _contextSizeController = TextEditingController(text: '');
  String? _selectedModelPath;

  /// The preset the context box was last brought in step with.
  String? _contextPreset;

  // Remote API fields
  final _apiUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelNameController = TextEditingController();
  String? _connectionStatus;
  bool _isTesting = false;
  bool _showKeyEditor = false;
  bool _xaiKeyOpen = false;

  // Preset fields
  List<File> _localPresets = [];
  final _kcppsModelExists = PathExistsMemo();

  @override
  void initState() {
    super.initState();
    final storage = Provider.of<StorageService>(context, listen: false);
    // Local settings
    _selectedModelPath = storage.backendSettings.lastUsedModelPath;
    _gpuLayersController.text = storage.backendSettings.gpuLayers.toString();
    _contextSizeController.text = storage.backendSettings.contextSize
        .toString();
    _contextPreset = storage.backendSettings.activeKcppsPath;
    // Remote settings
    _apiUrlController.text = storage.backendSettings.remoteApiUrl;
    _apiKeyController.text = typedRemoteApiKey(storage.backendSettings);
    _modelNameController.text = storage.backendSettings.remoteModelName;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scanLocalPresets();
    });
  }

  void _scanLocalPresets() {
    final storage = Provider.of<StorageService>(context, listen: false);
    setState(() {
      _localPresets = kcppsPresetFiles(storage.binDir.path);
    });
  }

  /// The user chose [path] as the preset, from the list or with Browse, or
  /// none when it is null. It is kept for the model it loads
  /// ([chooseKoboldPreset]). A running engine is left alone: the start button
  /// below applies it.
  Future<void> _choosePreset(String? path) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    await chooseKoboldPreset(storage, path);
    if (!mounted) return;
    // A preset that names its model on this computer owns the choice.
    if (path != null &&
        storage.backendSettings.kcppsHasModel &&
        _kcppsModelExists.of(storage.backendSettings.kcppsModelPath)) {
      setState(() {
        _selectedModelPath = null;
      });
    }
  }

  Future<void> _browsePicked(String path) async {
    await _choosePreset(path);
    if (mounted) _scanLocalPresets();
  }

  Future<void> _restartBackend() =>
      restartKoboldBackend(context, pickedModel: () => _selectedModelPath);

  void _saveRemoteSettings({bool snackbar = false}) {
    final storage = Provider.of<StorageService>(context, listen: false);
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    saveRemoteApiSettings(
      storage,
      activeBackend: llmProvider.activeBackend,
      apiUrl: _apiUrlController.text,
      apiKey: _apiKeyController.text,
      modelName: _modelNameController.text,
    );
    if (snackbar) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('API settings saved.')));
    }
  }

  String _probeKeyFor(String apiUrl) => remoteProbeKey(
    Provider.of<StorageService>(context, listen: false),
    typedKey: _apiKeyController.text,
    apiUrl: apiUrl,
  );

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _connectionStatus = null;
    });
    _saveRemoteSettings();
    final openRouter = Provider.of<OpenRouterService>(context, listen: false);
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    // Force oMLX localhost URL when oMLX backend is active (ignores whatever is in the URL field)
    final apiUrl = remoteProbeUrl(
      llmProvider.activeBackend,
      _apiUrlController.text,
    );
    // Override form — NEVER configure() the live service just to probe
    // (that silently re-routes active chat traffic; see the service's own
    // fetchAvailableModels doc note).
    final result = await openRouter.testConnection(
      apiUrl: apiUrl,
      apiKey: _probeKeyFor(apiUrl),
    );
    if (mounted) {
      setState(() {
        _isTesting = false;
        _connectionStatus = result;
      });
    }
  }

  Future<void> _showModelPicker() async {
    // Resolve the target from the backend selected AT TAP TIME — after an
    // oMLX ↔ Remote toggle the picker must ask the NEWLY selected provider
    // (maintainer bug: it choked asking the remote provider with the stale
    // pre-toggle configuration).
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final apiUrl = remoteProbeUrl(
      llmProvider.activeBackend,
      _apiUrlController.text,
    );
    final selected = await pickRemoteModel(
      context,
      apiUrl: apiUrl,
      apiKey: _probeKeyFor(apiUrl),
      currentModel: _modelNameController.text,
    );
    if (selected != null && mounted) {
      setState(() {
        _modelNameController.text = selected;
      });
      _saveRemoteSettings();
    }
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

  @override
  Widget build(BuildContext context) {
    final llmProvider = Provider.of<LLMProvider>(context);
    final storage = Provider.of<StorageService>(context);
    final backend = llmProvider.activeBackend;
    final providerKind = resolveRemoteProviderKind(
      backendType: switch (backend) {
        BackendType.kobold => 'kobold',
        BackendType.omlx => 'omlx',
        BackendType.openRouter => 'openRouter',
      },
      url: storage.backendSettings.remoteApiUrl,
    );

    return Dialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 540,
        constraints: const BoxConstraints(maxHeight: 680),
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

            RemoteProviderBar(
              selected: providerKind,
              showOmlx: Platform.isMacOS,
              onSelected: (kind) async {
                await applyRemoteProvider(
                  kind: kind,
                  storage: storage,
                  llm: llmProvider,
                  urlController: _apiUrlController,
                  keyController: _apiKeyController,
                  modelController: _modelNameController,
                );
                if (!mounted) return;
                setState(() {
                  _showKeyEditor = false;
                  _connectionStatus = null;
                });
              },
            ),
            const SizedBox(height: 16),

            // Content area
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    backend == BackendType.kobold
                        ? _localSettings()
                        : _remoteSettings(isOmLx: backend == BackendType.omlx),
                    // Same widget + prefs as Settings → Backend (H0: under
                    // the chat stack, not a twin host/key row above the key).
                    WorkerBackendSection(
                      kcppsPresets: _localPresets,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _localSettings() {
    final storage = Provider.of<StorageService>(context);
    final modelManager = Provider.of<ModelManager>(context);
    final hardwareService = Provider.of<HardwareService>(context);
    final koboldService = Provider.of<KoboldService>(context);
    // Start on the last-used model when the scan has it, else nothing chosen.
    // Skip when a kcpps preset with a valid model is active (use "Managed by kcpps").
    // Gate the exists memo on kcppsHasModel — same short-circuit the old
    // `kcppsHasModel && kcppsModelFileExists` used — so a rebuild without a
    // preset never reads kcppsModelPath or stats a file.
    final kcppsModelExists =
        storage.backendSettings.kcppsHasModel &&
        _kcppsModelExists.of(storage.backendSettings.kcppsModelPath);
    if (_selectedModelPath == null &&
        modelManager.models.isNotEmpty &&
        !kcppsModelExists) {
      _selectedModelPath = modelListStart(
        modelManager.models,
        storage.backendSettings.lastUsedModelPath,
      );
    }
    // A preset sets its own context, so the box follows the preset that is
    // active instead of showing what it held when the dialog opened.
    final activePreset = storage.backendSettings.activeKcppsPath;
    if (activePreset != _contextPreset) {
      _contextPreset = activePreset;
      _contextSizeController.text = storage.backendSettings.contextSize
          .toString();
    }

    return LocalBackendSettings(
      storage: storage,
      models: modelManager.models,
      selectedModelPath: _selectedModelPath,
      showManagedByKcpps:
          storage.backendSettings.kcppsHasModel && kcppsModelExists,
      hardware: hardwareService,
      koboldRunning: koboldService.isRunning,
      localPresets: _localPresets,
      gpuLayersController: _gpuLayersController,
      contextSizeController: _contextSizeController,
      onModelChanged: (val) {
        if (val == null) {
          setState(() {
            _selectedModelPath = null;
          });
        } else {
          setState(() {
            _selectedModelPath = val;
          });
          selectKoboldModel(storage, val);
        }
      },
      onChoosePreset: _choosePreset,
      onBrowsePicked: _browsePicked,
      onRefresh: () => setState(() {}),
      onRestart: _restartBackend,
    );
  }

  Widget _remoteSettings({bool isOmLx = false}) {
    return RemoteBackendSettings(
      isOmLx: isOmLx,
      apiUrlController: _apiUrlController,
      apiKeyController: _apiKeyController,
      modelName: _modelNameController.text,
      showKeyEditor: _showKeyEditor,
      xaiKeyOpen: _xaiKeyOpen,
      connectionStatus: _connectionStatus,
      isTesting: _isTesting,
      onSave: _saveRemoteSettings,
      onKeySubmitted: () {
        _saveRemoteSettings();
        setState(() => _showKeyEditor = false);
      },
      onOpenXaiKey: () => setState(() => _xaiKeyOpen = true),
      onEditKey: () => setState(() => _showKeyEditor = true),
      onPickModel: () => _showModelPicker(),
      onTest: _testConnection,
    );
  }
}
