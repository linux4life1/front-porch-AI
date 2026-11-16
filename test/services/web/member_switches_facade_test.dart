// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// PR 3 of docs/design/one-chat-ux.md, the phone's half: the tools feed speaks
// for the focused participant (`?participant=`), and the memberRealism /
// memberNeeds / memberAfterglow toggles flip that member's switch alone.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart' as shelf_router;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools/chat_tools_memory_bank.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools_facade.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';
import 'package:front_porch_ai/services/chat/group_memory.dart';
import 'package:front_porch_ai/utils/character_id.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

import '../../helpers/chat_db_teardown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => call.method == 'getApplicationDocumentsDirectory'
            ? Directory.systemTemp.createTempSync('fpai_sw_facade_').path
            : null,
      );

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late ChatToolsFacade facade;
  late shelf_router.Router router;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
      'needs_sim_default': true,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage));
    await storage.initialized;
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    final blobs = buildGroupRealismBlobs(
      seeds: {
        'mem-ana': defaultGroupMemberRealismSeed(),
        'mem-bea': defaultGroupMemberRealismSeed(),
      },
      needsEnabled: true,
      timeOfDay: 'morning',
      dayCount: 1,
    );
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-fac',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    for (final m in [('mem-ana', 'Ana'), ('mem-bea', 'Bea')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: m.$1,
          groupId: 'grp-fac',
          name: m.$2,
          firstMessage: const Value('Evening.'),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(
        id: 'grp-fac',
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.setRealismEnabled(true);
    await chat.setNeedsSimEnabled(true);
    facade = ChatToolsFacade(chat, storage, null);
    router = shelf_router.Router();
    WebChatToolsRoutes(facade, router);
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  ChatParticipant who(String n) => chat.cast.firstWhere((p) => p.name == n);

  Future<void> toggle(String name, String member, bool v) async {
    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/chat/tools/toggle'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'id': groupMemberStoreId(who(member).card),
          'value': v,
        }),
      ),
    );
    expect(res.statusCode, 200);
  }

  Map<String, dynamic> feed(String member) =>
      facade.state(participantId: who(member).id);

  test('the feed carries the focused member\'s switches and id', () async {
    final bea = feed('Bea');
    expect(bea['memberId'], groupMemberStoreId(who('Bea').card));
    expect(bea['realismSwitch'], isTrue);
    expect(bea['needsEnabled'], isTrue);
    expect((bea['nsfw'] as Map)['afterglowSwitch'], isTrue);
  });

  test('memberRealism, memberNeeds and memberAfterglow flip the focused '
      'participant alone', () async {
    await toggle('memberRealism', 'Bea', false);
    await toggle('memberNeeds', 'Bea', false);
    await toggle('memberAfterglow', 'Bea', false);

    final bea = feed('Bea');
    expect(bea['realismSwitch'], isFalse);
    expect(bea['realismEnabled'], isFalse);
    expect(bea['needsEnabled'], isFalse);
    expect((bea['nsfw'] as Map)['afterglowSwitch'], isFalse);

    final ana = feed('Ana');
    expect(ana['realismSwitch'], isTrue, reason: 'only Bea');
    expect(ana['realismEnabled'], isTrue);
    expect(ana['needsEnabled'], isTrue);
    expect((ana['nsfw'] as Map)['afterglowSwitch'], isTrue);
  });

  test('a member toggle with no member id is refused', () async {
    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/chat/tools/toggle'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'name': 'memberRealism', 'value': false}),
      ),
    );
    expect(res.statusCode, 400);
    expect(chat.realismSwitchFor(chat.characterIdFor(who('Ana').card)), isTrue);
  });

  test('in a group the web Memory switch and count are the group\'s own, '
      'and the global 1:1 setting stays put', () async {
    await storage.memorySettings.setRagEnabled(true);
    await storage.memorySettings.setRagRetrievalCount(5);
    expect(feed('Ana')['memory']['ragScope'], 'group');
    expect(feed('Ana')['memory']['ragEnabled'], chat.groupRagEnabled);
    expect(feed('Ana')['memory']['ragGlobalEnabled'], isTrue);

    final res = await router.call(
      shelf.Request(
        'POST',
        Uri.parse('http://localhost/api/chat/tools/settings'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'ragEnabled': false, 'ragRetrievalCount': 9}),
      ),
    );
    expect(res.statusCode, 200);

    expect(chat.groupRagEnabled, isFalse, reason: 'the group gate flipped');
    expect(chat.groupRetrievalCount, 9);
    expect(storage.memorySettings.ragEnabled, isTrue, reason: 'global kept');
    expect(storage.memorySettings.ragRetrievalCount, 5);
    final memory = feed('Bea')['memory'] as Map;
    expect(memory['ragEnabled'], isFalse, reason: 'the feed reads the gate');
    expect(memory['ragRetrievalCount'], 9);
  });

  group('the Memory section\'s Sources and Data Bank', () {
    late CharacterRepository library;
    late shelf_router.Router bankRouter;

    setUp(() async {
      for (final n in ['Ana', 'Bea', 'Zoe']) {
        await db
            .into(db.characters)
            .insert(
              CharactersCompanion.insert(
                id: 'lib-${n.toLowerCase()}',
                name: n,
                imagePath: Value('/library/${n}_1.png'),
              ),
            );
      }
      library = CharacterRepository(db, storage);
      await library.loadCharacters();
      final withBank = ChatToolsFacade(
        chat,
        storage,
        null,
        db: db,
        library: library,
      );
      bankRouter = shelf_router.Router();
      WebChatToolsRoutes(withBank, bankRouter);
    });

    Future<Map<String, dynamic>> call(
      String method,
      String path,
      String member, [
      Map<String, dynamic>? body,
    ]) async {
      final res = await bankRouter.call(
        shelf.Request(
          method,
          Uri.parse(
            'http://localhost/api/chat/tools/memory/$path'
            '?participant=${who(member).id}',
          ),
          headers: {'content-type': 'application/json'},
          body: body == null ? '' : jsonEncode(body),
        ),
      );
      final out = jsonDecode(await res.readAsString());
      return {'status': res.statusCode, ...(out as Map<String, dynamic>)};
    }

    test(
      'the Data Bank is the focused member\'s, kept under their memory id',
      () async {
        final add = await call('POST', 'databank', 'Ana', {
          'action': 'add',
          'title': 'Gate',
          'content': 'The garden gate is blue.',
        });
        expect(add['status'], 200);
        expect((add['entries'] as List).single['title'], 'Gate');
        expect(add['unembedded'], 1);

        // The row is the one the desktop dialog and retrieval read.
        final rows = await db.getDataBankEntriesForCharacter(
          memoryKeyFor(who('Ana').card, library.characters),
        );
        expect(rows.single.content, 'The garden gate is blue.');
        expect((await call('GET', 'databank', 'Bea'))['entries'], isEmpty);

        final id = (add['entries'] as List).single['id'] as String;
        // Another member's entry is not theirs to edit or delete.
        expect(
          (await call('POST', 'databank', 'Bea', {
            'action': 'delete',
            'id': id,
          }))['status'],
          400,
        );
        final edit = await call('POST', 'databank', 'Ana', {
          'action': 'edit',
          'id': id,
          'title': 'Gate',
          'content': 'The garden gate is red.',
        });
        expect((edit['entries'] as List).single['content'], contains('red'));
        final gone = await call('POST', 'databank', 'Ana', {
          'action': 'delete',
          'id': id,
        });
        expect(gone['entries'], isEmpty);
        expect(
          await db.getDataBankEntriesForCharacter(
            memoryKeyFor(who('Ana').card, library.characters),
          ),
          isEmpty,
        );
      },
    );

    test('Data Bank import chunks a text file; embed says when the engine is '
        'down', () async {
      final text = List.generate(
        7,
        (p) => List.generate(100, (i) => 'word${p}_$i').join(' '),
      ).join('\n\n');
      final imp = await call('POST', 'databank', 'Ana', {
        'action': 'import',
        'fileName': 'notes.txt',
        'dataBase64': base64Encode(utf8.encode(text)),
      });
      expect(imp['status'], 200);
      expect((imp['entries'] as List), hasLength(2));
      expect(imp['note'], contains('Imported 2'));
      final embed = await call('POST', 'databank', 'Ana', {'action': 'embed'});
      expect(embed['note'], ChatToolsMemoryBank.kEmbeddingUnavailable);
    });

    test(
      'Sources: the library minus the member, persisted on each toggle',
      () async {
        final before = await call('GET', 'sources', 'Ana');
        expect(before['available'], isTrue);
        final names = [for (final c in before['choices'] as List) c['name']];
        expect(names, containsAll(['Bea', 'Zoe']));
        expect(names, isNot(contains('Ana')));
        expect(before['selected'], isEmpty);

        final on = await call('POST', 'sources', 'Ana', {
          'id': 'Zoe_1',
          'selected': true,
        });
        expect(on['selected'], ['Zoe_1']);
        expect(await library.getMemorySources('lib-ana'), ['Zoe_1']);
        expect(await library.getMemorySources('lib-bea'), isEmpty);

        final off = await call('POST', 'sources', 'Ana', {
          'id': 'Zoe_1',
          'selected': false,
        });
        expect(off['selected'], isEmpty);
        expect(await library.getMemorySources('lib-ana'), isEmpty);
      },
    );
  });
}
