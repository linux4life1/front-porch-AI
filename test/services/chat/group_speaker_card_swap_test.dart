// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Group generation prompt is Swap, not Join: only the speaker wears a
// costume, after the transcript. Proven red: restore the
// `_groupCharacters.map` Join in `_assembleGenerationBlocks` and the
// Senjumaru-turn assertions fail.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools_facade.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

import '../../../integration_test/support/fake_backend.dart';
import '../../golden/support/fakes.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_swap_').path;
        }
        return null;
      });
}

const _off = '{"realism_engine":{"realism_enabled":false}}';

({String system, String user}) _wire(FakeBackendServer backend) {
  final messages =
      (jsonDecode(backend.lastChatBody) as Map)['messages'] as List;
  return (
    system: messages.first['content'] as String,
    user: messages.last['content'] as String,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late FakeBackendServer backend;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    backend = await FakeBackendServer.start(
      replyPieces: const ['She looks toward the porch rail.'],
    );
    db = AppDatabase.forTesting();
    storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    await storage.initialized;
  });

  tearDown(() async {
    chat.dispose();
    await backend.close();
    await db.close();
  });

  Future<void> bootGroup() async {
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-swap', name: 'The Cast'),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-zinna',
        groupId: 'grp-swap',
        name: 'Zinna',
        personality: const Value('ZINNA_PERSONA_MARKER porch host'),
        mesExample: const Value('ZINNA_EXAMPLE_MARKER: evening on the porch.'),
        scenario: const Value('ZINNA_SCENARIO_MARKER the front porch at dusk'),
        avatarFilename: const Value('zinna.png'),
        frontPorchExtensions: const Value(_off),
      ),
    );
    await db.insertGroupMember(
      GroupMembersCompanion.insert(
        id: 'mem-senju',
        groupId: 'grp-swap',
        name: 'Senjumaru',
        personality: const Value('SENJUMARU_PERSONA_MARKER thousand arms'),
        mesExample: const Value(
          'SENJUMARU_EXAMPLE_MARKER: the loom clicks once.',
        ),
        scenario: const Value(
          'SENJUMARU_SCENARIO_MARKER riverside of the World of the Living',
        ),
        avatarFilename: const Value('senju.png'),
        frontPorchExtensions: const Value(_off),
      ),
    );
    await chat.setActiveGroup(
      GroupChat(id: 'grp-swap', name: 'The Cast'),
      groupRepo: GroupChatRepository(storage, db),
    );
  }

  CharacterCard member(String name) =>
      chat.groupCharacters.firstWhere((c) => c.name == name);

  test("Senjumaru's turn does not wear Zinna's costume", () async {
    await bootGroup();
    chat.setNextCharacter(member('Senjumaru'));
    await chat.sendMessage('What do you see?');

    final w = _wire(backend);
    expect(w.user, contains('SENJUMARU_PERSONA_MARKER'));
    expect(w.user, contains('SENJUMARU_EXAMPLE_MARKER'));
    expect(w.system, isNot(contains('ZINNA_PERSONA_MARKER')));
    expect(w.user, isNot(contains('ZINNA_PERSONA_MARKER')));
    expect(w.system, isNot(contains('ZINNA_EXAMPLE_MARKER')));
    expect(w.user, isNot(contains('ZINNA_EXAMPLE_MARKER')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('costume sits after the transcript, not in system', () async {
    await bootGroup();
    chat.setNextCharacter(member('Senjumaru'));
    await chat.sendMessage('What do you see?');

    final w = _wire(backend);
    expect(w.system, isNot(contains('SENJUMARU_PERSONA_MARKER')));
    expect(w.system, isNot(contains('SENJUMARU_EXAMPLE_MARKER')));
    expect(w.user, contains('SENJUMARU_PERSONA_MARKER'));
    expect(w.user, contains('You are Senjumaru'));
    expect(
      w.user.indexOf('<START>'),
      lessThan(w.user.indexOf('SENJUMARU_PERSONA_MARKER')),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('riverside is not the Scenario block', () async {
    await bootGroup();
    chat.setNextCharacter(member('Senjumaru'));
    await chat.sendMessage('What do you see?');

    final w = _wire(backend);
    expect(w.system, isNot(contains('SENJUMARU_SCENARIO_MARKER')));
    expect(w.user, isNot(contains('SENJUMARU_SCENARIO_MARKER')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test("Zinna's turn does not wear Senjumaru's costume", () async {
    await bootGroup();
    chat.setNextCharacter(member('Zinna'));
    await chat.sendMessage('Good evening.');

    final w = _wire(backend);
    expect(w.user, contains('ZINNA_PERSONA_MARKER'));
    expect(w.user, contains('ZINNA_EXAMPLE_MARKER'));
    expect(w.system, isNot(contains('SENJUMARU_PERSONA_MARKER')));
    expect(w.user, isNot(contains('SENJUMARU_PERSONA_MARKER')));
    expect(w.system, isNot(contains('SENJUMARU_EXAMPLE_MARKER')));
    expect(w.user, isNot(contains('SENJUMARU_EXAMPLE_MARKER')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('1:1 still puts persona in system', () async {
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Malumbra',
        personality: 'SOLO_PERSONA_MARKER a quiet host',
        firstMessage: 'The hall is cold.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'char-solo-swap',
    );
    await chat.sendMessage('Hello.');
    final w = _wire(backend);
    expect(w.system, contains('SOLO_PERSONA_MARKER'));
    expect(w.system, contains("Malumbra's Persona"));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test("Continue of Senjumaru keeps Senjumaru's costume", () async {
    await bootGroup();
    chat.setNextCharacter(member('Senjumaru'));
    await chat.sendMessage('What do you see?');
    await chat.continueGeneration();

    final w = _wire(backend);
    expect(w.user, contains('SENJUMARU_PERSONA_MARKER'));
    expect(w.user, isNot(contains('ZINNA_PERSONA_MARKER')));
    expect(w.user, isNot(contains('ZINNA_EXAMPLE_MARKER')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('regen of Senjumaru still resolves Senjumaru', () async {
    await bootGroup();
    chat.setNextCharacter(member('Senjumaru'));
    await chat.sendMessage('What do you see?');
    expect(chat.messages.last.sender, 'Senjumaru');
    await chat.regenerateLastMessage();
    expect(chat.messages.last.sender, 'Senjumaru');
    final w = _wire(backend);
    expect(w.user, contains('SENJUMARU_PERSONA_MARKER'));
    expect(w.user, isNot(contains('ZINNA_PERSONA_MARKER')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('group impersonate uses the roster, not joined personas', () async {
    await bootGroup();
    await chat.impersonateUser(onToken: (_) {});
    final w = _wire(backend);
    expect(w.system, contains('Also present:'));
    expect(w.system, isNot(contains('ZINNA_PERSONA_MARKER')));
    expect(w.system, isNot(contains('SENJUMARU_PERSONA_MARKER')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  group('turn card (layout B)', () {
    Future<void> bootPorch({String groupPrompt = ''}) async {
      await db.insertGroup(
        GroupsCompanion.insert(id: 'grp-porch', name: 'Porch'),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-ayla',
          groupId: 'grp-porch',
          name: 'Ayla',
          personality: const Value('Ayla is warm.'),
          mesExample: const Value(
            '<START>\n{{user}}: Hi.\n{{char}}: AYLA_EXAMPLE_MARKER',
          ),
          systemPrompt: const Value('AYLA_CARD_PROMPT_MARKER'),
          postHistoryInstructions: const Value('AYLA_POST_HISTORY_MARKER'),
          avatarFilename: const Value('ayla.png'),
          frontPorchExtensions: const Value(_off),
        ),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-misty',
          groupId: 'grp-porch',
          name: 'Misty',
          personality: const Value('Misty loves stray cats.'),
          avatarFilename: const Value('misty.png'),
          frontPorchExtensions: const Value(
            '{"version":"2.5","realism_engine":{"tier":"lite"}}',
          ),
        ),
      );
      await chat.setActiveGroup(
        GroupChat(
          id: 'grp-porch',
          name: 'Porch',
          scenario: 'PORCH_SCENE_MARKER a summer evening',
          systemPrompt: groupPrompt,
        ),
        groupRepo: GroupChatRepository(storage, db),
      );
    }

    test('the card carries framed examples and every instruction', () async {
      await bootPorch();
      chat.setNextCharacter(member('Ayla'));
      await chat.sendMessage('Evening, Ayla.');
      final w = _wire(backend);
      expect('<START>'.allMatches(w.user), hasLength(1));
      expect(w.user, contains('(example only, not part of this scene)'));
      expect(w.user, contains('AYLA_EXAMPLE_MARKER'));
      expect(w.user, contains('[Instructions for Ayla]'));
      expect(w.user, contains('AYLA_CARD_PROMPT_MARKER'));
      expect(w.user, contains('AYLA_POST_HISTORY_MARKER'));
      expect(w.system, isNot(contains('AYLA_CARD_PROMPT_MARKER')));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'a visitor keeps the shared scene and is marked in the cast',
      () async {
        await bootPorch();
        chat.setNextCharacter(member('Misty'));
        await chat.sendMessage('Misty, is that your cat?');
        final w = _wire(backend);
        expect(w.user, contains('PORCH_SCENE_MARKER'));
        expect(w.user, contains('SCENE GUEST TURN. You are Misty'));
        expect(w.system, contains('Misty (visitor)'));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('a custom group prompt replaces only the style', () async {
      await bootPorch(groupPrompt: 'CUSTOM_STYLE_MARKER');
      chat.setNextCharacter(member('Ayla'));
      await chat.sendMessage('Evening.');
      final w = _wire(backend);
      expect(w.system, startsWith('CUSTOM_STYLE_MARKER'));
      expect(w.system, contains('[Group scene]'));
      expect(w.system, isNot(contains('[Director Mode]')));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('group impersonate keeps the reply head, not the card', () async {
      await bootPorch();
      chat.setNextCharacter(member('Ayla'));
      await chat.sendMessage('Evening.');
      await chat.impersonateUser(onToken: (_) {});
      final w = _wire(backend);
      expect(w.system, contains('[Group scene]'));
      expect(w.system, isNot(contains('AYLA_CARD_PROMPT_MARKER')));
      expect(w.system, isNot(contains('The card below')));
      expect(w.user, contains('PORCH_SCENE_MARKER'));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // A group has no active character between turns. The post-reply pass put
  // the pointer back only when there had been one, so whoever answered first
  // stayed active for the rest of the visit: the chat page dressed your
  // bubbles in their colours and font, and the phone's panels with nobody
  // focused read whoever that was, or nobody.
  group('once a member has answered, none stays active', () {
    Future<void> drain() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    testWidgets('your bubbles keep your own colours and font', (tester) async {
      const zinnaInk = Color(0xFFE53935);
      late ChatMessage yours;
      await tester.runAsync(() async {
        await bootGroup();
        member('Zinna').frontPorchExtensions!
          ..userTextColor = zinnaInk
          ..chatFontFamily = 'Zinna Hand';
        await chat.sendMessage('Evening, both of you.');
        await drain();
        yours = chat.messages.lastWhere((m) => m.isUser);
      });
      expect(chat.messages.last.sender, 'Zinna');
      expect(chat.activeCharacter, isNull);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<StorageService>.value(value: storage),
            ChangeNotifierProvider<TtsService>.value(value: FakeTtsService()),
            ChangeNotifierProvider<ChatService>.value(value: chat),
            ChangeNotifierProvider<UserPersonaService>.value(
              value: FakeUserPersonaService(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: yours,
                index: chat.messages.indexOf(yours),
                chatService: chat,
              ),
            ),
          ),
        ),
      );
      // The style your words are drawn in, as the bubble's spans resolve it.
      TextStyle? drawn;
      void walk(InlineSpan span, TextStyle? outer) {
        final style = outer?.merge(span.style) ?? span.style;
        if (span is! TextSpan) return;
        if ((span.text ?? '').contains('Evening')) drawn ??= style;
        for (final child in span.children ?? const <InlineSpan>[]) {
          walk(child, style);
        }
      }

      walk(
        tester
            .widget<RichText>(
              find.textContaining('Evening, both of you.', findRichText: true),
            )
            .text,
        null,
      );
      expect(drawn?.color, storage.uiSettings.getUserTextColor(null));
      expect(drawn?.color, isNot(zinnaInk));
      expect(drawn?.fontFamily, isNot('Zinna Hand'));
    });

    test("a goal set on the phone with nobody focused is the first member's, "
        'as its header shows', () async {
      await bootGroup();
      await chat.sendMessage('Evening, both of you.');
      await drain();
      expect(chat.messages.last.sender, 'Zinna');
      expect(chat.nextCharacter?.name, 'Senjumaru');

      await ChatToolsFacade(
        chat,
        storage,
        null,
      ).setObjective('Mend the porch rail');
      Future<List<String>> goalsOf(String name) async => [
        for (final o in await chat.getActiveObjectivesFor(member(name)))
          o.objective,
      ];
      expect(await goalsOf('Zinna'), ['Mend the porch rail']);
      expect(await goalsOf('Senjumaru'), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test("the phone's pockets with nobody focused are the first "
        "member's", () async {
      await storage.realismSettings.setPocketsEnabled(true);
      await bootGroup();
      final tools = ChatToolsFacade(chat, storage, null);
      expect(tools.state()['pockets'], isNotNull, reason: "Zinna's kit shows");

      await tools.addPocketItem(section: 'carrying', name: 'a brass key');
      List<String>? carried() => chat
          .pocketsFor(chat.characterIdFor(member('Zinna')))
          ?.carrying
          .map((i) => i.name)
          .toList();
      expect(carried(), ['a brass key']);

      await tools.removePocketItem(section: 'carrying', index: 0);
      expect(carried(), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
