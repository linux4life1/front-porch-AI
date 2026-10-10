// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Stoop sign-in's empty Password box must not show dots as its hint: a
// row of bullets reads as a password that is already filled in.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/repository/repository_auth_view.dart';

void main() {
  String? passwordHint(WidgetTester tester) {
    final field = tester
        .widgetList<TextField>(find.byType(TextField))
        .where((f) => f.obscureText);
    expect(field, hasLength(1));
    return field.single.decoration?.hintText;
  }

  testWidgets('the empty password box says what to type, not dots', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RepositoryAuthView())),
    );

    expect(passwordHint(tester), 'Your password');
    expect(find.textContaining('•'), findsNothing);

    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(passwordHint(tester), 'At least 8 characters');
    expect(find.textContaining('•'), findsNothing);
  });
}
