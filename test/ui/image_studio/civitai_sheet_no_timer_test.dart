// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Opening the CivitAI sheet with no models folder saved looks for ComfyUI's
// models folder, which asks this computer's process list (ps, lsof,
// PowerShell) with a time limit. (A saved folder skips that ask.) Closing
// the sheet while that is under way must not leave the limit's timer behind
// in the caller's zone; the test framework fails a test that ends with a
// timer still pending.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/ui/image_studio/studio_civitai_get.dart';

void main() {
  testWidgets('a sheet closed mid folder scan leaves no timer pending', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: StudioCivitaiGet(
          lora: true,
          adult: false,
          adultAllowed: false,
          backend: 'comfyui',
          onInstalled: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Get a LoRA from CivitAI'), findsOneWidget);
    // The test ends with the scan still under way.
  });
}
