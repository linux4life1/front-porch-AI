// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// First-launch rework: boot must NEVER download the KoboldCpp engine on its
// own. A genuine first launch (no engine, no recorded choice) shows the
// one-time choice; picking the managed engine (or "Not sure") starts a
// BACKGROUND fetch; picking "own backend" flips backendType and never
// downloads; remote users and already-installed engines resolve the choice
// silently.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/setup_service.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';

class FakeStorageService extends ChangeNotifier implements StorageService {
  FakeStorageService({String type = 'kobold', bool choiceDone = false}) {
    backendSettings.initializeBase(null, notifyListeners);
    backendSettings.setBackendType(type);
    backendSettings.setBackendChoiceDone(choiceDone);
    backendSettings.setAutostartBackend(false);
  }

  @override
  final BackendSettings backendSettings = BackendSettings();

  @override
  Future<void> get initialized => Future.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBackendManager extends ChangeNotifier implements BackendManager {
  FakeBackendManager({this.installedPath});

  String? installedPath;
  int ensureCalls = 0;
  int downloadCalls = 0;

  @override
  bool get isIntelMac => false;

  @override
  String? get backendPath => installedPath;

  @override
  Future<void> checkBackendAvailability() async {}

  @override
  Future<void> ensureEngineInstalled() async {
    ensureCalls++;
  }

  @override
  Future<void> downloadBackend() async {
    downloadCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeKoboldService extends ChangeNotifier implements KoboldService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  SetupService build(FakeStorageService storage, FakeBackendManager backend) =>
      SetupService(storage, backend, FakeKoboldService());

  test(
    'first launch (no engine, no choice) shows the choice — no download',
    () async {
      final storage = FakeStorageService();
      final backend = FakeBackendManager();
      final setup = build(storage, backend);

      await setup.runAutoSetup();

      expect(setup.currentStep, SetupStep.firstRunChoice);
      expect(backend.downloadCalls, 0);
      expect(backend.ensureCalls, 0);
      expect(storage.backendSettings.backendChoiceDone, isFalse);
    },
  );

  test(
    'choosing the managed engine starts a background fetch and dismisses',
    () async {
      final storage = FakeStorageService();
      final backend = FakeBackendManager();
      final setup = build(storage, backend);
      await setup.runAutoSetup();

      await setup.chooseManagedEngine();

      expect(setup.currentStep, SetupStep.complete);
      expect(storage.backendSettings.backendChoiceDone, isTrue);
      expect(backend.ensureCalls, 1);
    },
  );

  test(
    'choosing an own backend never downloads and flips backendType',
    () async {
      final storage = FakeStorageService();
      final backend = FakeBackendManager();
      final setup = build(storage, backend);
      await setup.runAutoSetup();

      await setup.chooseOwnBackend();

      expect(setup.currentStep, SetupStep.complete);
      expect(storage.backendSettings.backendChoiceDone, isTrue);
      expect(storage.backendSettings.backendType, 'openRouter');
      expect(backend.ensureCalls, 0);
      expect(backend.downloadCalls, 0);
    },
  );

  test(
    'choice made but binary missing: background re-acquire, no blocking',
    () async {
      final storage = FakeStorageService(choiceDone: true);
      final backend = FakeBackendManager();
      final setup = build(storage, backend);

      await setup.runAutoSetup();

      expect(setup.currentStep, SetupStep.complete);
      expect(backend.ensureCalls, 1);
      expect(backend.downloadCalls, 0); // ensure is the only acquisition path
    },
  );

  test(
    'remote backend skips everything and records the implicit choice',
    () async {
      final storage = FakeStorageService(type: 'openRouter');
      final backend = FakeBackendManager();
      final setup = build(storage, backend);

      await setup.runAutoSetup();

      expect(setup.currentStep, SetupStep.complete);
      expect(storage.backendSettings.backendChoiceDone, isTrue);
      expect(backend.ensureCalls, 0);
    },
  );

  test('an installed engine IS the choice — no first-run ask', () async {
    final storage = FakeStorageService();
    final backend = FakeBackendManager(installedPath: '/bin/koboldcpp');
    final setup = build(storage, backend);

    await setup.runAutoSetup();

    expect(setup.currentStep, SetupStep.complete);
    expect(storage.backendSettings.backendChoiceDone, isTrue);
    expect(backend.ensureCalls, 0);
    expect(backend.downloadCalls, 0);
  });
}
