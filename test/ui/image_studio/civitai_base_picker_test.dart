// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/image_studio/studio_civitai_get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Civit search can type a base and limit the list to installed models',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: StudioCivitaiGet(
            lora: true,
            adult: false,
            adultAllowed: false,
            backend: 'comfyui',
            onInstalled: _ignore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Filter bases'), findsOneWidget);
      expect(find.text('Only installed models'), findsOneWidget);
      expect(find.text('Base model'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('studio-civitai-base-filter')),
        'qwen',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('studio-civitai-base')));
      await tester.pumpAndSettle();
      expect(find.text('Qwen 2.1'), findsWidgets);
      expect(find.text('Flux.1 Dev'), findsNothing);
    },
  );
}

void _ignore(String _) {}
