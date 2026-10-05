// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The sidebar's tool-calling pill says when its answer was kept from an
// earlier run instead of asked just now, so a model that shows "supported"
// the moment a chat opens is not a mystery, and a tap is known to ask again.
// The real pill is drawn over a real chat service; only the model that answers
// the question is scripted. The same flag goes to the phone in the chat
// state's toolSupport object, which is checked here beside the words.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/chat/tool_verdict_stamp.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/system_role_probe.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/tool_calling_pill.dart';
import 'package:front_porch_ai/utils/local_model_key.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/chat_db_teardown.dart';

const _savedNote = 'Saved from an earlier test. Tap to ask again.';
const _freshYes = 'Realism, Journal & Growth use native tool calls';
const _freshNo = 'This model uses the text fallback — still works';

const _calls = LlmToolResponse(
  calls: [
    LlmToolCall(name: 'report_ping', arguments: {'ok': true}),
  ],
  text: '',
);
const _prose = LlmToolResponse(calls: [], text: 'Sure, here you go.');

/// The model that answers the tool-calling question.
class _Answering extends LLMService {
  int asked = 0;
  LlmToolResponse reply = _calls;

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
    return reply;
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

  /// A chat service on a local model whose earlier answer is on file: the
  /// one [reply] says, which is also what the model will say when asked.
  Future<void> open(
    WidgetTester tester, {
    required LlmToolResponse reply,
  }) async {
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('fpai pill saved');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'getApplicationDocumentsDirectory'
                ? dir.path
                : null,
          );
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      db = AppDatabase.forTesting(sameIsolate: true);
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
      answering = _Answering()..reply = reply;
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
      final file = File(p.join(dir.path, 'gemma.gguf'))
        ..writeAsBytesSync(List.filled(2048, 1));
      storage.toolVerdictSettings.remember(
        'Scripted|||${localModelKey(file.path)}',
        reply.calls.isNotEmpty,
        stamp: toolVerdictStamp(),
      );
      await storage.backendSettings.setLastUsedModelPath(file.path);
    });
    addTearDown(() async {
      await disposeChatThenCloseDb(chat, db);
      provider.dispose();
      kobold.dispose();
      await dir.delete(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: ListenableBuilder(
              listenable: chat,
              builder: (_, _) => ToolCallingPill(chatService: chat),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> tapThePill(WidgetTester tester) async {
    await tester.tap(find.byType(ToolCallingPill));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a kept "yes" says it is saved, and a tap asks the model and '
      'shows a fresh answer', (tester) async {
    await open(tester, reply: _calls);

    expect(find.text('Tool calling: supported'), findsOneWidget);
    expect(find.text(_savedNote), findsOneWidget);
    expect(find.text(_freshYes), findsNothing);
    expect(chat.toolSupportJson['state'], 'supported');
    expect(chat.toolSupportJson['saved'], isTrue);
    expect(answering.asked, 0, reason: 'nothing was asked to show this');

    await tapThePill(tester);

    expect(answering.asked, 1);
    expect(find.text('Tool calling: supported'), findsOneWidget);
    expect(find.text(_freshYes), findsOneWidget);
    expect(find.text(_savedNote), findsNothing);
    expect(chat.toolSupportJson['saved'], isFalse);
  });

  testWidgets('a kept "no" says it is saved too, and a tap shows a fresh '
      'answer', (tester) async {
    await open(tester, reply: _prose);

    expect(find.text('Tool calling: not supported'), findsOneWidget);
    expect(find.text(_savedNote), findsOneWidget);
    expect(find.text(_freshNo), findsNothing);
    expect(chat.toolSupportJson['saved'], isTrue);
    expect(answering.asked, 0);

    await tapThePill(tester);

    expect(answering.asked, 1);
    expect(find.text('Tool calling: not supported'), findsOneWidget);
    expect(find.text(_freshNo), findsOneWidget);
    expect(find.text(_savedNote), findsNothing);
    expect(chat.toolSupportJson['saved'], isFalse);
  });
}
