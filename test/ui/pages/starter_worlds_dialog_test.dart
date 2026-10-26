// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Worlds page's Starter worlds picker: it opens from the page header,
// lists the bundled worlds, a fast double click on Add imports exactly
// once, and the list scrolls without overflow in a small window. Real
// repository on an in-memory database; the header glow repeats, so only
// bounded pumps here, never pumpAndSettle.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/world_management_page.dart';
import 'package:front_porch_ai/ui/pages/worlds/worlds.dart';

import '../../helpers/double_tap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late AppDatabase db;
  late Directory tempRoot;
  late WorldRepository repo;

  setUp(() async {
    tempRoot = Directory.systemTemp.createTempSync('fpai_starter_dialog_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return tempRoot.path;
          }
          return null;
        });
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(sameIsolate: true);
    final storage = StorageService();
    await storage.setRootPath(tempRoot.path);
    repo = WorldRepository(storage, db);
    await repo.loadWorlds();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    repo.dispose();
    await db.close();
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  void window(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Let the asset read and the database writes finish, then draw, until
  /// [done] shows (bounded: a hang fails on the expectation after it).
  Future<void> settleUntil(WidgetTester tester, Finder done) async {
    for (var i = 0; i < 100 && done.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  final rows = find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('starter-row-'),
  );

  testWidgets('opens from the Worlds header, lists seven, and a double '
      'click on Add imports Harborside once', (tester) async {
    window(tester, const Size(1280, 900));
    await tester.pumpWidget(
      ChangeNotifierProvider<WorldRepository>.value(
        value: repo,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
          home: const WorldManagementPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const Key('worlds-starter')));
    await settleUntil(tester, rows);
    expect(find.text('Starter worlds'), findsWidgets);
    expect(rows, findsNWidgets(7));
    expect(find.text('Harborside'), findsOneWidget);

    final add = find.byKey(const Key('starter-add-harborside'));
    await tester.ensureVisible(add);
    await tester.pump();
    await doubleTapNoFrame(tester, add);
    await settleUntil(tester, find.text('Added as "Harborside".'));

    final roots = repo.placeWorlds
        .where((w) => w.sourceId == StarterWorlds.sourceIdFor('harborside'))
        .toList();
    expect(roots, hasLength(1), reason: 'one click, one import');
    expect(
      repo.placeWorlds.where((w) => w.parentWorldId == roots.single.id),
      hasLength(3),
    );
    expect(find.text('Added as "Harborside".'), findsOneWidget);
    expect(find.text('Add again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the list scrolls in a 400 x 600 window without overflow', (
    tester,
  ) async {
    window(tester, const Size(400, 600));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showStarterWorldsDialog(context, repo),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settleUntil(tester, rows);
    expect(rows, findsNWidgets(7));
    expect(tester.takeException(), isNull);

    final list = find.byKey(const Key('starter-worlds-list'));
    final dialog = tester.getRect(find.byType(AlertDialog));
    expect(dialog.bottom, lessThanOrEqualTo(600));
    expect(dialog.right, lessThanOrEqualTo(400));
    // The last row starts below the fold and is reachable by scrolling.
    final last = find.byKey(const Key('starter-add-greenhollow'));
    expect(tester.getRect(last).top, greaterThan(tester.getRect(list).bottom));
    await tester.drag(list, const Offset(0, -3000));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getRect(last).bottom, lessThanOrEqualTo(dialog.bottom));
    expect(find.text('Close'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
