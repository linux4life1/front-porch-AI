// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Enhance Review must offer keep-or-accept for Porch Life, and an empty
// proposal must default Use this OFF so a mute model cannot wipe a wardrobe.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chat_grounding.dart';
import 'package:front_porch_ai/ui/pages/home/enhance/enhance_review_body.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('Porch Life proposal shows Before vs After with Use this on', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        EnhanceReviewBody(
          original: CharacterCard(
            name: 'Nina',
            frontPorchExtensions: FrontPorchExtensions(
              ambitions: const ['old goal'],
              inventory: const {
                'worn': ['old coat'],
              },
            ),
          ),
          enhanced: CharacterCard(
            name: 'Nina',
            frontPorchExtensions: FrontPorchExtensions(
              ambitions: const ['stay fed'],
              inventory: const {
                'worn': ['flour-dusted apron'],
              },
            ),
          ),
          selection: const EnhanceSelection(
            description: false,
            personality: false,
            exampleDialogue: false,
            porchLife: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Porch Life (wardrobe, ambitions, likes)'),
      findsOneWidget,
    );
    expect(find.textContaining('old goal'), findsOneWidget);
    expect(find.text('stay fed'), findsOneWidget);
    final useSwitch = tester.widget<Switch>(find.byType(Switch).first);
    expect(useSwitch.value, isTrue);
  });

  testWidgets('empty Porch Life proposal defaults Use this off', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        EnhanceReviewBody(
          original: CharacterCard(
            name: 'Nina',
            frontPorchExtensions: FrontPorchExtensions(
              ambitions: const ['old goal'],
            ),
          ),
          enhanced: CharacterCard(name: 'Nina'),
          selection: const EnhanceSelection(
            description: false,
            personality: false,
            exampleDialogue: false,
            porchLife: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final useSwitch = tester.widget<Switch>(find.byType(Switch).first);
    expect(useSwitch.value, isFalse);
  });

  testWidgets(
    'empty proposed description and personality default Use this off',
    (tester) async {
      await tester.pumpWidget(
        _app(
          EnhanceReviewBody(
            original: CharacterCard(
              name: 'Nina',
              description: 'authored description',
              personality: 'authored personality',
            ),
            enhanced: CharacterCard(
              name: 'Nina',
              description: '   ',
              personality: '',
            ),
            selection: const EnhanceSelection(
              description: true,
              personality: true,
              exampleDialogue: false,
              porchLife: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches, hasLength(2));
      expect(switches[0].value, isFalse);
      expect(switches[1].value, isFalse);
    },
  );

  testWidgets('non-empty proposed description still defaults Use this on', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        EnhanceReviewBody(
          original: CharacterCard(name: 'Nina', description: 'old'),
          enhanced: CharacterCard(name: 'Nina', description: 'rewritten'),
          selection: const EnhanceSelection(
            description: true,
            personality: false,
            exampleDialogue: false,
            porchLife: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final useSwitch = tester.widget<Switch>(find.byType(Switch).first);
    expect(useSwitch.value, isTrue);
  });

  testWidgets('empty proposed greetings default Use this off', (tester) async {
    await tester.pumpWidget(
      _app(
        EnhanceReviewBody(
          original: CharacterCard(name: 'Nina', firstMessage: 'Hey there.'),
          enhanced: CharacterCard(name: 'Nina', firstMessage: ''),
          selection: const EnhanceSelection(
            description: false,
            personality: false,
            exampleDialogue: false,
            greetings: true,
            porchLife: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final useSwitch = tester.widget<Switch>(find.byType(Switch).first);
    expect(useSwitch.value, isFalse);
  });
}
