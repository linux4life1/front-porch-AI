// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/pages/user_persona/persona_list_cards.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

void main() {
  testWidgets('empty-state Import JSON icon is porch amber, not cyan', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: PersonaEmptyState(onCreate: () {}, onImport: () {}),
        ),
      ),
    );

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.widgetWithText(OutlinedButton, 'Import JSON'),
        matching: find.byIcon(Icons.download),
      ),
    );
    expect(icon.color, AppColors.porchAmber);
  });
}
