// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/worker_backend_section.dart';
import 'package:front_porch_ai/ui/settings/widgets/remote_model_picker_field.dart';
import 'package:front_porch_ai/ui/settings/widgets/remote_provider_bar.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _Store extends FakeStorageService {
  _Store({this.backendType = 'openRouter', this.remoteApiUrl = kNanoGptApiV1}) {
    _backend.initializeBase(null, notifyListeners);
  }

  @override
  String backendType;
  @override
  String remoteApiUrl;

  final BackendSettings _backend = BackendSettings();

  @override
  BackendSettings get backendSettings => _backend;
}

class _Llm extends FakeLLMProvider {
  _Llm({super.activeBackend = BackendType.openRouter, this.refused = false});

  final bool refused;

  @override
  bool get workerRefusedDualLocal => refused;
}

class _Mgr extends ChangeNotifier implements BackendManager {
  @override
  bool get isIntelMac => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  required _Store storage,
  FakeLLMProvider? llm,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: storage),
        ChangeNotifierProvider<LLMProvider>.value(value: llm ?? _Llm()),
        ChangeNotifierProvider<BackendManager>.value(value: _Mgr()),
      ],
      child: const MaterialApp(home: Scaffold(body: WorkerBackendSection())),
    ),
  );
}

void main() {
  test('same-host helper treats empty worker as inherited', () {
    expect(
      workerHostMatchesChat(
        mouthType: 'openRouter',
        mouthUrl: kNanoGptApiV1,
        workerType: '',
        workerUrl: '',
      ),
      isTrue,
    );
    expect(
      workerHostMatchesChat(
        mouthType: 'openRouter',
        mouthUrl: kNanoGptApiV1,
        workerType: 'openRouter',
        workerUrl: kNanoGptApiV1,
      ),
      isTrue,
    );
    expect(
      workerHostMatchesChat(
        mouthType: 'openRouter',
        mouthUrl: kNanoGptApiV1,
        workerType: 'openRouter',
        workerUrl: kOpenRouterApiV1,
      ),
      isFalse,
    );
  });

  test('second key only when host differs and vault is empty', () {
    expect(
      workerShowsApiKeyField(
        sameHost: true,
        workerKind: RemoteProviderKind.openRouter,
        vaultHasKey: false,
      ),
      isFalse,
    );
    expect(
      workerShowsApiKeyField(
        sameHost: false,
        workerKind: RemoteProviderKind.openRouter,
        vaultHasKey: true,
      ),
      isFalse,
    );
    expect(
      workerShowsApiKeyField(
        sameHost: false,
        workerKind: RemoteProviderKind.openRouter,
        vaultHasKey: false,
      ),
      isTrue,
    );
  });

  testWidgets('H2 Same as chat hides extras', (tester) async {
    await _pump(tester, storage: _Store());

    expect(find.text('Realism evals'), findsOneWidget);
    expect(find.text('Worker backend'), findsNothing);
    expect(find.byKey(const Key('side-jobs-same-as-chat')), findsOneWidget);
    expect(find.byType(RemoteProviderBar), findsNothing);
    expect(find.byType(RemoteModelPickerField), findsNothing);
    expect(find.byKey(const Key('side-jobs-worker-url')), findsNothing);
    expect(find.byKey(const Key('side-jobs-worker-key')), findsNothing);
    expect(find.text('Browse models'), findsNothing);
    expect(find.text('Realism evals use the chat host above.'), findsOneWidget);
  });

  testWidgets('H3 same host shows model picker only', (tester) async {
    final storage = _Store();
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kNanoGptApiV1);
    await storage.setWorkerRemoteModelName('z-ai/glm-5.3');
    await _pump(tester, storage: storage);

    expect(find.byType(RemoteModelPickerField), findsOneWidget);
    expect(find.text('Refresh Models'), findsOneWidget);
    expect(find.text('Browse models'), findsNothing);
    expect(find.byKey(const Key('side-jobs-worker-url')), findsNothing);
    expect(find.byKey(const Key('side-jobs-worker-key')), findsNothing);
    expect(find.text('Worker API key'), findsNothing);
    expect(find.text('Worker API URL'), findsNothing);
  });

  testWidgets('H4 different host shows key when vault is empty', (
    tester,
  ) async {
    final storage = _Store();
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kOpenRouterApiV1);
    await _pump(tester, storage: storage);

    expect(find.byKey(const Key('side-jobs-worker-key')), findsOneWidget);
    expect(find.byKey(const Key('side-jobs-worker-url')), findsNothing);
    expect(find.byType(RemoteModelPickerField), findsOneWidget);
    expect(find.text('Refresh Models'), findsOneWidget);
    expect(find.text('Browse models'), findsNothing);
  });

  testWidgets('H4 different host with saved key hides the key field', (
    tester,
  ) async {
    final storage = _Store();
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kOpenRouterApiV1);
    await storage.setRemoteApiKeyFor(kOpenRouterApiV1, 'sk-or-saved');
    await _pump(tester, storage: storage);

    expect(find.byKey(const Key('side-jobs-worker-key')), findsNothing);
    expect(find.byKey(const Key('side-jobs-saved-key-hint')), findsOneWidget);
  });

  testWidgets('H5 dual-local banner still shows when refused', (tester) async {
    final storage = _Store(backendType: 'kobold', remoteApiUrl: '');
    await storage.setWorkerBackendType('omlx');
    await storage.setWorkerRemoteApiUrl(kOmlxApiV1);
    await _pump(
      tester,
      storage: storage,
      llm: _Llm(activeBackend: BackendType.kobold, refused: true),
    );

    expect(find.byKey(const Key('worker-dual-local-banner')), findsOneWidget);
    expect(find.text(kWorkerDualLocalMessage), findsOneWidget);
  });

  testWidgets('H2 tapping Same as chat hides the host row', (tester) async {
    final storage = _Store();
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kOpenRouterApiV1);
    await _pump(tester, storage: storage);
    expect(find.byType(RemoteProviderBar), findsOneWidget);

    await tester.tap(find.byKey(const Key('side-jobs-same-as-chat')));
    await tester.pumpAndSettle();

    expect(storage.workerBackendType, isEmpty);
    expect(find.byType(RemoteProviderBar), findsNothing);
    expect(find.byType(RemoteModelPickerField), findsNothing);
  });
}
