// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The ROCm flash attention fallback is for the first reply only (maintainer
// ruling K, 2026-10-05, design decision 10). When the ROCm build dies in the
// middle of a reply with flash attention on, and no reply has finished since
// that KoboldCpp process started, the machine is marked, Flash Attention is
// switched off in Settings and the engine is started again without it. Once
// a reply has finished (KoboldCpp's "CtxLimit:" line), flash attention works
// on this machine, so a later crash is something else: it only stops, with
// its reason, and nothing is marked or switched off. Each process starts
// with no reply finished.
//
// The engine here is a real process, a shell script that prints what
// KoboldCpp prints, run by the real KoboldCpp service.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_admin_swap.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:path/path.dart' as p;

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

/// A finished reply, as KoboldCpp prints it.
const _replyDone =
    '[09:59:50] CtxLimit:290/16384, Init:0.15s, Processed:240 in 34.03s '
    '(7.05T/s), Generated:50/64 in 2.10s (23.81T/s), Total:36.13s';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  group('with the real service and a ROCm launch with flash attention on', () {
    late StorageService storage;
    late KoboldService kobold;
    late Directory dir;
    late String engine;
    late String model;

    setUp(() async {
      storage = await createStorageService();
      await storage.backendSettings.setBackendType('kobold');
      await storage.backendSettings.setUseRocm(true);
      await storage.backendSettings.setFlashAttentionEnabled(true);
      kobold = KoboldService(storage);
      dir = Directory.systemTemp.createTempSync('fpai_rocm_first_reply_');
      engine = p.join(dir.path, 'koboldcpp');
      // Loads, says it is ready, says it finished a reply when told to, and
      // dies in the middle of the next prompt once told to.
      File(engine).writeAsStringSync('''
#!/bin/sh
trap 'exit 0' TERM
here=\$(dirname "\$0")
echo "Load Text Model OK: True"
echo "Please connect to custom endpoint at http://localhost:5999"
if [ -f "\$here/replied" ]; then echo "$_replyDone"; fi
while [ ! -f "\$here/crash" ]; do sleep 0.2; done
echo "Processing Prompt [BATCH] (512 / 2156 tokens)"
sleep 0.5
exit 1
''');
      await Process.run('chmod', ['755', engine]);
      model = p.join(dir.path, 'model.gguf');
      File(model).writeAsBytesSync([...'GGUF'.codeUnits, 3, 0, 0, 0]);
      await storage.backendSettings.setLastUsedModelPath(model);
    });

    tearDown(() async {
      await kobold.stopKobold();
      kobold.dispose();
      final admin = koboldAdminDirFor(storage);
      if (FileSystemEntity.isFileSync(admin)) File(admin).deleteSync();
      dir.deleteSync(recursive: true);
    });

    final skipOnWindows = Platform.isWindows
        ? 'the engine here is a shell script'
        : false;

    int count(String text) => kobold.logs.where((l) => l.contains(text)).length;

    Future<void> until(bool Function() done, String what) async {
      for (var i = 0; i < 150 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(done(), isTrue, reason: 'waited for: $what');
    }

    /// Starts the engine and waits until it has said it is ready.
    Future<void> start() async {
      final started = await kobold.launch(
        engine,
        pickedModel: model,
        port: 5999,
      );
      expect(started.started, isTrue, reason: started.message);
      await until(() => kobold.modelReady, 'the engine to be ready');
    }

    void crash() => File(p.join(dir.path, 'crash')).createSync();

    test('a crash on the first reply marks the machine, switches flash '
        'attention off and starts the engine again', () async {
      await start();

      crash();
      await until(
        () => storage.backendSettings.rocmFlashAttentionFailed,
        'the machine to be marked',
      );
      await until(
        () => count('Process exited with code') == 2,
        'the second start to end too',
      );

      expect(storage.backendSettings.flashAttentionEnabled, isFalse);
      expect(count('Starting Koboldcpp (PID'), 2, reason: 'started again once');
    }, skip: skipOnWindows);

    test('a crash after a reply finished only stops, with its reason: nothing '
        'is marked or switched off, and it is not started again', () async {
      File(p.join(dir.path, 'replied')).createSync();
      await start();

      crash();
      await until(
        () => count('Process exited with code') == 1,
        'the engine to end',
      );
      // The retry, had there been one, waits a second before it starts.
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(kobold.lastFailure?.kind, KoboldFailureKind.diedWhileAnswering);
      expect(count('stopped while answering, without saying why'), 1);
      expect(storage.backendSettings.rocmFlashAttentionFailed, isFalse);
      expect(storage.backendSettings.flashAttentionEnabled, isTrue);
      expect(count('Starting Koboldcpp (PID'), 1, reason: 'not started again');
    }, skip: skipOnWindows);

    test('each process starts with no reply finished: after one that '
        'finished a reply was stopped, a new one that crashes on its first '
        'reply falls back', () async {
      File(p.join(dir.path, 'replied')).createSync();
      await start();
      await kobold.stopKobold();
      File(p.join(dir.path, 'replied')).deleteSync();

      await start();
      crash();
      await until(
        () => storage.backendSettings.rocmFlashAttentionFailed,
        'the machine to be marked',
      );
      await until(
        () => count('Process exited with code') == 3,
        'the start after the fallback to end too',
      );

      expect(storage.backendSettings.flashAttentionEnabled, isFalse);
    }, skip: skipOnWindows);
  });
}
