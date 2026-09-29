// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/image_studio/studio_desk_frame.dart';

void main() {
  testWidgets('wide desk shows the picture under Expression pack', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1040, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 640,
            child: StudioDeskFrame(
              well: 'Start from a picture',
              packNote: 'Pack note',
              stove: Column(
                children: [
                  Text('STOVETOP'),
                  SizedBox(height: 1800),
                  Text('STOVEBOTTOM'),
                ],
              ),
              output: SizedBox(
                key: Key('picture'),
                height: 900,
                child: Text('OUTPUTMARK'),
              ),
            ),
          ),
        ),
      ),
    );

    final picture = tester.getRect(find.byKey(const Key('picture')));
    final pack = tester.getRect(find.text('Expression pack'));
    final stoveTop = tester.getRect(find.text('STOVETOP'));
    final stoveBottom = tester.getRect(find.text('STOVEBOTTOM'));

    expect(find.byKey(const Key('studio-desk-wide')), findsOneWidget);
    expect(find.byKey(const Key('studio-desk-output')), findsOneWidget);
    expect(picture.top, greaterThan(pack.top));
    expect(picture.left, lessThan(stoveTop.left));
    expect(picture.top, lessThan(640));
    expect(stoveBottom.top, greaterThan(640));
  });

  testWidgets('narrow desk keeps the picture below the stove', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 700,
            child: SingleChildScrollView(
              child: StudioDeskFrame(
                well: 'Start from a picture',
                packNote: 'Pack note',
                stove: SizedBox(height: 400, child: Text('STOVEMARK')),
                output: SizedBox(
                  key: Key('picture'),
                  height: 80,
                  child: Text('OUTPUTMARK'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final picture = tester.getRect(find.byKey(const Key('picture')));
    final stove = tester.getRect(find.text('STOVEMARK'));
    expect(find.byKey(const Key('studio-desk-narrow')), findsOneWidget);
    expect(find.byKey(const Key('studio-desk-output')), findsNothing);
    expect(picture.top, greaterThan(stove.bottom - 1));
  });
}
