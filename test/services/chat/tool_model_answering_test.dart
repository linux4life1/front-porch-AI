// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A tool-calling verdict is filed under the model that GAVE the answer, not
// under the model the app has been told to use. Picking another model changes
// the app's record at once, while the engine goes on answering with the first
// one until a reload has been asked for, carried out and read back; a ping in
// that gap asks the old weights, and filing their answer under the new model
// would keep a wrong verdict across restarts. The real KoboldService is driven
// through its own state methods here (a start, a swap that is read back, one
// that is not); only the model that answers the question is scripted.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/system_role_probe.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/utils/local_model_key.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/chat_db_teardown.dart';

/// The model that answers the tool-calling question, and how often it was asked.
class _Answering extends LLMService {
  int asked = 0;

  @override
  Stream<String> generateStream(GenerationParams params) =>
      const Stream.empty();

  @override
  bool get isReady => true;

  @override
  String get backendName => 'Scripted';

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    asked++;
    return const LlmToolResponse(
      calls: [
        LlmToolCall(name: 'report_ping', arguments: {'ok': true}),
      ],
      text: '',
    );
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
  late _Answering answering;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fpai tool answering');
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
    answering = _Answering();
    chat =
        ChatService(
            kobold,
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setLLMProvider(provider)
          ..testLlmServiceOverride = answering
          ..testIsLocalOverride = true;
  });

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    provider.dispose();
    kobold.dispose();
    await dir.delete(recursive: true);
  });

  File model(String name, int bytes) =>
      File(p.join(dir.path, name))..writeAsBytesSync(List.filled(bytes, 1));

  /// KoboldCpp started, and its model read back as loaded.
  Future<void> startWith(File file) async {
    kobold.debugMarkProcessRunning();
    kobold.noteAdminLoadedPair(modelPath: file.path, kcppsPath: '');
    kobold.noteResident('config of ${p.basename(file.path)}');
    await kobold.debugMarkModelReady();
    await _settle();
  }

  /// What the engine does when asked for another model: it forgets what it
  /// had loaded and starts loading, is asked for [file], and answers again.
  Future<void> reloadAsked(File file) async {
    kobold.markModelLoading('Loading ${p.basename(file.path)}...');
    kobold.noteAdminLoadedPair(modelPath: file.path, kcppsPath: '');
    await kobold.debugMarkModelReady();
    await _settle();
  }

  /// The eval identity of a local model: the backend that answers (the
  /// scripted one here), no host, no remote name, and the model's key.
  String keyOf(File file) => 'Scripted|||${localModelKey(file.path)}';

  test('a model picked while another is loaded is not what answers: the '
      'answer is filed under the loaded one', () async {
    final alpha = model('alpha.gguf', 2048);
    final beta = model('beta.gguf', 4096);
    await startWith(alpha);
    expect(answering.asked, 1, reason: 'the loaded model was tested once');

    // The Local model card's pick: the record moves at once, and nothing has
    // been reloaded yet.
    await storage.backendSettings.setLastUsedModelPath(beta.path);
    await _settle();

    expect(chat.debugEvalBackendIdentity, keyOf(alpha));
    expect(
      storage.toolVerdictSettings.verdictFor(keyOf(beta)),
      isNull,
      reason: 'beta has not been asked a thing',
    );
    expect(storage.toolVerdictSettings.verdictFor(keyOf(alpha)), isTrue);
    expect(answering.asked, 1, reason: 'alpha is known: nobody is asked again');
  });

  test('a model whose load is still being read back is not asked, and is as '
      'soon as it is confirmed', () async {
    final alpha = model('alpha.gguf', 2048);
    final beta = model('beta.gguf', 4096);
    await startWith(alpha);
    expect(answering.asked, 1);

    // beta is picked, and the engine is asked for it.
    await storage.backendSettings.setLastUsedModelPath(beta.path);
    // The engine says it is ready, and has not yet been checked to be running
    // what it was asked for (a reload it cannot do goes back, and says so).
    await reloadAsked(beta);
    expect(answering.asked, 1, reason: 'nobody asked: unconfirmed');
    expect(chat.debugEvalBackendIdentity, contains('(unknown)'));
    expect(storage.toolVerdictSettings.verdictFor(keyOf(beta)), isNull);

    kobold.noteResident('config of beta.gguf'); // read back: it is beta
    await _settle();

    expect(chat.debugEvalBackendIdentity, keyOf(beta));
    expect(answering.asked, 2, reason: 'confirmed: beta is asked, once');
    expect(storage.toolVerdictSettings.verdictFor(keyOf(beta)), isTrue);
  });

  test('after a reload that did not load what it asked for nothing is filed '
      'under the model it asked for', () async {
    final alpha = model('alpha.gguf', 2048);
    final beta = model('beta.gguf', 4096);
    await startWith(alpha);

    await storage.backendSettings.setLastUsedModelPath(beta.path);
    await reloadAsked(beta);
    // KoboldCpp went back to what it had: the read-back says so.
    kobold.noteResident('');
    kobold.forgetAdminLoadedPair();
    await _settle();

    expect(chat.debugEvalBackendIdentity, contains('(unknown)'));
    expect(answering.asked, 1, reason: 'unknown model: not asked on its own');

    // A tap on the pill still asks whatever answers, and the answer is shown
    // but never kept: it belongs to no model anybody can name.
    await chat.testToolCalling();
    expect(answering.asked, 2);
    expect(chat.toolCallSupport, ToolCallSupport.supported);
    expect(storage.toolVerdictSettings.verdictFor(keyOf(beta)), isNull);
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(
      storage.toolVerdictSettings.k('tool_verdicts'),
    );
    expect(saved, isNot(contains('(unknown)')));
  });

  test('while a model is loading nothing can be asked, and the pill shows what '
      'is known of the model being loaded', () async {
    final alpha = model('alpha.gguf', 2048);
    final beta = model('beta.gguf', 4096);
    await startWith(alpha);
    // What an earlier run kept for beta.
    storage.toolVerdictSettings.remember(keyOf(beta), false);

    kobold.markModelLoading('Loading beta.gguf...');
    kobold.noteAdminLoadedPair(modelPath: beta.path, kcppsPath: '');
    await _settle();

    expect(chat.debugEvalBackendIdentity, keyOf(beta));
    expect(chat.toolCallSupport, ToolCallSupport.unsupported);
    expect(answering.asked, 1, reason: 'a model that is loading is not asked');
  });

  test(
    'with no engine running the identity names the model that will load',
    () async {
      final beta = model('beta.gguf', 4096);
      await storage.backendSettings.setLastUsedModelPath(beta.path);
      expect(chat.debugEvalBackendIdentity, keyOf(beta));
    },
  );

  test('a reload that was asked for and not read back leaves the running '
      "model's name alone; the read-back is what renames it", () async {
    final alpha = model('alpha.gguf', 2048);
    await startWith(alpha);
    final named = chat.debugEvalBackendIdentity;
    expect(named, keyOf(alpha));

    // Another quant is put at the same path while the first one runs.
    alpha.writeAsBytesSync(List.filled(4096, 1));
    // The engine is asked to load it; nothing has read the answer back, and
    // what runs is still the old weights.
    kobold.noteAdminLoadedPair(modelPath: alpha.path, kcppsPath: '');
    await _settle();
    expect(chat.debugEvalBackendIdentity, named);

    // Read back as running what is at the path now: it is the new file.
    kobold.noteResident('config of the new alpha.gguf');
    await _settle();
    expect(chat.debugEvalBackendIdentity, isNot(named));
    expect(chat.debugEvalBackendIdentity, keyOf(alpha));
  });
}
