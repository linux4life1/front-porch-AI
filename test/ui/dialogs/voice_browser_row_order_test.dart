// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Voice Model Browser: installing or deleting a voice used to re-sort the
// list at once (installed voices first), so the row under the pointer
// became a different voice's button. Rows now keep the order they had when
// the browser opened.
//
// The catalog comes from the on-disk copy the browser keeps: flutter_test
// lets no real request out, so the fetch falls back to it exactly as it
// does when the voice host is down.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/voice_browser_dialog.dart';

import 'piper_catalog_fixture.dart';

void main() {
  late Directory docs;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('fpai_voice_order_');
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

  /// Y of each voice's row, top to bottom.
  List<String> rowOrder(WidgetTester tester) {
    final names = ['alba', 'amy', 'ryan', 'thorsten'];
    names.sort(
      (a, b) => tester
          .getTopLeft(find.text(a))
          .dy
          .compareTo(tester.getTopLeft(find.text(b)).dy),
    );
    return names;
  }

  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 500 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('deleting a voice leaves every row where it was', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    // The 120 px Quality filter's selected item (a 64 px row inside the
    // dropdown) overflows to the right around "medium" in the test font.
    // That layout is not what this test is about, so only that one report
    // is set aside; any other overflow or error still fails the test.
    final reportError = FlutterError.onError;
    bool isQualityFilterOverflow(FlutterErrorDetails d) {
      final text = d.toString();
      return d.exceptionAsString().contains('RenderFlex overflowed by') &&
          d.exceptionAsString().contains('on the right') &&
          text.contains('DropdownButtonFormField<String>') &&
          text.contains('voice_browser_dialog.dart') &&
          text.contains('constraints: BoxConstraints(w=64.0');
    }

    FlutterError.onError = (details) {
      if (isQualityFilterOverflow(details)) return;
      reportError?.call(details);
    };
    addTearDown(() => FlutterError.onError = reportError);

    final voices = (await tester.runAsync(() async {
      final storage = StorageService();
      await storage.initialized;
      final vm = VoiceManager(storage);
      await seedPiperVoices(
        storage.rootPath ?? docs.path,
        installed: ['en_US-ryan-high'],
      );
      await vm.fetchCatalog();
      return vm;
    }))!;
    expect(voices.catalog, hasLength(4), reason: 'the on-disk catalog loads');

    await tester.pumpWidget(
      ChangeNotifierProvider<VoiceManager>.value(
        value: voices,
        child: const MaterialApp(home: Scaffold(body: VoiceBrowserDialog())),
      ),
    );
    final deleteRyan = find.byTooltip('Delete');
    await pumpUntil(tester, () => deleteRyan.evaluate().isNotEmpty);

    final before = rowOrder(tester);
    expect(before, ['ryan', 'alba', 'amy', 'thorsten']);

    await tester.tap(deleteRyan);
    await pumpUntil(tester, () => find.byTooltip('Delete').evaluate().isEmpty);
    expect(find.byTooltip('Delete'), findsNothing, reason: 'ryan was deleted');

    expect(rowOrder(tester), before);
    FlutterError.onError = reportError;
  });
}
