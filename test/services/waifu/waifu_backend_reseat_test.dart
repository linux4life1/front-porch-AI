// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('Nano-GPT and oMLX are different OpenCode targets', () {
    final nano = openCodeBackendFromProvider(
      OpenRouterService(
        apiUrl: kNanoGptApiV1,
        apiKey: 'sk-fake-nano',
        modelName: 'gpt-4o-mini',
      ),
    );
    final omlx = openCodeBackendFromProvider(
      OpenRouterService(
        apiUrl: 'http://localhost:8000/v1',
        apiKey: 'x',
        modelName: 'mlx-community/Qwen',
      ),
    );
    expect(openCodeBackendSame(nano, omlx), isFalse);
    expect(omlx.baseUrl, contains('localhost:8000'));
    expect(nano.modelId, 'gpt-4o-mini');
    expect(waifuBackendNeedsReseat(seated: nano, live: omlx), isTrue);
    expect(waifuBackendNeedsReseat(seated: nano, live: nano), isFalse);
    expect(waifuBackendNeedsReseat(seated: null, live: omlx), isFalse);
  });

  test('oMLX config write is localhost:8000, not the Nano-GPT URL', () async {
    final dir = await Directory.systemTemp.createTemp('waifu_omlx_cfg_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final closet = OpenCodeCloset(dir.path);
    await writeWaifuOpenCodeConfig(
      closet: closet,
      coworker: CharacterCard(name: 'Mira'),
      backend: openCodeBackendFromProvider(
        OpenRouterService(
          apiUrl: 'http://localhost:8000/v1',
          apiKey: 'x',
          modelName: 'mlx-community/Qwen',
        ),
      ),
      pathMode: WaifuPathMode.folderJail,
      mode: WaifuMode.build,
    );
    final raw = await File(closet.configFilePath).readAsString();
    expect(raw, contains('localhost:8000'));
    expect(raw, contains('mlx-community/Qwen'));
    expect(raw, isNot(contains('nano-gpt.com')));
  });
}
