// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What the image settings surface has to do, asked of the desk: the backend
// can be chosen and is saved, a local server's status and files are shown and
// its LoRAs can be put in a slot (Automatic1111 included), the ComfyUI address
// can be changed, the size is chosen and saved, and a remote host says whose
// account it bills (or that there is no key). The settings dialog is the desk.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/image/image_studio_remote.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/dialogs/image_gen_settings_dialog.dart';
import 'package:front_porch_ai/ui/image_studio/studio_desk.dart';
import 'package:front_porch_ai/ui/image_studio/studio_desk_knobs.dart';

/// A reachable Automatic1111: two checkpoints, two LoRAs. Nothing is dialled.
class _ReachableA1111 extends ImageGenService {
  _ReachableA1111(super.storage, {this.up = true});

  /// Whether the server answers.
  final bool up;
  final List<String> asked = [];

  @override
  Future<bool> testLocalConnection(String baseUrl) async {
    asked.add('connect $baseUrl');
    return up;
  }

  @override
  Future<List<String>> fetchA1111Models(String baseUrl) async => const [
    'portrait.safetensors',
    'scene.safetensors',
  ];

  @override
  Future<List<LoraOption>> fetchA1111Loras(String baseUrl) async => const [
    LoraOption('lora1.safetensors', ModelFamily.sd15),
    LoraOption('lora2.safetensors', ModelFamily.sd15),
  ];

  @override
  Future<List<String>> fetchA1111Samplers(String baseUrl) async => const [
    'Euler a',
  ];

  @override
  Future<List<String>> fetchA1111Schedulers(String baseUrl) async => const [
    'Automatic',
  ];
}

void main() {
  late StorageService storage;

  setUp(() {
    final dir = Directory.systemTemp.createTempSync('desk-settings');
    addTearDown(() => dir.deleteSync(recursive: true));
    storage = StorageService.sandbox(dir.path);
  });

  Future<void> pump(
    WidgetTester tester,
    Widget body, {
    ImageGenService? service,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<ImageGenService>.value(
              value: service ?? ImageGenService(storage),
            ),
          ],
          child: Scaffold(body: SingleChildScrollView(child: body)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the backend', () {
    testWidgets('is chosen from the desk and saved', (tester) async {
      await storage.imageGenSettings.setImageGenBackend('comfyui');
      await pump(tester, const StudioDesk());

      await tester.tap(find.text('Change…'));
      await tester.pumpAndSettle();
      expect(find.text('Remote'), findsOneWidget);
      expect(find.text('ComfyUI'), findsWidgets);
      expect(find.text('Automatic1111'), findsOneWidget);

      await tester.tap(find.text('Automatic1111'));
      await tester.pumpAndSettle();
      expect(storage.imageGenSettings.imageGenBackend, 'a1111');

      await tester.tap(find.text('Change…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remote'));
      await tester.pumpAndSettle();
      expect(storage.imageGenSettings.imageGenBackend, 'remote');
    });
  });

  group('Automatic1111', () {
    setUp(() async {
      await storage.imageGenSettings.setImageGenBackend('a1111');
    });

    testWidgets('says what its server has when it is checked', (tester) async {
      final service = _ReachableA1111(storage);
      await pump(tester, const StudioDesk(), service: service);

      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();

      expect(
        find.text('Reachable · 0 diffusion files · 2 LoRAs'),
        findsOneWidget,
      );
      expect(
        service.asked,
        contains(
          startsWith('connect ${storage.imageGenSettings.localImageGenUrl}'),
        ),
      );
    });

    testWidgets('lists its LoRAs and a picked one is saved in the slot', (
      tester,
    ) async {
      await pump(tester, const StudioDesk(), service: _ReachableA1111(storage));
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('lora1.safetensors'), findsWidgets);
      expect(find.text('lora2.safetensors'), findsWidgets);

      await tester.tap(find.text('lora1.safetensors').first);
      await tester.pumpAndSettle();

      expect(
        storage.imageGenSettings.imageGenLoraSlots.first.file,
        'lora1.safetensors',
      );
    });

    testWidgets('a server that does not answer is shown as not running', (
      tester,
    ) async {
      await pump(
        tester,
        const StudioDesk(),
        service: _ReachableA1111(storage, up: false),
      );
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
      expect(find.text('Not running'), findsOneWidget);
      expect(find.textContaining('Reachable'), findsNothing);
    });
  });

  group('ComfyUI', () {
    testWidgets('shows its address, and the address can be changed', (
      tester,
    ) async {
      await storage.imageGenSettings.setImageGenBackend('comfyui');
      await pump(tester, const StudioDesk());

      // The address is a visible field now, not a tap that opens a dialog.
      final address = find.widgetWithText(TextField, 'ComfyUI address');
      expect(find.text(storage.imageGenSettings.comfyUiUrl), findsOneWidget);
      await tester.enterText(address, 'http://10.0.0.5:8188');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(storage.imageGenSettings.comfyUiUrl, 'http://10.0.0.5:8188');
    });
  });

  group('the size', () {
    testWidgets('is chosen from the chips and saved', (tester) async {
      await storage.imageGenSettings.setImageGenBackend('comfyui');
      await pump(tester, const StudioDesk());

      await tester.tap(find.text('768×768'));
      await tester.pumpAndSettle();
      expect(storage.imageGenSettings.imageGenSize, '768x768');

      await tester.tap(find.text('1536×1024'));
      await tester.pumpAndSettle();
      expect(storage.imageGenSettings.imageGenSize, '1536x1024');
    });
  });

  group('a remote host', () {
    testWidgets('with no key says there is none and nothing is free', (
      tester,
    ) async {
      await storage.imageGenSettings.setImageGenBackend('remote');
      await pump(tester, const StudioDesk());

      expect(
        find.textContaining('No Remote API key configured'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Bills your Remote API account'),
        findsNothing,
      );
    });

    testWidgets('with a key names the account it bills', (tester) async {
      await storage.backendSettings.setRemoteApiUrl(
        'https://nano-gpt.com/api/v1',
      );
      await storage.backendSettings.setRemoteApiKey('nk-test');
      await storage.imageGenSettings.setImageGenBackend('remote');
      await pump(tester, const StudioDesk());

      expect(
        find.textContaining('Bills your Remote API account (nano-gpt.com)'),
        findsOneWidget,
      );
      expect(find.textContaining('No Remote API key configured'), findsNothing);
    });
  });

  group('the settings dialog', () {
    testWidgets('is the desk, without its own Generate', (tester) async {
      await storage.imageGenSettings.setImageGenBackend('comfyui');
      await pump(tester, const ImageGenSettingsDialog());

      expect(find.byType(StudioDesk), findsOneWidget);
      expect(
        tester.widget<StudioDesk>(find.byType(StudioDesk)).showGenerate,
        isFalse,
      );
      expect(find.text('Generate'), findsNothing);
    });

    testWidgets('has one Style and one Prompt format, and they save', (
      tester,
    ) async {
      final s = storage.imageGenSettings;
      final host = kImageStudioRemoteHosts.first.url;
      await s.setImageGenBackend('remote');
      await s.setImageRemoteApiUrl(host);
      await storage.backendSettings.setRemoteApiKeyFor(host, 'test-key');
      await s.setImageGenStyle('photorealistic');
      await s.setImageGenPromptParadigm('natural');
      await pump(tester, const ImageGenSettingsDialog());

      await tester.ensureVisible(find.textContaining('Advanced'));
      await tester.tap(find.textContaining('Advanced'));
      await tester.pumpAndSettle();
      expect(find.text('Style'), findsOneWidget);
      expect(find.text('Prompt format'), findsOneWidget);

      await tester.ensureVisible(find.text('Style'));
      await tester.tap(find.text('Photorealistic'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Watercolor').last);
      await tester.pumpAndSettle();
      expect(s.imageGenStyle, 'watercolor');

      await tester.ensureVisible(find.text('Prompt format'));
      await tester.tap(find.text('Natural language (FLUX / SD3)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Danbooru tags (SD 1.5 / anime)').last);
      await tester.pumpAndSettle();
      expect(s.imageGenPromptParadigm, 'tags');
    });
  });

  group('Style and Prompt format', () {
    const hint = 'Style and Prompt format are in Create mode.';

    Future<void> knobs(WidgetTester tester, {required bool edit}) async {
      final s = storage.imageGenSettings;
      await s.setImageGenBackend('comfyui');
      await pump(tester, StudioDeskKnobs(settings: s, edit: edit));
    }

    testWidgets('are on the desk in Create mode, with no hint', (tester) async {
      await knobs(tester, edit: false);
      expect(find.text('Style'), findsOneWidget);
      expect(find.text('Prompt format'), findsOneWidget);
      expect(find.text(hint), findsNothing);
    });

    testWidgets('are not in Edit mode, which says where they are', (
      tester,
    ) async {
      await knobs(tester, edit: true);
      expect(find.text('Style'), findsNothing);
      expect(find.text(hint), findsOneWidget);
    });
  });
}
