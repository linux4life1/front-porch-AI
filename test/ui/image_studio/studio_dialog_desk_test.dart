// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/image_gen_types.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/services/image/studio_desk_logic.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/image_studio/image_studio.dart';
import 'package:front_porch_ai/ui/image_studio/studio_desk_copy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        return Directory.systemTemp.createTempSync('fpai_desk_').path;
      });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<StorageService> pumpDesk(
    WidgetTester tester,
    Size size, {
    Future<void> Function(StorageService storage)? prepare,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('desk-dialog');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final storage = StorageService.sandbox(dir.path);
    final prefs = await SharedPreferences.getInstance();
    storage.imageGenSettings.initializeBase(prefs, storage.notifyListeners);
    storage.imageGenSettings.load();
    if (prepare != null) await prepare(storage);
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
    return storage;
  }

  Future<void> show(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  String fieldText(WidgetTester tester, Key key) {
    return tester.widget<TextField>(find.byKey(key)).controller!.text;
  }

  testWidgets('wide dialog is the two-column desk', (tester) async {
    await pumpDesk(
      tester,
      const Size(1040, 1600),
      prepare: (storage) async {
        await storage.imageGenSettings.setImageGenBackend('a1111');
        await storage.imageGenSettings.setImageGenModel(
          'z_image_turbo_bf16.safetensors',
        );
        await storage.imageGenSettings.setComfyCreateWorkflowId(
          'z_image_turbo',
        );
      },
    );

    expect(find.byKey(const Key('studio-desk-wide')), findsOneWidget);
    expect(find.byKey(const Key('studio-desk-narrow')), findsNothing);
    expect(find.text('Freeform'), findsOneWidget);
    expect(find.text('Character'), findsOneWidget);
    expect(find.text('Your persona'), findsOneWidget);
    expect(find.text('Write it for me'), findsOneWidget);
    expect(find.text(kStudioCreateWell), findsOneWidget);
    expect(find.text('Expression pack'), findsWidgets);
    expect(
      find.text('Pack uses this Create model to vary the portrait.'),
      findsOneWidget,
    );
    expect(find.text('make a new portrait'), findsOneWidget);
    expect(find.text('change this portrait'), findsOneWidget);
    expect(find.text('Connection'), findsOneWidget);
    expect(find.text('Change…'), findsOneWidget);
    expect(find.text('Change graph'), findsNothing);
    expect(find.text('Change model'), findsOneWidget);
    expect(find.text('Get a model from CivitAI'), findsOneWidget);
    expect(find.text('Get a LoRA from CivitAI'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('This graph also loads'), findsOneWidget);
    expect(find.text(kStudioLoraFamilyNote), findsOneWidget);
    expect(
      find.text('Workflow · Text to image · z_image_turbo'),
      findsOneWidget,
    );
    expect(find.text('Model search'), findsNothing);
    expect(find.text('Graph search'), findsNothing);
    expect(find.text('Graph upload'), findsNothing);
    expect(find.text('LoRA search'), findsNothing);
    expect(find.text('CivitAI sign-in'), findsNothing);

    await show(tester, find.textContaining('Advanced ▸'));
    expect(find.text('Steps'), findsNothing);
    expect(find.text('Seed'), findsNothing);
    await tester.tap(find.textContaining('Advanced ▸'));
    await tester.pump();
    expect(find.textContaining('Advanced ▾'), findsOneWidget);
    expect(find.text('Change graph'), findsOneWidget);
    expect(find.textContaining('Advanced ▸'), findsNothing);
    expect(find.text('Steps'), findsOneWidget);
    expect(find.text('CFG'), findsOneWidget);
    expect(find.text('Sampler'), findsOneWidget);
    expect(find.text('Scheduler'), findsOneWidget);
    expect(find.text('Seed'), findsNothing);
    expect(find.text('Negative prompt'), findsNothing);

    await show(tester, find.text('512×512'));
    expect(find.text('768×768'), findsOneWidget);
    expect(find.text('1024×1024'), findsOneWidget);
    expect(find.text('1536×1024'), findsOneWidget);
    expect(find.text('1024×1536'), findsOneWidget);
    await tester.tap(find.text('512×512'));
    await tester.pump();
    expect(
      find.text(
        'Sends 512×512. Each side snaps to a multiple of 64, from 256 to 2048.',
      ),
      findsOneWidget,
    );
    expect(fieldText(tester, const Key('studio-width')), '512');
    expect(fieldText(tester, const Key('studio-height')), '512');

    await tester.enterText(find.byKey(const Key('studio-width')), '300');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(
      find.text(
        'Sends 320×512. Each side snaps to a multiple of 64, from 256 to 2048.',
      ),
      findsOneWidget,
    );
    expect(fieldText(tester, const Key('studio-width')), '320');
    expect(fieldText(tester, const Key('studio-height')), '512');

    await show(tester, find.text('Change graph'));
    await tester.tap(find.text('Change graph'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Change graph — Create'), findsOneWidget);
    expect(find.text(kStudioDropCopy), findsOneWidget);
    expect(find.text('JSON, or a PNG from Comfy’s Save.'), findsOneWidget);
    expect(find.text('Z-Image Turbo'), findsOneWidget);
    expect(find.text('Text to image graphs'), findsOneWidget);
    expect(find.text('Choose file'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Generate'), findsOneWidget);

    await tester.tap(find.text('Close').last);
    await tester.pump();
    await show(tester, find.text('Change model'));
    await tester.tap(find.text('Change model'));
    await tester.pump();
    expect(find.text('Change model — Create'), findsOneWidget);
    expect(find.text('Search families or files'), findsOneWidget);
    await tester.tap(find.text('Close').last);
    await tester.pump();
    await show(tester, find.text('Get a model from CivitAI'));
    await tester.tap(find.text('Get a model from CivitAI'));
    await tester.pump();
    expect(find.text('On this computer'), findsOneWidget);
    expect(find.text('CivitAI'), findsWidgets);
    expect(find.text('Include adult models from civitai.red'), findsOneWidget);
    expect(find.text('API key'), findsOneWidget);
    expect(find.text('CivitAI sign-in'), findsNothing);
    await tester.tap(find.text('Close').last);
    await tester.pump();
    await show(tester, find.text('change this portrait'));
    await tester.tap(find.text('change this portrait'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Portrait in this chat'), findsOneWidget);
    expect(
      find.textContaining('Edit sends an instruction with this picture.'),
      findsOneWidget,
    );
    expect(find.text('Pack uses this edit model.'), findsOneWidget);
  });

  testWidgets('a GGUF model leaves the checkpoint graph', (tester) async {
    await pumpDesk(
      tester,
      const Size(1040, 1600),
      prepare: (storage) async {
        await storage.imageGenSettings.setImageGenBackend('comfyui');
        await storage.imageGenSettings.setComfyCreateWorkflowId('sd');
      },
    );
    expect(find.text('Change graph'), findsNothing);
    await show(tester, find.text('Change model'));
    await tester.tap(find.text('Change model'));
    await tester.pump();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Search families or files',
      ),
      'z_image_turbo_q8.gguf',
    );
    await tester.pump();
    await tester.tap(find.text('Use this name'));
    await tester.pump();
    expect(
      find.text('Workflow · GGUF · chosen for this file · z_image_turbo'),
      findsOneWidget,
    );
  });

  testWidgets('narrow dialog stacks the same desk', (tester) async {
    await pumpDesk(tester, const Size(390, 1400));
    expect(find.byKey(const Key('studio-desk-narrow')), findsOneWidget);
    expect(find.byKey(const Key('studio-desk-wide')), findsNothing);
    expect(find.text('Write it for me'), findsOneWidget);
    expect(find.text(kStudioCheckpointSupport), findsOneWidget);
    expect(find.text('Generate'), findsOneWidget);
    expect(find.textContaining('Advanced ▸'), findsOneWidget);
  });

  testWidgets('metadata clash keeps Generate off until Use anyway', (
    tester,
  ) async {
    await pumpDesk(
      tester,
      const Size(1040, 1600),
      prepare: (storage) async {
        await storage.imageGenSettings.setImageGenBackend('a1111');
        await storage.imageGenSettings.setImageGenModel(
          'z_image_turbo_bf16.safetensors',
        );
        await storage.imageGenSettings.setImageGenLoraSlot(
          0,
          file: 'qwen_image_lora.safetensors',
        );
        await saveLoraFacts(storage.imageGenSettings, [
          DeskLoraCheck(
            'qwen_image_lora.safetensors',
            ModelFamily.qwen,
            metadataBacked: true,
          ),
        ]);
      },
    );

    expect(find.text('other base'), findsOneWidget);
    expect(
      find.textContaining(
        'Generate stays off until you pick a matching LoRA or press Use anyway.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Not ready — LoRA architecture does not match z_image_turbo_bf16.safetensors.',
      ),
      findsOneWidget,
    );
    final blocked = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Generate'),
    );
    expect(blocked.onPressed, isNull);

    await show(tester, find.text('Use anyway'));
    await tester.tap(find.text('Use anyway'));
    await tester.pump();
    final open = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Generate'),
    );
    expect(open.onPressed, isNotNull);
  });

  testWidgets('a name-only mismatch stays likely and can generate', (
    tester,
  ) async {
    await pumpDesk(
      tester,
      const Size(1040, 1600),
      prepare: (storage) async {
        await storage.imageGenSettings.setImageGenBackend('a1111');
        await storage.imageGenSettings.setImageGenModel(
          'z_image_turbo_bf16.safetensors',
        );
        await storage.imageGenSettings.setImageGenLoraSlot(
          0,
          file: 'qwen_image_lora.safetensors',
        );
      },
    );

    expect(find.text('likely'), findsOneWidget);
    expect(find.text('other base'), findsNothing);
    expect(find.text('Use anyway'), findsNothing);
    expect(find.text('Ready to generate.'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Generate'),
    );
    expect(button.onPressed, isNotNull);
  });
}
