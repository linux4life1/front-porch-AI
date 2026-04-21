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
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:front_porch_ai/services/hardware_service.dart';
import 'package:front_porch_ai/services/optimization_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/ui/widgets/log_view.dart';
import 'package:front_porch_ai/ui/dialogs/rocm_guidance_dialog.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/services/update_service.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/stt_service.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/folder_service.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/web_server_service.dart';
import 'package:front_porch_ai/ui/dialogs/tts_settings_dialog.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/ui/dialogs/image_gen_settings_dialog.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _gpuLayersController = TextEditingController(text: '0');
  final _contextSizeController = TextEditingController(text: '8192');
  double _contextSizeValue = 8192;
  final _apiController = TextEditingController();
  final _remoteApiUrlController = TextEditingController();
  final _remoteApiKeyController = TextEditingController();
  bool _useVulkan = false;
  bool _useCublas = false;
  bool _useMetal = false;
  bool _useRocm = false;
  String? _selectedModelPath;
  late final TextEditingController _systemPromptController;
  late final TextEditingController _bannedPhrasesController;

  // Remote API state
  List<RemoteModelInfo> _availableModels = [];
  bool _isFetchingModels = false;
  bool _isCheckingConnection = false;

  @override
  void initState() {
    super.initState();
    _apiController.text = Provider.of<KoboldService>(
      context,
      listen: false,
    ).baseUrl;
    _systemPromptController = TextEditingController(
      text: Provider.of<StorageService>(context, listen: false).systemPrompt,
    );
    _bannedPhrasesController = TextEditingController(
      text: Provider.of<StorageService>(
        context,
        listen: false,
      ).bannedPhrases.join('\n'),
    );
    _remoteApiUrlController.text = Provider.of<StorageService>(
      context,
      listen: false,
    ).remoteApiUrl;
    _remoteApiKeyController.text = Provider.of<StorageService>(
      context,
      listen: false,
    ).remoteApiKey;

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
    openRouter.configure(
      apiUrl: storage.remoteApiUrl,
      apiKey: storage.remoteApiKey,
    );

    try {
      final models = await openRouter.fetchAvailableModels();
      if (mounted && models.isNotEmpty) {
        setState(() => _availableModels = models);
      }
    } catch (_) {
      // Silent fail on startup — user can manually refresh
    }
  }

  /// Apply GPU defaults based on detected hardware info.
  void _applyHardwareDefaults(HardwareInfo hw) {
    final storage = Provider.of<StorageService>(context, listen: false);
    bool changed = false;

    // NVIDIA Logic: Default to CuBLAS if not set
    if (hw.vendor == 'Nvidia') {
      if (storage.useCublas == null) {
        storage.setUseCublas(true);
        storage.setUseVulkan(false);
        _useCublas = true;
        _useVulkan = false;
        changed = true;
      } else {
        _useCublas = storage.useCublas!;
        if (storage.useVulkan != null) {
          _useVulkan = storage.useVulkan!;
        } else if (_useCublas) {
          _useVulkan = false;
        }
      }
    }
    // MacOS Logic: Default to Metal if not set
    else if (Platform.isMacOS) {
      if (storage.useMetal == null) {
        storage.setUseMetal(true);
        storage.setUseVulkan(false);
        storage.setUseCublas(false);
        _useMetal = true;
        _useVulkan = false;
        _useCublas = false;
        changed = true;
      } else {
        _useMetal = storage.useMetal!;
        if (storage.useVulkan != null) _useVulkan = storage.useVulkan!;
        if (storage.useCublas != null) _useCublas = storage.useCublas!;
        if (storage.useRocm != null) _useRocm = storage.useRocm!;
      }
    }
    // Non-NVIDIA/Non-Mac Logic: Default to ROCm if available, else Vulkan
    else {
      if (storage.useVulkan == null && storage.useRocm == null) {
        // First run: auto-detect best GPU backend
        if (hw.vendor == 'AMD' && Platform.isLinux && hw.hasRocm) {
          storage.setUseRocm(true);
          storage.setUseVulkan(false);
          storage.setUseCublas(false);
          storage.setUseMetal(false);
          _useRocm = true;
          _useVulkan = false;
          _useCublas = false;
          _useMetal = false;
        } else {
          storage.setUseVulkan(true);
          storage.setUseCublas(false);
          storage.setUseMetal(false);
          storage.setUseRocm(false);
          _useVulkan = true;
          _useCublas = false;
          _useMetal = false;
          _useRocm = false;
        }
        changed = true;
      } else {
        _useVulkan = storage.useVulkan ?? false;
        if (storage.useCublas != null) _useCublas = storage.useCublas!;
        if (storage.useMetal != null) _useMetal = storage.useMetal!;
        if (storage.useRocm != null) _useRocm = storage.useRocm!;
      }
    }

    if (changed) {
      setState(() {});
      final String msg;
      if (hw.vendor == 'Nvidia') {
        msg = 'NVIDIA GPU detected: CuBLAS enabled.';
      } else if (Platform.isMacOS) {
        msg = 'Apple Silicon detected: Metal enabled.';
      } else if (hw.vendor == 'AMD' && Platform.isLinux && hw.hasRocm) {
        msg = 'AMD GPU detected: ROCm enabled for native GPU acceleration.';
      } else if (hw.vendor == 'AMD' &&
          Platform.isLinux &&
          hw.hasRocm == false) {
        msg =
            'AMD GPU detected: Vulkan enabled. Install ROCm for better performance.';
        showRocmGuidanceDialog(context, hw.linuxDistro);
      } else {
        msg = 'Non-NVIDIA GPU detected: Vulkan enabled.';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } else {
      // Just update UI to match loaded persistence
      setState(() {});
    }

    // Trigger silent autoconfig on load if model is present
    // BUT only if user hasn't manually customized GPU layers.
    // A non-zero persisted gpuLayers means the user or a previous
    // explicit auto-config set it — don't silently overwrite.
    if (_selectedModelPath != null && storage.gpuLayers == 0) {
      _applyAutoConfiguration(silent: true);
    } else if (_selectedModelPath != null) {
      // Respect previously saved settings — just load them into the UI
      _gpuLayersController.text = storage.gpuLayers.toString();
      _contextSizeController.text = storage.contextSize.toString();
    }
  }

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

  Future<void> _pickStoragePath() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory != null) {
      if (mounted) {
        // Close the current database so the file can be moved
        await AppDatabase.closeAndReset();
        await Provider.of<StorageService>(
          context,
          listen: false,
        ).setRootPath(selectedDirectory);
        // Reopen the database from the new location
        final newDb = await AppDatabase.instance();
        // Update ALL downstream services that hold a DB reference
        if (mounted) {
          Provider.of<CharacterRepository>(
            context,
            listen: false,
          ).updateDatabase(newDb);
          Provider.of<FolderService>(
            context,
            listen: false,
          ).updateDatabase(newDb);
          Provider.of<UserPersonaService>(
            context,
            listen: false,
          ).updateDatabase(newDb);
          Provider.of<GroupChatRepository>(
            context,
            listen: false,
          ).updateDatabase(newDb);
          Provider.of<WorldRepository>(
            context,
            listen: false,
          ).updateDatabase(newDb);
          Provider.of<ChatService>(
            context,
            listen: false,
          ).updateDatabase(newDb);
          // Reload data from the new DB location
          await Provider.of<CharacterRepository>(
            context,
            listen: false,
          ).loadCharacters();
          await Provider.of<FolderService>(context, listen: false).reload();
          // Refresh backend/models after path change
          Provider.of<BackendManager>(
            context,
            listen: false,
          ).checkBackendAvailability();
          Provider.of<ModelManager>(context, listen: false).refreshModels();
        }
      }
    }
  }

  void _applyAutoConfiguration({bool silent = false}) {
    final hardware = Provider.of<HardwareService>(
      context,
      listen: false,
    ).hardwareInfo;
    if (hardware == null) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hardware not detected yet.')),
        );
      }
      return;
    }

    if (silent) {
      _runOptimization(hardware.vramMb, hardware, silent: true);
    } else {
      final vramController = TextEditingController(
        text: hardware.vramMb.toString(),
      );
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text(
            'Auto-Configuration',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Confirm your System VRAM (MB):',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: vramController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Note: Some systems report incorrect VRAM (e.g. 4095MB for >4GB cards). Adjust if necessary.',
                style: TextStyle(color: Colors.white30, fontSize: 10),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final adjustedVram =
                    int.tryParse(vramController.text) ?? hardware.vramMb;
                Navigator.pop(context);
                _runOptimization(adjustedVram, hardware, silent: false);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      );
    }
  }

  void _runOptimization(
    int vramMb,
    HardwareInfo hardware, {
    required bool silent,
  }) {
    // Create temp hardware info with adjusted VRAM
    final adjustedHw = HardwareInfo(
      gpuName: hardware.gpuName,
      vramMb: vramMb,
      ramMb: hardware.ramMb,
      vendor: hardware.vendor,
    );

    // Attempt to estimate model size from selected model
    int modelSize = 5000;
    if (_selectedModelPath != null) {
      try {
        final file = File(_selectedModelPath!);
        if (file.existsSync()) {
          modelSize = (file.lengthSync() / (1024 * 1024)).round();
        }
      } catch (e) {
        print('Error getting file size: $e');
      }
    }

    // Respect user's context size — pass it to the optimizer so only GPU layers adjust
    final userContext = int.tryParse(_contextSizeController.text);

    int? kvBytesPerToken;
    if (_selectedModelPath != null && mounted) {
      final modelManager = Provider.of<ModelManager>(context, listen: false);
      kvBytesPerToken = modelManager.getCachedKvBytesPerToken(
        _selectedModelPath!,
      );
    }

    final suggestion = OptimizationService.calculateSettings(
      adjustedHw,
      modelSizeMb: modelSize,
      requestedContextSize: userContext,
      kvBytesPerToken: kvBytesPerToken,
      kvQuantizationLevel: Provider.of<StorageService>(
        context,
        listen: false,
      ).kvQuantizationLevel,
    );

    // Persist settings to storage so they survive app restart
    final storage = Provider.of<StorageService>(context, listen: false);
    storage.setGpuLayers(suggestion.gpuLayers);
    storage.setContextSize(suggestion.contextSize);

    setState(() {
      _gpuLayersController.text = suggestion.gpuLayers.toString();
      _contextSizeController.text = suggestion.contextSize.toString();
      // If user has Mac, suggest Metal
      if (Platform.isMacOS) {
        _useMetal = true;
        _useVulkan = false;
        _useCublas = false;
        storage.setUseMetal(true);
        storage.setUseVulkan(false);
        storage.setUseCublas(false);
      }
      // If user has Nvidia, suggest Cublas instead of Vulkan usually
      else if (hardware.vendor == 'Nvidia') {
        _useCublas = true;
        _useVulkan = false;
        _useMetal = false;
        storage.setUseCublas(true);
        storage.setUseVulkan(false);
      } else {
        _useCublas = false;
        _useMetal = false;
      }
    });

    if (!silent) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(suggestion.reasoning)));
    }
  }

  void _autoConfigure() {
    _applyAutoConfiguration(silent: false);
  }

  Future<void> _toggleKobold(BuildContext context) async {
    final koboldService = Provider.of<KoboldService>(context, listen: false);
    final backendManager = Provider.of<BackendManager>(context, listen: false);

    if (koboldService.isRunning) {
      await koboldService.stopKobold();
    } else {
      if (backendManager.backendPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backend not found. Please download it first.'),
          ),
        );
        return;
      }
      if (_selectedModelPath == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please select a model.')));
        return;
      }

      // Check if model file actually exists
      if (!File(_selectedModelPath!).existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selected model file does not exist!')),
        );
        return;
      }

      final gpuLayers = int.tryParse(_gpuLayersController.text) ?? 0;
      final contextSize = int.tryParse(_contextSizeController.text) ?? 4096;

      // Persist settings so autostart uses them on next launch
      final storage = Provider.of<StorageService>(context, listen: false);
      storage.setGpuLayers(gpuLayers);
      storage.setContextSize(contextSize);
      storage.setUseCublas(_useCublas);
      storage.setUseVulkan(_useVulkan);
      storage.setUseMetal(_useMetal);
      storage.setUseRocm(_useRocm);

      koboldService.startKobold(
        backendManager.backendPath!,
        _selectedModelPath!,
        gpuLayers: gpuLayers,
        contextSize: contextSize,
        useVulkan: _useVulkan,
        useCublas: _useCublas,
        useMetal: _useMetal,
        useRocm: _useRocm,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text('Settings', style: theme.textTheme.titleLarge),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: theme.iconTheme,
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            overlayColor: WidgetStateProperty.all(Colors.transparent),
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
            _buildGeneralTab(context),
            _buildGenerationTab(context),
            _buildVoiceMediaTab(context),
            _buildBackendTab(context),
            _buildAdvancedTab(context),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralTab(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Dark Mode', style: theme.textTheme.titleMedium),
              Switch(
                value: Provider.of<AppState>(context).darkMode,
                onChanged: (_) =>
                    Provider.of<AppState>(context, listen: false).toggleTheme(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (UpdateService.isSupported)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Check for Updates', style: theme.textTheme.titleMedium),
                Consumer<UpdateService>(
                  builder: (context, updateService, _) => Switch(
                    value: updateService.autoCheckEnabled,
                    onChanged: (val) => updateService.setAutoCheckEnabled(val),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 16),
          _buildSlider(
            'Font Size Scale',
            storageService.textScale,
            0.7,
            2.0,
            (val) => storageService.setTextScale(val),
            context,
            divisions: 13,
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Realism Mode', context),
          const SizedBox(height: 8),
          Consumer<StorageService>(
            builder: (context, storageService, _) =>
                _buildRealismModeSection(context, storageService),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Model Instructions', context),
          const SizedBox(height: 8),
          // Prompt library row
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: null,
                  isExpanded: true,
                  hint: const Text(
                    'Load saved prompt...',
                    style: TextStyle(fontSize: 13),
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: theme.cardColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: storageService.savedPrompts
                      .map(
                        (p) => DropdownMenuItem<String>(
                          value: p['name'],
                          child: Text(
                            p['name']!,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (name) {
                    if (name != null) {
                      storageService.loadSavedPrompt(name);
                      _systemPromptController.text =
                          storageService.systemPrompt;
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Save current prompt',
                icon: const Icon(Icons.save, color: Colors.amber),
                onPressed: () => _showSavePromptDialog(context, storageService),
              ),
              IconButton(
                tooltip: 'Delete a saved prompt',
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () =>
                    _showDeletePromptDialog(context, storageService),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Built-in preset chips
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _buildPresetChip(
                label: '📡 API Default',
                prompt: ChatService.defaultApiSystemPrompt,
                storageService: storageService,
                context: context,
              ),
              _buildPresetChip(
                label: '🖥️ KoboldCPP',
                prompt: ChatService.defaultKoboldSystemPrompt,
                storageService: storageService,
                context: context,
              ),
              _buildPresetChip(
                label: '👥 Group Chat',
                prompt: ChatService.defaultGroupSystemPrompt,
                storageService: storageService,
                context: context,
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppTextField(
            controller: _systemPromptController,
            maxLines: 5,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'System Prompt...',
              hintStyle: TextStyle(color: theme.textTheme.bodySmall?.color),
              filled: true,
              fillColor: theme.cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (val) => storageService.setSystemPrompt(val),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceMediaTab(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final modelManager = Provider.of<ModelManager>(context);
    final llmProvider = Provider.of<LLMProvider>(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Text-to-Speech', context),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.volume_up, color: Colors.blueAccent, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _engineDisplayName(storageService.ttsEngine),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        storageService.ttsEnabled
                            ? () {
                                final voiceKey = storageService.ttsVoiceModel;
                                if (voiceKey.isEmpty)
                                  return 'Enabled — Voice: Not set';
                                final ttsService = Provider.of<TtsService>(
                                  context,
                                  listen: false,
                                );
                                final match = ttsService.activeVoices.where(
                                  (v) => v.id == voiceKey,
                                );
                                final displayName = match.isNotEmpty
                                    ? match.first.name
                                    : voiceKey;
                                return 'Enabled — Voice: $displayName';
                              }()
                            : 'Disabled',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => TtsSettingsDialog(),
                  ),
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('Configure'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('Voice Input (STT)', context),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.mic,
                          color: Colors.greenAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Enable Voice Input',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Switch(
                      value: storageService.sttEnabled,
                      onChanged: (val) => storageService.setSttEnabled(val),
                    ),
                  ],
                ),
                if (storageService.sttEnabled) ...[
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Whisper Model',
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            DropdownButtonFormField<String>(
                              initialValue: storageService.whisperModel,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: theme.scaffoldBackgroundColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'tiny.en',
                                  child: Text('Tiny (~40MB, fastest)'),
                                ),
                                DropdownMenuItem(
                                  value: 'base.en',
                                  child: Text('Base (~75MB, balanced)'),
                                ),
                                DropdownMenuItem(
                                  value: 'small.en',
                                  child: Text('Small (~250MB, best accuracy)'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null)
                                  storageService.setWhisperModel(val);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Download model button with progress
                  Consumer<SttService>(
                    builder: (context, sttService, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: sttService.isDownloading
                                  ? null
                                  : () async {
                                      final ok = await sttService
                                          .downloadModel();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              ok
                                                  ? '✅ Model "${storageService.whisperModel}" downloaded!'
                                                  : '❌ ${sttService.downloadError ?? "Download failed"}',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                              icon: sttService.isDownloading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white54,
                                      ),
                                    )
                                  : const Icon(Icons.download, size: 18),
                              label: Text(
                                sttService.isDownloading
                                    ? sttService.downloadStatus
                                    : 'Download Model',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.greenAccent,
                                side: const BorderSide(
                                  color: Colors.greenAccent,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                          if (sttService.isDownloading) ...[
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: sttService.downloadProgress > 0
                                    ? sttService.downloadProgress
                                    : null,
                                backgroundColor: Colors.white10,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.greenAccent,
                                ),
                                minHeight: 4,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Microphone selector
                  Consumer<SttService>(
                    builder: (context, sttService, _) {
                      // Auto-refresh devices on first render so dropdown is populated
                      if (sttService.inputDevices.isEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          sttService.refreshInputDevices();
                        });
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Microphone',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 4),
                                    DropdownButtonFormField<String>(
                                      initialValue:
                                          sttService.inputDevices.any(
                                            (d) =>
                                                d.id ==
                                                sttService.selectedDeviceId,
                                          )
                                          ? sttService.selectedDeviceId
                                          : null,
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor:
                                            theme.scaffoldBackgroundColor,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                      ),
                                      items: [
                                        const DropdownMenuItem<String>(
                                          value: null,
                                          child: Text('System Default'),
                                        ),
                                        ...sttService.inputDevices.map(
                                          (d) => DropdownMenuItem<String>(
                                            value: d.id,
                                            child: Text(
                                              d.label,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: (val) =>
                                          sttService.setSelectedDevice(val),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(
                                  Icons.refresh,
                                  size: 20,
                                  color: Colors.white54,
                                ),
                                tooltip: 'Refresh devices',
                                onPressed: () =>
                                    sttService.refreshInputDevices(),
                              ),
                            ],
                          ),
                          if (sttService.inputDevices.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'No microphones detected. Click refresh to scan.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orangeAccent.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Voice call model selector — backend-aware
                  Builder(
                    builder: (context) {
                      final isLocal =
                          llmProvider.activeBackend == BackendType.kobold;
                      final List<Map<String, String>> callModels;
                      if (isLocal) {
                        callModels = modelManager.models.map((f) {
                          final basename = f.path
                              .split('/')
                              .last
                              .split('\\')
                              .last;
                          final displayName = basename.replaceAll(
                            RegExp(r'\.gguf$', caseSensitive: false),
                            '',
                          );
                          return {'id': f.path, 'name': displayName};
                        }).toList();
                      } else {
                        callModels = _availableModels
                            .map((m) => {'id': m.id, 'name': m.name})
                            .toList();
                      }

                      final recommended = callModels
                          .where((m) {
                            final lower = m['name']!.toLowerCase();
                            return lower.contains('mini') ||
                                lower.contains('tiny') ||
                                lower.contains('1b') ||
                                lower.contains('3b') ||
                                lower.contains('4b') ||
                                lower.contains('flash') ||
                                lower.contains('haiku') ||
                                lower.contains('nano') ||
                                lower.contains('small');
                          })
                          .take(8)
                          .toList();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Voice Call Model',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isLocal
                                      ? Colors.orangeAccent.withValues(
                                          alpha: 0.15,
                                        )
                                      : Colors.blueAccent.withValues(
                                          alpha: 0.15,
                                        ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  isLocal ? 'Local' : 'API',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: isLocal
                                        ? Colors.orangeAccent
                                        : Colors.blueAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (callModels.isNotEmpty)
                            DropdownButtonFormField<String>(
                              initialValue: storageService.callModelName.isEmpty
                                  ? ''
                                  : (callModels.any(
                                          (m) =>
                                              m['id'] ==
                                              storageService.callModelName,
                                        )
                                        ? storageService.callModelName
                                        : ''),
                              isExpanded: true,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: theme.scaffoldBackgroundColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              items: [
                                const DropdownMenuItem<String>(
                                  value: '',
                                  child: Text(
                                    'Same as main model',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                ...callModels.map((m) {
                                  final name = m['name']!;
                                  final isRec = recommended.any(
                                    (r) => r['id'] == m['id'],
                                  );
                                  return DropdownMenuItem<String>(
                                    value: m['id'],
                                    child: Row(
                                      children: [
                                        if (isRec) ...[
                                          const Icon(
                                            Icons.star,
                                            size: 12,
                                            color: Colors.amber,
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        Expanded(
                                          child: Text(
                                            name.length > 45
                                                ? '${name.substring(0, 42)}...'
                                                : name,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (val) {
                                if (val != null)
                                  storageService.setCallModelName(val);
                              },
                            )
                          else
                            TextFormField(
                              initialValue: storageService.callModelName,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: theme.scaffoldBackgroundColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                hintText: isLocal
                                    ? 'No local models found — add models in Model Manager'
                                    : 'Enter model ID or configure API first',
                                hintStyle: const TextStyle(
                                  color: Colors.white24,
                                  fontSize: 13,
                                ),
                              ),
                              style: const TextStyle(fontSize: 13),
                              onChanged: (val) =>
                                  storageService.setCallModelName(val.trim()),
                            ),
                          const SizedBox(height: 4),
                          const Text(
                            '💡 Use a smaller, faster model for voice calls.\n'
                            'Reasoning/thinking models add latency — not recommended.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
                          if (recommended.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            const Text(
                              '⭐ Recommended for voice calls:',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white24,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: recommended.map((m) {
                                final name = m['name']!;
                                final id = m['id']!;
                                final isSelected =
                                    storageService.callModelName == id;
                                return ActionChip(
                                  label: Text(
                                    name.length > 30
                                        ? '${name.substring(0, 27)}...'
                                        : name,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isSelected
                                          ? Colors.greenAccent
                                          : Colors.white54,
                                    ),
                                  ),
                                  backgroundColor: isSelected
                                      ? Colors.greenAccent.withValues(
                                          alpha: 0.15,
                                        )
                                      : Colors.white.withValues(alpha: 0.05),
                                  side: BorderSide(
                                    color: isSelected
                                        ? Colors.greenAccent.withValues(
                                            alpha: 0.4,
                                          )
                                        : Colors.white12,
                                  ),
                                  onPressed: () =>
                                      storageService.setCallModelName(id),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // Voice buffer size slider
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Voice Buffer',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            '${storageService.callBufferSentences} sentences',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: storageService.callBufferSentences.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        activeColor: Colors.blueAccent,
                        onChanged: (val) =>
                            storageService.setCallBufferSentences(val.round()),
                      ),
                      const Text(
                        'Sentences to pre-generate before playback starts. '
                        'Auto-expands if generation is slow.',
                        style: TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Call system prompt
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Call System Prompt',
                            style: theme.textTheme.bodySmall,
                          ),
                          TextButton.icon(
                            onPressed: () {
                              storageService.setCallSystemPrompt(
                                'You are on a live voice call. Respond naturally as if speaking on the phone. '
                                'ALWAYS write in first person \u2014 never narrate in third person. '
                                'Keep responses concise: 1-3 sentences max. '
                                'No actions, no narration, no stage directions \u2014 just speak directly.',
                              );
                            },
                            icon: const Icon(Icons.restore, size: 14),
                            label: const Text(
                              'Reset',
                              style: TextStyle(fontSize: 11),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white38,
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 24),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextFormField(
                        key: ValueKey(storageService.callSystemPrompt.hashCode),
                        initialValue: storageService.callSystemPrompt,
                        maxLines: 4,
                        minLines: 2,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: theme.scaffoldBackgroundColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          hintText:
                              'Instructions appended during voice calls...',
                          hintStyle: const TextStyle(
                            color: Colors.white24,
                            fontSize: 13,
                          ),
                        ),
                        style: const TextStyle(fontSize: 12),
                        onChanged: (val) =>
                            storageService.setCallSystemPrompt(val),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Appended to the system prompt during voice calls to control response style.',
                        style: TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.send,
                            color: Colors.blueAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Auto-send transcription',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                      Switch(
                        value: storageService.autoSendTranscription,
                        onChanged: (val) =>
                            storageService.setAutoSendTranscription(val),
                      ),
                    ],
                  ),
                  const Text(
                    'When enabled, transcribed text is sent automatically instead of being placed in the input field.',
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('Image Generation', context),
          const SizedBox(height: 8),
          Consumer<StorageService>(
            builder: (context, storage, _) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          storage.imageGenEnabled
                              ? Icons.auto_awesome
                              : Icons.auto_awesome_outlined,
                          color: storage.imageGenEnabled
                              ? Colors.tealAccent
                              : Colors.white38,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'AI Image Generation',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                storage.imageGenEnabled
                                    ? 'Enabled — Model: ${storage.imageGenModel.isEmpty ? "Not set" : storage.imageGenModel}'
                                    : 'Disabled',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: storage.imageGenEnabled,
                          onChanged: (val) => storage.setImageGenEnabled(val),
                          activeTrackColor: Colors.tealAccent,
                        ),
                      ],
                    ),
                    if (storage.imageGenEnabled) ...[
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 8),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => ImageGenSettingsDialog(),
                          ),
                          icon: const Icon(Icons.settings, size: 16),
                          label: const Text('Configure Image Gen'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.tealAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBackendTab(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final modelManager = Provider.of<ModelManager>(context);
    final backendManager = Provider.of<BackendManager>(context);
    final koboldService = Provider.of<KoboldService>(context);
    final llmProvider = Provider.of<LLMProvider>(context);
    final theme = Theme.of(context);

    // Auto-select first model if none selected and models exist
    if (_selectedModelPath == null && modelManager.models.isNotEmpty) {
      _selectedModelPath = modelManager.models.first.path;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Backend Mode', context),
          const SizedBox(height: 8),
          // Intel Mac warning banner
          if (backendManager.isIntelMac) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Local inference is not supported on Intel Macs. Only Remote API mode is available.',
                      style: TextStyle(fontSize: 12, color: Colors.orange[200]),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<BackendType>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Icon(
                              Icons.computer,
                              size: 18,
                              color: backendManager.isIntelMac
                                  ? Colors.grey
                                  : theme.iconTheme.color,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Local (KoboldCPP)',
                              style: TextStyle(
                                fontSize: 13,
                                color: backendManager.isIntelMac
                                    ? Colors.grey
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        value: BackendType.kobold,
                        groupValue: llmProvider.activeBackend,
                        onChanged: backendManager.isIntelMac
                            ? null
                            : (val) async {
                                if (val != null) {
                                  await llmProvider.setActiveBackend(val);
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Switched to local KoboldCPP backend.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<BackendType>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Icon(
                              Icons.cloud,
                              size: 18,
                              color: theme.iconTheme.color,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Remote API',
                              style: TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                        value: BackendType.openRouter,
                        groupValue: llmProvider.activeBackend,
                        onChanged: (val) async {
                          if (val != null) {
                            final stoppedKobold = await llmProvider
                                .setActiveBackend(val);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    stoppedKobold
                                        ? 'Shutting down KoboldCPP… Switched to Remote API.'
                                        : 'Switched to Remote API backend.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (llmProvider.isLocal)
                  Text(
                    'Use a local KoboldCPP instance to run models on your hardware.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  )
                else
                  Text(
                    'Connect to OpenRouter, Nano-GPT, or any OpenAI-compatible API.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
              ],
            ),
          ),

          // ── Remote API Configuration ──
          if (!llmProvider.isLocal) ...[
            const SizedBox(height: 24),
            _buildSectionHeader('API Configuration', context),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Quick-connect presets
                  Text('Quick Connect', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildApiPresetChip(
                        label: '🖥️ LM Studio',
                        url: 'http://localhost:1234/v1',
                        storageService: storageService,
                        context: context,
                      ),
                      _buildApiPresetChip(
                        label: '🌐 OpenRouter',
                        url: 'https://openrouter.ai/api/v1',
                        storageService: storageService,
                        context: context,
                      ),
                      _buildApiPresetChip(
                        label: '⚡ Nano-GPT',
                        url: 'https://nano-gpt.com/api/v1',
                        storageService: storageService,
                        context: context,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('API URL', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _remoteApiUrlController,
                    decoration: InputDecoration(
                      hintText: 'https://openrouter.ai/api/v1',
                      filled: true,
                      fillColor: theme.scaffoldBackgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    onChanged: (val) =>
                        storageService.setRemoteApiUrl(val.trim()),
                  ),
                  const SizedBox(height: 16),
                  Text('API Key', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _remoteApiKeyController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'sk-or-...',
                      filled: true,
                      fillColor: theme.scaffoldBackgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      suffixIcon: const Icon(Icons.key, size: 18),
                    ),
                    onChanged: (val) =>
                        storageService.setRemoteApiKey(val.trim()),
                  ),
                  const SizedBox(height: 12),
                  // ── Check Connection Button ──
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isCheckingConnection
                          ? null
                          : () async {
                              setState(() => _isCheckingConnection = true);
                              final openRouter = Provider.of<OpenRouterService>(
                                context,
                                listen: false,
                              );
                              openRouter.configure(
                                apiUrl: storageService.remoteApiUrl,
                                apiKey: storageService.remoteApiKey,
                              );
                              final result = await openRouter.testConnection();
                              if (mounted) {
                                setState(() => _isCheckingConnection = false);
                                final isSuccess = result.contains('successful');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        Icon(
                                          isSuccess
                                              ? Icons.check_circle
                                              : Icons.error,
                                          color: isSuccess
                                              ? Colors.greenAccent
                                              : Colors.redAccent,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(result)),
                                      ],
                                    ),
                                  ),
                                );
                              }
                            },
                      icon: _isCheckingConnection
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.wifi_tethering, size: 18),
                      label: Text(
                        _isCheckingConnection
                            ? 'Checking...'
                            : 'Check Connection',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent.withValues(
                          alpha: 0.8,
                        ),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // ── Model Selection ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Model', style: theme.textTheme.bodySmall),
                      TextButton.icon(
                        onPressed: _isFetchingModels
                            ? null
                            : () async {
                                setState(() => _isFetchingModels = true);
                                final openRouter =
                                    Provider.of<OpenRouterService>(
                                      context,
                                      listen: false,
                                    );
                                openRouter.configure(
                                  apiUrl: storageService.remoteApiUrl,
                                  apiKey: storageService.remoteApiKey,
                                );
                                final models = await openRouter
                                    .fetchAvailableModels();
                                if (mounted) {
                                  setState(() {
                                    _availableModels = models;
                                    _isFetchingModels = false;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        models.isEmpty
                                            ? 'No models found. Check your API URL and key.'
                                            : 'Found ${models.length} available models.',
                                      ),
                                    ),
                                  );
                                }
                              },
                        icon: _isFetchingModels
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh, size: 16),
                        label: Text(
                          _isFetchingModels ? 'Loading...' : 'Refresh Models',
                        ),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (_availableModels.isNotEmpty)
                    InkWell(
                      onTap: () =>
                          _showModelSearchDialog(context, storageService),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.dividerColor),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    storageService.remoteModelName.isNotEmpty
                                        ? storageService.remoteModelName
                                        : 'Tap to select a model...',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color:
                                          storageService
                                              .remoteModelName
                                              .isNotEmpty
                                          ? null
                                          : Colors.grey,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (storageService
                                      .remoteModelName
                                      .isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Builder(
                                      builder: (context) {
                                        final match = _availableModels
                                            .where(
                                              (m) =>
                                                  m.id ==
                                                  storageService
                                                      .remoteModelName,
                                            )
                                            .toList();
                                        if (match.isEmpty)
                                          return const SizedBox.shrink();
                                        return Text(
                                          match.first.pricingLabel,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_drop_down,
                              color: Colors.grey[500],
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    TextFormField(
                      initialValue: storageService.remoteModelName,
                      decoration: InputDecoration(
                        hintText: 'e.g. nousresearch/hermes-3-llama-3.1-405b',
                        filled: true,
                        fillColor: theme.scaffoldBackgroundColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        suffixIcon: const Icon(Icons.smart_toy, size: 18),
                      ),
                      onChanged: (val) =>
                          storageService.setRemoteModelName(val.trim()),
                    ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Works with OpenRouter, Nano-GPT, or any OpenAI-compatible endpoint.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Local KoboldCPP sections (only when local mode and not Intel Mac) ──
          if (llmProvider.isLocal && !backendManager.isIntelMac) ...[
            const SizedBox(height: 24),
            _buildSectionHeader('Koboldcpp Backend', context),
            // ... (Existing Backend Logic adapted) ...
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (backendManager.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      backendManager.error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            backendManager.backendPath != null
                                ? 'Status: Ready'
                                : 'Status: Missing',
                            style: TextStyle(
                              color: backendManager.backendPath != null
                                  ? Colors.green
                                  : Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (backendManager.backendPath != null)
                            Text(
                              backendManager.backendPath!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 10,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (backendManager.isDownloading)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      ElevatedButton(
                        onPressed: () => backendManager.downloadBackend(),
                        child: Text(
                          backendManager.backendPath != null
                              ? 'Update'
                              : 'Download',
                        ),
                      ),
                  ],
                ),
                if (backendManager.isDownloading)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: LinearProgressIndicator(
                      value: backendManager.downloadProgress,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SwitchListTile(
                title: const Text(
                  'Auto-start model on launch',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  'Automatically load the last used model when the app starts',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
                value: storageService.autostartBackend,
                activeTrackColor: Colors.blueAccent,
                onChanged: (val) {
                  storageService.setAutostartBackend(val);
                },
              ),
            ),

            const SizedBox(height: 24),
            _buildSectionHeader('Model Selection', context),
            const SizedBox(height: 16),
            if (modelManager.models.isEmpty)
              const Text(
                'No models available. Go to "Manage Models" to download one.',
                style: TextStyle(color: Colors.orange),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedModelPath,
                    isExpanded: true,
                    dropdownColor: theme.cardColor,
                    style: theme.textTheme.bodyMedium,
                    icon: Icon(
                      Icons.arrow_drop_down,
                      color: theme.iconTheme.color,
                    ),
                    items: modelManager.models.map((file) {
                      return DropdownMenuItem(
                        value: file.path,
                        child: Text(
                          file.path.split(Platform.pathSeparator).last,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedModelPath = val;
                      });
                      Provider.of<StorageService>(
                        context,
                        listen: false,
                      ).setLastUsedModelPath(val);
                      _applyAutoConfiguration(silent: true);
                    },
                  ),
                ),
              ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: backendManager.backendPath == null
                    ? null
                    : () => _toggleKobold(context),
                icon: Icon(
                  koboldService.isRunning ? Icons.stop : Icons.play_arrow,
                ),
                label: Text(
                  koboldService.isRunning ? 'Stop Backend' : 'Start Backend',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: koboldService.isRunning
                      ? Colors.red.withValues(alpha: 0.8)
                      : Colors.green.withValues(alpha: 0.8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('Process Logs', context),
            const SizedBox(height: 8),
            LogView(logs: koboldService.logs),
          ], // end isLocal
        ],
      ),
    );
  }

  Widget _buildAdvancedTab(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final hardwareService = Provider.of<HardwareService>(context);
    final llmProvider = Provider.of<LLMProvider>(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Storage Configuration', context),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder, color: Colors.blueAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Data Directory', style: theme.textTheme.bodySmall),
                      Text(
                        storageService.rootPath ?? 'Not set',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.edit, color: theme.iconTheme.color),
                  onPressed: _pickStoragePath,
                  tooltip: 'Change Data Directory',
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('Web Server', context),
          const SizedBox(height: 8),
          Consumer2<StorageService, WebServerService>(
            builder: (context, storage, webServer, _) {
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              webServer.isRunning
                                  ? Icons.wifi_tethering
                                  : Icons.wifi_tethering_off,
                              color: webServer.isRunning
                                  ? Colors.greenAccent
                                  : Colors.white38,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Enable Web Server',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Switch(
                          value: storage.webServerEnabled,
                          onChanged: (val) async {
                            await storage.setWebServerEnabled(val);
                            if (val) {
                              await webServer.start(storage.webServerPort);
                            } else {
                              await webServer.stop();
                            }
                          },
                        ),
                      ],
                    ),
                    if (storage.webServerEnabled) ...[
                      const Divider(color: Colors.white10),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Port', style: theme.textTheme.bodySmall),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: 120,
                                  child: TextFormField(
                                    initialValue: storage.webServerPort
                                        .toString(),
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: theme.scaffoldBackgroundColor,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                    ),
                                    onFieldSubmitted: (val) async {
                                      final port = int.tryParse(val) ?? 8085;
                                      await storage.setWebServerPort(port);
                                      if (webServer.isRunning) {
                                        await webServer.stop();
                                        await webServer.start(port);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('PIN', style: theme.textTheme.bodySmall),
                                const SizedBox(height: 4),
                                SizedBox(
                                  width: 120,
                                  child: TextFormField(
                                    initialValue: storage.webServerPin,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      letterSpacing: 4,
                                    ),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: theme.scaffoldBackgroundColor,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                      hintText: '6 digits',
                                      hintStyle: TextStyle(
                                        color: Colors.white24,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    maxLength: 6,
                                    buildCounter:
                                        (
                                          _, {
                                          required currentLength,
                                          required isFocused,
                                          maxLength,
                                        }) => null,
                                    onFieldSubmitted: (val) async {
                                      if (val.length >= 4 &&
                                          int.tryParse(val) != null) {
                                        await storage.setWebServerPin(val);
                                      }
                                    },
                                    onChanged: (val) async {
                                      if (val.length == 6 &&
                                          int.tryParse(val) != null) {
                                        await storage.setWebServerPin(val);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Status',
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: webServer.isRunning
                                            ? Colors.greenAccent
                                            : Colors.redAccent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      webServer.isRunning
                                          ? 'Running'
                                          : 'Stopped',
                                      style: TextStyle(
                                        color: webServer.isRunning
                                            ? Colors.greenAccent
                                            : Colors.redAccent,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (webServer.lanIp != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blueAccent.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.language,
                                color: Colors.blueAccent,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SelectableText(
                                  'http://${webServer.lanIp}:${storage.webServerPort}',
                                  style: const TextStyle(
                                    color: Colors.blueAccent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (webServer.hasActiveClient) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.devices,
                                color: Colors.amber,
                                size: 16,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Client connected: ${webServer.connectedClientIp ?? "Unknown"}',
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSectionHeader('Hardware & GPU', context),
              TextButton.icon(
                onPressed: _autoConfigure,
                icon: const Icon(Icons.auto_fix_high, color: Colors.amber),
                label: const Text(
                  'Auto-Configure',
                  style: TextStyle(color: Colors.amber),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Hardware Info with VRAM Gauge (always shown)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
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
                      // GPU Name header
                      Row(
                        children: [
                          Icon(
                            Icons.memory,
                            color: Colors.blueAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              hardwareService.hardwareInfo!.gpuName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // VRAM Gauge
                      if (llmProvider.isLocal)
                        FutureBuilder<int?>(
                          future: _selectedModelPath != null
                              ? Provider.of<ModelManager>(
                                  context,
                                  listen: false,
                                ).getKvCacheBytesPerToken(_selectedModelPath!)
                              : Future.value(null),
                          builder: (context, snapshot) {
                            final totalVram = hardwareService
                                .hardwareInfo!
                                .vramMb
                                .toDouble();
                            if (totalVram <= 0) return const SizedBox.shrink();

                            // Estimate model VRAM usage from model size
                            final modelSizeMb = _getSelectedModelSizeMb();
                            final contextSize =
                                int.tryParse(_contextSizeController.text) ??
                                4096;

                            // Use exact KV cost if parsed, else fallback to 100MB per 1k heuristic
                            final kvBytesPerToken = snapshot.data;
                            double contextVramMb = kvBytesPerToken != null
                                ? (contextSize *
                                      kvBytesPerToken /
                                      (1024 * 1024))
                                : (contextSize / 1024 * 100.0);

                            if (storageService.kvQuantizationLevel == 1) {
                              contextVramMb *= 0.5;
                            } else if (storageService.kvQuantizationLevel ==
                                2) {
                              contextVramMb *= 0.25;
                            }

                            final gpuLayers =
                                int.tryParse(_gpuLayersController.text) ?? 0;
                            // If GPU layers < 99, only part of model is on GPU
                            final modelVramMb = gpuLayers >= 99
                                ? modelSizeMb.toDouble()
                                : (modelSizeMb * (gpuLayers / 40.0)).clamp(
                                    0,
                                    modelSizeMb.toDouble(),
                                  );
                            final usedVram = modelVramMb + contextVramMb;
                            final usedRatio = (usedVram / totalVram).clamp(
                              0.0,
                              1.0,
                            );
                            final modelRatio = (modelVramMb / totalVram).clamp(
                              0.0,
                              1.0,
                            );
                            final contextRatio = (contextVramMb / totalVram)
                                .clamp(0.0, usedRatio);
                            final freeVram = (totalVram - usedVram).clamp(
                              0,
                              totalVram,
                            );

                            Color gaugeColor;
                            if (usedRatio > 0.95) {
                              gaugeColor = Colors.redAccent;
                            } else if (usedRatio > 0.8) {
                              gaugeColor = Colors.orangeAccent;
                            } else {
                              gaugeColor = Colors.greenAccent;
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // VRAM bar
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final totalWidth = constraints.maxWidth;
                                    final modelWidth = totalWidth * modelRatio;
                                    final contextWidth =
                                        totalWidth * contextRatio;

                                    return ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: SizedBox(
                                        height: 20,
                                        child: Stack(
                                          children: [
                                            // Background (free)
                                            Container(
                                              width: double.infinity,
                                              color: Colors.white.withValues(
                                                alpha: 0.08,
                                              ),
                                            ),
                                            // Model portion (starts at left)
                                            Positioned(
                                              left: 0,
                                              top: 0,
                                              bottom: 0,
                                              width: modelWidth,
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Colors.blueAccent,
                                                      Colors.blue.shade700,
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                            // Context portion (starts exactly where model ends)
                                            if (contextWidth > 0)
                                              Positioned(
                                                left: modelWidth,
                                                top: 0,
                                                bottom: 0,
                                                width: contextWidth,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [
                                                        Colors.tealAccent,
                                                        Colors.teal.shade700,
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 8),
                                // Legend
                                Row(
                                  children: [
                                    _buildVramLegendDot(
                                      Colors.blueAccent,
                                      'Model ~${modelVramMb.round()} MB',
                                    ),
                                    const SizedBox(width: 16),
                                    _buildVramLegendDot(
                                      Colors.tealAccent,
                                      'Context ~${contextVramMb.round()} MB',
                                    ),
                                    const SizedBox(width: 16),
                                    _buildVramLegendDot(
                                      Colors.white24,
                                      'Free ~${freeVram.round()} MB',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${usedVram.round()} / ${totalVram.round()} MB used',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: gaugeColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      else ...[
                        // Remote API — show total VRAM only, no usage estimate
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            height: 20,
                            width: double.infinity,
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildVramLegendDot(
                              Colors.white24,
                              'Total ${hardwareService.hardwareInfo!.vramMb} MB',
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'Remote API — GPU not in use',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),

          const SizedBox(height: 16),
          // Context Size — slider with presets + text field
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.straighten,
                      color: Colors.tealAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Context Window',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    // Manual text input
                    SizedBox(
                      width: 90,
                      child: TextField(
                        controller: _contextSizeController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: theme.scaffoldBackgroundColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Colors.tealAccent.withValues(alpha: 0.3),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          isDense: true,
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val);
                          if (parsed != null && parsed > 0) {
                            storageService.setContextSize(parsed);
                            setState(() {}); // refresh VRAM gauge
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Slider
                Builder(
                  builder: (context) {
                    final currentVal =
                        int.tryParse(_contextSizeController.text) ?? 4096;
                    // Map context size to slider position (log scale)
                    final presets = [
                      512,
                      1024,
                      2048,
                      4096,
                      8192,
                      16384,
                      32768,
                      65536,
                      131072,
                    ];
                    int closestIdx = 0;
                    int closestDist = (presets[0] - currentVal).abs();
                    for (int i = 1; i < presets.length; i++) {
                      final dist = (presets[i] - currentVal).abs();
                      if (dist < closestDist) {
                        closestDist = dist;
                        closestIdx = i;
                      }
                    }

                    return Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: Colors.tealAccent,
                            inactiveTrackColor: Colors.tealAccent.withValues(
                              alpha: 0.15,
                            ),
                            thumbColor: Colors.tealAccent,
                            overlayColor: Colors.tealAccent.withValues(
                              alpha: 0.2,
                            ),
                          ),
                          child: Slider(
                            value: closestIdx.toDouble(),
                            min: 0,
                            max: (presets.length - 1).toDouble(),
                            divisions: presets.length - 1,
                            onChanged: (val) {
                              final newSize = presets[val.round()];
                              _contextSizeController.text = newSize.toString();
                              storageService.setContextSize(newSize);
                              setState(() {});
                            },
                          ),
                        ),
                        // Preset chips
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children:
                              [
                                512,
                                2048,
                                4096,
                                8192,
                                16384,
                                32768,
                                65536,
                                131072,
                              ].map((size) {
                                final isSelected = currentVal == size;
                                final label = size >= 1024
                                    ? '${size ~/ 1024}K'
                                    : '$size';
                                return ChoiceChip(
                                  label: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white54,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  selected: isSelected,
                                  selectedColor: Colors.tealAccent,
                                  backgroundColor: Colors.white.withValues(
                                    alpha: 0.05,
                                  ),
                                  side: BorderSide(
                                    color: isSelected
                                        ? Colors.tealAccent
                                        : Colors.white12,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  onSelected: (_) {
                                    _contextSizeController.text = size
                                        .toString();
                                    storageService.setContextSize(size);
                                    setState(() {});
                                  },
                                );
                              }).toList(),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white10),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text(
                      'KV Cache Quantization:',
                      style: TextStyle(fontSize: 13, color: Colors.white70),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: storageService.kvQuantizationLevel,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF374151),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                          onChanged: (val) {
                            if (val != null) {
                              storageService.setKvQuantizationLevel(val);
                              setState(() {}); // Refresh VRAM gauge
                            }
                          },
                          items: const [
                            DropdownMenuItem(
                              value: 0,
                              child: Text('0 - None (Highest Quality, FP16)'),
                            ),
                            DropdownMenuItem(
                              value: 1,
                              child: Text('1 - 8-Bit Q8 (~50% VRAM Savings)'),
                            ),
                            DropdownMenuItem(
                              value: 2,
                              child: Text('2 - 4-Bit Q4 (~75% VRAM Savings)'),
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
                        color: Colors.tealAccent.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Larger context = more memory per conversation. Auto-configure adjusts GPU layers to fit.',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          // GPU Layers
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  label: 'GPU Layers',
                  controller: _gpuLayersController,
                  context: context,
                  isNumber: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('Use Vulkan'),
                selected: _useVulkan,
                onSelected: (val) {
                  setState(() {
                    _useVulkan = val;
                    if (val) {
                      _useCublas = false;
                      _useRocm = false;
                      _useMetal = false;
                    }
                  });
                  final ss = Provider.of<StorageService>(
                    context,
                    listen: false,
                  );
                  ss.setUseVulkan(val);
                  if (val) {
                    ss.setUseCublas(false);
                    ss.setUseRocm(false);
                    ss.setUseMetal(false);
                  }
                },
              ),
              Tooltip(
                message: hardwareService.hardwareInfo?.hasRocm == true
                    ? 'Use ROCm for native AMD GPU acceleration'
                    : 'Requires ROCm installation (AMD GPU)',
                child: FilterChip(
                  label: const Text('Use ROCm (AMD)'),
                  selected: _useRocm,
                  onSelected: hardwareService.hardwareInfo?.hasRocm == true
                      ? (val) {
                          setState(() {
                            _useRocm = val;
                            if (val) {
                              _useVulkan = false;
                              _useCublas = false;
                              _useMetal = false;
                            }
                          });
                          final ss = Provider.of<StorageService>(
                            context,
                            listen: false,
                          );
                          ss.setUseRocm(val);
                          if (val) {
                            ss.setUseVulkan(false);
                            ss.setUseCublas(false);
                            ss.setUseMetal(false);
                          }
                        }
                      : null, // Disabled if ROCm not installed
                  avatar: hardwareService.hardwareInfo?.hasRocm == true
                      ? null
                      : const Icon(Icons.block, size: 16),
                ),
              ),
              Tooltip(
                message: hardwareService.hardwareInfo?.vendor == 'Nvidia'
                    ? 'Use CUDA (NVIDIA only)'
                    : 'Requires NVIDIA GPU',
                child: FilterChip(
                  label: const Text('Use CuBLAS (Nvidia)'),
                  selected: _useCublas,
                  onSelected: hardwareService.hardwareInfo?.vendor == 'Nvidia'
                      ? (val) {
                          setState(() {
                            _useCublas = val;
                            if (val) {
                              _useVulkan = false;
                              _useRocm = false;
                              _useMetal = false;
                            }
                          });
                          final ss = Provider.of<StorageService>(
                            context,
                            listen: false,
                          );
                          ss.setUseCublas(val);
                          if (val) {
                            ss.setUseVulkan(false);
                            ss.setUseRocm(false);
                            ss.setUseMetal(false);
                          }
                        }
                      : null, // Disabled if not Nvidia
                  avatar: hardwareService.hardwareInfo?.vendor == 'Nvidia'
                      ? null
                      : const Icon(Icons.block, size: 16),
                ),
              ),
              Tooltip(
                message: hardwareService.hardwareInfo?.hasMetal == true
                    ? 'Use Metal (Apple Silicon/Mac)'
                    : 'Requires MacOS with Metal support',
                child: FilterChip(
                  label: const Text('Use Metal (MacOS)'),
                  selected: _useMetal,
                  onSelected: hardwareService.hardwareInfo?.hasMetal == true
                      ? (val) {
                          setState(() {
                            _useMetal = val;
                            if (val) {
                              _useVulkan = false;
                              _useCublas = false;
                              _useRocm = false;
                            }
                          });
                          final ss = Provider.of<StorageService>(
                            context,
                            listen: false,
                          );
                          ss.setUseMetal(val);
                          if (val) {
                            ss.setUseVulkan(false);
                            ss.setUseCublas(false);
                            ss.setUseRocm(false);
                          }
                        }
                      : null, // Disabled if not MacOS/Metal
                  avatar: hardwareService.hardwareInfo?.hasMetal == true
                      ? null
                      : const Icon(Icons.block, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildRealismModeSection(
    BuildContext context,
    StorageService storageService,
  ) {
    // storageService drives the toggle values — it holds the global defaults
    // that apply to every new session. chatService is also updated immediately
    // so the currently active chat reflects the change right away.
    final chatService = Provider.of<ChatService>(context, listen: false);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Master Realism Mode Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.theater_comedy,
                    size: 18,
                    color: Colors.tealAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Enable Realism Mode',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
              Switch(
                value: storageService.realismDefault,
                activeColor: Colors.tealAccent,
                onChanged: (val) {
                  storageService.setRealismDefault(val);
                  chatService.setRealismEnabled(val);
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Adds relationship tracking, emotional state, and physical realism to roleplay.',
            style: TextStyle(
              fontSize: 12,
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
          const SizedBox(height: 16),
          // Sub-options (only shown when realism is enabled globally)
          if (storageService.realismDefault) ...[
            const Divider(height: 1),
            const SizedBox(height: 12),
            // NSFW / Cooldown Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      size: 16,
                      color: Colors.deepOrangeAccent,
                    ),
                    const SizedBox(width: 8),
                    Text('NSFW Cooldown', style: theme.textTheme.bodyLarge),
                  ],
                ),
                Switch(
                  value: storageService.nsfwCooldownDefault,
                  activeColor: Colors.deepOrangeAccent,
                  onChanged: (val) {
                    storageService.setNsfwCooldownDefault(val);
                    chatService.setNsfwCooldownEnabled(val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Tracks arousal level and enforces refractory periods after intimate scenes.',
              style: TextStyle(
                fontSize: 11,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
            const SizedBox(height: 16),
            // Passage of Time Toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 16,
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Automatic Passage of Time',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
                Switch(
                  value: storageService.passageOfTimeDefault,
                  activeColor: Colors.blueAccent,
                  onChanged: (val) {
                    storageService.setPassageOfTimeDefault(val);
                    chatService.setPassageOfTimeEnabled(val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Time automatically advances (dawn→morning→afternoon→evening→night) as you chat.',
              style: TextStyle(
                fontSize: 11,
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    Function(double) onChanged,
    BuildContext context, {
    int? divisions,
    String? tooltip,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
                if (tooltip != null)
                  Tooltip(
                    message: tooltip,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.white38,
                      ),
                    ),
                  ),
              ],
            ),
            Text(
              value.toStringAsFixed(2),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  /// Small colored dot + label for the VRAM gauge legend.
  Widget _buildVramLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.white54),
        ),
      ],
    );
  }

  /// Estimate the selected model's file size in MB for the VRAM gauge.
  int _getSelectedModelSizeMb() {
    if (_selectedModelPath == null) return 0;
    try {
      final file = File(_selectedModelPath!);
      if (file.existsSync()) {
        return (file.lengthSync() / (1024 * 1024)).round();
      }
    } catch (_) {}
    return 0;
  }

  Widget _buildSectionHeader(String title, [BuildContext? context]) {
    final theme = context != null ? Theme.of(context) : null;
    return Text(
      title,
      style:
          theme?.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.blueAccent,
          ) ??
          const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.blueAccent,
          ),
    );
  }

  Widget _buildModeChip({
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.tealAccent.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.tealAccent : Colors.white12,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.tealAccent : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: isSelected
                    ? Colors.tealAccent.withValues(alpha: 0.6)
                    : Colors.white30,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required BuildContext context,
    bool isNumber = false,
  }) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: theme.textTheme.bodySmall?.color),
        filled: true,
        fillColor: theme.cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  void _showSavePromptDialog(
    BuildContext context,
    StorageService storageService,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Save Prompt', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Prompt name...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              storageService.savePrompt(
                value.trim(),
                storageService.systemPrompt,
              );
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Prompt "${value.trim()}" saved!')),
              );
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
            ),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                storageService.savePrompt(
                  controller.text.trim(),
                  storageService.systemPrompt,
                );
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Prompt "${controller.text.trim()}" saved!'),
                  ),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeletePromptDialog(
    BuildContext context,
    StorageService storageService,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text(
          'Delete Saved Prompt',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 300,
          child: storageService.savedPrompts.isEmpty
              ? const Text(
                  'No saved prompts.',
                  style: TextStyle(color: Colors.white54),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: storageService.savedPrompts
                      .map(
                        (p) => ListTile(
                          title: Text(
                            p['name']!,
                            style: const TextStyle(color: Colors.white),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            onPressed: () {
                              storageService.deleteSavedPrompt(p['name']!);
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Prompt "${p['name']}" deleted.',
                                  ),
                                ),
                              );
                            },
                          ),
                          dense: true,
                        ),
                      )
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  /// Shows a full dialog with a search bar to filter and select from available models.
  void _showModelSearchDialog(
    BuildContext context,
    StorageService storageService,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtered = searchQuery.isEmpty
                ? _availableModels
                : _availableModels.where((m) {
                    final q = searchQuery.toLowerCase();
                    return m.id.toLowerCase().contains(q) ||
                        m.name.toLowerCase().contains(q);
                  }).toList();

            return AlertDialog(
              backgroundColor: const Color(0xFF1F2937),
              title: const Text(
                'Select Model',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: 500,
                height: 450,
                child: Column(
                  children: [
                    // Search bar
                    TextField(
                      autofocus: true,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search ${_availableModels.length} models...',
                        hintStyle: const TextStyle(
                          color: Colors.white38,
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.white38,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF111827),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onChanged: (val) =>
                          setDialogState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 8),
                    // Result count
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${filtered.length} models',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Model list
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'No models match your search.',
                                style: TextStyle(color: Colors.white38),
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final model = filtered[i];
                                final isSelected =
                                    model.id == storageService.remoteModelName;
                                return ListTile(
                                  dense: true,
                                  selected: isSelected,
                                  selectedTileColor: Colors.blueAccent
                                      .withValues(alpha: 0.15),
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
                                          : Colors.white,
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
                                          margin: const EdgeInsets.only(
                                            right: 6,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.withValues(
                                              alpha: 0.2,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
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
                                            color: Colors.grey[500],
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
                                  onTap: () {
                                    storageService.setRemoteModelName(model.id);
                                    Navigator.pop(ctx);
                                    setState(
                                      () {},
                                    ); // Refresh the settings page
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Builds a compact chip that loads a built-in system prompt preset.
  Widget _buildPresetChip({
    required String label,
    required String prompt,
    required StorageService storageService,
    required BuildContext context,
  }) {
    final isActive = _systemPromptController.text == prompt;
    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isActive ? Colors.white : Colors.white70,
        ),
      ),
      backgroundColor: isActive ? Colors.deepPurple : const Color(0xFF2D3748),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive ? Colors.deepPurpleAccent : Colors.white24,
        ),
      ),
      onPressed: () {
        setState(() {
          _systemPromptController.text = prompt;
        });
        storageService.setSystemPrompt(prompt);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded "$label" system prompt'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }

  Widget _buildApiPresetChip({
    required String label,
    required String url,
    required StorageService storageService,
    required BuildContext context,
  }) {
    final isActive = storageService.remoteApiUrl == url;
    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isActive ? Colors.white : Colors.white70,
        ),
      ),
      backgroundColor: isActive ? Colors.indigo : const Color(0xFF2D3748),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isActive ? Colors.indigoAccent : Colors.white24,
        ),
      ),
      onPressed: () async {
        // Always preserve the API key in storage - just change the URL
        // LM Studio won't use an API key since it's local, and when we switch
        // back to Nano-GPT/OpenRouter, the key will still be there.
        storageService.setRemoteApiUrl(url);
        _remoteApiUrlController.text = url;

        // Configure OpenRouter with stored values (apiKey persists across switches)
        final openRouter = Provider.of<OpenRouterService>(
          context,
          listen: false,
        );
        openRouter.configure(apiUrl: url, apiKey: storageService.remoteApiKey);

        setState(() => _isFetchingModels = true);
        try {
          final models = await openRouter.fetchAvailableModels();
          if (mounted) {
            setState(() {
              _availableModels = models;
              _isFetchingModels = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  models.isEmpty
                      ? '$label connected — no models found yet.'
                      : '$label connected — found ${models.length} models.',
                ),
              ),
            );
          }
        } catch (_) {
          if (mounted) setState(() => _isFetchingModels = false);
        }
      },
    );
  }

  // ── Generation Settings Tab ─────────────────────────────────────────────
  Widget _buildGenerationTab(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    final llmProvider = Provider.of<LLMProvider>(context);
    final isRemote = !llmProvider.isLocal;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Reasoning (remote-only) ────────────────────────────────────
          if (isRemote) ...[
            _buildSectionHeader('Reasoning', context),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text(
                  'Request Reasoning',
                  style: TextStyle(color: Colors.white),
                ),
                const Spacer(),
                Switch(
                  value: storage.reasoningEnabled,
                  onChanged: (val) => storage.setReasoningEnabled(val),
                  activeTrackColor: Colors.blueAccent,
                ),
              ],
            ),
            if (storage.reasoningEnabled)
              Row(
                children: [
                  const Text(
                    'Effort Level',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: storage.reasoningEffort,
                        dropdownColor: Theme.of(context).cardColor,
                        style: const TextStyle(color: Colors.white),
                        items: const [
                          DropdownMenuItem(value: 'low', child: Text('Low')),
                          DropdownMenuItem(
                            value: 'medium',
                            child: Text('Medium'),
                          ),
                          DropdownMenuItem(value: 'high', child: Text('High')),
                        ],
                        onChanged: (val) {
                          if (val != null) storage.setReasoningEffort(val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 24),
          ],

          // ── Generation Parameters ──────────────────────────────────────
          _buildSectionHeader('Generation Parameters', context),
          const SizedBox(height: 8),
          _buildSlider(
            'Temperature',
            storage.temperature,
            0.0,
            2.0,
            (val) => storage.setTemperature(val),
            context,
            divisions: 20,
          ),
          _buildSlider(
            'Min-P',
            storage.minP,
            0.0,
            1.0,
            (val) => storage.setMinP(val),
            context,
            divisions: 100,
          ),
          _buildSlider(
            'Repeat Penalty',
            storage.repeatPenalty,
            1.0,
            3.0,
            (val) => storage.setRepeatPenalty(val),
            context,
            divisions: 200,
          ),
          _buildSlider(
            'Repeat Penalty Tokens',
            storage.repeatPenaltyTokens.toDouble(),
            0,
            512,
            (val) => storage.setRepeatPenaltyTokens(val.toInt()),
            context,
            divisions: 512,
          ),
          _buildSlider(
            'XTC Threshold',
            storage.xtcThreshold,
            0.0,
            0.5,
            (val) => storage.setXtcThreshold(val),
            context,
            divisions: 50,
          ),
          _buildSlider(
            'XTC Probability',
            storage.xtcProbability,
            0.0,
            1.0,
            (val) => storage.setXtcProbability(val),
            context,
            divisions: 20,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Dynamic Temperature',
                style: TextStyle(color: Colors.white70),
              ),
              const Spacer(),
              Switch(
                value: storage.dynamicTempEnabled,
                onChanged: (val) => storage.setDynamicTempEnabled(val),
                activeTrackColor: Colors.blueAccent,
              ),
            ],
          ),
          if (storage.dynamicTempEnabled)
            _buildSlider(
              'Dynatemp Range',
              storage.dynamicTempRange,
              0.0,
              2.0,
              (val) => storage.setDynamicTempRange(val),
              context,
              divisions: 20,
            ),
          const SizedBox(height: 24),

          // ── Output Limits ──────────────────────────────────────────────
          _buildSectionHeader('Output Limits', context),
          const SizedBox(height: 8),
          _buildSlider(
            'Max Output Tokens',
            storage.maxLength.toDouble(),
            16,
            16384,
            (val) => storage.setMaxLength(val.toInt()),
            context,
          ),
          _buildSlider(
            'Min Output Tokens',
            storage.minLength.toDouble(),
            0,
            512,
            (val) => storage.setMinLength(val.toInt()),
            context,
            divisions: 512,
          ),
          // Context size — wider range for remote backends
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Context Size',
                    style: TextStyle(color: Colors.white70),
                  ),
                  Text(
                    storage.contextSize.toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Slider(
                value: storage.contextSize.toDouble().clamp(
                  512,
                  isRemote ? 500000.0 : 131072.0,
                ),
                min: 512,
                max: isRemote ? 500000.0 : 131072.0,
                divisions: isRemote ? null : ((131072 - 512) ~/ 512),
                onChanged: (val) => storage.setContextSize(val.toInt()),
                activeColor: Colors.blueAccent,
                inactiveColor: Colors.white24,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Display Output ─────────────────────────────────────────────
          _buildSectionHeader('Display Output', context),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'Smooth Output Buffer',
                style: TextStyle(color: Colors.white70),
              ),
              const Spacer(),
              Switch(
                value: storage.displayBufferEnabled,
                onChanged: (val) => storage.setDisplayBufferEnabled(val),
                activeTrackColor: Colors.blueAccent,
              ),
            ],
          ),
          if (storage.displayBufferEnabled) ...[
            _buildSlider(
              'Target Display Speed (t/s)',
              storage.targetDisplayTps,
              5.0,
              60.0,
              (val) => storage.setTargetDisplayTps(val),
              context,
              divisions: 55,
            ),
            _buildSlider(
              'Buffer Duration (seconds)',
              storage.bufferDurationSeconds,
              1.0,
              10.0,
              (val) => storage.setBufferDurationSeconds(val),
              context,
              divisions: 9,
            ),
          ],
          const SizedBox(height: 24),

          // ── Stop Sequences ─────────────────────────────────────────────
          _buildSectionHeader('Stop Sequences', context),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Add stop sequence...',
                            hintStyle: TextStyle(color: Colors.white38),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (val) {
                            if (val.isNotEmpty) storage.addStopSequence(val);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
                ...storage.stopSequences.map(
                  (seq) => ListTile(
                    title: Text(
                      seq.replaceAll('\n', '\\n'),
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      onPressed: () => storage.removeStopSequence(seq),
                    ),
                    dense: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Banned Phrases (KoboldCpp only) ────────────────────────────
          if (!isRemote) ...[
            _buildSectionHeader('Banned Phrases', context),
            const SizedBox(height: 4),
            Text(
              'One phrase per line. If any appear during generation the model backtracks and retries.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: _bannedPhrasesController,
                maxLines: 6,
                minLines: 2,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'shivers down\na cold shiver\nher eyes sparkled',
                  hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
                onChanged: (val) {
                  final phrases = val
                      .split('\n')
                      .where((s) => s.trim().isNotEmpty)
                      .map((s) => s.trim())
                      .toList();
                  storage.setBannedPhrases(phrases);
                },
              ),
            ),
            if (storage.bannedPhrases.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${storage.bannedPhrases.length} phrase${storage.bannedPhrases.length == 1 ? '' : 's'} banned',
                  style: TextStyle(color: Colors.amber.shade300, fontSize: 11),
                ),
              ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

String _engineDisplayName(String engineId) {
  switch (engineId) {
    case 'kokoro':
      return 'Kokoro TTS';
    case 'openai':
      return 'OpenAI TTS';
    case 'piper':
      return 'Piper TTS';
    default:
      return 'TTS';
  }
}
