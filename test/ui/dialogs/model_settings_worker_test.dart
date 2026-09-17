// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/ui/dialogs/model_settings_dialog.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/worker_backend_section.dart';
import 'package:front_porch_ai/ui/settings/widgets/remote_model_picker_field.dart';
import 'package:front_porch_ai/ui/settings/widgets/remote_provider_bar.dart';

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

Future<void> _pump(WidgetTester tester, {required _Store storage}) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final resolvedLlm = FakeLLMProvider(activeBackend: BackendType.openRouter);
  final mgr = _Mgr();
  addTearDown(() {
    storage.dispose();
    resolvedLlm.dispose();
    mgr.dispose();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<StorageService>.value(value: storage),
        ChangeNotifierProvider<LLMProvider>.value(value: resolvedLlm),
        ChangeNotifierProvider<BackendManager>.value(value: mgr),
      ],
      child: const MaterialApp(home: Material(child: ModelSettingsDialog())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dialog shows Realism evals under the chat stack (H0)', (
    tester,
  ) async {
    await _pump(tester, storage: _Store());

    expect(find.byType(WorkerBackendSection), findsOneWidget);
    expect(find.text('Realism evals'), findsOneWidget);
    expect(find.byKey(const Key('side-jobs-same-as-chat')), findsOneWidget);
    expect(find.text('Worker backend'), findsNothing);

    final mouthModel = tester.getTopLeft(find.text('Model').first);
    final realism = tester.getTopLeft(find.text('Realism evals'));
    expect(
      realism.dy > mouthModel.dy,
      isTrue,
      reason: 'H0: Realism evals stay under the chat model, not above the key',
    );
  });

  testWidgets('same-as-chat hides the second picker', (tester) async {
    await _pump(tester, storage: _Store());

    expect(find.byKey(const Key('side-jobs-section')), findsOneWidget);
    expect(find.byType(RemoteModelPickerField), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('side-jobs-section')),
        matching: find.byType(RemoteProviderBar),
      ),
      findsNothing,
    );
    expect(find.text('Realism evals use the chat host above.'), findsOneWidget);
  });

  testWidgets('saving a worker host from the dialog writes Settings keys', (
    tester,
  ) async {
    final storage = _Store();
    await _pump(tester, storage: storage);

    await tester.ensureVisible(
      find.byKey(const Key('side-jobs-different-host')),
    );
    await tester.tap(find.byKey(const Key('side-jobs-different-host')));
    await tester.pumpAndSettle();

    final workerOpenRouter = find.descendant(
      of: find.byKey(const Key('side-jobs-section')),
      matching: find.text('OpenRouter'),
    );
    await tester.ensureVisible(workerOpenRouter);
    await tester.tap(workerOpenRouter);
    await tester.pumpAndSettle();

    expect(storage.workerBackendType, 'openRouter');
    expect(storage.workerRemoteApiUrl, kOpenRouterApiV1);

    expect(find.byType(RemoteModelPickerField), findsOneWidget);
    final workerModelField = find.descendant(
      of: find.byKey(const Key('side-jobs-model-picker')),
      matching: find.byType(TextFormField),
    );
    await tester.ensureVisible(workerModelField);
    await tester.enterText(workerModelField, 'z-ai/glm-5.3');
    await tester.pump();
    expect(storage.workerRemoteModelName, 'z-ai/glm-5.3');
  });

  testWidgets('Same as chat from the dialog clears the worker type', (
    tester,
  ) async {
    final storage = _Store();
    await storage.setWorkerBackendType('openRouter');
    await storage.setWorkerRemoteApiUrl(kOpenRouterApiV1);
    await storage.setWorkerRemoteModelName('z-ai/glm-5.3');
    await _pump(tester, storage: storage);

    expect(find.byType(RemoteModelPickerField), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('side-jobs-same-as-chat')));
    await tester.tap(find.byKey(const Key('side-jobs-same-as-chat')));
    await tester.pumpAndSettle();

    expect(storage.workerBackendType, isEmpty);
    expect(find.byType(RemoteModelPickerField), findsNothing);
  });
}
