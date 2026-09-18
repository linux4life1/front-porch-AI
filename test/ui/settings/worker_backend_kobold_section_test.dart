// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/worker_backend_section.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

import '../../golden/support/fakes.dart';
import '../../golden/support/fakes_storage.dart';

class _Store extends FakeStorageService {
  _Store() {
    _backend.initializeBase(null, notifyListeners);
    _backend.setBackendType('kobold');
    _backend.setLastUsedModelPath('/models/mouth.gguf');
  }

  final BackendSettings _backend = BackendSettings();

  @override
  BackendSettings get backendSettings => _backend;
}

class _Llm extends FakeLLMProvider {
  _Llm() : super(activeBackend: BackendType.kobold);
}

class _Mgr extends ChangeNotifier implements BackendManager {
  @override
  bool get isIntelMac => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Kobold worker slot shows a dedicated GGUF picker', (
    tester,
  ) async {
    final storage = _Store();
    await storage.setWorkerBackendType('kobold');
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<LLMProvider>.value(value: _Llm()),
          ChangeNotifierProvider<BackendManager>.value(value: _Mgr()),
        ],
        child: const MaterialApp(home: Scaffold(body: WorkerBackendSection())),
      ),
    );

    expect(find.byType(WorkerKoboldModelPicker), findsOneWidget);
    expect(find.byType(WorkerKoboldKcppsPicker), findsOneWidget);
    expect(find.byKey(const Key('side-jobs-kobold-model')), findsOneWidget);
    expect(find.byKey(const Key('side-jobs-kobold-kcpps')), findsOneWidget);
    expect(find.byType(VisionProjectorField), findsNothing);
    expect(find.textContaining('Same as Models tab'), findsOneWidget);
    expect(find.textContaining('mouth.gguf'), findsWidgets);
  });
}
