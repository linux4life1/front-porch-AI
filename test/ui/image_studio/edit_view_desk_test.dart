// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Edit tab on the desk: it shows progress while it runs, keeps the
// "how much should change" control where an edit can use it, and tells the
// person what is missing instead of doing nothing.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/image_studio/edit_view.dart';
import 'package:front_porch_ai/ui/image_studio/studio_edit_pane.dart';

void main() {
  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('edit-desk');
    addTearDown(() => dir.deleteSync(recursive: true));
    storage = StorageService.sandbox(dir.path);
    final prefs = await SharedPreferences.getInstance();
    storage.imageGenSettings.initializeBase(prefs, storage.notifyListeners);
    storage.imageGenSettings.load();
  });

  Future<void> pump(WidgetTester tester, Widget body) async {
    await tester.binding.setSurfaceSize(const Size(900, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<ImageGenService>(
            create: (_) => ImageGenService(storage),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: body)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('a running edit shows progress on the stove', (tester) async {
    await storage.imageGenSettings.setImageGenBackend('a1111');
    await storage.imageGenSettings.setImageGenEditModel('edit.safetensors');
    await pump(tester, const StudioEditPane(busy: true));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('an idle edit shows none', (tester) async {
    await storage.imageGenSettings.setImageGenBackend('a1111');
    await storage.imageGenSettings.setImageGenEditModel('edit.safetensors');
    await pump(tester, const StudioEditPane());
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  group('how much should change', () {
    testWidgets('is offered where the backend uses it', (tester) async {
      await storage.imageGenSettings.setImageGenBackend('a1111');
      await storage.imageGenSettings.setImageGenEditModel('edit.safetensors');
      await pump(tester, const EditView());
      expect(find.text('How much should change?'), findsOneWidget);
      expect(find.byType(Slider), findsWidgets);
    });

    testWidgets('is left out for a Remote API, which ignores it', (
      tester,
    ) async {
      await storage.imageGenSettings.setImageGenBackend('remote');
      await storage.imageGenSettings.setImageGenEditModel('vendor/flux');
      await pump(tester, const EditView());
      expect(find.text('How much should change?'), findsNothing);
    });
  });

  testWidgets('Generate with no photo says what to add', (tester) async {
    await storage.imageGenSettings.setImageGenBackend('a1111');
    await storage.imageGenSettings.setImageGenEditModel('edit.safetensors');
    await pump(tester, const EditView());
    await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
    await tester.pump();
    expect(find.text('Add a photo to edit first.'), findsOneWidget);
  });
}
