// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Enhance Review must offer keep-or-accept for Porch Life, and an empty
// proposal must default Use this OFF so a mute model cannot wipe a wardrobe.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/ui/pages/home/enhance/enhance_review_body.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

const _porchOnly = EnhanceSelection(
  description: false,
  personality: false,
  exampleDialogue: false,
  porchLife: true,
);

FrontPorchExtensions _authored() => FrontPorchExtensions(
  ambitions: const ['old goal'],
  inventory: const {
    'worn': ['old coat'],
  },
);

CharacterCard _nina({FrontPorchExtensions? ext}) =>
    CharacterCard(name: 'Nina', frontPorchExtensions: ext);

void main() {
  testWidgets('Porch Life proposal shows Before vs After with Use this on', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        EnhanceReviewBody(
          original: _nina(ext: _authored()),
          enhanced: _nina(
            ext: FrontPorchExtensions(
              ambitions: const ['stay fed'],
              inventory: const {
                'worn': ['flour-dusted apron'],
              },
            ),
          ),
          selection: _porchOnly,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Porch Life (wardrobe, ambitions, likes)'),
      findsOneWidget,
    );
    expect(find.text('After (editable)'), findsOneWidget);
    expect(find.text('Use this'), findsOneWidget);
    // Before is the authored line, not a silent overwrite of the After chips.
    expect(find.text('Ambitions: old goal'), findsOneWidget);
    expect(find.text('Wearing: old coat'), findsOneWidget);
    expect(find.text('stay fed'), findsOneWidget);
    expect(find.text('flour-dusted apron'), findsOneWidget);
    final useSwitch = tester.widget<Switch>(find.byType(Switch).first);
    expect(useSwitch.value, isTrue);
  });

  testWidgets('empty Porch Life proposal defaults Use this off', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        EnhanceReviewBody(
          original: _nina(ext: _authored()),
          // Mute-seed shape: copyWith empty lists, not a null extensions
          // object. A pin on `_nina()` (null ext) can stay green while
          // `extensions != null` defaults Use this ON.
          enhanced: _nina(
            ext: FrontPorchExtensions(
              ambitions: const [],
              inventory: const {'worn': <String>[], 'carrying': <String>[]},
            ),
          ),
          selection: _porchOnly,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('After (editable)'), findsOneWidget);
    expect(find.text('Ambitions: old goal'), findsOneWidget);
    expect(find.text('Wearing: old coat'), findsOneWidget);
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

  test('Save writes Porch Life only when Use this is on', () {
    final src = File(
      'lib/ui/pages/home/enhance/enhance_review_body.dart',
    ).readAsStringSync();
    final saveAt = src.indexOf('Future<CharacterCard?> save()');
    expect(saveAt, greaterThanOrEqualTo(0));
    final save = src.substring(saveAt);
    expect(
      save,
      contains("widget.selection.porchLife && (_use['porchLife'] ?? false)"),
    );
    expect(save, contains('applyPorchLifeProposal'));
    expect(save.contains('ext.copyWith('), isFalse);
  });
}
