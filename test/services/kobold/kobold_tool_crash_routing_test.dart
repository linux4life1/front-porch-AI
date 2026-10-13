// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/kobold_tool_crash_guard.dart';

class _Kobold extends KoboldService {
  _Kobold(super.storage);
  @override
  Future<void> reconnectIfAlive() async {}
  @override
  Future<void> stopKobold() async {}
  @override
  bool get isReady => true;
  @override
  String get toolConfigurationKey => 'synthetic-engine-model-template';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'confirmed grammar crash bypasses native sampling at the service entry',
    () async {
      final root = await Directory.systemTemp.createTemp('fpai-tool-crash-');
      final storage = StorageService.sandbox(root.path);
      final kobold = _Kobold(storage)..setBaseUrl('http://127.0.0.1:9');
      try {
        kobold.toolCrashGuard.begin(
          kobold.toolConfigurationKey,
          reasoningOff: true,
        );
        kobold.toolCrashGuard.observe(
          '(Reasoning Budget of 0 tokens exceeded! Finishing thinking...)',
        );
        kobold.toolCrashGuard.observe(
          'gpttype_adapter.cpp: GGML_ASSERT(!grammar->stacks.empty()) failed',
        );
        final response = await kobold.generateWithTools(
          GenerationParams(prompt: 'synthetic eval', reasoningEnabled: false),
          [
            {
              'type': 'function',
              'function': {'name': 'report_result'},
            },
          ],
        );
        expect(response, isNull);
        expect(
          kobold.toolCrashGuard.nativeAttempts,
          1,
          reason: 'A quarantined eval must not enter the native sampling path.',
        );
        expect(
          kobold.toolCrashGuard.blocks(kobold.toolConfigurationKey),
          isTrue,
        );
        kobold.toolCrashGuard.clear();
        expect(
          kobold.toolCrashGuard.blocks(kobold.toolConfigurationKey),
          isFalse,
        );
      } finally {
        kobold.dispose();
        storage.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'ordinary logs, reasoning-on, and other configurations do not block native tools',
    () {
      final guard = KoboldToolCrashGuard();
      guard.begin('first', reasoningOff: true);
      guard.observe('GGML_ASSERT(!grammar->stacks.empty()) failed');
      expect(guard.blocks('first'), isFalse);
      guard.begin('second', reasoningOff: false);
      guard.observe('Reasoning Budget of 0 tokens exceeded');
      guard.observe('GGML_ASSERT(!grammar->stacks.empty()) failed');
      expect(guard.blocks('second'), isFalse);
      guard.begin('third', reasoningOff: true);
      guard.observe('Reasoning Budget of 0 tokens exceeded');
      guard.observe('GGML_ASSERT(!grammar->stacks.empty()) failed');
      expect(guard.blocks('third'), isTrue);
      expect(guard.blocks('new-template'), isFalse);
    },
  );
}
