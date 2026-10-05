// Which requests belong to a chat. Only a chat reply names its chat
// (`GenerationParams.kvChat`), because the slot keeper saves the cache after
// a reply and loads it before the next one: a judge, a needs check or a
// suggestion that named the chat would be saved and loaded like a reply and
// push the real ones out. The twins are walked together: send, Continue,
// regenerate, a group speaker and impersonate are replies; the judges and
// the passes after a reply, suggested actions and the doorbell are not.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../helpers/chat_db_teardown.dart';
import '../../helpers/kobold_engine_harness.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_kv_paths_').path;
        }
        return null;
      });
}

typedef _Request = ({String kind, bool hasSystem, String? kvChat});

/// Answers like a model and writes down what each request said about itself.
class _Recorder extends LLMService {
  final List<_Request> requests = [];

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    requests.add((
      kind: 'stream',
      hasSystem: params.systemPrompt != null,
      kvChat: params.kvChat,
    ));
    if (params.systemPrompt != null) {
      yield ' and stays on the rail.';
      return;
    }
    final p = params.prompt;
    if (p.contains('relationship_delta')) {
      yield '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"steady"}';
    } else if (p.contains('hunger_delta')) {
      yield '{"hunger_delta": 0, "bladder_delta": 0, "energy_delta": 0, '
          '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
          '"comfort_delta": 0, "reason": "none"}';
    } else if (p.contains('emotion_intensity')) {
      yield '{"emotion":"neutral","emotion_intensity":"mild"}';
    } else if (p.contains('Suggest 4 short actions')) {
      yield '1. Smile\n2. Wave\n3. Nod\n4. Sit down';
    } else {
      yield '{}';
    }
  }

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    requests.add((
      kind: 'tools',
      hasSystem: params.systemPrompt != null,
      kvChat: params.kvChat,
    ));
    return const LlmToolResponse(calls: [], text: '');
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'Recorder';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _Recorder llm;

  Future<void> drain() async {
    for (
      var i = 0;
      i < 400 && (chat.isGenerating || chat.isSettlingTurn);
      i++
    ) {
      await Future<void>.delayed(Duration.zero);
    }
    for (var i = 0; i < 40; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': true,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _Recorder();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = llm;
    await storage.initialized;
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> openNia() async {
    final nia = CharacterCard(
      name: 'Nia',
      description: 'Keeps the porch.',
      firstMessage: 'Evening.',
      imagePath: '/tmp/nia-kv-paths.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: true,
      ),
    );
    await CharacterRepository(db, storage).addCharacter(nia);
    await chat.setActiveCharacter(nia);
    await drain();
    llm.requests.clear();
  }

  Iterable<_Request> replies() => llm.requests.where((r) => r.hasSystem);
  Iterable<_Request> helpers() => llm.requests.where((r) => !r.hasSystem);

  void expectOneReplyNamingTheChat() {
    final sid = chat.currentSessionId;
    expect(sid, isNotNull);
    expect(replies(), hasLength(1));
    expect(replies().single.kvChat, sid);
    expect(
      helpers().where((r) => r.kvChat != null),
      isEmpty,
      reason: 'a helper named the chat, so it would be saved like a reply',
    );
  }

  test('a sent message: the reply names the chat, the judges do not', () async {
    await openNia();

    await chat.sendMessage('Hello there.');
    await drain();

    expectOneReplyNamingTheChat();
    expect(helpers(), isNotEmpty, reason: 'the judges and passes ran');
  });

  test('Continue: the continued reply names the chat', () async {
    await openNia();
    await chat.sendMessage('Hello there.');
    await drain();
    llm.requests.clear();

    await chat.continueGeneration();
    await drain();

    expectOneReplyNamingTheChat();
  });

  test('regenerate: the new reply names the chat, the judges do not', () async {
    await openNia();
    await chat.sendMessage('Hello there.');
    await drain();
    llm.requests.clear();

    await chat.regenerateLastMessage();
    await drain();

    expectOneReplyNamingTheChat();
  });

  test('impersonate: the line in the user\'s voice names the chat', () async {
    await openNia();
    await chat.sendMessage('Hello there.');
    await drain();
    llm.requests.clear();

    await chat.impersonateUser(onToken: (_) {});
    await drain();

    expectOneReplyNamingTheChat();
  });

  test('suggested actions are a helper: they do not name the chat', () async {
    await openNia();
    await chat.sendMessage('Hello there.');
    await drain();
    llm.requests.clear();

    await chat.generateActions();
    await drain();

    expect(llm.requests, isNotEmpty);
    expect(llm.requests.where((r) => r.kvChat != null), isEmpty);
  });

  test(
    'a group speaker names the group chat, and the dance does not',
    () async {
      await db.insertGroup(
        GroupsCompanion.insert(id: 'grp-kv', name: 'The Cast'),
      );
      for (final (id, name) in [('mem-ada', 'Ada'), ('mem-bea', 'Bea')]) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: id,
            groupId: 'grp-kv',
            name: name,
            personality: Value('$name keeps the porch.'),
            avatarFilename: Value('${name.toLowerCase()}.png'),
            frontPorchExtensions: const Value(
              '{"realism_engine":{"realism_enabled":true}}',
            ),
          ),
        );
      }
      await chat.setActiveGroup(
        GroupChat(id: 'grp-kv', name: 'The Cast'),
        groupRepo: GroupChatRepository(storage, db),
      );
      await chat.setRealismEnabled(true);
      await drain();
      llm.requests.clear();

      chat.setNextCharacter(
        chat.groupCharacters.firstWhere((c) => c.name == 'Ada'),
      );
      await chat.sendMessage('I bring you both a cup of tea.');
      await drain();
      expectOneReplyNamingTheChat();
      final first = chat.currentSessionId;

      llm.requests.clear();
      chat.setNextCharacter(
        chat.groupCharacters.firstWhere((c) => c.name == 'Bea'),
      );
      await chat.triggerNextCharacter();
      await drain();
      expectOneReplyNamingTheChat();
      expect(
        chat.currentSessionId,
        first,
        reason: 'both speakers share the one group chat and so its one slot',
      );
    },
  );

  test('through the real service: a reply, a helper, then the next reply loads '
      'the chat back and reads only what is new', () async {
    // The service below talks to an engine stand-in on a loopback socket, so
    // what the keeper does shows in the order of the engine's own requests.
    final h = await KoboldEngineHarness.start();
    addTearDown(h.dispose);
    h.kobold.debugKeeperPlan = () async => const KoboldKeeperPlan.keep(3);
    final realDb = AppDatabase.forTesting();
    final real =
        ChatService(
            h.kobold,
            UserPersonaService(realDb),
            h.storage,
            WorldRepository(h.storage, realDb),
          )
          ..setDatabase(realDb)
          ..setCharacterRepository(CharacterRepository(realDb, h.storage));
    addTearDown(() => disposeChatThenCloseDb(real, realDb));
    final ada = CharacterCard(
      name: 'Ada',
      description: 'Keeps the porch.',
      firstMessage: 'Evening.',
      imagePath: '/tmp/ada-kv-paths.png',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
      ),
    );
    await CharacterRepository(realDb, h.storage).addCharacter(ada);
    await real.setActiveCharacter(ada);
    h.engine.forgetLog();
    h.engine.live = [];

    Future<void> settle() async {
      for (
        var i = 0;
        i < 400 && (real.isGenerating || real.isSettlingTurn);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await h.kobold.waitForIdle();
    }

    await real.sendMessage('Good evening, Ada.');
    await settle();
    await real.generateActions(); // a helper, asked for by a tap
    await settle();
    await real.sendMessage('Did the rain stop?');
    await settle();

    final replies = h.engine
        .of('chat')
        .where((r) => r.prompt.first == '<system>')
        .toList();
    expect(replies, hasLength(2));
    expect(
      h.engine.kinds,
      containsAllInOrder(['chat', 'save', 'chat', 'load', 'chat']),
    );
    final second = h.engine.log.indexOf(replies.last);
    expect(
      h.engine.log[second - 1].kind,
      'load',
      reason: 'loaded just before the reply',
    );
    expect(
      replies.last.processed,
      lessThan(replies.last.promptTokens ~/ 2),
      reason: 'the reply read only what the chat added since the last one',
    );
  });
}
