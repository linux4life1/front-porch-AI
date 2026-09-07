// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/ui/desk/desk_page.dart';

void main() {
  testWidgets('composer grows with the prompt instead of staying one line', (
    tester,
  ) async {
    final session = DeskSession(
      folderRoot: '/tmp/throwaway-desk',
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(MaterialApp(home: DeskPage(session: session)));
    final field = tester.widget<TextField>(
      find.byKey(const Key('desk-composer')),
    );
    expect(field.minLines, 1);
    expect(field.maxLines, 10);
    expect(field.textInputAction, TextInputAction.newline);

    final before = tester
        .getSize(find.byKey(const Key('desk-composer')))
        .height;
    await tester.enterText(
      find.byKey(const Key('desk-composer')),
      'line one\nline two\nline three\nline four\nline five',
    );
    await tester.pump();
    final after = tester.getSize(find.byKey(const Key('desk-composer'))).height;
    expect(after, greaterThan(before));
  });
}
