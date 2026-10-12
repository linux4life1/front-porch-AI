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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/services/comfy_ui_service.dart';
import 'package:front_porch_ai/services/grpc/draw_things_grpc_service.dart';
import 'package:front_porch_ai/services/image/image_gen_lora_slots.dart';

import 'image_gen_payload.dart';
import 'image_gen_status.dart';

/// Generate via AUTOMATIC1111 / Draw Things local server.
///
/// Endpoint: POST {baseUrl}/sdapi/v1/txt2img — or /sdapi/v1/img2img when a
/// [referenceImage] is supplied (init image at [denoise] denoising strength).
/// Response: { "images": ["<base64>", ...] }
///
/// When [modelCheckpoint] is non-empty and the backend is Draw Things,
/// the active model is switched via `POST /sdapi/v1/options` first,
/// mimicking "create a new project" with the selected model.
Future<Uint8List> generateViaA1111({
  required ImageGenStatus status,
  required String? lastLoadedCheckpoint,
  required Future<bool> Function(String baseUrl, String modelName)
  switchLocalModel,
  required String baseUrl,
  required String prompt,
  String negativePrompt = '',
  String size = '1024x1024',
  String modelCheckpoint = '',
  bool switchModelFirst = false,
  String loraName = '',
  double loraWeight = 0.8,
  List<ImageGenLoraSlot> loras = const [],
  int steps = 20,
  double cfgScale = 7.0,
  String samplerName = 'Euler a',
  String scheduler = 'Automatic',
  int seed = -1,
  Uint8List? referenceImage,
  double denoise = 0.5,
}) async {
  // Switch model only if a different checkpoint was requested.
  // Skipping redundant switches prevents the unload→reload cycle that
  // can leave tensors split across CPU & CUDA on Windows/nVidia setups.
  if (switchModelFirst &&
      modelCheckpoint.isNotEmpty &&
      modelCheckpoint != lastLoadedCheckpoint) {
    status.say('Loading model: $modelCheckpoint…');
    await switchLocalModel(baseUrl, modelCheckpoint);
  }

  final (width, height) = parseImageGenSize(size);
  // img2img when a reference image is supplied; else txt2img (unchanged path).
  final isImg2Img = referenceImage != null && referenceImage.isNotEmpty;
  final endpoint = isImg2Img ? 'img2img' : 'txt2img';
  final uri = Uri.parse(
    '${ComfyUiService.ensureHttpScheme(baseUrl)}/sdapi/v1/$endpoint',
  );

  // Inject every filled slot: <lora:name:weight>
  final stacked = loras.isNotEmpty
      ? loras
      : [ImageGenLoraSlot(file: loraName, weight: loraWeight)];
  final effectivePrompt = promptWithLoras(prompt, stacked);

  debugPrint(
    'ImageGen: POST $uri (model=${modelCheckpoint.isNotEmpty ? modelCheckpoint : "current"}, lora=${loraName.isNotEmpty ? loraName : "none"})',
  );

  final payload = buildA1111PayloadMap(
    prompt: effectivePrompt,
    negativePrompt: negativePrompt,
    width: width,
    height: height,
    steps: steps,
    cfgScale: cfgScale,
    samplerName: samplerName,
    scheduler: scheduler,
    seed: seed,
    referenceImageB64: isImg2Img ? base64Encode(referenceImage) : null,
    denoise: denoise,
  );

  final client = http.Client();
  // Live progress while the txt2img request is in flight: A1111 exposes
  // GET /sdapi/v1/progress with a percent AND an in-progress preview frame,
  // so the chat/studio can show the image forming instead of a spinner.
  final progressUri = Uri.parse(
    '${ComfyUiService.ensureHttpScheme(baseUrl)}/sdapi/v1/progress',
  );
  final progressTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
    try {
      final r = await http.get(progressUri).timeout(const Duration(seconds: 2));
      if (r.statusCode != 200) return;
      final p = jsonDecode(r.body) as Map<String, dynamic>;
      final pct = (p['progress'] as num?)?.toDouble();
      final b64 = p['current_image'] as String?;
      status.updateGenProgress(
        (pct != null && pct > 0) ? pct.clamp(0.0, 1.0) : null,
        (b64 != null && b64.isNotEmpty) ? base64Decode(b64) : null,
      );
    } catch (_) {
      // transient — the next tick retries; the request itself is the truth
    }
  });
  try {
    final response = await client
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 600)); // allow time for model load

    if (response.statusCode != 200) {
      String errorMsg = 'HTTP ${response.statusCode}';
      try {
        final errBody = jsonDecode(response.body);
        final detail = errBody['detail'];
        if (detail is String) errorMsg = detail;
      } catch (_) {}
      throw Exception(errorMsg);
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final images = body['images'] as List<dynamic>?;
    if (images == null || images.isEmpty) {
      throw Exception('No images returned from local server');
    }

    final b64 = images[0] as String;
    return base64Decode(b64);
  } finally {
    progressTimer.cancel();
    client.close();
  }
}

/// Generate via Draw Things gRPC service (Python client bridge).
/// Extended with DT-native params, LoRAs, + optional reference image (passed through to CLI).
Future<Uint8List> generateViaDrawThingsGrpc({
  required DrawThingsGrpcService grpcService,
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
  int sampler = 16,
  int seedMode = 2,
  bool teaCache = false,
  double teaCacheThreshold = 0.15,
  bool cfgZeroStar = false,
  List<Map<String, dynamic>> loras = const [],
  Uint8List? referenceImage,
  void Function(int step, int totalSteps)? onProgress,
}) async {
  return await grpcService.generateImage(
    prompt: prompt,
    negativePrompt: negativePrompt,
    model: model,
    width: width,
    height: height,
    steps: steps,
    cfgScale: cfgScale,
    seed: seed,
    strength: strength,
    shift: shift,
    sampler: sampler,
    seedMode: seedMode,
    teaCache: teaCache,
    teaCacheThreshold: teaCacheThreshold,
    cfgZeroStar: cfgZeroStar,
    loras: loras,
    referenceImageBytes: referenceImage,
    onProgress: onProgress,
  );
}
