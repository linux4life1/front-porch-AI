// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Desktop cast chips must show GUEST + Promote for soft guests — Character
// State used to hide both when the focused speaker was lite. Proven red:
// drop isLite / onPromote and these fail.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/sidebar_tokens.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

void main() {
  test('Character State stays up for a group guest, not a 1:1 guest', () {
    expect(characterStateAccordionVisible(isLite: true, isGroup: true), isTrue);
    expect(
      characterStateAccordionVisible(isLite: true, isGroup: false),
      isFalse,
    );
    expect(
      characterStateAccordionVisible(isLite: false, isGroup: true),
      isTrue,
    );
    expect(
      characterStateAccordionVisible(isLite: false, isGroup: false),
      isTrue,
    );
  });

  testWidgets('lite chip shows amber GUEST and a tappable Promote', (t) async {
    var promoted = false;
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: CastRosterChip(
            name: 'Mara',
            color: AppColors.formMasterAccent,
            isFocused: true,
            isLite: true,
            onFocus: () {},
            onPromote: () => promoted = true,
          ),
        ),
      ),
    );

    expect(find.text('GUEST'), findsOneWidget);
    expect(find.text('Promote'), findsOneWidget);
    expect(find.text('Mara'), findsOneWidget);

    await t.tap(find.text('Promote'));
    expect(promoted, isTrue);
  });

  testWidgets('full member chip has no GUEST or Promote', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CastRosterChip(
            name: 'Zinna',
            color: AppColors.formMasterAccent,
            isFocused: false,
            isLite: false,
            onFocus: () {},
          ),
        ),
      ),
    );

    expect(find.text('GUEST'), findsNothing);
    expect(find.text('Promote'), findsNothing);
    expect(find.text('Zinna'), findsOneWidget);
  });
}
