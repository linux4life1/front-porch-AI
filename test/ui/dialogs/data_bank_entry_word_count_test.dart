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
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/ui/dialogs/data_bank/data_bank.dart';

// Every Data Bank tile used to read "1w": the word split used the raw regex
// r'\\s+', which matches a literal backslash, so content never split.
void main() {
  Future<void> pumpTile(WidgetTester tester, String content) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DataBankEntryTile(
            entry: DataBankEntry(
              id: 'bank-1',
              characterId: 'Mara_1',
              title: 'keys',
              content: content,
              dimensions: 0,
              createdAt: DateTime(2026),
            ),
            onEdit: () {},
            onDelete: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('tile shows the real word count of the entry', (tester) async {
    await pumpTile(tester, 'She keeps the\nspare  under the mat.');
    expect(find.text('7w'), findsOneWidget);
    expect(find.text('1w'), findsNothing);
  });

  testWidgets('blank entry counts zero words', (tester) async {
    await pumpTile(tester, '   ');
    expect(find.text('0w'), findsOneWidget);
  });
}
