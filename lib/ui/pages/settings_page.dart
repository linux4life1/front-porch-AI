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
import 'package:path/path.dart' as p;

// Barrel imports (high-frequency services + widgets)
import 'package:front_porch_ai/services/gpu_backend_resolver.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

// Modules and dialogs not in the barrels (internal, low-frequency, or single-use)
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/optimization_service.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';
import 'package:front_porch_ai/ui/dialogs/web_access_setup_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/rocm_guidance_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/database_cleanup_dialog.dart';

import 'package:front_porch_ai/ui/settings/widgets/section_header.dart';
import 'package:front_porch_ai/ui/settings/tabs/general_tab.dart';
import 'package:front_porch_ai/ui/settings/tabs/generation_tab.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend_tab.dart';

import 'package:front_porch_ai/ui/settings/tabs/voice_media_tab.dart';
import 'package:front_porch_ai/ui/settings/widgets/web_login_section.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';
// Note: Image Generation *config* options (backend / model / LoRAs) live in a first-class
// tab-like panel inside the Image Studio (see generation_options_tab.dart + studio integration).
// Only the discoverable on/off switch was re-surfaced in the Voice & Media tab via
// ImageGenEnableSection — the chat toolbar's Image Studio button stays hidden until it is on.

// The Advanced tab and backend-launch orchestration live in these `part of`
// files (extensions on _SettingsPageState) to keep every file under the
// 500-LOC cap — same pattern chat_service.dart uses. They share this library's
// imports and access the page's private state directly, so behavior is
// unchanged.
part 'settings_page.controls.dart';
part 'settings_page.advanced.dart';
part 'settings_page.hardware.dart';
part 'settings_page.gpu.dart';
part 'settings_page.launch.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _gpuLayersController = TextEditingController(text: '0');
  final _contextSizeController = TextEditingController(text: '16384');
  double? _dragContextSize;
  double? _dragCallBuffer;
  final _apiController = TextEditingController();
  final _remoteApiUrlController = TextEditingController();
  final _remoteApiKeyController = TextEditingController();
  bool _useVulkan = false;
  bool _useCublas = false;
  bool _useMetal = false;
  bool _useRocm = false;
  String? _selectedModelPath;
  final TextEditingController _systemPromptController = TextEditingController();
  final TextEditingController _bannedPhrasesController =
      TextEditingController();

  // Remote API state (the fetched model list is shared with the Voice tab;
  // the fetch/check spinners now live in the extracted backend sections).
  List<RemoteModelInfo> _availableModels = [];

  // Local Preset state
  List<File> _localPresets = [];

  @override
  void initState() {
    super.initState();
    _apiController.text = Provider.of<KoboldService>(
      context,
      listen: false,
    ).baseUrl;
    _systemPromptController.text = Provider.of<StorageService>(
      context,
      listen: false,
    ).systemPrompt;
    _bannedPhrasesController.text = Provider.of<StorageService>(
      context,
      listen: false,
    ).bannedPhrases.join('\n');
    _remoteApiUrlController.text = Provider.of<StorageService>(
      context,
      listen: false,
    ).backendSettings.remoteApiUrl;
    _remoteApiKeyController.text = Provider.of<StorageService>(
      context,
      listen: false,
    ).backendSettings.remoteApiKey;

    // Sync local state with storage
    final storage = Provider.of<StorageService>(context, listen: false);
    // Default to false if null, logic below handles the "first run" auto-enable
    _useCublas = storage.useCublas == true;
    _useVulkan = storage.useVulkan == true;
    _useMetal = storage.useMetal == true;
    // Apply hardware-based defaults once hardware info is available.
    // HardwareService.detectHardware() is already called in its constructor,
    // so we just use the cached result. If detection is still in progress,
    // listen for changes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final hardwareService = Provider.of<HardwareService>(
        context,
        listen: false,
      );

      if (hardwareService.hardwareInfo != null) {
        _applyHardwareDefaults(hardwareService.hardwareInfo!);
      } else {
        // Detection still in progress — listen for completion
        void listener() {
          if (!mounted) return;
          if (!hardwareService.isDetecting &&
              hardwareService.hardwareInfo != null) {
            hardwareService.removeListener(listener);
            _applyHardwareDefaults(hardwareService.hardwareInfo!);
          }
        }

        hardwareService.addListener(listener);
      }

      // Auto-fetch available models if API is configured
      _autoFetchModels();

      // Auto-fetch .kcpps presets
      _scanLocalPresets();
    });
  }

  void _scanLocalPresets() {
    final storage = Provider.of<StorageService>(context, listen: false);
    final files = scanKcppsPresets(storage.binDir);
    setState(() {
      _localPresets = files;
    });
  }

  /// Fetch available models from the configured API on startup.
  void _autoFetchModels() async {
    final storage = Provider.of<StorageService>(context, listen: false);
    // Allow empty API key for local backends (LM Studio, vLLM, etc.)
    final isLocal =
        storage.remoteApiUrl.contains('localhost') ||
        storage.remoteApiUrl.contains('127.0.0.1');
    if (storage.remoteApiUrl.isEmpty) return; // No API URL configured
    if (storage.remoteApiKey.isEmpty && !isLocal) return; // no API configured

    final openRouter = Provider.of<OpenRouterService>(context, listen: false);
    // Explicit-target fetch — configure() here silently re-routed the ACTIVE
    // backend (opening Settings while on oMLX pointed all chat traffic at the
    // Remote API provider until the next storage sync).
    try {
      final models = await openRouter.fetchAvailableModels(
        apiUrl: storage.remoteApiUrl,
        apiKey: storage.remoteApiKey,
      );
      if (mounted && models.isNotEmpty) {
        setState(() => _availableModels = models);
      }
    } catch (_) {
      // Silent fail on startup — user can manually refresh
    }
  }

  /// Re-exposes the protected [setState] for the `part of` extensions
  /// (`settings_page.*.dart`), which hold the Advanced tab and launch
  /// orchestration but can't call a State's protected members directly.
  void rebuildState(VoidCallback fn) => setState(fn);

  @override
  void dispose() {
    _gpuLayersController.dispose();
    _contextSizeController.dispose();
    _apiController.dispose();
    _remoteApiUrlController.dispose();
    _remoteApiKeyController.dispose();
    _bannedPhrasesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        DefaultTabController(
          length: 5,
          child: Scaffold(
            backgroundColor: AppColors.backgroundOf(
              context,
            ).withValues(alpha: 0),
            appBar: AppBar(
              title: Text('Settings', style: theme.textTheme.titleLarge),
              backgroundColor: AppColors.backgroundOf(
                context,
              ).withValues(alpha: 0),
              elevation: 0,
              iconTheme: theme.iconTheme,
              bottom: TabBar(
                labelColor: AppColors.textPrimary(context),
                unselectedLabelColor: AppColors.textSecondary(context),
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                overlayColor: WidgetStateProperty.all(
                  AppColors.surfaceOf(context).withValues(alpha: 0),
                ),
                splashFactory: NoSplash.splashFactory,
                tabs: const [
                  Tab(text: 'General'),
                  Tab(text: 'Generation'),
                  Tab(text: 'Voice & Media'),
                  Tab(text: 'Backend'),
                  Tab(text: 'Advanced'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                GeneralTab(systemPromptController: _systemPromptController),
                GenerationTab(
                  bannedPhrasesController: _bannedPhrasesController,
                ),
                VoiceMediaTab(
                  dragCallBuffer: _dragCallBuffer,
                  onDragCallBufferChanged: (v) =>
                      setState(() => _dragCallBuffer = v),
                  availableModels: _availableModels,
                ),
                _backendTab(),
                _buildAdvancedTab(context),
              ],
            ),
          ),
        ),
        // Glassmorphic download overlay — shown only while ONNX model is downloading
        Consumer<ExpressionClassifierService>(
          builder: (context, expressionService, _) {
            if (!expressionService.isDownloading) {
              return const SizedBox.shrink();
            }
            return OnnxDownloadOverlay(classifierService: expressionService);
          },
        ),
      ],
    );
  }

  // _buildOnnxDownloadButton deleted (dead after voice extraction + lift of copy to voice tab; deletion part of task).

  // _buildGeneralTab extracted to lib/ui/settings/tabs/general_tab.dart (Stage 5 remaining tabs step); deletion part of task.
  // Shell now delegates; state passed via ctor.

  // _buildColorRow deleted (dead after general tab extraction; deletion part of task).

  // _buildVoiceMediaTab extracted to VoiceMediaTab (Stage 5; largest tab first per plan;
  // full lift + AppColors exclusive + shared state via ctor; body deleted as part of task).
  // See lib/ui/settings/tabs/voice_media_tab.dart

  /// Backend tab: thin wrapper that wires the extracted [BackendTab] widget
  /// with the page's shared launch state. The auto-select-first-model default
  /// and every state-mutating callback are the original _buildBackendTab
  /// closures, moved here verbatim so launch behavior is unchanged.
  Widget _backendTab() {
    final storageService = Provider.of<StorageService>(context);
    final modelManager = Provider.of<ModelManager>(context);

    // Auto-select first model if none selected and models exist. Skip when a
    // kcpps preset with a valid model is active (use "Managed by kcpps").
    if (_selectedModelPath == null &&
        modelManager.models.isNotEmpty &&
        !(storageService.kcppsHasModel &&
            storageService.kcppsModelFileExists)) {
      _selectedModelPath = modelManager.models.first.path;
    }
    // Warm architecture info for the (possibly just auto-selected) model so
    // the first Auto-Configure or gauge update is accurate.
    if (_selectedModelPath != null) {
      modelManager.getModelArchitectureInfo(_selectedModelPath!);
    }

    return BackendTab(
      apiUrlController: _remoteApiUrlController,
      apiKeyController: _remoteApiKeyController,
      availableModels: _availableModels,
      onModelsFetched: (m) => setState(() => _availableModels = m),
      selectedModelPath: _selectedModelPath,
      localPresets: _localPresets,
      onModelSelected: (val) {
        if (val == null) {
          setState(() {
            _selectedModelPath = null;
          });
        } else {
          setState(() {
            _selectedModelPath = val;
          });
          storageService.setLastUsedModelPath(val);
          final savedPreset = storageService.modelPresetMap[val];
          if (savedPreset != null &&
              savedPreset.isNotEmpty &&
              File(savedPreset).existsSync()) {
            storageService.setActiveKcppsPath(savedPreset);
          } else {
            storageService.setActiveKcppsPath(null);
          }

          // Eagerly warm the GGUF architecture + KV cache so that
          // Auto-Configure (and the live VRAM gauge) get accurate
          // nLayers / bytes-per-layer on the first click instead of
          // falling back to weaker heuristics.
          modelManager.getModelArchitectureInfo(val); // fire-and-forget

          _applyAutoConfiguration(silent: true);
        }
      },
      onVisionChanged: () => setState(() {}),
      onScanPresets: _scanLocalPresets,
      onKcppsChanged: (val) {
        storageService.setActiveKcppsPath(val);
        if (_selectedModelPath != null && val != null) {
          storageService.setModelPreset(_selectedModelPath!, val);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Preset saved for model: ${p.basename(_selectedModelPath!)}',
              ),
            ),
          );
        } else if (_selectedModelPath != null && val == null) {
          storageService.setModelPreset(_selectedModelPath!, '');
        }
        if (val != null &&
            storageService.kcppsHasModel &&
            storageService.kcppsModelFileExists) {
          setState(() {
            _selectedModelPath = null;
          });
        }
      },
      onKcppsExternalClear: () {
        storageService.setActiveKcppsPath(null);
        if (_selectedModelPath != null) {
          storageService.setModelPreset(_selectedModelPath!, '');
        }
      },
      onKcppsBrowsePicked: (path) {
        if (_selectedModelPath != null) {
          storageService.setModelPreset(_selectedModelPath!, path);
        }
        _scanLocalPresets();
        if (storageService.kcppsHasModel &&
            storageService.kcppsModelFileExists) {
          setState(() {
            _selectedModelPath = null;
          });
        }
      },
      onKcppsModelStatusChanged: (_) {
        setState(() {});
      },
      onGenerateKcppsDone: () {
        _scanLocalPresets();
        setState(() {});
      },
      onToggleBackend: () => _toggleManagedBackend(context),
    );
  }

  bool _advancedLaunchExpanded = false;

  // _showSavePromptDialog extracted to lib/ui/settings/dialogs/prompt_save_dialog.dart (Stage 5 helper dialogs step); deletion part of task.

  // _showDeletePromptDialog extracted to lib/ui/settings/dialogs/prompt_delete_dialog.dart (Stage 5); deletion part of task.
}

// _showColorPicker extracted to lib/ui/settings/dialogs/color_picker_dialog.dart (Stage 5 helper dialogs); deletion part of task.
