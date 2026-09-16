// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Wizard Setup must switch OpenRouter ↔ Nano-GPT the same way Model
// Settings does — each host keeps its own key and last model.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/setup_backend_picker.dart';

import '../../golden/support/fakes.dart';

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_setup_picker_').path;
        }
        return null;
      });
}

class _Llm extends FakeLLMProvider {
  _Llm() : super(activeBackend: BackendType.openRouter);

  @override
  Future<void> setActiveBackend(BackendType type) async {}

  // Skip the live /models fetch — this test only cares that the URL swaps.
  @override
  bool get hasManagedProcess => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _mockPathProvider();

  testWidgets('remote API shows OpenRouter / Nano-GPT / LM Studio', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    late final StorageService storage;
    await tester.runAsync(() async {
      storage = StorageService();
      await storage.initialized;
      await storage.setBackendType('openRouter');
      await storage.setRemoteApiUrl(kOpenRouterApiV1);
      await storage.setRemoteApiKey('sk-or-test');
    });
    addTearDown(storage.dispose);

    final llm = _Llm();
    addTearDown(llm.dispose);
    final state = CreatorState();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<LLMProvider>.value(value: llm),
          ],
          child: Scaffold(body: SetupBackendPicker(state: state)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('API (Remote)'), findsOneWidget);
    expect(find.text('OpenRouter'), findsOneWidget);
    expect(find.text('Nano-GPT'), findsOneWidget);
    expect(find.text('LM Studio'), findsOneWidget);

    await tester.tap(find.text('Nano-GPT'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();

    expect(storage.remoteApiUrl, kNanoGptApiV1);
  });
}
