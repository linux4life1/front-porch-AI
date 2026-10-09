// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's World from Wiki asks the host whether the chat model can use
// tools, and the host answers from chat's own tool check (the sidebar's Tool
// calling pill), not from the model's file name: not running yet, checking,
// tested and failed, or passed. Scout refuses with the same plain words until
// the check passed. A helper model configured for chat changes nothing: the
// wizard's model is asked by the same ping, and the helper's answer is never
// borrowed for it.
//
// The real facade, chat service, provider, tester and probe run; only the
// models that answer the tool-calling question are scripted, and their answer
// is the input (a tool call, or words), never the gate's verdict.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/system_role_probe.dart';
import 'package:front_porch_ai/services/web/facade/world_from_wiki_facade.dart';
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

/// A model whose answer to the tool-calling question waits on [answer].
class _Model extends LLMService {
  _Model(this.backendName);

  bool ready = false;
  int asked = 0;
  Completer<LlmToolResponse> answer = Completer();

  @override
  final String backendName;

  @override
  Stream<String> generateStream(GenerationParams params) =>
      const Stream.empty();

  @override
  bool get isReady => ready;

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) {
    asked++;
    return answer.future;
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
  late _Model model;
  late WorldFromWikiFacade facade;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fpai wiki tools web');
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
    model = _Model('Scripted');
    chat =
        ChatService(
            kobold,
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setLLMProvider(provider)
          ..testLlmServiceOverride = model
          ..testIsLocalOverride = true;
    final file = File(
      p.join(dir.path, 'TheDrummer_Orion-26B-A4B-v1-IQ4_XS.gguf'),
    )..writeAsBytesSync(List.filled(2048, 1));
    await storage.backendSettings.setLastUsedModelPath(file.path);
    facade = WorldFromWikiFacade(provider, storage, null, chat);
  });

  tearDown(() async {
    if (!model.answer.isCompleted) model.answer.complete(_prose);
    await _settle();
    await disposeChatThenCloseDb(chat, db);
    provider.dispose();
    kobold.dispose();
    await dir.delete(recursive: true);
  });

  Future<String> gate() async => (await facade.status())['toolsGate'] as String;

  Future<Map<String, dynamic>> scout() =>
      facade.scout({'wikiUrl': 'https://bleach.fandom.com', 'name': 'Quay'});

  test('not running: the phone is told to start the model first', () async {
    expect(await gate(), 'notRunning');
    expect((await facade.status())['toolsAdvertised'], isFalse);
    final refused = await scout();
    expect(refused['ok'], isFalse);
    expect(refused['error'], contains('has to be running first'));
    expect(refused['error'], contains('Models page'));
    expect(model.asked, 0);
  });

  test('running: chat\'s check asks the model; a tool call opens the '
      'wizard', () async {
    model.ready = true;
    await facade.status();
    await _settle();
    expect(model.asked, 1);
    expect(await gate(), 'checking');

    model.answer.complete(_calls);
    await _settle();

    expect(chat.toolCallSupport, ToolCallSupport.supported);
    expect(await gate(), 'ready');
    expect((await facade.status())['toolsAdvertised'], isTrue);
  });

  test('tested and answered in words: failed, and Scout says why', () async {
    model.ready = true;
    await facade.status();
    await _settle();
    model.answer.complete(_prose);
    await _settle();

    expect(chat.toolCallSupport, ToolCallSupport.unsupported);
    expect(await gate(), 'failed');
    final refused = await scout();
    expect(refused['ok'], isFalse);
    expect(
      refused['error'],
      startsWith(
        "This model was tested and didn't answer the tool-calling check "
        "correctly, so it can't be used for World from Wiki.",
      ),
    );
  });

  test('with a helper model configured, the wizard\'s own model is asked '
      'and a tool call opens the wizard', () async {
    final helper = _Model('Helper')..ready = true;
    chat.testWorkerLlmServiceOverride = helper;
    model.ready = true;
    // The sidebar pill (which checks the helper) says "no".
    helper.answer.complete(_prose);
    await chat.testToolCalling();
    expect(chat.toolCallSupport, ToolCallSupport.unsupported);

    await facade.status();
    await _settle();
    expect(model.asked, 1, reason: "the wizard's model itself was asked");
    expect(await gate(), 'checking');
    model.answer.complete(_calls);
    await _settle();

    expect(await gate(), 'ready', reason: "the helper's no is not borrowed");
  });

  test('with a helper model configured, Check now asks the wizard\'s model '
      'again', () async {
    final helper = _Model('Helper')..ready = true;
    chat.testWorkerLlmServiceOverride = helper;
    model.ready = true;
    // The sidebar pill (which checks the helper) says "yes".
    helper.answer.complete(_calls);
    await chat.testToolCalling();
    expect(chat.toolCallSupport, ToolCallSupport.supported);

    await facade.status();
    await _settle();
    model.answer.complete(_prose);
    await _settle();
    expect(await gate(), 'failed', reason: "the helper's yes is not borrowed");

    model.answer = Completer()..complete(_calls);
    final after = await facade.testTools();

    expect(model.asked, 2);
    expect(after['toolsGate'], 'ready');
  });

  test('a model that passed and has since stopped is not ready', () async {
    model.ready = true;
    await facade.status();
    await _settle();
    model.answer.complete(_calls);
    await _settle();
    expect(await gate(), 'ready');

    model.ready = false;

    expect(chat.toolCallSupport, ToolCallSupport.supported);
    expect(await gate(), 'notRunning');
  });
}
