import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:front_porch_ai/services/hardware_service.dart';

enum ContextManagementMode {
  slidingWindowAttention,
  fastForwardSmartCache,
}

class KcppsGeneratorService {
  /// OS-specific physical core detection.
  static Future<int> detectPhysicalCores() async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run(
          'wmic',
          ['cpu', 'get', 'NumberOfCores'],
        );
        if (r.exitCode == 0) {
          for (final line in r.stdout.toString().split('\n')) {
            final trimmed = line.trim();
            final cores = int.tryParse(trimmed);
            if (cores != null && cores > 0) return cores;
          }
        }
      } else if (Platform.isMacOS) {
        final r = await Process.run('sysctl', ['-n', 'hw.physicalcpu']);
        if (r.exitCode == 0) {
          final cores = int.tryParse(r.stdout.toString().trim());
          if (cores != null && cores > 0) return cores;
        }
      } else if (Platform.isLinux) {
        final r = await Process.run('lscpu', ['-p=core']);
        if (r.exitCode == 0) {
          final coreIds = <String>{};
          for (final line in r.stdout.toString().split('\n')) {
            if (line.startsWith('#')) continue;
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;
            final parts = trimmed.split(',');
            if (parts.length >= 2) coreIds.add(parts[1]);
          }
          if (coreIds.isNotEmpty) return coreIds.length;
        }
      }
    } catch (_) {}
    return Platform.numberOfProcessors;
  }

  /// Suggest thread count based on SMT detection.
  static Future<int> suggestThreadCount() async {
    final logical = Platform.numberOfProcessors;
    final physical = await detectPhysicalCores();
    if (logical > physical) return physical;
    return (logical - 1).clamp(1, logical);
  }

  /// Build GPU backend config map from [HardwareInfo].
  static Map<String, dynamic> detectGpuBackend(HardwareInfo? hw) {
    if (hw == null) return {};

    if (hw.hasCuda) {
      return {'usecublas': ['normal', 0]};
    } else if (hw.hasMetal) {
      return {}; // Metal is automatic, no flag needed
    } else if (hw.vendor == 'AMD' || hw.vendor == 'Intel') {
      // Vulkan, never hipblas: exported .kcpps files run against the
      // MAINLINE koboldcpp builds, which on Windows have no hipblas at
      // all (the old hasRocm branch emitted a flag the exe rejects).
      return {'usevulkan': []};
    }

    // For unknown/Intel GPUs on Windows, try Vulkan if available
    if (Platform.isWindows) {
      return {'usevulkan': [0]};
    }

    return {};
  }

  /// Build the full kcpps content map.
  static Map<String, dynamic> buildKcppsContent({
    required String modelPath,
    required int contextSize,
    required int batchSize,
    required int threads,
    required String kvQuant,
    required bool greedyAllocation,
    required Map<String, dynamic> gpuConfig,
    required ContextManagementMode contextMode,
    int smartCacheSlots = 5,
  }) {
    final content = <String, dynamic>{
      'model_param': modelPath,
      'contextsize': contextSize,
      'batchsize': batchSize,
      'gpulayers': -1,
      'autofit': true,
      'autofitpadding': greedyAllocation ? 32 : 1024,
      'usemmap': true,
      'usemlock': false,
      'quantkv': kvQuant,
      'threads': threads,
      'noflashattention': false,
    };

    if (gpuConfig.isNotEmpty) content.addAll(gpuConfig);

    if (contextMode == ContextManagementMode.slidingWindowAttention) {
      content['noswa'] = false;
      content['swapadding'] = 0;
      content['nofastforward'] = true;
      content['noshift'] = true;
    } else {
      content['noswa'] = true;
      content['nofastforward'] = false;
      content['noshift'] = false;
      content['smartcache'] = smartCacheSlots.clamp(1, 20);
    }

    return content;
  }

  /// Write kcpps JSON to [binDir] and return the full file path.
  static Future<File> writeKcppsFile(
    Directory binDir,
    String modelPath,
    Map<String, dynamic> content,
  ) async {
    final basename = path.basenameWithoutExtension(modelPath);
    final kcppsFile = File(path.join(binDir.path, '$basename.kcpps'));
    final encoder = const JsonEncoder.withIndent('  ');
    await kcppsFile.writeAsString(encoder.convert(content));
    return kcppsFile;
  }
}
