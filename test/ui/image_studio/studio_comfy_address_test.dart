// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The ComfyUI address on the stove: what is typed is checked and saved on
// submit or when the field is left, never per keystroke, and a bad address
// is refused with a reason.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/ui/image_studio/studio_comfy_address.dart';
import 'package:front_porch_ai/ui/image_studio/studio_desk.dart';

void main() {
  late List<String> saved;
  late List<String> tested;

  Future<void> pump(
    WidgetTester tester, {
    String url = 'http://127.0.0.1:8188',
    bool explicit = true,
    String? offer,
    bool up = true,
  }) async {
    saved = [];
    tested = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              StudioComfyAddress(
                url: url,
                explicit: explicit,
                offer: offer,
                onSave: (value) async => saved.add(value),
                answers: (value) async {
                  tested.add(value);
                  return up;
                },
              ),
              const TextField(key: Key('elsewhere')),
            ],
          ),
        ),
      ),
    );
  }

  Finder field() => find.widgetWithText(TextField, 'ComfyUI address');

  testWidgets('a valid address is saved on submit, with a scheme, and tested', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(field(), '127.0.0.1:8000');
    expect(saved, isEmpty, reason: 'nothing is saved per keystroke');

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(saved, ['http://127.0.0.1:8000']);
    expect(tested, ['http://127.0.0.1:8000']);
    expect(
      find.text('ComfyUI answers at http://127.0.0.1:8000.'),
      findsOneWidget,
    );
  });

  testWidgets('leaving the field saves it too, and an unreachable one is saved '
      'anyway, saying so', (tester) async {
    await pump(tester, up: false);
    await tester.enterText(field(), 'localhost:8189');
    await tester.tap(find.byKey(const Key('elsewhere')));
    await tester.pumpAndSettle();

    expect(saved, ['http://localhost:8189']);
    expect(
      find.text('Nothing answers at http://localhost:8189. Saved anyway.'),
      findsOneWidget,
    );
  });

  testWidgets('a bad address is refused with a reason and not saved', (
    tester,
  ) async {
    await pump(tester);
    for (final bad in [
      '127.0.0.1:99999',
      'http://127.0.0.1:8188/api',
      'ftp://127.0.0.1',
    ]) {
      await tester.enterText(field(), bad);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.text('Use a host and port, like 127.0.0.1:8188.'),
        findsOneWidget,
        reason: bad,
      );
    }
    expect(saved, isEmpty);
    expect(tested, isEmpty);
  });

  testWidgets('clearing it turns finding ComfyUI back on', (tester) async {
    await pump(tester);
    await tester.enterText(field(), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(saved, ['']);
  });

  testWidgets(
    'an address found elsewhere is offered, and taken with Use this',
    (tester) async {
      await pump(tester, offer: 'http://127.0.0.1:8000');
      expect(
        find.text('ComfyUI answers at http://127.0.0.1:8000'),
        findsOneWidget,
      );
      await tester.tap(find.text('Use this'));
      await tester.pumpAndSettle();
      expect(saved, ['http://127.0.0.1:8000']);
    },
  );

  testWidgets('one that was found, not typed, says so', (tester) async {
    await pump(tester, explicit: false);
    expect(
      find.text('Found automatically. Type one to keep it.'),
      findsOneWidget,
    );
  });

  testWidgets('on the desk it writes the setting and marks it as given', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('comfy-address');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = StorageService.sandbox(dir.path);
    final settings = storage.imageGenSettings;
    await settings.setImageGenBackend('comfyui');
    await settings.adoptFoundComfyUiUrl('http://127.0.0.1:8188');
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: StudioDesk())),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(field(), '127.0.0.1:8000');
    expect(settings.comfyUiUrl, 'http://127.0.0.1:8188');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(settings.comfyUiUrl, 'http://127.0.0.1:8000');
    expect(settings.comfyUiUrlExplicit, isTrue);

    await tester.enterText(field(), 'not a port:x');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(settings.comfyUiUrl, 'http://127.0.0.1:8000');

    await tester.pumpWidget(const SizedBox());
  });
}
