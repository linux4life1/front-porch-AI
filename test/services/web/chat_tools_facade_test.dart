// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/chat/objective_rewards.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools_facade.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';

import '../../golden/support/fakes.dart';

/// A fake with one set-aside character goal and one card goal from before
/// v58 (no origin column yet), for the web's objective JSON.
class _GoalsChat extends FakeChatService {
  _GoalsChat() : super(activeCharacter: CharacterCard(name: 'Vera'));

  static Objective _o(String id, {bool primary = false, String? status}) =>
      Objective(
        id: id,
        characterId: 'vera',
        objective: 'goal $id',
        tasks: '[]',
        active: true,
        isPrimary: primary,
        checkFrequency: 3,
        injectionDepth: 4,
        servedAmbition: primary ? null : 'open a bakery',
        createdAt: DateTime(2026),
        origin: primary ? null : 'character',
        status: status,
      );

  @override
  List<Objective> getObjectivesForGroupCharacter(CharacterCard character) => [
    _o('main', primary: true),
    _o('side', status: 'dormant'),
  ];
}

/// The same goals, with a tally cached for [owner].
class _TallyChat extends _GoalsChat {
  _TallyChat(this.owner);

  final String owner;

  @override
  ObjectiveTally get objectiveTally =>
      ObjectiveTally(charId: owner, landed: 2, letGo: 1);
}

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_test_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('ChatToolsFacade', () {
    late StorageService storage;
    late ChatToolsFacade facade;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
      // Hub is null: a unit test never broadcasts. The fake seeds chaos/nsfw/
      // time/needs deterministically (evening, day 3) and exposes empty
      // objectives, so the read snapshot is fully exercisable.
      facade = ChatToolsFacade(FakeChatService(), storage, null);
    });

    test('state() mirrors the desktop sidebar sections', () {
      final s = facade.state();
      expect(s['realismEnabled'], isTrue);
      expect((s['time'] as Map)['timeOfDay'], 'evening');
      expect((s['time'] as Map)['dayCount'], 3);
      expect((s['objectives'] as Map)['primary'], isNull);
      expect((s['objectives'] as Map)['secondary'], isEmpty);
      // Memory + recap blocks are present with defaults from StorageService.
      expect((s['memory'] as Map).containsKey('ragEnabled'), isTrue);
      expect((s['memory'] as Map).containsKey('journalEnabled'), isTrue);
      expect((s['summary'] as Map).containsKey('text'), isTrue);
    });

    test('applySettings only writes keys that are present', () async {
      final beforeWindow = storage.memorySettings.ragWindowSize;
      await facade.applySettings({
        'ragEnabled': true,
        'journalInterval': 9,
        'unknownKey': 'ignored',
      });
      expect(storage.memorySettings.ragEnabled, isTrue);
      expect(storage.memorySettings.journalInterval, 9);
      // A setting we never passed must stay untouched.
      expect(storage.memorySettings.ragWindowSize, beforeWindow);
    });

    test('applySettings ignores wrong-typed values', () async {
      final before = storage.memorySettings.journalInterval;
      await facade.applySettings({'journalInterval': 'not-an-int'});
      expect(storage.memorySettings.journalInterval, before);
    });

    // 2026-10-16, objectives that keep up: the web's goals panel shows a
    // set-aside goal dimmed and needs to know who the goal is from.
    test('objective JSON carries dormant and origin for the web', () {
      final f = ChatToolsFacade(_GoalsChat(), storage, null);
      final obj = f.state()['objectives'] as Map;
      final primary = obj['primary'] as Map;
      final side = (obj['secondary'] as List).single as Map;
      expect(primary['dormant'], isFalse);
      expect(primary['origin'], 'user', reason: 'pre-v58, no served ambition');
      expect(side['dormant'], isTrue);
      expect(side['origin'], 'character');
    });

    // 2026-10-16, objectives that keep up part 6: the phone shows the same
    // "2 landed · 1 let go" line as the desktop panel, and only for the
    // character whose goals are loaded.
    test('objective JSON carries the loaded character\'s tally', () {
      Map objectives(String owner) =>
          ChatToolsFacade(
                _TallyChat(owner),
                storage,
                null,
              ).state()['objectives']
              as Map;
      expect(objectives('Vera')['tally'], '2 landed · 1 let go');
      expect(objectives('Bram')['tally'], '');
    });

    test('objective task ops return false when the id is unknown', () async {
      expect(await facade.generateTasks('missing'), isFalse);
      expect(await facade.toggleTask('missing', 0), isFalse);
      expect(await facade.clearObjective('missing'), isFalse);
    });
  });

  // Stories from group chats (docs/design/stories-from-group-chats.md §5):
  // the relay's to-story accepts a group chat and makes the roster the
  // cast, led by the member the body names, set in the chat's world.
  group('ChatToolsFacade.toStory from a group chat', () {
    late AppDatabase db;
    late StorageService storage;
    late StoryRepository stories;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.forTesting(sameIsolate: true);
      storage = StorageService();
      stories = StoryRepository(db);
    });
    tearDown(() => db.close());

    ChatToolsFacade facadeFor(FakeChatService chat) => ChatToolsFacade(
      chat,
      storage,
      null,
      storyRepo: stories,
      personas: FakeUserPersonaService(),
      chatWorld: () => (id: 'kitchens', name: 'Greenhollow Estate'),
    );

    test(
      'three members become a three-member cast with the named lead',
      () async {
        final r = await facadeFor(_GroupChat()).toStory(
          faithful: true,
          length: 'Novella',
          pov: 'First Person',
          lead: 'm-dov',
        );
        expect(r['error'], isNull, reason: '$r');
        final saved = stories.getById(r['id'] as String)!;
        expect(saved.title, r['title']);
        expect(saved.chatGroupId, 'g-crew');
        expect(saved.chatGroupName, 'The Crew');
        expect(saved.chatHistorySessionIds, ['s-crew']);
        expect(saved.chatHistoryCharacterIds, ['m-mira', 'm-dov', 'm-ash']);
        expect(saved.characterCardSnapshots.map((s) => s['name']), [
          'Mira',
          'Dov',
          'Ash',
        ]);
        expect(saved.characterCardSnapshots.map((s) => s['role']), [
          'Supporting',
          'Protagonist',
          'Supporting',
        ]);
        expect(saved.characterCardSnapshots[1]['personality'], 'Dry.');
        expect(saved.includeUserPersona, isTrue);
        expect(saved.worldId, 'kitchens');
        expect(saved.worldName, 'Greenhollow Estate');
        expect(saved.concept, contains('between Mira, Dov & Ash'));
      },
    );

    test(
      'no lead named: the first member leads; the persona may lead too',
      () async {
        final first = await facadeFor(
          _GroupChat(),
        ).toStory(faithful: false, length: 'Short story', pov: 'First Person');
        final p = stories.getById(first['id'] as String)!;
        expect(p.characterCardSnapshots.first['role'], 'Protagonist');
        expect(p.characterCardSnapshots[1]['role'], 'Supporting');

        final you = await facadeFor(_GroupChat()).toStory(
          faithful: false,
          length: 'Short story',
          pov: 'First Person',
          lead: 'persona',
        );
        final q = stories.getById(you['id'] as String)!;
        expect(q.characterCardSnapshots.map((s) => s['role']).toSet(), {
          'Supporting',
        });
        expect(q.userPersonaRole, 'Protagonist');
      },
    );

    test('a 1:1 chat still makes a one-character story', () async {
      final r = await facadeFor(
        FakeChatService(activeCharacter: CharacterCard(name: 'Vera')),
      ).toStory(faithful: true, length: 'Novella', pov: 'First Person');
      final p = stories.getById(r['id'] as String)!;
      expect(p.chatGroupId, isNull);
      expect(p.characterCardSnapshots.single['name'], 'Vera');
      expect(p.worldId, 'kitchens');
    });
  });

  group("the phone's Afterglow switch", () {
    test("it is this chat's own, shown while Porch Life allows it, and the "
        "switch's old name flips it", () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await storage.initialized;
      final chat = _AfterglowChat();
      chat.nsfwService.seedFromV2OrExt(nsfwCooldownEnabled: false);
      final facade = ChatToolsFacade(chat, storage, null);
      final router = Router();
      WebChatToolsRoutes(facade, router);
      Map<String, dynamic> nsfw() =>
          facade.state()['nsfw'] as Map<String, dynamic>;

      expect(nsfw()['afterglowAllowed'], isFalse, reason: '18+ is off');
      await storage.realismSettings.setAdultThemesEnabled(true);
      await storage.realismSettings.setNsfwCooldownDefault(true);
      expect(nsfw()['afterglowAllowed'], isTrue);
      expect(nsfw()['afterglowSwitch'], isFalse);

      final res = await router.call(
        shelf.Request(
          'POST',
          Uri.parse('http://localhost/api/chat/tools/toggle'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'name': 'nsfwCooldown', 'value': true}),
        ),
      );
      expect(res.statusCode, 200);
      expect(chat.asked, [true]);
    });
  });
}

/// Records what the phone's Afterglow switch asks of the chat.
class _AfterglowChat extends FakeChatService {
  final asked = <bool>[];

  @override
  Future<void> setAfterglowEnabled(bool on) async => asked.add(on);
}

/// A group chat of three, as the chat service holds it: the roster's cards
/// carry the member ids as their dbId.
class _GroupChat extends FakeChatService {
  @override
  bool get isGroupMode => true;

  @override
  GroupChat? get activeGroup => GroupChat(id: 'g-crew', name: 'The Crew');

  @override
  List<CharacterCard> get groupCharacters => [
    CharacterCard(dbId: 'm-mira', name: 'Mira', description: 'A keeper.'),
    CharacterCard(dbId: 'm-dov', name: 'Dov', personality: 'Dry.'),
    CharacterCard(dbId: 'm-ash', name: 'Ash'),
  ];

  @override
  String? get currentSessionId => 's-crew';
}
