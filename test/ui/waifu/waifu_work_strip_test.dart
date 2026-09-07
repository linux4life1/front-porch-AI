// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_work_strip.dart';

void main() {
  test('waifuClipWorkPreview caps lines and chars', () {
    final many = List.generate(40, (i) => 'line $i').join('\n');
    final clipped = waifuClipWorkPreview(many);
    expect(
      clipped.split('\n').length,
      lessThanOrEqualTo(kWaifuWorkStripMaxLines + 1),
    );
    expect(clipped.length, lessThanOrEqualTo(kWaifuWorkStripMaxChars + 1));
    expect(clipped, isNot(contains('line 39')));
  });

  testWidgets('huge last-write does not overflow the chat column', (
    tester,
  ) async {
    final huge = List.generate(
      200,
      (i) => 'pubspec line $i sdk constraint',
    ).join('\n');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.expand()),
              WaifuWorkStrip(
                record: WaifuWriteRecord(
                  relativePath: 'pubspec.yaml',
                  before: huge,
                  after: huge,
                ),
              ),
              const SizedBox(height: 48, child: Text('composer')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('waifu-work-strip')), findsOneWidget);
    expect(find.textContaining('Last write: pubspec.yaml'), findsOneWidget);
    expect(find.textContaining('pubspec line 199'), findsNothing);
    expect(find.text('composer'), findsOneWidget);
  });
}
