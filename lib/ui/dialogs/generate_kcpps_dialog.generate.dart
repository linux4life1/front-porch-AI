// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Detect, estimate VRAM, and write the .kcpps. The form stays
// on generate_kcpps_dialog.dart.

part of 'generate_kcpps_dialog.dart';

extension _GenerateKcppsDialogGenerate on _GenerateKcppsDialogState {
  Future<void> _initDetection() async {
    int? detected;
    try {
      final hardware = Provider.of<HardwareService>(context, listen: false);
      _hardwareInfo = hardware.hardwareInfo;
      _gpu = _detectGpu();
      detected = await suggestKoboldThreads();
    } catch (e) {
      debugPrint('Preset dialog: hardware detection failed: $e');
    }
    // The dialog may have been closed while the cores were counted.
    if (!mounted) return;

    rebuildState(() {
      if (detected != null) {
        _threads = detected;
        _threadsController.text = '$detected';
        _batchSize = _suggestBatchSize();
      }
      _detecting = false;
    });
    if (detected != null) _computeVramEstimate();
  }

  Future<void> _refreshModelInfo() async {
    if (_selectedModelPath == null) return;
    final mgr = Provider.of<ModelManager>(context, listen: false);
    final info = await mgr.getModelArchitectureInfo(_selectedModelPath!);
    if (!mounted) return;
    rebuildState(() {
      _modelInfo = info;
      _batchSize = _suggestBatchSize();
      _batchSizeController.text = '$_batchSize';
    });
    _computeVramEstimate();
  }

  Future<void> _refreshDefaults() async {
    rebuildState(() {
      _batchSize = _suggestBatchSize();
      _batchSizeController.text = '$_batchSize';
    });
    _computeVramEstimate();
  }

  void _debouncedEstimate() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _computeVramEstimate();
      rebuildState(() {});
    });
  }

  void _computeVramEstimate() {
    if (_selectedModelPath == null) {
      _vramEstimate = null;
      return;
    }
    final file = File(_selectedModelPath!);
    final missing = !file.existsSync(); // io-ok: model change / generate
    if (missing) {
      _vramEstimate = null;
      return;
    }
    final fileSizeBytes = file.lengthSync(); // io-ok: model change / generate
    final fileSizeMb = fileSizeBytes ~/ (1024 * 1024);

    if (_modelInfo != null) {
      _vramEstimate = VramEstimator.estimateFromArchitecture(
        modelInfo: _modelInfo!,
        fileSizeBytes: fileSizeBytes,
        contextSize: _contextSize,
        batchSize: _batchSize,
        kvQuant: _preset(_selectedModelPath!).kvQuant.wire,
        isSwa: _contextMode == ContextManagementMode.slidingWindowAttention,
        // On Apple Silicon, CPU and GPU share unified memory: offloading MoE
        // experts to "CPU" frees no memory and would only slow generation, so
        // the whole quantized model is modelled as GPU-resident there.
        moeExpertsOnCpu: !Platform.isMacOS,
        backend: _memoryBackend,
        flashAttention: _preset(_selectedModelPath!).flashAttention,
      );
    } else if (_hardwareInfo?.vramMb != null && _hardwareInfo!.vramMb > 0) {
      final totalMb = VramEstimator.estimateVramNeeded(
        fileSizeBytes: fileSizeBytes,
        contextSize: _contextSize,
      );
      final kvMb = (totalMb - fileSizeMb - VramEstimator.defaultFixedOverheadMb)
          .clamp(0, totalMb);
      _vramEstimate = (
        weightsMb: fileSizeMb,
        kvCacheMb: kvMb,
        computeBufMb: 0,
        overheadMb: VramEstimator.defaultFixedOverheadMb,
        totalMb: totalMb,
        activeWeightRatio: 1.0,
      );
    } else {
      _vramEstimate = null;
    }
  }

  int _suggestBatchSize() {
    final vramMb = _hardwareInfo?.vramMb ?? 0;
    if (vramMb <= 0 || _selectedModelPath == null) return 512;
    final file = File(_selectedModelPath!);
    if (!file.existsSync()) return 512; // io-ok: model change / generate

    // Use a reasonable default if model info isn't available yet
    final modelInfo =
        _modelInfo ??
        GGUFModelInfo(
          nLayers: 32,
          nHeads: 32,
          nKvHeads: 8,
          nEmbd: 4096,
          kvBytesPerToken: 2048,
        );

    final padding = koboldAutofitPaddingMb(greedy: _greedyAllocation);

    return VramEstimator.suggestBatchSize(
      modelInfo: modelInfo,
      fileSizeBytes: file.lengthSync(), // io-ok: model change / generate
      contextSize: _contextSize,
      kvQuant: _preset(_selectedModelPath!).kvQuant.wire,
      isSwa: _contextMode == ContextManagementMode.slidingWindowAttention,
      moeExpertsOnCpu:
          !Platform.isMacOS, // unified memory; see _computeVramEstimate
      availableVramMb: vramMb,
      autofitpaddingMb: padding,
      backend: _memoryBackend,
      flashAttention: _preset(_selectedModelPath!).flashAttention,
    );
  }

  /// The preset the dialog's choices make. The file written and the
  /// estimate shown both come from it, so they cannot disagree on a
  /// setting that changes memory (flash attention, for one).
  KoboldLaunchConfig _preset(
    String model, {
    ({KoboldGpuBackend backend, int? gpuId})? gpu,
    String mmprojPath = '',
  }) {
    final card = gpu ?? _gpu ?? _detectGpu();
    return koboldGeneratedPreset(
      modelPath: model,
      contextSize: _contextSize,
      batchSize: _batchSize,
      threads: _threads,
      greedyAllocation: _greedyAllocation,
      kvQuant: _kvQuant,
      backend: card.backend,
      gpuId: card.gpuId,
      contextMode: _contextMode,
      smartCacheSlots: _smartCacheSlots,
      mmprojPath: mmprojPath,
      architecture: _modelInfo?.architecture,
    );
  }

  /// Where the preset being made will run, for the estimate: the working
  /// buffer and the engine's extra memory differ by backend.
  KoboldMemoryBackend get _memoryBackend {
    if (Platform.isMacOS) return KoboldMemoryBackend.metal;
    return (_gpu ?? _detectGpu()).backend == KoboldGpuBackend.vulkan
        ? KoboldMemoryBackend.vulkan
        : KoboldMemoryBackend.cuda;
  }

  Future<void> _generate() async {
    if (_selectedModelPath == null) {
      rebuildState(() => _errorMessage = 'Please select a model first.');
      return;
    }

    rebuildState(() {
      _generating = true;
      _errorMessage = null;
    });

    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final model = _selectedModelPath!;
      final gpu = _gpu ?? _detectGpu();
      // The vision file chosen for this model travels in the preset, so a
      // preset loaded by a live swap still has it.
      final mmproj = storage.presetSettings.modelMmprojMap[model] ?? '';
      final version = await KoboldBinaryVersion.read(storage.binDir.path);
      final config = _preset(
        model,
        gpu: gpu,
        mmprojPath: mmproj.isNotEmpty && await File(mmproj).exists()
            ? mmproj
            : '',
      );
      final kcppsFile = File(
        path.join(
          storage.binDir.path,
          '${path.basenameWithoutExtension(model)}.kcpps',
        ),
      );
      await kcppsFile.writeAsString(
        writeKcpps(
          config,
          caps: KoboldCapabilities.forVersion(version.version),
        ),
      );

      await storage.presetSettings.setModelPreset(
        _selectedModelPath!,
        kcppsFile.path,
      );
      await storage.backendSettings.setActiveKcppsPath(kcppsFile.path);

      if (!mounted) return;
      // Show the confirmation via the captured messenger (survives the pop)
      // and close the dialog. Don't reset `_generating` here — the State is
      // about to be torn down, so a setState after pop would be a no-op/error.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'KCPPS config generated for ${path.basename(_selectedModelPath!)}',
          ),
        ),
      );
      navigator.pop(true);
    } catch (e) {
      if (!mounted) return;
      rebuildState(() {
        _generating = false;
        _errorMessage = 'Failed to generate config: $e';
      });
    }
  }

  ({KoboldGpuBackend backend, int? gpuId}) _detectGpu() => koboldGpuFor(
    _hardwareInfo,
    gpuId: Provider.of<StorageService>(
      context,
      listen: false,
    ).backendSettings.gpuId,
  );

  /// The backend setting the preset will carry, for the hardware tile.
  Map<String, dynamic> get _gpuKeys => switch (_gpu?.backend) {
    KoboldGpuBackend.cuda => const {'usecublas': true},
    KoboldGpuBackend.vulkan => const {'usevulkan': true},
    _ => const {},
  };
}
