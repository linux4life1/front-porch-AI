// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/fakes.dart';

class _SeededPersonas extends FakeUserPersonaService {
  @override
  List<UserPersona> get personas => [
    UserPersona(id: 'p1', name: 'Sam', birthday: '1998-03-15'),
  ];

  @override
  UserPersona get persona => personas.first;
}

void main() {
  Future<void> pumpDialog(
    WidgetTester tester,
    UserPersonaService personas,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<UserPersonaService>.value(
        value: personas,
        child: const MaterialApp(home: Scaffold(body: UserPersonaDialog())),
      ),
    );
  }

  testWidgets('Speak as… create form has the birthday row', (tester) async {
    final personas = FakeUserPersonaService();
    addTearDown(personas.dispose);
    await pumpDialog(tester, personas);

    expect(find.byType(BirthdayRow), findsNothing);
    await tester.tap(find.text('Add New Persona'));
    await tester.pump();

    expect(find.byType(BirthdayRow), findsOneWidget);
    expect(find.text('No birthday set'), findsOneWidget);
    expect(find.text('Set'), findsOneWidget);
  });

  testWidgets('Speak as… edit loads the stored birthday', (tester) async {
    final personas = _SeededPersonas();
    addTearDown(personas.dispose);
    await pumpDialog(tester, personas);

    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();

    expect(find.byType(BirthdayRow), findsOneWidget);
    expect(find.text('March 15, 1998'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
  });

  test('create and update both write the birthday field', () {
    final src = File(
      'lib/ui/dialogs/user_persona_dialog.dart',
    ).readAsStringSync();
    expect(src, contains('birthday: _birthday'));
    expect('birthday: _birthday'.allMatches(src).length, 2);
  });
}
