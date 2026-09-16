// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/remote_api_section.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/worker_backend_section.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend_tab.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _Store extends FakeStorageService {
  _Store() {
    _backend.initializeBase(null, notifyListeners);
  }

  @override
  String get backendType => 'openRouter';

  @override
  String get remoteApiUrl => kNanoGptApiV1;

  @override
  String get remoteApiKey => '';

  @override
  String get remoteModelName => 'moonshotai/kimi-k2.6:thinking';

  final BackendSettings _backend = BackendSettings();

  @override
  BackendSettings get backendSettings => _backend;
}

class _Mgr extends ChangeNotifier implements BackendManager {
  @override
  bool get isIntelMac => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('H0 chat stack is contiguous before Side jobs', (tester) async {
    final url = TextEditingController(text: kNanoGptApiV1);
    final key = TextEditingController();
    addTearDown(url.dispose);
    addTearDown(key.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: _Store()),
          ChangeNotifierProvider<LLMProvider>.value(
            value: FakeLLMProvider(activeBackend: BackendType.openRouter),
          ),
          ChangeNotifierProvider<BackendManager>.value(value: _Mgr()),
          ChangeNotifierProvider<OpenRouterService>.value(
            value: OpenRouterService(),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                OpenCodeManager(rootPath: '', remoteLookup: () async => null),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BackendTab(
              apiUrlController: url,
              apiKeyController: key,
              availableModels: const [],
              onModelsFetched: (_) {},
              selectedModelPath: null,
              localPresets: const [],
              onModelSelected: (_) {},
              onVisionChanged: () {},
              onScanPresets: () {},
              onKcppsChanged: (_) {},
              onKcppsExternalClear: () {},
              onKcppsBrowsePicked: (_) {},
              onKcppsModelStatusChanged: (_) {},
              onGenerateKcppsDone: () {},
              onToggleBackend: () {},
              kcppsModelExists: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Chat speech'), findsOneWidget);
    expect(find.text('API Configuration'), findsNothing);
    expect(find.text('Backend Mode'), findsNothing);
    expect(find.text('Worker backend'), findsNothing);
    expect(find.text('Realism evals'), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('Check Connection'), findsOneWidget);

    final speech = tester.getTopLeft(
      find.byKey(const Key('chat-speech-section')),
    );
    final api = tester.getTopLeft(find.byType(RemoteApiSection));
    final apiKey = tester.getTopLeft(find.text('API Key'));
    final check = tester.getTopLeft(find.text('Check Connection'));
    final side = tester.getTopLeft(find.byKey(const Key('side-jobs-section')));
    final openCode = tester.getTopLeft(
      find.byKey(const Key('opencode-managed-section')),
    );

    expect(speech.dy < api.dy, isTrue, reason: 'chips header above API fields');
    expect(
      api.dy < apiKey.dy,
      isTrue,
      reason: 'API fields stay in the chat stack',
    );
    expect(
      apiKey.dy < check.dy,
      isTrue,
      reason: 'H0: key immediately before check',
    );
    expect(
      check.dy < side.dy,
      isTrue,
      reason: 'H0: Side jobs after chat stack',
    );
    expect(
      openCode.dy > check.dy,
      isTrue,
      reason: 'OpenCode is not between chips and key',
    );
    expect(
      openCode.dy < side.dy,
      isTrue,
      reason: 'OpenCode stays above Side jobs',
    );
    expect(find.byType(WorkerBackendSection), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(WorkerBackendSection)).dy >
          tester.getTopLeft(find.byType(RemoteApiSection)).dy,
      isTrue,
    );
  });
}
