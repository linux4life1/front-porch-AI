import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/kcpps_generator_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/context_management_selector.dart';
import 'package:front_porch_ai/ui/widgets/gpu_info_tile.dart';
import 'package:front_porch_ai/ui/widgets/vram_usage_section.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';
import 'package:front_porch_ai/utils/vram_estimator.dart';

class GenerateKcppsDialog extends StatefulWidget {
  const GenerateKcppsDialog({super.key});

  @override
  State<GenerateKcppsDialog> createState() => _GenerateKcppsDialogState();
}

class _GenerateKcppsDialogState extends State<GenerateKcppsDialog> {
  String? _selectedModelPath;
  final _contextSizeController = TextEditingController(text: '16384');
  int _contextSize = 16384;
  String _kvQuant = 'f16';
  int _threads = 4;
  final _threadsController = TextEditingController(text: '4');
  final _batchSizeController = TextEditingController(text: '512');
  final _batchSizeFocusNode = FocusNode();
  int _batchSize = 512;
  bool _greedyAllocation = false;
  ContextManagementMode _contextMode = ContextManagementMode.fastForwardSmartCache;
  int _smartCacheSlots = 5;
  final _smartCacheSlotsController = TextEditingController(text: '5');
  bool _detecting = true;
  bool _generating = false;
  GGUFModelInfo? _modelInfo;
  HardwareInfo? _hardwareInfo;
  Map<String, dynamic> _gpuConfig = {};
  String? _errorMessage;
  VramEstimateBreakdown? _vramEstimate;

  final _kvQuantOptions = ['f16', 'q8_0', 'q4_0'];
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    Provider.of<HardwareService>(context, listen: false).addListener(_onHardwareChanged);
    _batchSizeFocusNode.addListener(() {
      if (!_batchSizeFocusNode.hasFocus) {
        final clamped = _batchSize.clamp(64, 8192);
        if (clamped != _batchSize) {
          setState(() {
            _batchSize = clamped;
            _batchSizeController.text = '$clamped';
          });
          _computeVramEstimate();
        }
      }
    });
    _initDetection();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _batchSizeFocusNode.dispose();
    _batchSizeController.dispose();
    _threadsController.dispose();
    Provider.of<HardwareService>(context, listen: false).removeListener(_onHardwareChanged);
    _contextSizeController.dispose();
    _smartCacheSlotsController.dispose();
    super.dispose();
  }

  void _onHardwareChanged() {
    if (!mounted) return;
    final hw = Provider.of<HardwareService>(context, listen: false);
    if (hw.hardwareInfo == null) return;
    if (_hardwareInfo == hw.hardwareInfo && _gpuConfig.isNotEmpty) return;

    _hardwareInfo = hw.hardwareInfo;
    _gpuConfig = KcppsGeneratorService.detectGpuBackend(_hardwareInfo);
    _computeVramEstimate();
    final newBatchSize = _suggestBatchSize();
    setState(() {
      _batchSize = newBatchSize;
      _batchSizeController.text = '$newBatchSize';
    });
  }

  Future<void> _initDetection() async {
    try {
      final hardware = Provider.of<HardwareService>(context, listen: false);
      _hardwareInfo = hardware.hardwareInfo;
      _gpuConfig = KcppsGeneratorService.detectGpuBackend(_hardwareInfo);

      final detected = await KcppsGeneratorService.suggestThreadCount();

      setState(() {
        _threads = detected;
        _threadsController.text = '$detected';
        _batchSize = _suggestBatchSize();
        _detecting = false;
      });
      _computeVramEstimate();
    } catch (_) {
      setState(() {
        _detecting = false;
      });
    }
  }

  Future<void> _refreshModelInfo() async {
    if (_selectedModelPath == null) return;
    final mgr = Provider.of<ModelManager>(context, listen: false);
    final info = await mgr.getModelArchitectureInfo(_selectedModelPath!);
    if (!mounted) return;
    setState(() {
      _modelInfo = info;
      _batchSize = _suggestBatchSize();
      _batchSizeController.text = '$_batchSize';
    });
    _computeVramEstimate();
  }

  Future<void> _refreshDefaults() async {
    setState(() {
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
      setState(() {});
    });
  }

  void _computeVramEstimate() {
    if (_selectedModelPath == null) {
      _vramEstimate = null;
      return;
    }
    final file = File(_selectedModelPath!);
    if (!file.existsSync()) {
      _vramEstimate = null;
      return;
    }
    final fileSizeBytes = file.lengthSync();
    final fileSizeMb = fileSizeBytes ~/ (1024 * 1024);

    if (_modelInfo != null) {
      _vramEstimate = VramEstimator.estimateFromArchitecture(
        modelInfo: _modelInfo!,
        fileSizeBytes: fileSizeBytes,
        contextSize: _contextSize,
        batchSize: _batchSize,
        kvQuant: _kvQuant,
        isSwa: _contextMode == ContextManagementMode.slidingWindowAttention,
        // On Apple Silicon, CPU and GPU share unified memory: offloading MoE
        // experts to "CPU" frees no memory and would only slow generation, so
        // the whole quantized model is modelled as GPU-resident there.
        moeExpertsOnCpu: !Platform.isMacOS,
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
    if (!file.existsSync()) return 512;

    // Use a reasonable default if model info isn't available yet
    final modelInfo = _modelInfo ?? GGUFModelInfo(
      nLayers: 32,
      nHeads: 32,
      nKvHeads: 8,
      nEmbd: 4096,
      kvBytesPerToken: 2048,
    );

    final padding = _greedyAllocation ? 32 : 1024;

    return VramEstimator.suggestBatchSize(
      modelInfo: modelInfo,
      fileSizeBytes: file.lengthSync(),
      contextSize: _contextSize,
      kvQuant: _kvQuant,
      isSwa: _contextMode == ContextManagementMode.slidingWindowAttention,
      moeExpertsOnCpu: !Platform.isMacOS, // unified memory; see _computeVramEstimate
      availableVramMb: vramMb,
      autofitpaddingMb: padding,
    );
  }

  Future<void> _generate() async {
    if (_selectedModelPath == null) {
      setState(() => _errorMessage = 'Please select a model first.');
      return;
    }

    setState(() {
      _generating = true;
      _errorMessage = null;
    });

    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final content = KcppsGeneratorService.buildKcppsContent(
        modelPath: _selectedModelPath!,
        contextSize: _contextSize,
        batchSize: _batchSize,
        threads: _threads,
        kvQuant: _kvQuant,
        greedyAllocation: _greedyAllocation,
        gpuConfig: _gpuConfig,
        contextMode: _contextMode,
        smartCacheSlots: _smartCacheSlots,
      );

      final kcppsFile = await KcppsGeneratorService.writeKcppsFile(
        storage.binDir,
        _selectedModelPath!,
        content,
      );

      await storage.setModelPreset(_selectedModelPath!, kcppsFile.path);
      await storage.setActiveKcppsPath(kcppsFile.path);

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
      setState(() {
        _generating = false;
        _errorMessage = 'Failed to generate config: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelManager = Provider.of<ModelManager>(context, listen: false);
    final theme = Theme.of(context);
    final colors = AppColors.surfaceContainerOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tune,
                    color: AppColors.textPrimary(context),
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Generate KCPPS Config',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ],
              ),
            ),
            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Model selector
                    Text(
                      'Model',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ModelSelector(
                      models: modelManager.models,
                      selectedModelPath: _selectedModelPath,
                      showManagedByKcpps: false,
                      onChanged: (val) {
                        setState(() {
                          _selectedModelPath = val;
                          _modelInfo = null;
                        });
                        if (val != null) _refreshModelInfo();
                      },
                    ),
                    const SizedBox(height: 20),

                    // Context size
                    Text(
                      'Context Size',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _contextSizeController,
                      keyboardType: TextInputType.number,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: colors,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        suffixText: 'tokens',
                        suffixStyle: TextStyle(
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      onChanged: (val) {
                        final parsed = int.tryParse(val);
                        if (parsed != null && parsed > 0) {
                          setState(() {
                            _contextSize = parsed;
                            _batchSize = _suggestBatchSize();
                            _batchSizeController.text = '$_batchSize';
                          });
                          _debouncedEstimate();
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // KV Cache Quantization
                    Text(
                      'KV Cache Quantization',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildDropdown(
                      value: _kvQuant,
                      items: _kvQuantOptions,
                      onChanged: (val) {
                        setState(() => _kvQuant = val!);
                        _refreshDefaults();
                      },
                      colors: colors,
                      theme: theme,
                    ),
                    const SizedBox(height: 20),

                    // CPU Threads
                    Text(
                      'CPU Threads',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _threadsController,
                      keyboardType: TextInputType.number,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: colors,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        hintText: _detecting ? 'Detecting...' : null,
                      ),
                      onChanged: (val) {
                        final parsed = int.tryParse(val);
                        if (parsed != null && parsed > 0) {
                          _threads = parsed;
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // Batch Size
                    Text(
                      'Batch Size',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _batchSizeController,
                      focusNode: _batchSizeFocusNode,
                      keyboardType: TextInputType.number,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: colors,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        final parsed = int.tryParse(val);
                        if (parsed != null && parsed > 0) {
                          _batchSize = parsed;
                        }
                        _debouncedEstimate();
                      },
                    ),
                    const SizedBox(height: 20),

                    ContextManagementSelector(
                      currentMode: _contextMode,
                      smartCacheController: _smartCacheSlotsController,
                      onModeChanged: (v) {
                        setState(() => _contextMode = v);
                        _computeVramEstimate();
                      },
                      onSmartCacheSlotsChanged: (v) {
                        _smartCacheSlots = v;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Greedy allocation toggle
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colors,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Greedy memory allocation',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  'Lower padding = more VRAM for model, '
                                  'brief system-wide freeze',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppColors.textSecondary(context),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _greedyAllocation,
                            activeTrackColor: Theme.of(context).colorScheme.primary,
                            onChanged: (val) {
                              setState(() => _greedyAllocation = val);
                              _computeVramEstimate();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    GpuInfoTile(
                      hardwareInfo: _hardwareInfo,
                      gpuConfig: _gpuConfig,
                    ),

                    const SizedBox(height: 16),
                    VramUsageSection(
                      selectedModelPath: _selectedModelPath,
                      vramEstimate: _vramEstimate,
                      modelInfo: _modelInfo,
                      hardwareInfo: _hardwareInfo,
                      isGreedyAllocation: _greedyAllocation,
                    ),
                    const SizedBox(height: 4),

                    // Error message
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Footer buttons
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed:
                        (_generating || _selectedModelPath == null)
                            ? null
                            : _generate,
                    icon: _generating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high, size: 18),
                    label: Text(
                      _generating ? 'Generating...' : 'Generate & Apply',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required Color colors,
    required ThemeData theme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: colors,
          style: theme.textTheme.bodyMedium?.apply(
            color: AppColors.textPrimary(context),
          ),
          icon: Icon(
            Icons.arrow_drop_down,
            color: AppColors.textSecondary(context),
          ),
          items: items.map((v) {
            String label;
            if (v == 'f16') {
              label = 'None (f16) — highest quality';
            } else if (v == 'q8_0') {
              label = '8-bit (q8_0) — ~50% savings';
            } else {
              label = '4-bit (q4_0) — ~75% savings';
            }
            return DropdownMenuItem<String>(
              value: v,
              child: Text(label, style: const TextStyle(fontSize: 13)),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
