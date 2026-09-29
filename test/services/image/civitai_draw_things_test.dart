// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/civitai_download.dart';
import 'package:front_porch_ai/services/image/studio_model_roots.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'Draw Things checkpoints sit in the Models folder and LoRAs in lora/',
    () {
      expect(
        civitaiSlotFolder(
          fromLoraSheet: false,
          civitaiType: 'Checkpoint',
          filename: 'z_image_turbo_bf16.safetensors',
          backend: 'drawthings',
        ),
        '',
      );
      expect(
        civitaiSlotFolder(
          fromLoraSheet: true,
          civitaiType: 'LORA',
          filename: 'z-image-turbo-realism.safetensors',
          backend: 'drawthings',
        ),
        'lora',
      );
      expect(
        civitaiSlotFolder(
          fromLoraSheet: false,
          civitaiType: 'Checkpoint',
          filename: 'model.gguf',
          backend: 'drawthings',
        ),
        isNull,
      );
      expect(
        civitaiDownloadPath(
          root: '/Models',
          folder: '',
          name: 'z_image_turbo_bf16.safetensors',
        ),
        p.join('/Models', 'z_image_turbo_bf16.safetensors'),
      );
      expect(
        civitaiDownloadPath(
          root: '/Models',
          folder: 'lora',
          name: 'z-image-turbo-realism.safetensors',
        ),
        p.join('/Models', 'lora', 'z-image-turbo-realism.safetensors'),
      );
      expect(
        civitaiBlockedDownload(backend: 'drawthings', savedRoot: '/Models'),
        isNull,
      );
      expect(
        civitaiBlockedDownload(backend: 'a1111', savedRoot: '/webui'),
        isNull,
      );
    },
  );

  test('a downloaded LoRA is recorded once in custom_lora.json', () async {
    final dir = await Directory.systemTemp.createTemp('dt_catalog_');
    try {
      const name = 'z-image-turbo-realism.safetensors';
      await rememberDrawThingsLora(dir, name);
      await rememberDrawThingsLora(dir, name);
      final rows =
          jsonDecode(
                await File(p.join(dir.path, 'custom_lora.json')).readAsString(),
              )
              as List;
      expect(rows, hasLength(1));
      expect(rows.single['file'], name);
      expect(rows.single['version'], 'z_image');
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
