// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A phone or web generate that needs the ComfyUI-GGUF loader update cannot
// answer the desktop's question, so it is told to confirm on the desktop at
// once instead of waiting on a dialog nobody in front of it can see.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/comfy_gguf_city96_gate.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/image_facade.dart';

import '../image/city96_test_loader.dart';
import '../image/city96_test_probe.dart';

Future<HttpServer> _comfy() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path == '/object_info') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          for (final c in [
            'UnetLoaderGGUF',
            'CLIPLoaderGGUF',
            'UNETLoader',
            'CLIPLoader',
            'VAELoader',
            'TextEncodeQwenImage21',
            'EmptySD3LatentImage',
            'KSampler',
            'VAEDecode',
            'SaveImage',
          ])
            c: <String, dynamic>{},
        }),
      );
    } else {
      await request.drain<void>();
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  return server;
}

void main() {
  test(
    'a web generate that needs the loader update is answered at once',
    () async {
      HttpOverrides.global = null;
      final server = await _comfy();
      addTearDown(() => server.close(force: true));
      final dir = Directory.systemTemp.createTempSync('facade-city96');
      addTearDown(() => dir.deleteSync(recursive: true));
      final loader = File('${dir.path}/loader.py')
        ..writeAsStringSync(kStockCity96Loader);
      var asked = 0;
      final saved = City96Gate.instance;
      City96Gate.instance = City96Gate(
        locate: (_) async => loader,
        probe: const FakeProbe(me: 1000),
        pidFor: (_) async => 100,
        // The desktop window: a question that nobody answers.
        ask: (_) {
          asked++;
          return Completer<bool>().future;
        },
      );
      addTearDown(() => City96Gate.instance = saved);

      final storage = StorageService.sandbox(dir.path);
      final s = storage.imageGenSettings;
      await s.setImageGenBackend('comfyui');
      await s.setComfyUiUrl('http://127.0.0.1:${server.port}');
      await s.setComfyCreateWorkflowId('qwen_image_21');
      for (final e in {
        '%MODEL_DIFFUSION%': 'qwen-image-2.1-Q2_K.gguf',
        '%MODEL_CLIP%': 'Qwen3-VL-8B-Instruct-Q4_K_M.gguf',
        '%MODEL_VAE%': 'qwen_image_2.1_vae_bf16.safetensors',
      }.entries) {
        await s.setComfyCreateModelChoice('qwen_image_21', e.key, e.value);
      }
      final image = ImageGenService(storage);
      final facade = ImageFacade(image, storage);

      final result = await facade
          .generate({'prompt': 'a porch at dusk'})
          .timeout(const Duration(seconds: 10));

      expect(result, isNull);
      expect(asked, 0);
      expect(image.statusMessage, startsWith(kCity96NeedsUpdate));
      expect(image.statusMessage, contains(kCity96ConfirmOnDesktop));
      expect(loader.readAsStringSync(), kStockCity96Loader);
    },
  );
}
