// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/ui/image_studio/expression_pack_widgets.dart';

void main() {
  testWidgets('seed-only reroll keeps later prompt rules active', (
    tester,
  ) async {
    final prompts = <String>[];
    final session = ExpressionPackSession(
      emotions: ['happy'],
      basePrompt: 'portrait',
      negativePrompt: '',
      denoise: 0.7,
      editMode: true,
      promptRules: ExpressionPromptRules(prefix: 'First wording'),
      generate:
          ({
            required prompt,
            required negativePrompt,
            required seed,
            required denoise,
          }) async {
            prompts.add(prompt);
            return Uint8List(0);
          },
    );
    addTearDown(session.dispose);
    await session.run();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showPackRerollEditor(context, session, 0),
              child: const Text('Open reroll'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open reroll'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New random seed'));
    await tester.tap(find.text('Re-roll'));
    await tester.pumpAndSettle();
    expect(session.slots.single.customPrompt, isNull);
    expect(
      session.updatePromptRules(ExpressionPromptRules(prefix: 'New wording')),
      isTrue,
    );
    await session.reroll(0);
    expect(prompts.last, startsWith('New wording'));
  });
  testWidgets('partial pack footer fits a narrow window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = StorageService.sandbox('unused-pack-footer');
    final image = ImageGenService(storage);
    addTearDown(image.dispose);
    addTearDown(storage.dispose);
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 32, height: 32)),
    );
    late ExpressionPackSession session;
    var calls = 0;
    session = ExpressionPackSession(
      emotions: ['happy', 'sad'],
      basePrompt: 'portrait',
      negativePrompt: '',
      denoise: 0.7,
      editMode: true,
      generate:
          ({
            required prompt,
            required negativePrompt,
            required seed,
            required denoise,
          }) async {
            if (++calls == 1) return png;
            session.cancel();
            return null;
          },
    );
    addTearDown(session.dispose);
    await session.run();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpressionPackGrid(
            storage: storage,
            session: session,
            imageGen: image,
            cancelRequested: false,
            importing: false,
            qc: null,
            resolvingVision: false,
            onVisionCheck: () {},
            onCancel: () {},
            onResume: () {},
            onImport: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Prompt rules…'), findsOneWidget);
    expect(find.text('Import 1 expressions'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
