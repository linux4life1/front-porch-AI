// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The tool-calling check on the helper (worker) model, which Realism, the
// Journal and Growth use, and whose answer is kept across runs. A swap that
// fails before the helper model is reached asked nothing. It was read as "this
// model cannot do tools", the same as an answer in prose, because only network
// errors were left out, and the "no" was kept.
//
// The real chat service, provider, swap occupancy, tester, probe and verdict
// store run; only the helper model that answers, and the swap's failure, are
// scripted.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/system_role_probe.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/local_model_key.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/chat_db_teardown.dart';

const _calls = LlmToolResponse(
  calls: [
    LlmToolCall(name: 'report_ping', arguments: {'ok': true}),
  ],
  text: '',
);
const _prose = LlmToolResponse(calls: [], text: 'Sure, here you go.');

/// The helper model that answers the tool-calling question.
class _Worker extends LLMService {
  bool ready = false;
  int asked = 0;
  LlmToolResponse reply = _calls;

  /// What asking it throws, when it refuses the request itself.
  Object? failWith;

  @override
  Stream<String> generateStream(GenerationParams params) =>
      const Stream.empty();

  @override
  bool get isReady => ready;

  @override
  String get backendName => 'Scripted';

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    asked++;
    if (failWith != null) throw failWith!;
    return reply;
  }
}

/// One side of the swap; [restore] fails the way a load that did not take
/// does, when [failWith] says so.
class _Host implements GpuSwapHost {
  _Host(this.label, {this.failWith});

  @override
  final String label;
  final Object? failWith;

  @override
  Future<void> unload() async {}

  @override
  Future<void> restore() async {
    if (failWith != null) throw failWith!;
  }
}

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase db;
  late StorageService storage;
  late KoboldService kobold;
  late LLMProvider provider;
  late ChatService chat;
  late _Worker worker;
  late File running;
  late File helper;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fpai worker verdict');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    db = AppDatabase.forTesting();
    storage = StorageService();
    await storage.initialized;
    running = File(p.join(dir.path, 'running.gguf'))
      ..writeAsBytesSync(List.filled(2048, 1));
    helper = File(p.join(dir.path, 'helper.gguf'))
      ..writeAsBytesSync(List.filled(4096, 1));
    await storage.backendSettings.setLastUsedModelPath(running.path);
    await storage.setWorkerBackendType('kobold');
    await storage.setWorkerKoboldModelPath(helper.path);
    kobold = KoboldService(
      storage,
      systemRoleProbe: SystemRoleProbe(retryBackoff: Duration.zero),
    )..setBaseUrl('http://127.0.0.1:1');
    provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      BackendManager(storage),
    );
    worker = _Worker();
    provider.debugWorkerService = worker;
    chat =
        ChatService(
            kobold,
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setLLMProvider(provider);
  });

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    provider.dispose();
    kobold.dispose();
    await dir.delete(recursive: true);
  });

  /// The helper's identity, which names its model by [file].
  String keyOf(File file) => 'worker|Scripted|||${localModelKey(file.path)}';

  /// The chat model is a local one that the helper's model is swapped in
  /// beside: the lane unloads it, loads the helper's model, and asks.
  void swapInHelper({Object? failWith}) {
    provider.debugGpuSwap = GpuSwapOccupancy(
      mouth: _Host('mouth'),
      worker: _Host('worker', failWith: failWith),
    );
  }

  group('a swap that fails before the helper model is reached', () {
    final failures = <String, Object>{
      'the load did not take': const KoboldSwapFailed(
        'KoboldCpp could not load helper.gguf; it went back to its startup '
        'model.',
      ),
      'the load was not done in time': const KoboldSwapTimeout(
        restarted: true,
        waited: Duration(seconds: 60),
      ),
      'the engine could not be asked': StateError(
        'Kobold admin restore missed, process still up',
      ),
    };

    for (final entry in failures.entries) {
      test('keeps nothing: ${entry.key}', () async {
        swapInHelper(failWith: entry.value);
        worker.ready = true;

        await chat.testToolCalling();
        await _settle();

        expect(chat.debugEvalBackendIdentity, keyOf(helper));
        expect(worker.asked, 0, reason: 'the helper model was never reached');
        expect(
          chat.toolCallSupport,
          ToolCallSupport.untested,
          reason: 'nothing was asked, so there is no answer',
        );
        expect(storage.toolVerdictSettings.verdictFor(keyOf(helper)), isNull);
      });
    }

    test('a helper that is reached and refuses the request is still a "no", '
        'kept', () async {
      swapInHelper();
      worker
        ..ready = true
        ..failWith = StateError('HTTP 400: this model does not support tools');

      await chat.testToolCalling();
      await _settle();

      expect(worker.asked, 1);
      expect(chat.toolCallSupport, ToolCallSupport.unsupported);
      expect(storage.toolVerdictSettings.verdictFor(keyOf(helper)), isFalse);
    });

    test('a helper that is reached and answers in prose is still a "no", '
        'kept', () async {
      swapInHelper();
      worker
        ..ready = true
        ..reply = _prose;

      await chat.testToolCalling();
      await _settle();

      expect(worker.asked, 1);
      expect(chat.toolCallSupport, ToolCallSupport.unsupported);
      expect(storage.toolVerdictSettings.verdictFor(keyOf(helper)), isFalse);
    });
  });
}
