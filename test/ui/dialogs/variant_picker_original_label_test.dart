// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The swipe picker labels the first reply "Original" (later ones stay
// "Regen"; the card's #N numbers them), and its character count covers only
// the text the reader sees, not the hidden thinking. The phone reads the
// same rows through toJson.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';

const _first =
    '<think>She weighs the peach, the porch, the hour, and decides to '
    'smile.</think>\nShe smiles.';
const _second = 'She takes the peach.';

void main() {
  test('rows label the original and count visible text only', () {
    final rows = buildVariantOptions([_first, _second, 'Third.'], 0);
    expect(rows.map((r) => r.label), ['Original', 'Regen', 'Regen']);
    expect(rows.first.charCount, 'She smiles.'.length);
    expect(rows.first.tokenCount, variantApproxTokens('She smiles.'.length));
    expect(rows.first.toJson()['label'], 'Original');
    expect(rows.first.toJson()['charCount'], 'She smiles.'.length);
  });

  test('greets keep the Greet label', () {
    final rows = buildVariantOptions(
      ['Hi there', 'Hey you'],
      0,
      kind: VariantKind.greet,
    );
    expect(rows.map((r) => r.label), ['Greet', 'Greet']);
  });

  testWidgets('picker shows Original and the visible-text count', (
    tester,
  ) async {
    final variants = buildVariantOptions([_first, _second], 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showVariantPickerDialog(
              context,
              title: 'Select variant',
              variants: variants,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Original · 11 characters · 3t'), findsOneWidget);
    expect(find.text('Regen · 20 characters · 5t'), findsOneWidget);
  });
}
