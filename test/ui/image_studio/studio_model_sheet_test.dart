// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Change model lists every file. One whose name looks wrong for the model is
// marked and listed after the ones that look right, never hidden, and picking
// it still works.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/image_studio/studio_model_sheet.dart';

const _marker = 'The name does not look like it fits this model.';

void main() {
  const items = [
    'a_sd15_encoder.safetensors',
    'qwen_3_4b.safetensors',
    'flux2-vae.safetensors',
  ];
  const unfit = {'a_sd15_encoder.safetensors'};

  Future<void> show(
    WidgetTester tester, {
    ValueChanged<String>? onPick,
    Set<String> odd = unfit,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudioModelSheet(
            edit: false,
            items: items,
            unfit: odd,
            onPick: onPick ?? (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('a file that looks wrong is shown, not hidden', (tester) async {
    await show(tester);

    for (final file in items) {
      expect(find.text(file), findsOneWidget, reason: file);
    }
  });

  testWidgets('only the file that looks wrong is marked', (tester) async {
    await show(tester);

    expect(find.text(_marker), findsOneWidget);
    final row = find.ancestor(
      of: find.text('a_sd15_encoder.safetensors'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: row, matching: find.text(_marker)),
      findsOneWidget,
    );
  });

  testWidgets('files that look wrong come after the ones that look right', (
    tester,
  ) async {
    await show(tester);

    final odd = tester.getTopLeft(find.text('a_sd15_encoder.safetensors')).dy;
    for (final good in ['qwen_3_4b.safetensors', 'flux2-vae.safetensors']) {
      expect(
        tester.getTopLeft(find.text(good)).dy,
        lessThan(odd),
        reason: good,
      );
    }
  });

  testWidgets('with nothing that looks wrong, nothing is marked', (
    tester,
  ) async {
    await show(tester, odd: const {});

    expect(find.text(_marker), findsNothing);
  });

  testWidgets('a marked file can still be picked', (tester) async {
    String? picked;
    await show(tester, onPick: (file) => picked = file);

    await tester.tap(find.text('a_sd15_encoder.safetensors'));
    await tester.pump();

    expect(picked, 'a_sd15_encoder.safetensors');
  });
}
