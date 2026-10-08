// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A reload of chat that KoboldCpp could not load, where the old model is kept
// running (see kobold_reload_puts_choice_back_test): the failed check leaves
// what runs unknown, and putting the choice back writes the record again. The
// tool-calling pill and its automatic test name the model by what the engine
// is known to run, so the record alone is not enough: the engine has to be
// known to run that model again. Without it the pill sits on "not tested" and
// nothing is asked for the rest of the session.
//
// The engine is a real HTTP server on loopback and the app's own reload, swap
// and put-back code run against it. Only the model that answers the
// tool-calling question is scripted.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/local_model_key.dart';

import '../../helpers/chat_db_teardown.dart';
import 'loopback_kobold.dart';

/// The model that answers the tool-calling question, and how often it was
/// asked. It is not ready until [ready] says so.
class _Answering extends LLMService {
  bool ready = false;
  int asked = 0;

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
  late Directory root;
  late KoboldRig rig;
  late AppDatabase db;
  late ChatService chat;
  late _Answering answering;
  late String oldModel;
  late String staged;

  /// What the app calls the model in the verdicts it keeps.
  String keyOf(String path) => 'Scripted|||${localModelKey(path)}';

  /// A file a fresh start would refuse: not a GGUF.
  String broken(String name) => (File(
    p.join(root.path, name),
  )..writeAsBytesSync('XXXX'.codeUnits + List.filled(32, 0))).path;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('fpai kept tools');
    rig = await KoboldRig.start(root);
    oldModel = rig.gguf('old.gguf');
    final oldPreset = rig.preset('Old.kcpps', {'contextsize': 8192}).path;
    final backend = rig.storage.backendSettings;
    await backend.setLastUsedModelPath(oldModel);
    await backend.setActiveKcppsPath(oldPreset);
    await rig.storage.presetSettings.setModelPreset(oldModel, oldPreset);
    // KoboldCpp goes back to this when a config does not load.
    rig.engine.model = rig.engine.startupModel = 'koboldcpp/old';

    // Chat runs the old model, as a start leaves it: the process up, the
    // config it was started with staged and noted as the one loaded.
    staged = jsonEncode({'model_param': oldModel, 'contextsize': 8192});
    File(
      p.join(rig.engine.adminDir, kStagedChatConfig),
    ).writeAsStringSync(staged);
    rig.kobold.debugMarkProcessRunning();
    rig.kobold.noteAdminLoadedPair(modelPath: oldModel, kcppsPath: oldPreset);
    rig.kobold.noteResident(staged);
    await rig.kobold.waitUntilReadyAfterSwap(attempts: 1);

    db = AppDatabase.forTesting();
    answering = _Answering();
    chat =
        ChatService(
            rig.kobold,
            UserPersonaService(db),
            rig.storage,
            WorldRepository(rig.storage, db),
          )
          ..setDatabase(db)
          ..setLLMProvider(rig.provider)
          ..testLlmServiceOverride = answering
          ..testIsLocalOverride = true;
  });

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    await rig.close();
    root.deleteSync(recursive: true);
  });

  test('after a refused reload that keeps the old model, the pill names that '
      'model and its automatic test asks it', () async {
    expect(chat.debugEvalBackendIdentity, keyOf(oldModel));
    rig.engine.failing.add(kStagedChatConfig);
    await selectKoboldModel(rig.storage, broken('new.gguf'));

    final result = await rig.provider.reloadChatKobold();

    expect(result?.refusal, contains('The previous one is still running'));
    expect(rig.engine.model, 'koboldcpp/old');
    expect(rig.storage.backendSettings.lastUsedModelPath, oldModel);
    expect(
      chat.debugEvalBackendIdentity,
      keyOf(oldModel),
      reason: 'KoboldCpp has said it runs the old model: it is known again',
    );
    expect(rig.kobold.answeringModelPath, oldModel);
    expect(answering.asked, 0, reason: 'nothing could be asked until now');

    // The model answers again, and the next notification finds a known model
    // nobody has asked yet.
    answering.ready = true;
    await rig.storage.backendSettings.setRemoteModelName('some/model');
    await _settle();

    expect(answering.asked, 1, reason: 'asked on its own, once');
    expect(chat.toolCallSupport, ToolCallSupport.supported);
    expect(rig.storage.toolVerdictSettings.verdictFor(keyOf(oldModel)), isTrue);
  });

  test('with no staged chat config to name, nothing is guessed: what runs '
      'stays unknown, and nothing is asked on its own', () async {
    File(p.join(rig.engine.adminDir, kStagedChatConfig)).deleteSync();
    rig.engine.failing.add(kStagedChatConfig);
    await selectKoboldModel(rig.storage, broken('new.gguf'));

    final result = await rig.provider.reloadChatKobold();

    expect(result?.refusal, contains('The previous one is still running'));
    expect(chat.debugEvalBackendIdentity, contains('(unknown)'));
    answering.ready = true;
    await rig.storage.backendSettings.setRemoteModelName('some/model');
    await _settle();
    expect(answering.asked, 0);
  });
}
