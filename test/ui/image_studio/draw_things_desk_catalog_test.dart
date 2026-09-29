// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/image_facade.dart';
import 'package:front_porch_ai/ui/image_studio/studio_desk.dart';
import 'package:provider/provider.dart';

/// Lists two checkpoints and one LoRA without talking to Draw Things.
class _ListedDrawThings extends ImageGenService {
  _ListedDrawThings(super.storage);

  @override
  Future<bool> testLocalConnection(String baseUrl) async => true;

  @override
  Future<List<String>> fetchDrawThingsModels(String baseUrl) async {
    return const ['qwen_image.safetensors', 'flux_dev.safetensors'];
  }

  @override
  Future<Map<String, String>> fetchDrawThingsModelVersions(
    String baseUrl,
  ) async => const {};

  @override
  Future<List<LoraOption>> fetchDrawThingsLoras(String baseUrl) async {
    return const [
      LoraOption(
        'detail.safetensors',
        ModelFamily.qwen,
        familyFromMetadata: true,
      ),
    ];
  }
}

/// A Klein 9B checkpoint with one matching LoRA and two other versions.
class _VersionedDrawThings extends ImageGenService {
  _VersionedDrawThings(super.storage);

  @override
  Future<bool> testLocalConnection(String baseUrl) async => true;

  @override
  Future<List<String>> fetchDrawThingsModels(String baseUrl) async {
    return const ['flux_2_klein_9b_q8p.ckpt'];
  }

  @override
  Future<Map<String, String>> fetchDrawThingsModelVersions(
    String baseUrl,
  ) async {
    return const {'flux_2_klein_9b_q8p.ckpt': 'flux2_9b'};
  }

  @override
  Future<List<LoraOption>> fetchDrawThingsLoras(String baseUrl) async {
    return const [
      LoraOption(
        'klein_unchained_v2_lora_f16.ckpt',
        ModelFamily.flux,
        familyFromMetadata: true,
        dtVersion: 'flux2_9b',
      ),
      LoraOption(
        'ltx_fingering_lora_f16.ckpt',
        ModelFamily.unknown,
        dtVersion: 'ltx2.3',
      ),
      LoraOption(
        'Flux2-Klein-Image-RestoreV1.safetensors',
        ModelFamily.flux,
        familyFromMetadata: true,
        dtVersion: 'flux1',
      ),
    ];
  }
}

void main() {
  test('Draw Things ready reports diffusion files and LoRAs', () async {
    final dir = Directory.systemTemp.createTempSync('dt-ready');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = StorageService.sandbox(dir.path);
    await storage.imageGenSettings.setImageGenBackend('drawthings');
    final ready = await ImageFacade(
      _ListedDrawThings(storage),
      storage,
    ).studioReady(edit: false);
    expect(ready['diffusionCount'], 2);
    expect(ready['loraCount'], 1);
    expect(ready['reachable'], isTrue);
  });

  testWidgets('Draw Things shows its diffusion count and listed LoRAs', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('dt-desk');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = StorageService.sandbox(dir.path);
    await storage.imageGenSettings.setImageGenBackend('drawthings');
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<ImageGenService>.value(
              value: _ListedDrawThings(storage),
            ),
          ],
          child: const Scaffold(body: StudioDesk()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Reachable · 2 diffusion files · 1 LoRAs'),
      findsOneWidget,
    );

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('detail.safetensors'), findsOneWidget);
    expect(
      find.text('No LoRA files were listed by the connected app.'),
      findsNothing,
    );
  });

  test('a Klein model catalog drops other LoRA versions', () async {
    final dir = Directory.systemTemp.createTempSync('dt-catalog');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = StorageService.sandbox(dir.path);
    await storage.imageGenSettings.setImageGenBackend('drawthings');
    final body = await ImageFacade(
      _VersionedDrawThings(storage),
      storage,
    ).localCatalog(model: 'flux_2_klein_9b_q8p.ckpt');
    expect(body['loras'], ['klein_unchained_v2_lora_f16.ckpt']);
    expect(body['loraCount'], 3);
    expect(body['diffusionCount'], 1);
  });

  testWidgets('Draw Things Add lists only the loaded model version', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('dt-versions');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = StorageService.sandbox(dir.path);
    await storage.imageGenSettings.setImageGenBackend('drawthings');
    await storage.imageGenSettings.setImageGenModel('flux_2_klein_9b_q8p.ckpt');
    await storage.imageGenSettings.setImageGenLoraSlot(
      0,
      file: 'Flux2-Klein-Image-RestoreV1.safetensors',
      weight: 0.9,
    );
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<ImageGenService>.value(
              value: _VersionedDrawThings(storage),
            ),
          ],
          child: const Scaffold(body: StudioDesk()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Reachable · 1 diffusion files · 3 LoRAs'),
      findsOneWidget,
    );

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    final sheet = find.byType(AlertDialog);
    expect(
      find.descendant(
        of: sheet,
        matching: find.text('klein_unchained_v2_lora_f16.ckpt'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: sheet,
        matching: find.text('ltx_fingering_lora_f16.ckpt'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: sheet,
        matching: find.text('Flux2-Klein-Image-RestoreV1.safetensors'),
      ),
      findsOneWidget,
    );
  });
}
