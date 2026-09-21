// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// GroupAlternateGreetingsEditor Add on a group with no alts. Same crash as
// the 1:1 character editor: alignGreetingSeeds(..., 0) used to return
// const [] and _seeds.add(null) threw UnmodifiableListMixin.add.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/widgets/group_alternate_greetings_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Add greeting works when the group has no alternate greetings yet',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GroupAlternateGreetingsEditor(
                greetings: const [],
                seeds: const [],
                onChanged: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No alternate greetings yet'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'group Add must not hit UnmodifiableListMixin.add — '
            'alignGreetingSeeds(const [], 0) used to return const []',
      );
      expect(find.text('No alternate greetings yet'), findsNothing);
      expect(find.text('Greeting 2'), findsOneWidget);
    },
  );
}
