// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The graphics-memory control: Automatic by default, a layer box when the
// user takes over, and the one-time note for people moved to Automatic.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool manual,
    int? retired,
    VoidCallback? onDismiss,
    ValueChanged<bool>? onManual,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GpuLayersField(
          manual: manual,
          onManualChanged: onManual ?? (_) {},
          controller: TextEditingController(text: '40'),
          retiredLayers: retired,
          onDismissRetired: onDismiss,
        ),
      ),
    ),
  );

  testWidgets('Automatic shows no layer box and, with nothing to say, no '
      'note', (tester) async {
    await pump(tester, manual: false);
    expect(find.text('Graphics memory: Automatic'), findsOneWidget);
    expect(find.byKey(const ValueKey('gpu-layers-number')), findsNothing);
    expect(find.byKey(const ValueKey('gpu-layers-retired-note')), findsNothing);
  });

  testWidgets('someone moved to Automatic sees what their number was, and '
      '"Got it" reports back', (tester) async {
    var dismissed = 0;
    await pump(
      tester,
      manual: false,
      retired: 40,
      onDismiss: () => dismissed++,
    );

    expect(find.textContaining('GPU layers was set to 40.'), findsOneWidget);
    expect(find.textContaining('Set layers myself'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('gpu-layers-retired-dismiss')));
    expect(dismissed, 1);
  });

  testWidgets('taking over shows the layer box and not the note', (
    tester,
  ) async {
    bool? asked;
    await pump(tester, manual: false, onManual: (v) => asked = v);
    await tester.tap(find.byKey(const ValueKey('gpu-layers-manual-switch')));
    expect(asked, isTrue);

    await pump(tester, manual: true, retired: 40);
    expect(find.text('Graphics memory: set by you'), findsOneWidget);
    expect(find.byKey(const ValueKey('gpu-layers-number')), findsOneWidget);
    expect(find.byKey(const ValueKey('gpu-layers-retired-note')), findsNothing);
  });
}
