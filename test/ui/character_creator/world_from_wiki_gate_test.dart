// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World from Wiki's Setup step reads chat's own tool check (the sidebar's
// Tool calling pill) for the model it runs on, and says in plain words why
// Next is locked: the model is not running yet, the check is asking it, or it
// was tested and failed. Only a passed check unlocks Next. A Gemma 4 fine-tune
// with a renamed file used to stay locked with no reason given, because the
// gate guessed from the file name.
//
// The real page, chat service, provider, tester and probe run; only the model
// that answers the tool-calling question is scripted, and its answer is the
// input (a tool call, or words), never the gate's verdict.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/system_role_probe.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_page.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/chat_db_teardown.dart';

const _calls = LlmToolResponse(
  calls: [
    LlmToolCall(name: 'report_ping', arguments: {'ok': true}),
  ],
  text: '',
);
const _prose = LlmToolResponse(calls: [], text: 'Sure, here you go.');

/// The chat model. Its answer to the tool-calling question waits on
/// [answer], so the test can look while it is still being asked.
class _Model extends LLMService {
  bool ready = false;
  int asked = 0;
  Completer<LlmToolResponse> answer = Completer();

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
  ) {
    asked++;
    return answer.future;
  }
}

class _NoHardware extends ChangeNotifier implements HardwareService {
  @override
  HardwareInfo? get hardwareInfo => null;
  @override
  bool get isDetecting => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _checking = 'Checking whether this model can use tools…';
const _notRunning = 'has to be running first';
const _failed =
    "This model was tested and didn't answer the tool-calling check "
    "correctly, so it can't be used for World from Wiki.";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase db;
  late StorageService storage;
  late KoboldService kobold;
  late LLMProvider provider;
  late ChatService chat;
  late _Model model;

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late UserPersonaService personas;
    late ModelManager models;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('fpai wiki tools');
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
      personas = UserPersonaService(db);
      models = ModelManager(storage, DownloadManager(targetDir: dir.path));
      model = _Model();
      chat =
          ChatService(kobold, personas, storage, WorldRepository(storage, db))
            ..setDatabase(db)
            ..setLLMProvider(provider)
            ..testLlmServiceOverride = model
            ..testIsLocalOverride = true;
      // A Gemma 4 fine-tune whose file name names no known family.
      final file = File(
        p.join(dir.path, 'TheDrummer_Orion-26B-A4B-v1-IQ4_XS.gguf'),
      )..writeAsBytesSync(List.filled(2048, 1));
      await storage.backendSettings.setLastUsedModelPath(file.path);
    });
    final hardware = _NoHardware();
    addTearDown(() async {
      if (!model.answer.isCompleted) model.answer.complete(_prose);
      await disposeChatThenCloseDb(chat, db);
      models.dispose();
      provider.dispose();
      kobold.dispose();
      hardware.dispose();
      await dir.delete(recursive: true);
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ChatService>.value(value: chat),
          ChangeNotifierProvider<LLMProvider>.value(value: provider),
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<UserPersonaService>.value(value: personas),
          ChangeNotifierProvider<KoboldService>.value(value: kobold),
          ChangeNotifierProvider<ModelManager>.value(value: models),
          ChangeNotifierProvider<HardwareService>.value(value: hardware),
        ],
        child: const MaterialApp(home: WorldFromWikiPage()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// The model answers; let the tester file the verdict and the page redraw.
  Future<void> answer(WidgetTester tester, LlmToolResponse reply) async {
    model.answer.complete(reply);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    await tester.pump();
  }

  /// The model came up and the Setup step redrew, which is when the page
  /// reads the tool check again.
  Future<void> modelStarts(WidgetTester tester) async {
    model.ready = true;
    final dynamic page = tester.state(find.byType(WorldFromWikiPage));
    page.creatorState.notify();
    await tester.pump();
    await tester.pump();
  }

  ButtonStyleButton next(WidgetTester tester) => tester
      .widget<ButtonStyleButton>(find.byKey(const Key('world-from-wiki-next')));

  String explanation(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('world-from-wiki-tools-copy')))
      .data!;

  testWidgets('a model that is not running says so; once it runs the check '
      'asks it, and a tool call unlocks Next', (tester) async {
    await open(tester);

    expect(explanation(tester), contains(_notRunning));
    expect(explanation(tester), contains('Start Backend'));
    expect(next(tester).onPressed, isNull);
    expect(model.asked, 0);

    await modelStarts(tester);

    expect(model.asked, 1, reason: "chat's own check asked the model");
    expect(explanation(tester), _checking);
    expect(next(tester).onPressed, isNull);

    await answer(tester, _calls);

    expect(chat.toolCallSupport, ToolCallSupport.supported);
    expect(find.byKey(const Key('world-from-wiki-tools-copy')), findsNothing);
    expect(next(tester).onPressed, isNotNull);
  });

  testWidgets('a model that was tested and answered in words says it failed '
      'the check and cannot be used, apart from "not tested"', (tester) async {
    await open(tester);
    await modelStarts(tester);
    expect(explanation(tester), _checking);

    await answer(tester, _prose);

    expect(chat.toolCallSupport, ToolCallSupport.unsupported);
    final text = explanation(tester);
    expect(text, startsWith(_failed));
    expect(text, contains('Pick a different model'));
    expect(text, isNot(contains(_notRunning)));
    expect(text, isNot(contains('Checking')));
    expect(next(tester).onPressed, isNull);
    expect(find.byKey(const Key('world-from-wiki-tools-retest')), findsNothing);
  });
}
