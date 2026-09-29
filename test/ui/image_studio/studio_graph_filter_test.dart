// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/image_gen_types.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/image_studio/image_studio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        return Directory.systemTemp.createTempSync('fpai_graph_').path;
      });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpDesk(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1040, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('desk-graph');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final storage = StorageService.sandbox(dir.path);
    final prefs = await SharedPreferences.getInstance();
    storage.imageGenSettings.initializeBase(prefs, storage.notifyListeners);
    storage.imageGenSettings.load();
    await storage.imageGenSettings.setImageGenBackend('comfyui');
    await storage.imageGenSettings.setComfyCreateWorkflowId('z_image_turbo');
    await storage.imageGenSettings.setComfyCreateModelChoice(
      'z_image_turbo',
      '%MODEL_DIFFUSION%',
      'z_image_turbo_bf16.safetensors',
    );
    final gen = ImageGenService(storage);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ImageGenService>.value(value: gen),
        ],
        child: const MaterialApp(
          home: ImageStudio(
            mode: ImageGenMode.customPrompt,
            characterName: 'Ada',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Change graph hides premades that cannot load the model', (
    tester,
  ) async {
    await pumpDesk(tester);
    await tester.ensureVisible(find.text('Change graph'));
    await tester.tap(find.text('Change graph'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Change graph — Create'), findsOneWidget);
    expect(find.text('Z-Image Turbo'), findsOneWidget);
    expect(find.text('Text to image · z_image_turbo'), findsOneWidget);
    expect(find.text('Flux / Schnell / Krea'), findsNothing);
    expect(find.text('Qwen-Image'), findsNothing);
    expect(find.text('Qwen-Image 2.1'), findsNothing);
    expect(find.text('SD / SDXL / Pony / Illustrious'), findsNothing);
    expect(find.text('Text to image · flux'), findsNothing);
    expect(find.text('Text to image · qwen_image'), findsNothing);
    expect(find.text('Text to image · sd'), findsNothing);
  });
}
