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

// The startup error screen has two variants with genuinely different advice:
// a settings-file parse failure must NOT tell the user to free disk space or
// close other copies (the pre-fix misdiagnosis that sent a field report down
// the wrong path), and vice versa.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/db_init_error_app.dart';

void main() {
  testWidgets('default variant blames the database', (tester) async {
    await tester.pumpWidget(
      const DbInitErrorApp(details: 'SqliteException: database is locked'),
    );

    expect(
      find.text("Front Porch AI couldn't open its database"),
      findsOneWidget,
    );
    expect(find.textContaining('full disk'), findsOneWidget);
    expect(find.textContaining('shared_preferences.json'), findsNothing);
    expect(find.text('SqliteException: database is locked'), findsOneWidget);
  });

  testWidgets('settings-corruption variant blames the settings file', (
    tester,
  ) async {
    await tester.pumpWidget(
      const DbInitErrorApp(
        details: 'FormatException: Unexpected character (at character 1)',
        settingsFileCorrupt: true,
      ),
    );

    expect(
      find.text("Front Porch AI couldn't read its settings"),
      findsOneWidget,
    );
    expect(find.textContaining('shared_preferences.json'), findsOneWidget);
    expect(find.textContaining('characters and chats'), findsOneWidget);
    expect(find.textContaining('full disk'), findsNothing);
  });

  testWidgets('scaffold paints the warm AppColors.background const', (
    tester,
  ) async {
    await tester.pumpWidget(
      const DbInitErrorApp(details: 'SqliteException: database is locked'),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.background);
  });
}
