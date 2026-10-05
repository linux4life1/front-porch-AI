// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What the chat service files its tool-calling verdicts under (the eval
// identity) names the MODEL: a local model by its file name and size, so the
// same file moved to another folder is the same model and another file at the
// same path is not; a remote model by the host and the model name. Neither
// carries the other's leftovers (the remote model name typed last week, the
// local path picked last month), or a harmless edit would send a known model
// to be tested again.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/chat_db_teardown.dart';

class _Backend extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) =>
      const Stream.empty();

  @override
  bool get isReady => false;

  @override
  String get backendName => 'Scripted';
}

/// A ready local backend that answers the tool-calling question, and counts
/// how many times it was asked.
class _Answering extends _Backend {
  int asked = 0;

  @override
  bool get isReady => true;

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fpai tool identity');
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
    chat = ChatService(
      KoboldService(storage),
      UserPersonaService(db),
      storage,
      WorldRepository(storage, db),
    )..setDatabase(db);
  });

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    await dir.delete(recursive: true);
  });

  File model(String folder, String name, int bytes) =>
      File(p.join(dir.path, folder, name))
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(bytes, 1));

  test(
    'a local model is its file name and size, wherever the file is',
    () async {
      chat
        ..testLlmServiceOverride = _Backend()
        ..testIsLocalOverride = true;
      final settings = storage.backendSettings;

      await settings.setLastUsedModelPath(model('a', 'gemma.gguf', 2048).path);
      final here = chat.debugEvalBackendIdentity;

      // The same file, moved: the same model.
      await settings.setLastUsedModelPath(model('b', 'gemma.gguf', 2048).path);
      expect(chat.debugEvalBackendIdentity, here);

      // Another file at a path of the same name: another model.
      await settings.setLastUsedModelPath(model('c', 'gemma.gguf', 4096).path);
      expect(chat.debugEvalBackendIdentity, isNot(here));

      // The remote model name typed last week is not part of a local model.
      final withName = chat.debugEvalBackendIdentity;
      await settings.setRemoteModelName('some/remote-model');
      expect(chat.debugEvalBackendIdentity, withName);
    },
  );

  test('a remote model is its host and name, whatever local model was last '
      'picked', () async {
    chat
      ..testLlmServiceOverride = _Backend()
      ..testIsLocalOverride = false;
    final settings = storage.backendSettings;
    await settings.setRemoteModelName('some/remote-model');
    final remote = chat.debugEvalBackendIdentity;

    await settings.setLastUsedModelPath(model('a', 'gemma.gguf', 2048).path);
    await settings.setLastUsedModelPath(model('b', 'qwen.gguf', 9999).path);
    expect(chat.debugEvalBackendIdentity, remote);

    await settings.setRemoteModelName('some/other-model');
    expect(chat.debugEvalBackendIdentity, isNot(remote));
  });

  test('a model the app already tried shows what was kept, to the pill and '
      'to the phone, before anything is asked', () async {
    chat
      ..testLlmServiceOverride = _Backend()
      ..testIsLocalOverride = true;
    await storage.backendSettings.setLastUsedModelPath(
      model('a', 'gemma.gguf', 2048).path,
    );
    expect(chat.toolCallSupport, ToolCallSupport.untested);

    // What an earlier run kept for this model.
    storage.toolVerdictSettings.remember(chat.debugEvalBackendIdentity, false);

    expect(chat.toolCallSupport, ToolCallSupport.unsupported);
    // The phone reads the same answer the sidebar does.
    expect(chat.toolSupportJson['state'], 'unsupported');
    expect(chat.isTestingToolSupport, isFalse);
  });

  test('a restart that finds the model file in another folder does not ask '
      'again', () async {
    // A first run: the model is tried once and the answer is kept.
    final first = _Answering();
    chat
      ..testLlmServiceOverride = first
      ..testIsLocalOverride = true;
    final before = model('before', 'gemma.gguf', 2048);
    await storage.backendSettings.setLastUsedModelPath(before.path);
    for (
      var i = 0;
      i < 20 && chat.toolCallSupport == ToolCallSupport.untested;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(first.asked, 1);
    expect(chat.toolCallSupport, ToolCallSupport.supported);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    // The app is opened again over the same preferences, and the file has
    // been moved to another folder meanwhile.
    await disposeChatThenCloseDb(chat, db);
    db = AppDatabase.forTesting();
    storage = StorageService();
    await storage.initialized;
    final second = _Answering();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..testLlmServiceOverride = second
          ..testIsLocalOverride = true;
    Directory(p.join(dir.path, 'after')).createSync();
    final after = before.renameSync(p.join(dir.path, 'after', 'gemma.gguf'));
    await storage.backendSettings.setLastUsedModelPath(after.path);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(chat.toolCallSupport, ToolCallSupport.supported);
    expect(second.asked, 0, reason: 'the same model: it is not asked again');
  });
}
