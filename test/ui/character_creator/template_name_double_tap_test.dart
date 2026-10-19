// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Save as template and Rename share one name dialog. A double click on its
// confirm button while the first write is still running must write once.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/widgets.dart';

import '../../helpers/double_tap.dart';

void main() {
  testWidgets('a double click on Save writes the template once', (
    tester,
  ) async {
    final gate = Completer<void>();
    final written = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreatorTheme(
            child: TemplateNameDialog(
              title: 'Save as template',
              confirmLabel: 'Save',
              initialName: 'Porch Cat',
              check: (_) => (problem: null, replaces: false),
              submit: (name) {
                written.add(name);
                return gate.future;
              },
              failure: 'Could not save.',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await doubleTapNoFrame(
      tester,
      find.byKey(const ValueKey('template-name-confirm')),
    );
    await tester.pump();
    expect(written, ['Porch Cat']);
  });
}
