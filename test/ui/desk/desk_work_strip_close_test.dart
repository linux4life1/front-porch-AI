// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/ui/desk/desk_page.dart';

void main() {
  testWidgets('close dismisses the last-write strip, not the file', (
    tester,
  ) async {
    final session =
        DeskSession(
            folderRoot: '/tmp/throwaway-desk',
            coworker: CharacterCard(name: 'Iris'),
          )
          ..lastWrite = const DeskWriteRecord(
            relativePath: 'hello.txt',
            before: '',
            after: 'hi',
          );
    await tester.pumpWidget(MaterialApp(home: DeskPage(session: session)));
    expect(find.byKey(const Key('desk-work-strip')), findsOneWidget);
    expect(find.byKey(const Key('desk-work-strip-close')), findsOneWidget);

    await tester.tap(find.byKey(const Key('desk-work-strip-close')));
    await tester.pump();
    expect(find.byKey(const Key('desk-work-strip')), findsNothing);
    expect(session.lastWrite, isNull);
  });
}
