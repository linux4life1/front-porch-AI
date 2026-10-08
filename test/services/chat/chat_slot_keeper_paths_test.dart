// Which requests belong to a chat. Only a chat reply names its chat
// (`GenerationParams.kvChat`), because the slot keeper saves the cache after
// a reply and loads it before the next one: a judge, a needs check or a
// suggestion that named the chat would be saved and loaded like a reply and
// push the real ones out. The twins are walked together: send, Continue,
// regenerate, a group speaker, a Scene Guest, a voice call and impersonate
// are replies; the judges and the passes after a reply, suggested actions
// and the doorbell are not.
//
// Nothing here tells a reply from a helper by the shape of its request. The
// one request that names the chat must be the one whose answer is on screen,
// and the tests with the real service read it from the keeper's own saves.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../helpers/chat_db_teardown.dart';
import '../../helpers/kobold_chat_harness.dart';

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

/// One request as the chat service made it, and what the model answered.
class _Request {
  _Request(this.params, [this.tools = const []]);

  final GenerationParams params;

  /// The names of the tools offered, for a tool round.
  final List<String> tools;
  String answer = '';

  String? get kvChat => params.kvChat;
}

/// Answers like a model and keeps every request whole. Each reply says which
/// answer it is, so the one on screen leads back to the request behind it.
class _Recorder extends LLMService {
  final List<_Request> requests = [];
  int _replies = 0;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    final request = _Request(params);
    requests.add(request);
    final p = params.prompt;
    if (params.systemPrompt != null) {
      request.answer = 'The rail holds, take ${++_replies}.';
    } else if (p.contains('relationship_delta')) {
      request.answer =
          '{"relationship_delta":0,"trust_delta":0,'
          '"bond_reason":"steady","trust_reason":"steady"}';
    } else if (p.contains('hunger_delta')) {
      request.answer =
          '{"hunger_delta": 0, "bladder_delta": 0, "energy_delta": 0, '
          '"social_delta": 0, "fun_delta": 0, "hygiene_delta": 0, '
          '"comfort_delta": 0, "reason": "none"}';
    } else if (p.contains('emotion_intensity')) {
      request.answer = '{"emotion":"neutral","emotion_intensity":"mild"}';
    } else if (p.contains('Suggest 4 short actions')) {
      request.answer = '1. Smile\n2. Wave\n3. Nod\n4. Sit down';
    } else {
      request.answer = '{}';
    }
    yield request.answer;
  }

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    requests.add(_Request(params, [for (final t in tools) _toolName(t)]));
    return const LlmToolResponse(calls: [], text: '');
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'Recorder';
}

CharacterCard _card(String name, String line) => CharacterCard(
  name: name,
  description: line,
  firstMessage: 'Evening.',
  imagePath: '/tmp/$name-kv-paths.png',
  frontPorchExtensions: FrontPorchExtensions(
    realismEnabled: true,
    needsSimEnabled: true,
  ),
);

String _toolName(Map<String, dynamic> tool) =>
    ((tool['function'] ?? tool) as Map)['name'].toString();

/// One recipe card on the shelf is enough to send the doorbell round before
/// a reply: the catalog advertises it and the round goes out.
void _putCardOnShelf(Directory shelf) {
  shelf.createSync(recursive: true);
  File('${shelf.path}/rail.json').writeAsStringSync(
    jsonEncode({
      'name': 'check_rail',
      'description': 'Look up what the rail is doing.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
      },
      'method': 'POST',
      'url': 'https://example.invalid/rail',
    }),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    _setupPathProviderMock();
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
    final nia = _card('Nia', 'Keeps the porch.');
    await CharacterRepository(db, storage).addCharacter(nia);
    await chat.setActiveCharacter(nia);
    await drain();
    llm.requests.clear();
  }

  /// The last thing a character said, as the chat shows it.
  ChatMessage lastSaid() =>
      chat.messages.lastWhere((m) => !m.isUser && !m.isStatusBanner);

  /// One request names the chat, it names the chat that is open, and it is
  /// the reply: its answer is the one on screen ([shown] when the reply does
  /// not land in the chat, like impersonate's).
  void expectOneReplyNamingTheChat({String? shown}) {
    final sid = chat.currentSessionId;
    expect(sid, isNotNull);
    final named = llm.requests.where((r) => r.kvChat != null).toList();
    expect(
      named.map((r) => r.kvChat),
      [sid],
      reason:
          'exactly one request names the chat, and this one: a helper that '
          'named it would be saved like a reply',
    );
    expect(
      shown ?? lastSaid().text,
      contains(named.single.answer),
      reason: 'the request that names the chat is not the reply on screen',
    );
  }

  test('a sent message: the reply names the chat, the judges do not', () async {
    await openNia();

    await chat.sendMessage('Hello there.');
    await drain();

    expectOneReplyNamingTheChat();
    expect(
      llm.requests.length,
      greaterThan(1),
      reason: 'the judges and passes ran',
    );
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

    var said = '';
    await chat.impersonateUser(onToken: (text) => said = text);
    await drain();

    expectOneReplyNamingTheChat(shown: said);
  });

  test('a Scene Guest\'s turn names the chat it speaks in', () async {
    await openNia();
    await chat.sendMessage('Hello there.');
    await drain();
    llm.requests.clear();

    await chat.generateGuestTurn(_card('Rue', 'Drops by.'));
    await drain();

    expect(lastSaid().sender, 'Rue', reason: 'the guest spoke');
    expectOneReplyNamingTheChat();
  });

  test('a voice call\'s message: the reply names the chat', () async {
    await openNia();
    chat.callMode = true;

    await chat.sendMessage('Can you hear me?');
    await drain();

    expectOneReplyNamingTheChat();
  });

  test('a recipe card\'s doorbell round is a helper: only the reply names '
      'the chat', () async {
    _putCardOnShelf(storage.toolsDir);
    await openNia();

    await chat.sendMessage('Hello there.');
    await drain();

    final doorbell = llm.requests.where((r) => r.tools.contains('check_rail'));
    expect(doorbell, hasLength(1), reason: 'the card was offered to the model');
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

  // The two tests below run the real service against an engine stand-in on a
  // loopback socket, so what the keeper does shows in the order of the
  // engine's own requests: a reply is a chat request that a save follows.

  test('through the real service: a reply, a helper, then the next reply loads '
      'the chat back and reads only what is new', () async {
    final h = await KoboldChatHarness.start();

    await h.chat.sendMessage('Good evening, Ada.');
    await h.settle();
    await h.chat.generateActions(); // a helper, asked for by a tap
    await h.settle();
    await h.chat.sendMessage('Did the rain stop?');
    await h.settle();

    final log = h.engine.log;
    final saved = [
      for (var i = 0; i < log.length - 1; i++)
        if (log[i].kind == 'chat' && log[i + 1].kind == 'save') log[i],
    ];
    expect(
      saved,
      hasLength(2),
      reason:
          'a save follows each of the two replies and nothing else: not the '
          'clock passes, not the suggestions',
    );
    expect(
      log.where((r) => r.kind == 'chat'),
      hasLength(greaterThan(2)),
      reason: 'the helpers ran too',
    );
    final second = log.indexOf(saved.last);
    expect(
      log[second - 1].kind,
      'load',
      reason: 'the second reply came after helpers, so it was loaded for',
    );
    expect(log.where((r) => r.kind == 'load'), hasLength(1));
    expect(
      saved.last.processed,
      lessThan(saved.last.promptTokens ~/ 2),
      reason: 'the reply read only what the chat added since the last one',
    );
  });

  test('through the real service, a recipe card\'s doorbell round is only a '
      'helper: the reply after it loads its chat back, and is saved', () async {
    final h = await KoboldChatHarness.start();
    _putCardOnShelf(h.base.storage.toolsDir);
    await h.chat.sendMessage('Good evening, Ada.');
    await h.settle();
    h.engine.forgetLog();

    await h.chat.sendMessage('Did the rain stop?');
    await h.settle();

    expect(
      h.engine.log.first.hadTools,
      isTrue,
      reason: 'the card was offered: the doorbell goes out before the reply',
    );
    expect(
      h.engine.kinds.take(4),
      ['chat', 'load', 'chat', 'save'],
      reason:
          'the doorbell is not loaded for and not saved after; the reply '
          'that follows brings its chat back, and is saved',
    );
  });
}
