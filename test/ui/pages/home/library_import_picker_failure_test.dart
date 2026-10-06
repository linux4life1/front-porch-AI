// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// The library's Import Cards, Import BYAF and Import Folder buttons call these
// pick steps without awaiting them. Before this, a file window that failed
// (Windows' hung dialog after an upgrade, issue #255) threw past the button
// and the click did nothing. HomePage itself reads ten providers, so the host
// here calls the same functions the buttons call, the same unawaited way.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/ui/pages/home/library_import_picks.dart';
import 'package:front_porch_ai/utils/utils.dart';

void main() {
  late Map<String, Object?> results;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    results = {};
  });

  tearDown(() {
    PickerPrefs.testNativePicker = null;
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () async =>
                      results['cards'] = await pickLibraryCards(context),
                  child: const Text('Import Cards'),
                ),
                TextButton(
                  onPressed: () async =>
                      results['byaf'] = await pickLibraryByafFiles(context),
                  child: const Text('Import BYAF'),
                ),
                TextButton(
                  onPressed: () async =>
                      results['folder'] = await pickLibraryFolder(context),
                  child: const Text('Import Folder'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Lets real directory I/O finish, then pumps until [finder] shows.
  /// Event-gated: returns as soon as it appears. The 10 s ceiling is for a
  /// loaded CI runner, not for a fast machine.
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 500 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Import Cards: a file window that fails says so, and Try again reopens it',
    (tester) async {
      var calls = 0;
      PickerPrefs.testNativePicker =
          ({required String op, required String? initialDirectory}) async {
            calls++;
            expect(op, 'pickFiles');
            if (calls == 1) throw const PickerDialogTimeout();
            return null;
          };
      await pumpHost(tester);

      await tester.tap(find.text('Import Cards'));
      await tester.pumpAndSettle();

      expect(find.textContaining("didn't open"), findsOneWidget);
      expect(find.textContaining('drag'), findsOneWidget);
      expect(calls, 1);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(calls, 2, reason: 'Try again opens the file window again');
      expect(find.textContaining("didn't open"), findsNothing);
      expect(results.containsKey('cards'), isTrue);
      expect(results['cards'], isNull);
    },
  );

  testWidgets('Import BYAF: a file window that fails says so', (tester) async {
    var calls = 0;
    PickerPrefs.testNativePicker =
        ({required String op, required String? initialDirectory}) async {
          calls++;
          expect(op, 'pickFiles');
          throw StateError('no file window on this computer');
        };
    await pumpHost(tester);

    await tester.tap(find.text('Import BYAF'));
    await tester.pumpAndSettle();

    expect(find.textContaining("didn't open"), findsOneWidget);
    expect(find.textContaining('.byaf'), findsWidgets);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.textContaining("didn't open"), findsNothing);
    expect(calls, 1, reason: 'Close does not reopen the window');
    expect(results.containsKey('byaf'), isTrue);
    expect(results['byaf'], isNull);
  });

  testWidgets('Import Folder: a folder window that fails says so', (
    tester,
  ) async {
    PickerPrefs.testNativePicker =
        ({required String op, required String? initialDirectory}) async {
          expect(op, 'getDirectoryPath');
          throw const PickerDialogTimeout();
        };
    await pumpHost(tester);

    await tester.tap(find.text('Import Folder'));
    await tester.pumpAndSettle();

    expect(find.textContaining("didn't open"), findsOneWidget);
    expect(find.textContaining('drag'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(results.containsKey('folder'), isTrue);
    expect(results['folder'], isNull);
  });

  testWidgets('Import Folder: a folder that cannot be read says so', (
    tester,
  ) async {
    final gone = p.join(
      Directory.systemTemp.path,
      'fpai_gone_${DateTime.now().microsecondsSinceEpoch}',
    );
    var calls = 0;
    PickerPrefs.testNativePicker =
        ({required String op, required String? initialDirectory}) async {
          calls++;
          expect(op, 'getDirectoryPath');
          // First pick: a folder that no longer exists. After "Pick another
          // folder", the user cancels.
          return calls == 1 ? gone : null;
        };
    await pumpHost(tester);

    await tester.tap(find.text('Import Folder'));
    await waitFor(tester, find.textContaining('look inside'));

    expect(find.textContaining('look inside'), findsOneWidget);

    await tester.tap(find.text('Pick another folder'));
    await tester.pumpAndSettle();

    expect(calls, 2, reason: 'Pick another folder opens the folder window');
    expect(find.textContaining('look inside'), findsNothing);
    expect(results.containsKey('folder'), isTrue);
    expect(results['folder'], isNull);
  });

  testWidgets('Import Folder: a readable folder lists its cards and archives', (
    tester,
  ) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('fpai_folder_scan_'),
    ))!;
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.runAsync(() async {
      await File(p.join(dir.path, 'a.png')).writeAsBytes(const [1]);
      await File(p.join(dir.path, 'b.byaf')).writeAsBytes(const [1]);
      await File(p.join(dir.path, 'notes.txt')).writeAsBytes(const [1]);
      final sub = await Directory(p.join(dir.path, 'sub')).create();
      await File(p.join(sub.path, 'c.PNG')).writeAsBytes(const [1]);
    });
    PickerPrefs.testNativePicker =
        ({required String op, required String? initialDirectory}) async =>
            dir.path;
    await pumpHost(tester);

    await tester.tap(find.text('Import Folder'));
    for (var i = 0; i < 500 && !results.containsKey('folder'); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    final found = results['folder'] as LibraryFolderFiles?;
    expect(found, isNotNull);
    expect(found!.pngs.map((f) => p.basename(f.path)).toSet(), {
      'a.png',
      'c.PNG',
    });
    expect(found.byafs.map((f) => p.basename(f.path)).toList(), ['b.byaf']);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
