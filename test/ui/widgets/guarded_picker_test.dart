// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// Export buttons (character cards, personas, places, chats, stories) save
// through GuardedPicker. A save that fails, in the window or while building
// the file, must say so instead of throwing past an unawaited button.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/ui/widgets/widgets.dart';
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
                      results['save'] = await GuardedPicker.saveFile(
                        context,
                        category: PickerPrefs.catExport,
                        bytes: Uint8List.fromList(const [1, 2, 3]),
                        fileName: 'chat.jsonl',
                      ),
                  child: const Text('Export chat'),
                ),
                TextButton(
                  onPressed: () async =>
                      results['built'] = await GuardedPicker.saveFromBuilder(
                        context,
                        category: PickerPrefs.catExport,
                        fileName: 'card.png',
                        writeTemp: (_) async =>
                            throw StateError('the card could not be drawn'),
                      ),
                  child: const Text('Export card'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a save window that fails says so, and Try again reopens it', (
    tester,
  ) async {
    var calls = 0;
    PickerPrefs.testNativePicker =
        ({required String op, required String? initialDirectory}) async {
          calls++;
          expect(op, 'saveFile');
          if (calls == 1) throw const PickerDialogTimeout();
          return null;
        };
    await pumpHost(tester);

    await tester.tap(find.text('Export chat'));
    await tester.pumpAndSettle();

    expect(find.textContaining("wasn't saved"), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(calls, 2, reason: 'Try again opens the save window again');
    expect(find.textContaining("wasn't saved"), findsNothing);
    expect(results.containsKey('save'), isTrue);
    expect(results['save'], isNull);
  });

  testWidgets('a file that cannot be built before saving says so', (
    tester,
  ) async {
    PickerPrefs.testNativePicker =
        ({required String op, required String? initialDirectory}) async =>
            fail('the save window must not open when the file was not built');
    await pumpHost(tester);

    await tester.tap(find.text('Export card'));
    // saveFromBuilder makes a real temp folder first.
    for (
      var i = 0;
      i < 500 && find.textContaining("wasn't saved").evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.textContaining("wasn't saved"), findsOneWidget);
    expect(find.textContaining('the card could not be drawn'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(results.containsKey('built'), isTrue);
    expect(results['built'], isNull);
  });
}
