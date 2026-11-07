// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Continue = regen for speaker identity (full-codebase audit P0):
//   * Scene Guest Continue must pass guestSpeaker so the host-ban cannot
//     sit on a guest suffix.
//   * Group Continue uses the id-first resolver and refuses to guess
//     when two members share a name.
//
// Proven red: restore firstWhere-by-name in _generateResponse and the
// group Continue prompt test picks the first Alex; delete the
// `_sceneGuestForMessage` infer and the source pin fails.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' hide Router;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/voice_facade.dart';
import 'package:front_porch_ai/services/web/routes/voice_routes.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';
import '../../golden/support/fakes.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_contid_').path;
        }
        return null;
      });
}

class _ScriptedLlm extends LLMService {
  final List<String> systems = [];
  final List<String> prompts = [];
  String reply = '*They keep talking.*';
  int pocketsPrompts = 0;

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    if (params.systemPrompt != null) {
      systems.add(params.systemPrompt!);
    }
    prompts.add(params.prompt);
    if (params.prompt.contains('You are keeping track of what')) {
      pocketsPrompts++;
      yield '{"inventory_ops": []}';
      return;
    }
    if (params.systemPrompt != null) {
      yield reply;
      return;
    }
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'ScriptedLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _ScriptedLlm llm;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'pockets_enabled': true,
      'journal_enabled': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _ScriptedLlm();
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
    await storage.realismSettings.setPocketsEnabled(true);
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<void> drainUntil(bool Function() done) async {
    for (var i = 0; i < 300 && !done(); i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'group Continue uses the stamped id when two members share a name',
    () async {
      await db.insertGroup(
        GroupsCompanion.insert(id: 'grp-alex', name: 'Two Alexes'),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-north',
          groupId: 'grp-alex',
          name: 'Alex',
          personality: const Value('Alex from the NORTH porch, maple syrup.'),
          systemPrompt: const Value('You are Alex from the NORTH porch.'),
          avatarFilename: const Value('Alex_north.png'),
          frontPorchExtensions: Value(
            jsonEncode({
              'realism_engine': {'inventory': <String, dynamic>{}},
            }),
          ),
        ),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-south',
          groupId: 'grp-alex',
          name: 'Alex',
          personality: const Value('Alex from the SOUTH dock, salt air.'),
          systemPrompt: const Value('You are Alex from the SOUTH dock.'),
          avatarFilename: const Value('Alex_south.png'),
          frontPorchExtensions: Value(
            jsonEncode({
              'realism_engine': {'inventory': <String, dynamic>{}},
            }),
          ),
        ),
      );
      await chat.setActiveGroup(
        GroupChat(id: 'grp-alex', name: 'Two Alexes'),
        groupRepo: GroupChatRepository(storage, db),
      );

      final south = chat.groupCharacters.firstWhere(
        (c) => c.personality.contains('SOUTH'),
      );
      chat.setNextCharacter(south);

      llm.reply = '*South Alex leans on the rail.*';
      await chat.sendMessage('Say something, South.');
      await drainUntil(
        () =>
            chat.messages.any((m) => !m.isUser && m.sender != 'System') &&
            !chat.isGenerating &&
            !chat.isSettlingTurn,
      );

      llm.systems.clear();
      llm.reply = ' The tide is loud tonight.';
      await chat.continueGeneration();
      await drainUntil(() => !chat.isGenerating && !chat.isSettlingTurn);

      expect(
        llm.systems,
        isNotEmpty,
        reason: 'Continue must fire a generation',
      );
      // Overlay sits on Speaker Card after history (not the system head),
      // so Continue identity is on the user prompt. first-match-by-name
      // would have said NORTH.
      final wire = [...llm.systems, ...llm.prompts].join('\n');
      expect(
        wire,
        contains('You are Alex from the SOUTH dock.'),
        reason: 'Continue must keep speaking as the stamped South Alex',
      );
      expect(
        wire,
        isNot(contains('You are Alex from the NORTH porch.')),
        reason: 'first-match-by-name would have loaded the first Alex',
      );
    },
  );

  test(
    'Scene Guest Continue uses the guest-turn note, not the host-ban',
    () async {
      await db.insertCharacter(
        CharactersCompanion.insert(
          id: 'char-host',
          name: 'Mara',
          imagePath: const Value('/tmp/Mara_host.png'),
          firstMessage: const Value('The porch light hums.'),
        ),
      );
      await db.insertCharacter(
        CharactersCompanion.insert(
          id: 'guest-riley',
          name: 'Riley',
          imagePath: const Value('/tmp/Riley_guest.png'),
          firstMessage: const Value('Riley waves from the steps.'),
        ),
      );
      final host = CharacterCard(
        name: 'Mara',
        firstMessage: 'The porch light hums.',
        imagePath: '/tmp/Mara_host.png',
        frontPorchExtensions: FrontPorchExtensions(
          inventory: {
            'carrying': ['car keys'],
          },
        ),
      )..dbId = 'char-host';
      await chat.setActiveCharacter(host);

      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-guest-cont-id',
          characterId: const Value('char-host'),
          groupRealismState: const Value('{"sceneGuests":["guest-riley"]}'),
        ),
      );
      for (final (i, seed) in const [
        ('Mara', false, 'Mara_host'),
        ('You', true, null),
        ('Riley', false, 'Riley_guest'),
      ].indexed) {
        await db.insertMessage(
          MessagesCompanion.insert(
            id: 'gcont-$i',
            sessionId: 'sess-guest-cont-id',
            position: i,
            sender: seed.$1,
            isUser: seed.$2,
            characterId: Value(seed.$3),
            swipes: const Value('["*The porch light hums while they talk.*"]'),
          ),
        );
      }
      await chat.loadSession('sess-guest-cont-id');
      for (var i = 0; i < 200 && chat.sceneGuestCards.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        chat.sceneGuestCards.map((c) => c.name),
        contains('Riley'),
        reason: 'the guest must be present so Continue can speak as them',
      );

      llm.systems.clear();
      llm.prompts.clear();
      llm.pocketsPrompts = 0;
      llm.reply = ' Riley keeps going.';
      await chat.continueGeneration();
      await drainUntil(() => !chat.isGenerating && !chat.isSettlingTurn);

      final blob = [...llm.systems, ...llm.prompts].join('\n');
      expect(
        blob,
        contains('SCENE GUEST TURN'),
        reason: 'Continue of a guest bubble must switch identity like regen',
      );
      expect(
        blob,
        isNot(contains('Stay entirely as Mara')),
        reason: 'the host-ban must not sit on a guest suffix',
      );
      expect(
        llm.pocketsPrompts,
        0,
        reason: 'present-guest Continue must not score the host kit',
      );
    },
  );

  // Voice is the member's, found by the id stamped on the line. Two members
  // named Alex used to share whichever voice the first Alex had, and the web
  // Speak button sent no speaker at all, so every line read the global voice.
  group('each group member speaks in their own voice', () {
    const gid = 'grp-voice';
    const sid = 'sess-voice';
    late _VoiceLog tts;

    setUp(() async {
      tts = _VoiceLog();
      await storage.ttsSettings.setTtsEnabled(true);
      await storage.ttsSettings.setTtsAutoPlay(true);
      chat.setTtsService(tts);
      await db.insertGroup(GroupsCompanion.insert(id: gid, name: 'Two Alexes'));
      for (final m in const [
        ('mem-north', 'NORTH', 'voice-north'),
        ('mem-south', 'SOUTH', 'voice-south'),
      ]) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: m.$1,
            groupId: gid,
            name: 'Alex',
            personality: Value('Alex from the ${m.$2} side.'),
            systemPrompt: Value('You are Alex from the ${m.$2} side.'),
            avatarFilename: Value('${m.$1}.png'),
            ttsVoice: Value(m.$3),
          ),
        );
      }
      await db.insertSession(
        SessionsCompanion.insert(id: sid, groupId: const Value(gid)),
      );
      for (final (i, seed) in const [
        ('Alex', false, 'mem-north', 'North pours the syrup.'),
        ('You', true, null, 'Evening, both of you.'),
        ('Alex', false, 'mem-south', 'South leans on the rail.'),
        ('Alex', false, null, 'A line from before lines were stamped.'),
      ].indexed) {
        await db.insertMessage(
          MessagesCompanion.insert(
            id: '$sid-$i',
            sessionId: sid,
            position: i,
            sender: seed.$1,
            isUser: seed.$2,
            characterId: Value(seed.$3),
            swipes: Value(jsonEncode([seed.$4])),
          ),
        );
      }
      await chat.setActiveGroup(
        GroupChat(id: gid, name: 'Two Alexes'),
        groupRepo: GroupChatRepository(storage, db),
      );
    });

    CharacterCard alex(String side) =>
        chat.groupCharacters.firstWhere((c) => c.personality.contains(side));

    test('auto-play reads the voice of the member who replied', () async {
      for (final side in const ['SOUTH', 'NORTH']) {
        chat.setNextCharacter(alex(side));
        llm.reply = '*$side Alex says a word.*';
        final before = tts.spoken.length;
        if (side == 'SOUTH') {
          await chat.sendMessage('Say something, South.');
        } else {
          await chat.triggerNextCharacter();
        }
        await drainUntil(
          () =>
              tts.spoken.length > before &&
              !chat.isGenerating &&
              !chat.isSettlingTurn,
        );
        expect(tts.spoken, hasLength(before + 1), reason: '$side spoke once');
        expect(
          tts.spoken.last,
          side == 'SOUTH' ? 'voice-south' : 'voice-north',
          reason:
              'matching by name gave both Alexes the first Alex\'s voice '
              '($side turn)',
        );
      }
    });

    test('the web relay speaks a line in the voice stamped on it, and a '
        'renamed member keeps theirs', () async {
      final relay = _relay(tts, storage, chat);
      int at(String text) =>
          chat.messages.indexWhere((m) => m.displayText == text);

      Future<String?> voiceOf(String text) async {
        await relay({'text': text, 'messageIndex': at(text)});
        return tts.generated.last;
      }

      expect(await voiceOf('South leans on the rail.'), 'voice-south');
      expect(await voiceOf('North pours the syrup.'), 'voice-north');
      expect(
        await voiceOf('A line from before lines were stamped.'),
        isNull,
        reason:
            'an unstamped line two members could have said reads the '
            'global voice, not a guess',
      );

      alex('SOUTH').name = 'Sandy';
      expect(
        await voiceOf('South leans on the rail.'),
        'voice-south',
        reason: 'the stamped id still finds South after a rename',
      );

      await relay({'text': 'Any.', 'voiceKey': 'picked', 'messageIndex': 0});
      expect(tts.generated.last, 'picked', reason: 'an explicit voice wins');
      await relay({'text': 'Any.', 'messageIndex': 99});
      expect(tts.generated.last, isNull, reason: 'a stale index is global');
      await relay({
        'text': 'North pours the syrup.',
        'messageIndex': at('South leans on the rail.'),
      });
      expect(
        tts.generated.last,
        isNull,
        reason:
            'an index that now points at another line must not read that '
            "line's speaker's voice",
      );
      final south = at('South leans on the rail.').toDouble();
      await relay({'text': 'South leans on the rail.', 'messageIndex': south});
      expect(
        tts.generated.last,
        isNull,
        reason: 'only an int is an index, as on the other index routes',
      );
      await relay({'text': 'Any.'});
      expect(tts.generated.last, isNull, reason: 'no index is global');
    });
  });

  test('the web relay reads a 1:1 character\'s own voice', () async {
    final tts = _VoiceLog();
    await storage.ttsSettings.setTtsEnabled(true);
    final host = CharacterCard(
      name: 'Mara',
      firstMessage: 'The porch light hums.',
      ttsVoice: 'voice-mara',
    );
    await chat.setActiveCharacter(host);
    await _relay(tts, storage, chat)({
      'text': 'The porch light hums.',
      'messageIndex': 0,
    });
    expect(tts.generated.single, 'voice-mara');
  });

  // A Scene Guest's lines are stamped with the guest's id. Every 1:1 voice
  // read went to the host, so Riley spoke in Mara's voice on every surface.
  group('a 1:1 Scene Guest speaks in their own voice', () {
    const sid = 'sess-guest-voice';
    late _VoiceLog tts;

    setUp(() async {
      tts = _VoiceLog();
      await storage.ttsSettings.setTtsEnabled(true);
      await storage.ttsSettings.setTtsAutoPlay(true);
      chat.setTtsService(tts);
      for (final c in const [
        ('char-mara', 'Mara', 'Mara_voice.png', 'voice-mara'),
        ('char-riley', 'Riley', 'Riley_voice.png', 'voice-riley'),
      ]) {
        await db.insertCharacter(
          CharactersCompanion.insert(
            id: c.$1,
            name: c.$2,
            imagePath: Value(c.$3),
            firstMessage: const Value('The porch light hums.'),
            ttsVoice: Value(c.$4),
          ),
        );
      }
      final host = CharacterCard(
        name: 'Mara',
        firstMessage: 'The porch light hums.',
        ttsVoice: 'voice-mara',
      )..dbId = 'char-mara';
      await chat.setActiveCharacter(host);
      await db.insertSession(
        SessionsCompanion.insert(
          id: sid,
          characterId: const Value('char-mara'),
          groupRealismState: const Value('{"sceneGuests":["char-riley"]}'),
        ),
      );
      for (final (i, seed) in const [
        ('Mara', false, null, 'Mara sets the kettle on.'),
        ('You', true, null, 'Evening, you two.'),
        ('Riley', false, 'Riley_voice', 'Riley waves from the steps.'),
      ].indexed) {
        await db.insertMessage(
          MessagesCompanion.insert(
            id: '$sid-$i',
            sessionId: sid,
            position: i,
            sender: seed.$1,
            isUser: seed.$2,
            characterId: Value(seed.$3),
            swipes: Value(jsonEncode([seed.$4])),
          ),
        );
      }
      await chat.loadSession(sid);
      await drainUntil(() => chat.sceneGuestCards.isNotEmpty);
      expect(chat.sceneGuestCards.map((c) => c.name), ['Riley']);
    });

    int at(String text) =>
        chat.messages.indexWhere((m) => m.displayText.startsWith(text));

    test('auto-play reads the guest\'s voice on their Continue', () async {
      llm.reply = ' She sits on the top step.';
      await chat.continueGeneration();
      await drainUntil(
        () =>
            tts.spoken.isNotEmpty && !chat.isGenerating && !chat.isSettlingTurn,
      );
      expect(chat.messages.last.sender, 'Riley');
      expect(tts.spoken, ['voice-riley'], reason: "not the host's voice");
    });

    test('the web relay reads the guest\'s voice, and the host\'s', () async {
      final relay = _relay(tts, storage, chat);
      for (final (line, voice) in const [
        ('Riley waves from the steps.', 'voice-riley'),
        ('Mara sets the kettle on.', 'voice-mara'),
      ]) {
        await relay({'text': line, 'messageIndex': at(line)});
        expect(tts.generated.last, voice, reason: line);
      }
    });

    testWidgets("the bubble's Speak button reads the guest's voice", (
      tester,
    ) async {
      final line = chat.messages[at('Riley waves')];
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<TtsService>.value(value: tts),
            ChangeNotifierProvider<ChatService>.value(value: chat),
            ChangeNotifierProvider<UserPersonaService>.value(
              value: FakeUserPersonaService(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: line,
                index: chat.messages.indexOf(line),
                chatService: chat,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Speak message'));
      await tester.pump();
      expect(tts.spoken, ['voice-riley']);
    });
  });
}

/// POSTs a body to the real `/api/tts/speak` route over a [VoiceFacade] that
/// reads [chat], the way the web server wires it.
Future<void> Function(Map<String, Object?> body) _relay(
  _VoiceLog tts,
  StorageService storage,
  ChatService chat,
) {
  final router = Router();
  WebVoiceRoutes(
    VoiceFacade(tts, FakeSttService(), storage, chat: chat),
    router,
  );
  return (body) async {
    await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/tts/speak'),
        body: jsonEncode(body),
        headers: {'content-type': 'application/json'},
      ),
    );
  };
}

/// Records the voice each speak and synthesis call asked for.
class _VoiceLog extends FakeTtsService {
  final List<String?> spoken = [];
  final List<String?> generated = [];

  @override
  Future<void> speak(String text, {String? voiceKey, String? messageId}) async {
    spoken.add(voiceKey);
  }

  @override
  Future<File?> generateAudioFile(String text, {String? voiceKey}) async {
    generated.add(voiceKey);
    return null;
  }
}
