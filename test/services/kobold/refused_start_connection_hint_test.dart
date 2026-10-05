// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Opening a chat starts the app's KoboldCpp ("Auto-start on chat open"). A
// start that was refused (the model file is not a GGUF, say) used to be
// dropped: the chat screen said "No API connection" and nothing said why.
// The start's refusal is now what the chat's connection hint says, in the
// composer on the desktop and in the chat state the phone reads (`llmHint`,
// additive: an older phone ignores it), for as long as nothing runs and the
// refusal is the last word on the engine.
//
// The real chat service, LLM provider and KoboldCpp service run; the start
// refuses a model that is not a GGUF before anything is spawned.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';

import '../../helpers/chat_db_teardown.dart';

class _Backend extends BackendManager {
  _Backend(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

class _InertLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'InertLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase db;
  late StorageService storage;
  late KoboldService kobold;
  late LLMProvider provider;
  late ChatService chat;
  late ChatFacade facade;
  late CharacterRepository repo;
  late String broken;

  setUp(() async {
    HttpOverrides.global = null;
    root = Directory.systemTemp.createTempSync('fpai chat entry start');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null;
        });
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    await storage.initialized;
    await storage.backendSettings.setBackendType('kobold');
    await storage.binDir.create(recursive: true);
    // Not a GGUF: the start refuses it before anything is spawned.
    broken = (File(
      p.join(root.path, 'broken.gguf'),
    )..writeAsBytesSync('XXXX'.codeUnits + List.filled(32, 0))).path;
    await storage.backendSettings.setLastUsedModelPath(broken);
    kobold = KoboldService(storage);
    provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _Backend(storage, p.join(storage.binDir.path, 'koboldcpp')),
    );
    repo = CharacterRepository(db, storage);
    chat =
        ChatService(
            kobold,
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..setLLMProvider(provider)
          ..testLlmServiceOverride = _InertLlm();
    facade = ChatFacade(chat, repo, null, null, null, llm: provider);
  });

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    provider.dispose();
    kobold.dispose();
    root.deleteSync(recursive: true);
  });

  String? hint() => provider.composerConnectionHint;

  Future<void> until(bool Function() done) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!done()) {
      if (DateTime.now().isAfter(deadline)) fail('still not there after 10s');
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  test('the answer of an app start that is refused is the refusal', () async {
    final dynamic result =
        await (provider.ensureManagedBackendIsRunning() as Future<dynamic>);

    expect(result?.started, isFalse);
    expect(result?.message, contains('Not a valid GGUF'));
  });

  test('with nothing running the connection hint is the refusal, and '
      'nothing is said once KoboldCpp runs', () async {
    expect(hint(), isNull, reason: 'nothing was refused yet');

    await (provider.ensureManagedBackendIsRunning() as Future<dynamic>);

    expect(provider.composerConnectionReady, isFalse);
    expect(hint(), contains('Not a valid GGUF'));

    kobold.debugMarkProcessRunning();
    expect(provider.composerConnectionReady, isTrue);
    expect(hint(), isNull);
  });

  test('a refusal an engine start has since overtaken is not said again '
      'when the engine stops', () async {
    await (provider.ensureManagedBackendIsRunning() as Future<dynamic>);
    expect(hint(), isNotNull);

    // The engine was started some other way and has stopped since: what it
    // loaded changed, so the old refusal is not why nothing runs now.
    kobold.noteAdminLoadedPair(modelPath: broken, kcppsPath: '');

    expect(provider.composerConnectionReady, isFalse);
    expect(hint(), isNull);
  });

  test('the last thing listeners are told is the reason: the chat screen '
      'and the phone rebuild on it', () async {
    final seen = <String?>[];
    provider.addListener(() => seen.add(provider.composerConnectionHint));

    await (provider.ensureManagedBackendIsRunning() as Future<dynamic>);

    expect(seen, isNotEmpty);
    expect(
      seen.last,
      contains('Not a valid GGUF'),
      reason:
          'the engine said it was done starting before the refusal was '
          'kept; a screen that rebuilt then would have none',
    );
  });

  test('a start refused because another is under way says nothing about '
      'how that one ends', () async {
    // A model a start can get through to its free-memory read, which holds
    // the first start there, as the app's own start at launch would be (it
    // goes straight to the service, not through the provider).
    final good = (File(
      p.join(root.path, 'good.gguf'),
    )..writeAsBytesSync('GGUF'.codeUnits + List.filled(32, 0))).path;
    await storage.backendSettings.setLastUsedModelPath(good);
    final gate = Completer<FreeMemoryMb?>();
    kobold.readFreeMemory = () => gate.future;
    final first = kobold.launch(p.join(storage.binDir.path, 'koboldcpp'));
    await until(() => kobold.isStarting);

    final dynamic second =
        await (provider.ensureManagedBackendIsRunning() as Future<dynamic>);
    expect(second?.message, contains('already starting'));
    gate.complete(null);
    // There is no engine program here: that start is refused in its turn.
    expect((await first).started, isFalse);

    expect(provider.composerConnectionReady, isFalse);
    expect(hint(), isNull, reason: 'the refusal that came first is not why');
  });

  test('a remote backend never says a KoboldCpp refusal', () async {
    await (provider.ensureManagedBackendIsRunning() as Future<dynamic>);
    expect(hint(), isNotNull);

    await storage.backendSettings.setBackendType('openRouter');

    expect(provider.composerConnectionReady, isFalse);
    expect(hint(), isNull);
  });

  test('opening a chat starts KoboldCpp, and a start that is refused is what '
      'the chat state tells the phone', () async {
    final card = CharacterCard(
      name: 'Sitter',
      description: 'Connection hint test card.',
      firstMessage: 'The porch light hums.',
    );
    await repo.addCharacter(card);

    await chat.setActiveCharacter(card);
    await until(() => facade.state()['llmHint'] != null);

    final state = facade.state();
    expect(state['llmReady'], isFalse);
    expect(state['llmHint'], contains('Not a valid GGUF'));
    expect(hint(), state['llmHint']);
  });
}
