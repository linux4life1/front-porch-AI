// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The desktop Tavily field must not write partial keys on every keystroke.
// Save and Remove are explicit, secure-store-backed actions.
//
// Guard proven red before passing: the old onChanged writer persisted the
// first edit immediately and had no Save button.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

String get _key => isPreRelease ? 'beta_search_api_key' : 'search_api_key';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp
              .createTempSync('fpai_web_search_key_')
              .path;
        }
        return null;
      });

  testWidgets('key writes only on Save and Remove clears it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    addTearDown(storage.dispose);
    await storage.initialized;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WebSearchKeyField(storage: storage)),
      ),
    );

    await tester.enterText(find.byType(TextField), 'tavily-desktop-secret');
    await tester.pump();
    expect(
      await const FlutterSecureStorage().read(key: _key),
      isNull,
      reason: 'typing must not persist partial secrets',
    );

    await tester.tap(find.text('Save key'));
    await tester.pumpAndSettle();
    expect(storage.webSearchSettings.hasApiKey, isTrue);
    expect(
      await const FlutterSecureStorage().read(key: _key),
      'tavily-desktop-secret',
    );
    expect((await SharedPreferences.getInstance()).containsKey(_key), isFalse);
    expect(find.text('Tavily key saved securely.'), findsOneWidget);

    await tester.tap(find.text('Remove key'));
    await tester.pumpAndSettle();
    expect(storage.webSearchSettings.hasApiKey, isFalse);
    expect(await const FlutterSecureStorage().read(key: _key), isNull);
    expect(find.text('Key removed — searches use Wikipedia.'), findsOneWidget);
  });
}
