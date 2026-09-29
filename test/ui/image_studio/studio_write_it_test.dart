// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Write it for me" is the LLM prompt writer, not a button that does nothing:
// with no language model ready it says so, exactly as it did before the desk.
// The Edit tab, which has no writer, does not show the button at all.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/ui/image_studio/image_studio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        return Directory.systemTemp.createTempSync('fpai_write_').path;
      });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpStudio(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1040, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('write-it');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = StorageService.sandbox(dir.path);
    final prefs = await SharedPreferences.getInstance();
    storage.imageGenSettings.initializeBase(prefs, storage.notifyListeners);
    storage.imageGenSettings.load();
    await storage.imageGenSettings.setImageGenBackend('a1111');
    final llm = LLMProvider(
      KoboldService(storage),
      OpenRouterService(),
      storage,
      BackendManager(storage),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ImageGenService>(
            create: (_) => ImageGenService(storage),
          ),
          ChangeNotifierProvider<LLMProvider>.value(value: llm),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: ImageStudio(
              mode: ImageGenMode.characterPortrait,
              characterName: 'Ada',
              characterDbId: 'ada-id',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Write it for me answers, and the box is left as it was', (
    tester,
  ) async {
    await pumpStudio(tester);

    final button = find.widgetWithText(TextButton, 'Write it for me');
    expect(button, findsOneWidget);
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);

    await tester.enterText(find.byType(TextField).first, 'a quiet porch');
    await tester.tap(button);
    await tester.pump();

    expect(
      find.text('LLM not ready for smart crafting (using static quality)'),
      findsOneWidget,
    );
    expect(find.text('a quiet porch'), findsOneWidget);
  });

  testWidgets('the Edit tab has no prompt writer and no dead button', (
    tester,
  ) async {
    await pumpStudio(tester);
    await tester.tap(find.text('change this portrait'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('Portrait in this chat'), findsOneWidget);
    // The Create desk is behind the Edit tab, and the Edit desk has neither.
    expect(find.text('Write it for me'), findsNothing);
    expect(find.text('Expression pack'), findsNothing);
  });
}
