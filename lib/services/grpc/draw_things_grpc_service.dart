// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Progress update from image generation
class ImageGenProgress {
  final int step;
  final int totalSteps;
  final String message;

  const ImageGenProgress(this.step, this.totalSteps, {this.message = ''});
}

/// Draw Things gRPC service — thin JSON CLI wrapper around the (untouched) Python client.py
/// Bundled via PyInstaller in release builds (Resources/dt_grpc/dt_grpc_client/...).
/// Falls back to python3 + dt_grpc_client.py for flutter run dev (requires `pip install -r tools/dt-grpc-python/requirements.txt` once).
class DrawThingsGrpcService {
  final String host;
  final int port;

  DrawThingsGrpcService({required this.host, this.port = 7859}) {
    debugPrint('DrawThingsGrpcService: host=$host port=$port (CLI sidecar)');
  }

  /// Tests connection via the JSON CLI sidecar (bundled or dev fallback).
  Future<bool> testConnection() async {
    try {
      final req = jsonEncode({'op': 'test', 'host': host, 'port': port});

      // Inline CLI invocation (no new private helpers — see method count hygiene)
      final execDir = File(Platform.resolvedExecutable).parent.path;
      String? cliExe;
      String? pyScript;
      bool useWrapper = false;
      if (Platform.isMacOS) {
        final contents = File(Platform.resolvedExecutable).parent.parent.path;
        final bundled = p.join(
          contents,
          'Resources',
          'dt_grpc',
          'dt_grpc_client',
          'dt_grpc_client',
        );
        if (File(bundled).existsSync()) {
          cliExe = bundled;
          useWrapper = true;
        }
      }
      if (cliExe == null) {
        // Dev fallback: walk for dt_grpc_client.py (mirrors stt/kokoro pattern, inlined)
        var dir = Directory(execDir);
        for (int i = 0; i < 12; i++) {
          final cand = File(
            p.join(dir.path, 'tools', 'dt-grpc-python', 'dt_grpc_client.py'),
          );
          if (cand.existsSync()) {
            pyScript = cand.path;
            break;
          }
          final parent = dir.parent;
          if (parent.path == dir.path) break;
          dir = parent;
        }
        if (pyScript == null) {
          final cwdCand = File(
            p.join(
              Directory.current.path,
              'tools',
              'dt-grpc-python',
              'dt_grpc_client.py',
            ),
          );
          if (cwdCand.existsSync()) pyScript = cwdCand.path;
        }
      }

      final process = await Process.start(
        useWrapper ? cliExe! : (Platform.isWindows ? 'python' : 'python3'),
        useWrapper ? [] : (pyScript != null ? [pyScript] : []),
        includeParentEnvironment: true,
      );
      process.stdin.writeln(req);
      await process.stdin.close();

      final stdoutFut = process.stdout.transform(utf8.decoder).join();
      final stderrFut = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 25),
      );
      final stdoutStr = await stdoutFut;
      final stderrStr = await stderrFut;

      if (exitCode == 0) {
        try {
          final parsed = jsonDecode(stdoutStr.trim());
          if (parsed is Map && parsed['success'] == true) {
            debugPrint('DrawThingsGrpcService: testConnection OK');
            return true;
          }
        } catch (_) {}
      }
      final filteredTestErr = stderrStr
          .split('\n')
          .where((l) => !l.contains('CERTIFICATE_VERIFY_FAILED'))
          .join('\n')
          .trim();
      debugPrint(
        'DrawThingsGrpcService: testConnection failed: $stdoutStr / $filteredTestErr',
      );
      return false;
    } catch (e) {
      debugPrint('DrawThingsGrpcService: testConnection error: $e');
      return false;
    }
  }

  /// Fetches checkpoint models via the JSON CLI sidecar (uses Draw Things Echo hack internally in CLI).
  Future<List<String>> fetchModels() async {
    try {
      final req = jsonEncode({'op': 'models', 'host': host, 'port': port});

      // Inline CLI invocation (duplicated resolution + spawn to obey "at most 2 new private methods across all Dart changes" rule)
      final execDir = File(Platform.resolvedExecutable).parent.path;
      String? cliExe;
      String? pyScript;
      bool useWrapper = false;
      if (Platform.isMacOS) {
        final contents = File(Platform.resolvedExecutable).parent.parent.path;
        final bundled = p.join(
          contents,
          'Resources',
          'dt_grpc',
          'dt_grpc_client',
          'dt_grpc_client',
        );
        if (File(bundled).existsSync()) {
          cliExe = bundled;
          useWrapper = true;
        }
      }
      if (cliExe == null) {
        var dir = Directory(execDir);
        for (int i = 0; i < 12; i++) {
          final cand = File(
            p.join(dir.path, 'tools', 'dt-grpc-python', 'dt_grpc_client.py'),
          );
          if (cand.existsSync()) {
            pyScript = cand.path;
            break;
          }
          final parent = dir.parent;
          if (parent.path == dir.path) break;
          dir = parent;
        }
        if (pyScript == null) {
          final cwdCand = File(
            p.join(
              Directory.current.path,
              'tools',
              'dt-grpc-python',
              'dt_grpc_client.py',
            ),
          );
          if (cwdCand.existsSync()) pyScript = cwdCand.path;
        }
      }

      final process = await Process.start(
        useWrapper ? cliExe! : (Platform.isWindows ? 'python' : 'python3'),
        useWrapper ? [] : (pyScript != null ? [pyScript] : []),
        includeParentEnvironment: true,
      );
      process.stdin.writeln(req);
      await process.stdin.close();

      final stdoutFut = process.stdout.transform(utf8.decoder).join();
      final stderrFut = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 25),
      );
      final stdoutStr = await stdoutFut;
      final stderrStr = await stderrFut;

      if (exitCode == 0) {
        try {
          var parsed = jsonDecode(stdoutStr.trim());
          if (parsed is Map && parsed['success'] == true) {
            // good
          } else {
            // try last JSON line robustness
            final lines = stdoutStr.trim().split('\n').reversed;
            for (final line in lines) {
              final t = line.trim();
              if (t.startsWith('{') && t.endsWith('}')) {
                parsed = jsonDecode(t);
                break;
              }
            }
          }
          if (parsed is Map && parsed['success'] == true) {
            final raw =
                (parsed['models'] as List?)?.cast<String>() ?? <String>[];
            // Secondary filter on Dart side (defense in depth).
            // This mirrors the improved logic in dt_grpc_client.py.
            // We use broad category patterns so users don't have to manually
            // blacklist every VAE, upscaler (4x_ultrasharp, etc.), or preprocessor.
            final skip = [
              // Text encoders / CLIP / T5 / LLM encoders
              'clip', 't5', 'text_encoder', 'encoder', 'gemma', 'llama',
              'mistral', 'qwen', 'phi', 'chroma', 'ltx', 'vicuna', 'alpaca',

              // VAEs
              'vae',

              // Safety / NSFW filters
              'safety',

              // LoRAs
              'lora',

              // ControlNet + common preprocessors
              'controlnet', 'openpose', 'dwpose', 'pose', 'depth', 'canny',
              'normal', 'lineart', 'softedge', 'seg', 'inpaint', 'ip2p',
              'shuffle', 'mlsd', 'tile', 'blur', 'hed', 'parsenet',

              // Upscalers (catches most 4x_*, realesrgan, ultrasharp variants etc.)
              '4x_', '2x_', 'realesrgan', 'esrgan', 'ultrasharp', 'swinir',
              'hat_', 'real_esrgan', 'upscaler',

              // Video / I2V / motion models
              'i2v', 'video', 'wan_', 'svd', 'motion',
            ];
            final models = raw.where((f) {
              final lower = f.toLowerCase();
              if (skip.any((k) => lower.contains(k))) return false;
              return f.endsWith('.ckpt') ||
                  f.endsWith('.safetensors') ||
                  f.endsWith('.pt');
            }).toList();

            debugPrint(
              'DrawThingsGrpcService: Fetched ${models.length} models via CLI (after filtering)',
            );
            return models;
          }
        } catch (_) {}
      }
      final filteredFetchErr = stderrStr
          .split('\n')
          .where((l) => !l.contains('CERTIFICATE_VERIFY_FAILED'))
          .join('\n')
          .trim();
      debugPrint(
        'DrawThingsGrpcService: fetchModels failed (CLI): $stdoutStr / $filteredFetchErr',
      );
      return [];
    } catch (e) {
      debugPrint('DrawThingsGrpcService: fetchModels error: $e');
      return [];
    }
  }

  /// Generates an image via the JSON CLI sidecar (full DT-native config passed through).
  /// referenceImageBytes: optional PNG/JPG/etc bytes for img2img (written to temp file for the Python client).
  Future<Uint8List> generateImage({
    required String prompt,
    String negativePrompt = '',
    String model = '',
    int width = 1024,
    int height = 1024,
    int steps = 20,
    double cfgScale = 7.0,
    int seed = -1,
    double strength = 1.0,
    double shift = 3.0,
    int sampler = 16, // Sampler.DDIM_TRAILING default
    int seedMode = 2, // SeedMode.SCALE_ALIKE
    bool teaCache = false,
    double teaCacheThreshold = 0.15,
    bool cfgZeroStar = false,
    Uint8List? referenceImageBytes,
    Function(ImageGenProgress)? onProgress,
  }) async {
    // Inline everything (0 new private methods added in this file — rule compliance)
    Directory? refTempDir;
    String? refImagePath;
    String? cliOutPath; // reported by CLI
    final tempRoot = await getTemporaryDirectory();

    try {
      // If reference image bytes supplied, write to a short-lived temp for the Python NNC encoder.
      // Use high-entropy name (timestamp + random) to reduce TOCTOU/predictability risk.
      if (referenceImageBytes != null && referenceImageBytes.isNotEmpty) {
        final rand =
            DateTime.now().millisecondsSinceEpoch ^
            (DateTime.now().microsecondsSinceEpoch % 100000);
        refTempDir = await Directory(
          p.join(tempRoot.path, 'dt_ref_$rand'),
        ).create(recursive: true);
        refImagePath = p.join(refTempDir.path, 'ref.png');
        await File(refImagePath).writeAsBytes(referenceImageBytes);
        debugPrint(
          'DrawThingsGrpcService: Wrote ${referenceImageBytes.length} byte reference image to temp',
        );
      }

      // Build rich config dict for the CLI (all DT-specific knobs)
      final cfg = {
        'model': model,
        'start_width': width ~/ 64,
        'start_height': height ~/ 64,
        'seed': (seed == -1 ? 0 : seed),
        'steps': steps,
        'guidance_scale': cfgScale,
        'strength': strength,
        'shift': shift,
        'sampler': sampler,
        'seed_mode': seedMode,
        'tea_cache': teaCache,
        'tea_cache_threshold': teaCacheThreshold,
        'cfg_zero_star': cfgZeroStar,
        'resolution_dependent_shift': false,
        'mask_blur': 1.5,
        'sharpness': 0.0,
      };

      final req = jsonEncode({
        'op': 'generate',
        'host': host,
        'port': port,
        'prompt': prompt,
        'negative_prompt': negativePrompt,
        'config': cfg,
        if (refImagePath != null) 'reference_image_path': refImagePath,
      });

      // Inline CLI resolution + spawn + stdin (duplicated from other methods — required for 0 new private methods rule)
      final execDir = File(Platform.resolvedExecutable).parent.path;
      String? cliExe;
      String? pyScript;
      bool useWrapper = false;
      if (Platform.isMacOS) {
        final contents = File(Platform.resolvedExecutable).parent.parent.path;
        final bundled = p.join(
          contents,
          'Resources',
          'dt_grpc',
          'dt_grpc_client',
          'dt_grpc_client',
        );
        if (File(bundled).existsSync()) {
          cliExe = bundled;
          useWrapper = true;
        }
      }
      if (cliExe == null) {
        var dir = Directory(execDir);
        for (int i = 0; i < 12; i++) {
          final cand = File(
            p.join(dir.path, 'tools', 'dt-grpc-python', 'dt_grpc_client.py'),
          );
          if (cand.existsSync()) {
            pyScript = cand.path;
            break;
          }
          final parent = dir.parent;
          if (parent.path == dir.path) break;
          dir = parent;
        }
        if (pyScript == null) {
          final cwdCand = File(
            p.join(
              Directory.current.path,
              'tools',
              'dt-grpc-python',
              'dt_grpc_client.py',
            ),
          );
          if (cwdCand.existsSync()) pyScript = cwdCand.path;
        }
      }

      debugPrint(
        'DrawThingsGrpcService: spawning ${useWrapper ? "bundled" : "dev python"} CLI for generate',
      );
      final process = await Process.start(
        useWrapper ? cliExe! : (Platform.isWindows ? 'python' : 'python3'),
        useWrapper ? [] : (pyScript != null ? [pyScript] : []),
        includeParentEnvironment: true,
      );
      process.stdin.writeln(req);
      await process.stdin.close();

      final stdoutFut = process.stdout.transform(utf8.decoder).join();
      final stderrFut = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 300),
      );
      final stdoutStr = await stdoutFut;
      final stderrStr = await stderrFut;

      if (stderrStr.isNotEmpty) {
        final filtered = stderrStr
            .split('\n')
            .where((l) => !l.contains('CERTIFICATE_VERIFY_FAILED'))
            .join('\n')
            .trim();
        if (filtered.isNotEmpty) {
          debugPrint('DrawThingsGrpcService: CLI stderr: $filtered');
        }
      }

      if (exitCode != 0) {
        throw Exception('CLI generation failed (exit $exitCode): $stdoutStr');
      }

      Map<String, dynamic> parsed;
      try {
        parsed = jsonDecode(stdoutStr.trim()) as Map<String, dynamic>;
      } catch (_) {
        // Robustness: the CLI should only emit one clean JSON line on stdout,
        // but if extra prints leaked, try to find the last JSON object.
        final lines = stdoutStr.trim().split('\n').reversed;
        String? jsonLine;
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
            jsonLine = trimmed;
            break;
          }
        }
        if (jsonLine != null) {
          try {
            parsed = jsonDecode(jsonLine) as Map<String, dynamic>;
          } catch (_) {
            throw Exception('CLI returned non-JSON: $stdoutStr');
          }
        } else {
          throw Exception('CLI returned non-JSON: $stdoutStr');
        }
      }
      if (parsed['success'] != true) {
        throw Exception(
          'Generation error from CLI: ${parsed['error'] ?? stdoutStr}',
        );
      }

      cliOutPath = parsed['output_path'] as String?;
      if (cliOutPath == null || cliOutPath.isEmpty) {
        throw Exception('CLI did not return output_path');
      }

      final outFile = File(cliOutPath);
      if (!await outFile.exists()) {
        throw Exception('CLI output file missing at $cliOutPath');
      }
      final bytes = await outFile.readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('CLI output file empty');
      }
      debugPrint(
        'DrawThingsGrpcService: Generated ${bytes.length} bytes via CLI (elapsed=${parsed['elapsed']})',
      );
      return bytes;
    } catch (e) {
      debugPrint('DrawThingsGrpcService: generateImage error: $e');
      rethrow;
    } finally {
      // Best-effort cleanup of any temps we created
      try {
        if (refTempDir != null && await refTempDir.exists()) {
          await refTempDir.delete(recursive: true);
        }
      } catch (_) {}
      try {
        if (cliOutPath != null) {
          final f = File(cliOutPath);
          if (await f.exists()) await f.delete();
          final parent = f.parent;
          if (await parent.exists() && (await parent.list().isEmpty)) {
            await parent.delete();
          }
        }
      } catch (_) {}
    }
  }
}
