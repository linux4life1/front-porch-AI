// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Where we are" must not say "No recap yet" and, under it, claim an update.
// The line under the recap reads the Journal pass cursor, which moves on any
// pass that comes back, even one where the model skipped the recap. So it
// is hidden while there is no recap, and otherwise says how far the Journal
// has read rather than that the recap was updated.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

Future<void> _pump(WidgetTester tester, FakeChatService chat) async {
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService();
  addTearDown(storage.dispose);
  addTearDown(chat.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: SizedBox(width: 320, child: SummarySection(chatService: chat)),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setupPathProviderMock();

  testWidgets('no recap: no claim that it was updated', (tester) async {
    // The c30 state: a Journal pass wrote cards (cursor at 4) but the
    // model skipped the recap.
    await _pump(tester, FakeChatService(summary: '', summaryLastIndex: 4));
    expect(
      find.text('No recap yet. It will generate after enough messages...'),
      findsOneWidget,
    );
    expect(find.textContaining('message #4'), findsNothing);
    expect(find.textContaining('Last updated'), findsNothing);
  });

  testWidgets('with a recap: says how far the Journal has read', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeChatService(
        summary: 'They are sharing peaches on the porch.',
        summaryLastIndex: 4,
      ),
    );
    expect(find.text('Journal has read up to message #4'), findsOneWidget);
    expect(find.textContaining('Last updated'), findsNothing);
  });
}
