// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// TTS Settings → Default Voice showed the file name "en_US-amy-medium"
// while the Voice Model Browser called the same voice "amy, English
// (United States), medium". The list now uses the browser's words, read
// from the catalog copy the browser keeps on disk (no network call).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/tts_settings_dialog.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';
import 'piper_catalog_fixture.dart';

void main() {
  late Directory docs;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('fpai_voice_label_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => docs.path,
        );
  });
  tearDown(() {
    try {
      docs.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('Default Voice names an installed voice the way the voice '
      'browser does, and keeps a custom voice\'s own name', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final storage = FakeStorageService();
    final tts = FakeTtsService();
    final voices = VoiceManager(storage);
    addTearDown(() {
      storage.dispose();
      tts.dispose();
      voices.dispose();
    });
    await tester.runAsync(() async {
      await storage.ttsSettings.setTtsEngine('piper');
      await storage.ttsSettings.setTtsVoiceModel('en_US-amy-medium');
      await seedPiperVoices(
        storage.rootPath ?? docs.path,
        installed: ['en_US-amy-medium', 'my_porch_voice'],
      );
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<TtsService>.value(value: tts),
          ChangeNotifierProvider<VoiceManager>.value(value: voices),
        ],
        child: const MaterialApp(home: Material(child: TtsSettingsDialog())),
      ),
    );
    final friendly = find.text('amy, English (United States), medium');
    for (var i = 0; i < 500 && friendly.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(friendly, findsOneWidget, reason: 'the chosen voice, shown');
    expect(find.text('en_US-amy-medium'), findsNothing);

    await tester.tap(friendly);
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('my_porch_voice'),
      findsWidgets,
      reason: 'a custom import has no catalog entry, so its own name stays',
    );
  });
}
