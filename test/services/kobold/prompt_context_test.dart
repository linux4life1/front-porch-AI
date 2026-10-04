// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A chat set to a longer context than the app's KoboldCpp runs with must
// not build a prompt that long: KoboldCpp would cut it from the start,
// character card first, without a word. Every prompt budget goes through
// resolveContextSize or BackendSettings.promptContext.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';

import '../../golden/support/fakes_storage.dart';

void main() {
  late FakeStorageService storage;

  setUp(() async {
    storage = FakeStorageService();
    await storage.backendSettings.setBackendType('kobold');
    await storage.backendSettings.setContextSize(16384);
  });

  tearDown(() => storage.dispose());

  test('a chat asking for more than the engine holds gets what it holds', () {
    storage.backendSettings.setEngineContextSize(16384);
    final chat = ChatGenerationSettings(contextSize: 32768);
    expect(chat.resolveContextSize(storage), 16384);
  });

  test('a chat asking for less keeps its own', () {
    storage.backendSettings.setEngineContextSize(16384);
    final chat = ChatGenerationSettings(contextSize: 8192);
    expect(chat.resolveContextSize(storage), 8192);
  });

  test('before the app has started KoboldCpp the setting stands', () {
    expect(
      ChatGenerationSettings(contextSize: 32768).resolveContextSize(storage),
      32768,
    );
    expect(ChatGenerationSettings().resolveContextSize(storage), 16384);
  });

  test('a remote backend is not held to the local engine', () async {
    storage.backendSettings.setEngineContextSize(16384);
    await storage.backendSettings.setBackendType('openRouter');
    expect(
      ChatGenerationSettings(contextSize: 65536).resolveContextSize(storage),
      65536,
    );
    expect(storage.backendSettings.promptContext(65536), 65536);
  });
}
