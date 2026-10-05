// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The sidebar's tool-calling pill on a REAL KoboldCpp, through the app's own
// KoboldService, LLMProvider and ChatService (nothing in the chain is a
// stand-in): once Start has the model ready the app asks it for a tool call
// by itself, keeps the answer for the next run, and a model record that moves
// while that first question is out does not lose the question. Run:
//   KOBOLD_LIVE_BIN=… KOBOLD_LIVE_MODEL=… flutter test --tags kobold_live \
//     test/live/kobold_tool_test_live_test.dart

@Tags(['kobold_live'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/chat_db_teardown.dart';
import 'live_engine.dart';

const _slow = Timeout(Duration(minutes: 10));

class _Engine extends BackendManager {
  _Engine(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

/// One run of the app: its own storage, engine process, provider and chat
/// service, over the data folder and preferences every run shares.
class _App {
  _App._(this.storage, this.kobold, this.provider, this.db, this.chat);

  final StorageService storage;
  final KoboldService kobold;
  final LLMProvider provider;
  final AppDatabase db;
  final ChatService chat;
  late String exe;
  late int port;

  /// True once the pill has shown "testing…" at any moment of this run.
  bool sawTesting = false;

  static Future<_App> open() async {
    final storage = StorageService();
    await storage.initialized;
    final exe = await copyEngineInto(storage.binDir);
    final port = await freePort();
    final kobold = KoboldService(storage)..setBaseUrl('http://127.0.0.1:$port');
    final db = AppDatabase.forTesting();
    final provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _Engine(storage, exe),
    );
    final chat = ChatService(
      kobold,
      UserPersonaService(db),
      storage,
      WorldRepository(storage, db),
    )..setDatabase(db);
    chat.setLLMProvider(provider);
    final app = _App._(storage, kobold, provider, db, chat)
      ..exe = exe
      ..port = port;
    chat.addListener(() {
      if (chat.isTestingToolSupport) app.sawTesting = true;
    });
    return app;
  }

  Future<void> start() async {
    expect((await kobold.launch(exe, port: port)).started, isTrue);
  }

  Future<void> waitForModel() async {
    await waitForLiveModel(port);
    for (var i = 0; i < 240 && !kobold.modelReady; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(kobold.modelReady, isTrue);
  }

  /// Until the pill has a verdict and is not asking any more.
  Future<void> waitForVerdict({int seconds = 120}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(deadline)) {
      if (chat.toolCallSupport != ToolCallSupport.untested &&
          !chat.isTestingToolSupport) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  /// Times the engine itself finished a 64-token answer: the size of the
  /// tool-calling question (the system-message check asks for one token).
  int get questionsAnswered => kobold.logs
      .where((line) => RegExp(r'Generated:\d+/64\b').hasMatch(line))
      .length;

  Future<void> close() async {
    await kobold.stopKobold();
    await disposeChatThenCloseDb(chat, db);
    provider.dispose();
  }
}

/// The verdicts the app has written to its preferences, as stored.
Future<Map<String, dynamic>> _storedVerdicts() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(
    isPreRelease ? 'beta_tool_verdicts' : 'tool_verdicts',
  );
  if (raw == null || raw.isEmpty) return {};
  return Map<String, dynamic>.from(jsonDecode(raw) as Map);
}

/// Waits for the app's write of a verdict to reach the preferences.
Future<void> _waitForStoredVerdict() async {
  for (var i = 0; i < 50 && (await _storedVerdicts()).isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  late Directory root;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('fpai tooltest live');
    root = Directory(temp.resolveSymbolicLinksSync());
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null;
        });
    // Both spellings of every key: a pre-release build reads the beta_ ones.
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'backend_type': 'kobold',
      'beta_backend_type': 'kobold',
      'context_size': 4096,
      'beta_context_size': 4096,
      'last_used_model_path': liveEngineModel,
      'beta_last_used_model_path': liveEngineModel,
    });
  });

  tearDown(() async {
    await stopLiveEnginesUnder(root);
    await root.delete(recursive: true);
  });

  /// What the app calls the model in the verdicts it keeps.
  String modelKey(String path) =>
      'KoboldCPP|||${p.basename(path)}#${File(path).lengthSync()}';

  test(
    'after Start the model is tested for tool calling by itself, and the '
    'answer is kept',
    () async {
      final app = await _App.open();
      addTearDown(app.close);

      await app.start();
      await app.waitForModel();
      await app.waitForVerdict();

      expect(app.chat.toolCallSupport, ToolCallSupport.supported);
      expect(app.sawTesting, isTrue, reason: 'the pill showed "testing…"');
      expect(
        app.questionsAnswered,
        greaterThan(0),
        reason: 'the engine really answered the tool-calling question',
      );
      expect(app.chat.toolSupportJson['state'], 'supported');
      // Kept for the next run, under the model's name.
      await _waitForStoredVerdict();
      expect(await _storedVerdicts(), {modelKey(liveEngineModel): true});
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a second run knows the model and does not ask it again',
    () async {
      final first = await _App.open();
      await first.start();
      await first.waitForModel();
      await first.waitForVerdict();
      expect(first.chat.toolCallSupport, ToolCallSupport.supported);
      expect(first.questionsAnswered, greaterThan(0));
      await _waitForStoredVerdict();
      await first.close();

      // The app is opened again over the same data and preferences.
      final second = await _App.open();
      addTearDown(second.close);
      expect(
        second.chat.toolCallSupport,
        ToolCallSupport.supported,
        reason: 'known before the engine is even started',
      );
      await second.start();
      await second.waitForModel();
      // Room for a question to be asked and answered, if one were going to be.
      await Future<void>.delayed(const Duration(seconds: 8));

      expect(second.chat.toolCallSupport, ToolCallSupport.supported);
      expect(second.chat.toolSupportJson['state'], 'supported');
      expect(second.sawTesting, isFalse, reason: 'no "testing…" this run');
      expect(
        second.questionsAnswered,
        0,
        reason: 'the engine was not asked for a tool call',
      );
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a model record that moves while the first test runs does not lose the '
    'test: the model it moved to is tested too',
    () async {
      final app = await _App.open();
      addTearDown(app.close);
      // Another path to the same file, so picking it costs no memory.
      final alias = p.join(app.storage.modelsDir.path, 'alias-model.gguf');
      Directory(app.storage.modelsDir.path).createSync(recursive: true);
      Link(alias).createSync(liveEngineModel);

      var moved = false;
      app.chat.addListener(() {
        if (app.chat.isTestingToolSupport && !moved) {
          moved = true;
          // What a pick, a preset choice or a reload's record does.
          unawaited(selectKoboldModel(app.storage, alias));
        }
      });
      await app.start();
      await app.waitForModel();
      await app.waitForVerdict();

      expect(moved, isTrue, reason: 'the record moved during the test');
      expect(app.chat.debugEvalBackendIdentity, contains('alias-model.gguf'));
      expect(
        app.chat.toolCallSupport,
        ToolCallSupport.supported,
        reason: 'the model it moved to was tested',
      );
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );
}
