// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/persona_picker_dialog.dart';

void main() {
  testWidgets('the new-chat picker marks the default persona, not whoever '
      'the open chat speaks as', (tester) async {
    final db = AppDatabase.forTesting(sameIsolate: true);
    final personas = UserPersonaService(db);
    await tester.runAsync(() async {
      while (personas.personas.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final chatAs = await personas.createPersona('', 'Rook', '', null);
      final newChatsAs = await personas.createPersona('', 'Wren', '', null);
      await personas.setDefaultPersona(newChatsAs);
      await personas.setActivePersona(chatAs);
    });
    expect(personas.persona.name, 'Rook');

    await tester.pumpWidget(
      ChangeNotifierProvider<UserPersonaService>.value(
        value: personas,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showPersonaPickerDialog(context, subject: 'Mabel'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final badge = find.text('Default');
    expect(badge, findsOneWidget);
    final row = find.ancestor(of: badge, matching: find.byType(ListTile));
    expect(
      find.descendant(of: row, matching: find.text('Wren')),
      findsOneWidget,
    );
    expect(find.text('Current'), findsNothing);

    await tester.runAsync(() async {
      personas.dispose();
      await db.close();
    });
  });
}
