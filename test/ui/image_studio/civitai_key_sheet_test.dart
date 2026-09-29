// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/civitai_credentials.dart';
import 'package:front_porch_ai/ui/image_studio/studio_civitai_get.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'civitai_credential_local': 'green-key',
    });
  });

  testWidgets(
    'a saved CivitAI key is back in the field after the sheet opens',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: StudioCivitaiGet(
            lora: true,
            adult: false,
            backend: 'comfyui',
            onInstalled: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('API key saved'), findsOneWidget);
      expect(find.text('civitai.red API key saved'), findsNothing);
      expect(
        find.text(
          'This key is used for search and for adult results on civitai.red.',
        ),
        findsOneWidget,
      );
      expect(find.text('green-key'), findsNothing);
      expect(find.text('civitai.red API key'), findsNothing);
      expect(find.widgetWithText(TextField, 'API key'), findsNothing);

      final again = await CivitaiCredentialStore.open();
      expect(await again.read('local'), 'green-key');
    },
  );
}
