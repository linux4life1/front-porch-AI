// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/engine_health.dart';

import 'dt_native/draw_things_native_client.dart';
import 'dt_native/dt_fpzip.dart';

/// Draw Things gRPC service — the pure-Dart native client
/// (dt_native/draw_things_native_client.dart), in-process, no Python (the
/// JSON CLI sidecar is gone — docs/design/sidecar-retirement.md phase 1).
/// `[DT-Native]` log lines show what happened; failures are tallied in
/// [EngineHealth] (pre-release builds surface the first one loudly).
class DrawThingsGrpcService {
  final String host;
  final int port;

  DrawThingsGrpcService({required this.host, this.port = 7859}) {
    debugPrint('DrawThingsGrpcService: host=$host port=$port (native gRPC)');
  }

  /// Tests the gRPC connection (TLS handshake + Echo).
  Future<bool> testConnection() async {
    final native = DrawThingsNativeClient(host: host, port: port);
    try {
      await native.echo();
      debugPrint('[DT-Native] testConnection OK');
      EngineHealth.instance.reportNative(EngineHealth.drawThings);
      return true;
    } catch (e) {
      debugPrint('[DT-Native] testConnection failed: $e');
      EngineHealth.instance.reportFailure(
        EngineHealth.drawThings,
        'connection failed: $e',
      );
      return false;
    } finally {
      unawaited(native.shutdown());
    }
  }

  /// Checkpoint filter for the raw Draw Things file listing.
  /// We use broad category patterns so users don't have to manually
  /// blacklist every VAE, upscaler (4x_ultrasharp, etc.), or preprocessor.
  /// Text encoders / CLIP / T5 / LLM sidecars — these skip a file ONLY
  /// when it lacks an image-model marker: modern checkpoints carry the
  /// LLM family name AND 'image' (qwen_image_*.ckpt, z_image_*,
  /// ernie_image_*), while encoder sidecars never do (qwen_2.5_vl_*,
  /// ministral_3_3b_*, t5_xxl_*). A blanket 'qwen' ban used to hide the
  /// Qwen-Image checkpoint itself.
  static List<String> _filterCheckpoints(List<String> raw) {
    const encoderKeywords = [
      'clip', 't5', 'text_encoder', 'encoder', 'gemma', 'llama',
      'mistral', 'ministral', 'qwen', 'phi', 'vicuna', 'alpaca',
    ];
    const skip = [
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

      // Upscalers / face restorers (4x_*, realesrgan, ultrasharp etc.)
      '4x_', '2x_', 'realesrgan', 'esrgan', 'ultrasharp', 'swinir',
      'hat_', 'real_esrgan', 'upscaler', 'restoreformer', 'gfpgan',
      'codeformer',

      // Video / I2V / motion models
      'i2v', 'video', 'wan_', 'svd', 'motion', 'ltx',
    ];
    // Include everything that is not a known sidecar type so the dropdown
    // populates even when Draw Things reports bare names, .pth files, or
    // paths.
    return raw.where((f) {
      final lower = f.toLowerCase();
      if (skip.any((k) => lower.contains(k))) return false;
      if (!lower.contains('image') &&
          encoderKeywords.any((k) => lower.contains(k))) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Fetches checkpoint models (Draw Things Echo("models") listing).
  Future<List<String>> fetchModels() async {
    final native = DrawThingsNativeClient(host: host, port: port);
    try {
      final models = _filterCheckpoints(await native.listFiles());
      debugPrint('[DT-Native] Fetched ${models.length} models (filtered)');
      return models;
    } catch (e) {
      debugPrint('[DT-Native] fetchModels failed: $e');
      return [];
    } finally {
      unawaited(native.shutdown());
    }
  }

  /// Fetches available LoRA files from Draw Things (same Echo('models')
  /// listing the checkpoint fetch uses, filtered to files containing
  /// "lora"). Returned names are passed verbatim into the generation
  /// config's `loras` list.
  Future<List<String>> fetchLoras() async {
    final native = DrawThingsNativeClient(host: host, port: port);
    try {
      final loras = (await native.listFiles())
          .where((f) => f.toLowerCase().contains('lora'))
          .toList();
      debugPrint('[DT-Native] Fetched ${loras.length} LoRAs');
      return loras;
    } catch (e) {
      debugPrint('[DT-Native] fetchLoras failed: $e');
      return [];
    } finally {
      unawaited(native.shutdown());
    }
  }

  /// Generates an image via the native gRPC client (full DT-native config
  /// passed through).
  /// referenceImageBytes: optional PNG/JPG/etc bytes for img2img.
  /// loras: optional list of {'file': name, 'weight': double} maps applied
  /// natively by Draw Things.
  /// [onProgress] receives (step, totalSteps) from Draw Things' streamed
  /// sampling signposts (no preview frames are available over this
  /// protocol).
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
    List<Map<String, dynamic>> loras = const [],
    Uint8List? referenceImageBytes,
    void Function(int step, int totalSteps)? onProgress,
  }) async {
    // Config dict with all DT-specific knobs (the FlatBuffer builder in the
    // native client consumes these keys).
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
      if (loras.isNotEmpty) 'loras': loras,
    };

    debugPrint(
      'DrawThingsGrpcService: generate (model=$model, '
      'loras=${loras.isEmpty ? "none" : loras.map((l) => l['file']).join(',')})',
    );

    // Pre-flight fpzip: generated images arrive as fpzip-compressed NNC
    // tensors, so without libfpzip the generation would only fail AFTER a
    // full (possibly minutes-long) render. Releases bundle libfpzip in
    // Contents/Frameworks/ — missing means broken packaging (or a dev
    // checkout that hasn't run scripts/build-fpzip-macos.sh).
    if (!DtFpzip.instance.isAvailable) {
      EngineHealth.instance.reportFailure(
        EngineHealth.drawThings,
        'libfpzip not found — cannot decode generated images',
      );
      throw Exception(
        'libfpzip is missing from this build — Draw Things images cannot '
        'be decoded (dev checkouts: run scripts/build-fpzip-macos.sh).',
      );
    }

    final native = DrawThingsNativeClient(host: host, port: port);
    try {
      final bytes = await native.generate(
        prompt: prompt,
        negativePrompt: negativePrompt,
        cfg: cfg,
        referenceImageBytes: referenceImageBytes,
        onStep: onProgress == null ? null : (step) => onProgress(step, steps),
      );
      debugPrint('[DT-Native] Generated ${bytes.length} bytes');
      EngineHealth.instance.reportNative(EngineHealth.drawThings);
      return bytes;
    } catch (e) {
      debugPrint('[DT-Native] generate failed: $e');
      EngineHealth.instance.reportFailure(
        EngineHealth.drawThings,
        'generation failed: $e',
      );
      rethrow;
    } finally {
      unawaited(native.shutdown());
    }
  }
}
