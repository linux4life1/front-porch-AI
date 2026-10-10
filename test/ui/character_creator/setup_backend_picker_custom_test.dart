// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The creator's Setup step must show which host is in use, including a
// Custom server, and switching to Custom must leave the user a way to say
// where that server is.

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
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import '../../golden/support/fakes.dart';

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_setup_custom_').path;
        }
        return null;
      });
}

class _Llm extends FakeLLMProvider {
  _Llm() : super(activeBackend: BackendType.openRouter);

  @override
  Future<void> setActiveBackend(BackendType type) async {}

  // Skip the live /models fetch — these tests only watch the host switch.
  @override
  bool get hasManagedProcess => true;
}

const _customUrl = 'http://192.168.1.50:5001/v1';

Future<StorageService> _storageAt(WidgetTester tester, String url) async {
  late final StorageService storage;
  await tester.runAsync(() async {
    storage = StorageService();
    await storage.initialized;
    await storage.backendSettings.setBackendType('openRouter');
    await storage.backendSettings.setRemoteApiUrl(url);
  });
  addTearDown(storage.dispose);
  return storage;
}

Future<CreatorState> _pump(WidgetTester tester, StorageService storage) async {
  final llm = _Llm();
  addTearDown(llm.dispose);
  final state = CreatorState();
  addTearDown(state.dispose);
  await tester.binding.setSurfaceSize(const Size(900, 600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
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
  return state;
}

/// A lit pill draws its label in the on-amber ink.
bool _lit(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.color ==
    AppColors.onChaosAccent;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _mockPathProvider();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a custom server lights the Custom chip and shows its address', (
    tester,
  ) async {
    final storage = await _storageAt(tester, _customUrl);
    await _pump(tester, storage);

    expect(find.text('Custom'), findsOneWidget);
    expect(_lit(tester, 'Custom'), isTrue);
    for (final other in ['OpenRouter', 'Nano-GPT', 'xAI', 'LM Studio']) {
      expect(_lit(tester, other), isFalse, reason: other);
    }
    expect(
      find.widgetWithText(TextField, _customUrl),
      findsOneWidget,
      reason: 'the address box shows the server in use',
    );
  });

  testWidgets('picking Custom lights it and takes a typed address', (
    tester,
  ) async {
    final storage = await _storageAt(tester, kOpenRouterApiV1);
    final state = await _pump(tester, storage);

    expect(_lit(tester, 'OpenRouter'), isTrue);
    expect(find.byKey(const ValueKey('creator-custom-url')), findsNothing);

    await tester.tap(find.text('Custom'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();

    expect(_lit(tester, 'Custom'), isTrue);
    expect(_lit(tester, 'OpenRouter'), isFalse);
    final box = find.byKey(const ValueKey('creator-custom-url'));
    expect(box, findsOneWidget);

    Future<void> settle() async {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump();
    }

    // Typing stays in the box: nothing is saved or fetched per keystroke.
    final before = storage.backendSettings.remoteApiUrl;
    state.selectedModelId = 'stale-model';
    await tester.enterText(box, _customUrl);
    await settle();
    expect(storage.backendSettings.remoteApiUrl, before);
    expect(state.selectedModelId, 'stale-model', reason: 'no fetch yet');

    // Leaving the box saves the address and fetches the new server's list.
    FocusManager.instance.primaryFocus?.unfocus();
    await settle();
    expect(storage.backendSettings.remoteApiUrl, _customUrl);
    expect(state.selectedModelId, '', reason: 'the model list was reloaded');
    expect(_lit(tester, 'Custom'), isTrue);

    // Back in and out with no change: no second save or fetch.
    state.selectedModelId = 'picked-after-fetch';
    await tester.tap(box);
    await settle();
    FocusManager.instance.primaryFocus?.unfocus();
    await settle();
    expect(state.selectedModelId, 'picked-after-fetch');
  });
}
