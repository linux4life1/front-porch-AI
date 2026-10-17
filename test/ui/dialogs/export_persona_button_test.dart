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

import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/dialogs/export_persona_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

void main() {
  testWidgets('Export button paints porch amber with inkOn foreground', (
    tester,
  ) async {
    final personas = [
      UserPersona(
        id: 'p1',
        title: 'Casual',
        name: 'Alex',
        persona: 'Friendly and relaxed.',
      ),
      UserPersona(
        id: 'p2',
        title: 'Professional',
        name: 'Alex (Work)',
        persona: 'Formal and precise.',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(body: ExportPersonaDialog(personas: personas)),
      ),
    );

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Export'),
    );
    expect(
      button.style?.backgroundColor?.resolve({}),
      AppColors.porchAmber,
      reason: 'Export button must be porch amber, not the old indigo',
    );
    expect(
      button.style?.foregroundColor?.resolve({}),
      AppColors.inkOn(AppColors.porchAmber),
    );
  });
}
