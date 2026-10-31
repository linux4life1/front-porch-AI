// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The existing-chats question: once Porch Life allows Afterglow, the chats
// whose own switch is off are counted and, only if asked, switched on. Only
// those chats' switches change: every other column, every chat already on,
// and a chat in the trash are left exactly as they were.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/existing_chats_offer.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';
import '../../golden/support/fakes.dart';
import '../../helpers/chat_db_teardown.dart';

/// A group chat open with Afterglow off that is left the moment its switch
/// has been read, as when the phone opens another chat mid-question.
class _LeavingChat extends FakeChatService {
  _LeavingChat(this._open);

  String? _open;

  @override
  String? get currentSessionId => _open;

  @override
  bool get isGroupMode => true;

  @override
  bool get afterglowChatSwitch {
    _open = 'another-chat';
    return false;
  }

  @override
  Future<void> setAfterglowEnabled(bool enabled) async =>
      fail('a chat no longer open is not switched live');
}

final Directory _root = Directory.systemTemp.createTempSync('fpai_offer_');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => call.method == 'getApplicationDocumentsDirectory'
            ? _root.path
            : null,
      );

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    db = AppDatabase.forTesting();
  });

  tearDown(() => db.close());

  final groupOff = jsonEncode({
    kGroupAfterglowKey: false,
    'perChar': {
      'mem-a': {'arousal': 0, 'affection': 40},
    },
  });
  final templateOff = buildGroupRealismBlobs(
    seeds: {'mem-a': defaultGroupMemberRealismSeed()},
    needsEnabled: true,
    afterglowEnabled: false,
    timeOfDay: 'evening',
    dayCount: 2,
  ).defaultMemberJson;

  Future<void> seed() async {
    await db.insertGroup(GroupsCompanion.insert(id: 'g-on', name: 'On'));
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'g-template-off',
        name: 'Template off',
        defaultMemberRealismState: Value(templateOff),
      ),
    );
    Future<void> session(
      String id, {
      String? character,
      String? group,
      bool afterglow = true,
      String? blob,
      bool deleted = false,
      int lust = 0,
    }) => db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: id,
            characterId: Value(character),
            groupId: Value(group),
            nsfwCooldownEnabled: Value(afterglow),
            groupRealismState: Value(blob ?? '{}'),
            characterEmotion: const Value('wistful'),
            arousalLevel: Value(lust),
            deletedAt: Value(deleted ? DateTime(2026, 10, 1) : null),
          ),
        );
    await session('one-off', character: 'char-a', afterglow: false);
    await session('one-on', character: 'char-b');
    // Stored off but holding Lust: the October overwrite, which opens on.
    await session(
      'one-repaired',
      character: 'char-d',
      afterglow: false,
      lust: 30,
    );
    await session(
      'one-trash',
      character: 'char-c',
      afterglow: false,
      deleted: true,
    );
    await session('group-off', group: 'g-on', blob: groupOff);
    await session('group-template-off', group: 'g-template-off');
    await session('group-on', group: 'g-on');
  }

  Future<Map<String, Map<String, Object?>>> rows() async => {
    for (final r in await db.customSelect('SELECT * FROM sessions').get())
      r.read<String>('id'): Map.of(r.data),
  };

  test(
    'counts the chats with their own Afterglow off: 1:1 and group, a '
    "group chat that still reads its group's choice, never the trash",
    () async {
      await seed();
      expect(await ExistingChatsOffer(db, null).countAfterglowOff(), 3);
    },
  );

  test("turning them on changes only those chats' switches", () async {
    await seed();
    final before = await rows();

    expect(await ExistingChatsOffer(db, null).turnAfterglowOn(), 3);
    final after = await rows();

    Set<String> changed(String id) => {
      for (final k in before[id]!.keys)
        if (before[id]![k] != after[id]![k]) k,
    };
    expect(changed('one-off'), {'nsfw_cooldown_enabled'});
    expect(after['one-off']!['nsfw_cooldown_enabled'], 1);
    expect(changed('group-off'), {'group_realism_state'});
    expect(changed('group-template-off'), {'group_realism_state'});
    for (final id in ['one-on', 'group-on', 'one-trash', 'one-repaired']) {
      expect(changed(id), isEmpty, reason: '$id was not asked about');
    }

    final group =
        jsonDecode(after['group-off']!['group_realism_state']! as String)
            as Map<String, dynamic>;
    expect(group[kGroupAfterglowKey], isTrue);
    expect(group['perChar'], jsonDecode(groupOff)['perChar'], reason: 'kept');
    final fromTemplate =
        after['group-template-off']!['group_realism_state']! as String;
    expect(groupAfterglowIn(fromTemplate), isTrue);
    expect(parseGroupRealismSeeds(fromTemplate).keys, [
      'mem-a',
    ], reason: "the chat keeps reading its group's seeds");
    expect(await ExistingChatsOffer(db, null).countAfterglowOff(), 0);
  });

  test('a group chat left between the count and the switch keeps its saved '
      'state: it is never written blind', () async {
    final saved = jsonEncode({
      kGroupAfterglowKey: false,
      'perChar': {
        'mem-a': {'affection': 40},
      },
    });
    await db.insertGroup(GroupsCompanion.insert(id: 'g-open', name: 'Open'));
    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: 'group-open',
            groupId: const Value('g-open'),
            groupRealismState: Value(saved),
          ),
        );
    final chat = _LeavingChat('group-open');
    addTearDown(chat.dispose);

    expect(await ExistingChatsOffer(db, chat).turnAfterglowOn(), 0);
    final row = await db
        .customSelect(
          "SELECT group_realism_state AS st FROM sessions WHERE id = 'group-open'",
        )
        .getSingle();
    expect(row.read<String>('st'), saved, reason: 'what it saved on leaving');
  });

  test('the open chat is read and switched live, so its next save keeps it '
      'on', () async {
    final storage = StorageService();
    final chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage));
    addTearDown(() => disposeChatThenCloseDb(chat, null));
    final previous = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = previous);
    await storage.initialized;
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Mara',
        firstMessage: 'The porch light hums.',
        frontPorchExtensions: FrontPorchExtensions(afterglowEnabled: false),
      )..dbId = 'char-offer-mara',
    );
    expect(chat.afterglowChatSwitch, isFalse, reason: 'the card starts it off');
    final offer = ExistingChatsOffer(db, chat);
    final open = chat.currentSessionId!;
    expect(await offer.countAfterglowOff(), greaterThanOrEqualTo(1));

    await offer.turnAfterglowOn();
    expect(chat.afterglowChatSwitch, isTrue);
    await chat.flushPendingSaves();
    final stored = await db
        .customSelect(
          'SELECT nsfw_cooldown_enabled AS n FROM sessions WHERE id = ?',
          variables: [Variable(open)],
        )
        .getSingle();
    expect(stored.read<bool>('n'), isTrue);
  });
  test("the phone's relay counts them, turns them on, and refuses a feature "
      'it does not know', () async {
    await seed();
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialized;
    final router = Router();
    WebSettingsRoutes(
      WebServerDeps(
        storage: storage,
        db: db,
        auth: AuthService(db),
        settingsFacade: SettingsFacade(storage, FakeLLMProvider()),
      ),
      router,
    );
    Future<shelf.Response> call(String method, String path, [Object? body]) =>
        router.call(
          shelf.Request(
            method,
            Uri.parse('http://localhost$path'),
            headers: {'content-type': 'application/json'},
            body: body == null ? null : jsonEncode(body),
          ),
        );
    Future<Map<String, dynamic>> ok(shelf.Response r) async {
      expect(r.statusCode, 200);
      return jsonDecode(await r.readAsString()) as Map<String, dynamic>;
    }

    const path = '/api/settings/existing-chats';
    expect(await ok(await call('GET', '$path?feature=afterglow')), {
      'count': 3,
    });
    expect((await call('GET', '$path?feature=lust')).statusCode, 400);
    expect(
      (await call('POST', path, {'feature': 'lust'})).statusCode,
      400,
      reason: 'and nothing changed',
    );
    expect(await ExistingChatsOffer(db, null).countAfterglowOff(), 3);
    expect(await ok(await call('POST', path, {'feature': 'afterglow'})), {
      'changed': 0,
    }, reason: 'Porch Life does not allow Afterglow here');
    expect(await ExistingChatsOffer(db, null).countAfterglowOff(), 3);
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    expect(await ok(await call('POST', path, {'feature': 'afterglow'})), {
      'changed': 3,
    });
    expect(await ok(await call('GET', '$path?feature=afterglow')), {
      'count': 0,
    });
  });
  test('Needs: counts the chats with their own Needs off that open off, and '
      "turning them on changes only those chats' Needs switch", () async {
    Future<void> session(
      String id, {
      String? character,
      String? group,
      String? vector,
      bool deleted = false,
      bool realism = false,
    }) => db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: id,
            characterId: Value(character),
            groupId: Value(group),
            needsSimEnabled: const Value(false),
            needsVector: Value(vector),
            realismEnabled: Value(realism),
            deletedAt: Value(deleted ? DateTime(2026, 10, 1) : null),
          ),
        );
    await db.insertGroup(GroupsCompanion.insert(id: 'g-n', name: 'N'));
    await session('lived-in', character: 'char-a', vector: '{"hunger":70}');
    await session('card-off', character: 'char-off');
    // No vector and a card that says nothing: it opens on with its Realism.
    await session('card-silent', character: 'char-a', realism: true);
    // The same with its Realism off: it opens off.
    await session('card-silent-off', character: 'char-a');
    await session('group-off', group: 'g-n');
    await session(
      'trash',
      character: 'char-a',
      vector: '{"hunger":70}',
      deleted: true,
    );
    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: 'already-on',
            characterId: const Value('char-a'),
            needsSimEnabled: const Value(true),
          ),
        );
    final cards = [
      CharacterCard(name: 'A')..dbId = 'char-a',
      CharacterCard(
        name: 'Off',
        frontPorchExtensions: FrontPorchExtensions(needsSimEnabled: false),
      )..dbId = 'char-off',
    ];
    final offer = ExistingChatsOffer(db, null, cards: cards);
    const needs = ExistingChatsFeature.needs;
    expect(await offer.countOff(needs), 4);

    final before = await rows();
    expect(await offer.turnOn(needs), 4);
    final after = await rows();
    for (final id in before.keys) {
      final changed = {
        for (final k in before[id]!.keys)
          if (before[id]![k] != after[id]![k]) k,
      };
      expect(
        changed,
        ['lived-in', 'card-off', 'card-silent-off', 'group-off'].contains(id)
            ? {'needs_sim_enabled'}
            : isEmpty,
        reason: id,
      );
    }
    expect(await offer.countOff(needs), 0);
  });
  test("the phone's relay asks about Needs too, and turns it on only while "
      'Porch Life allows it', () async {
    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: 'lived-in',
            characterId: const Value('char-a'),
            needsSimEnabled: const Value(false),
            needsVector: const Value('{"hunger":70}'),
          ),
        );
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialized;
    final router = Router();
    WebSettingsRoutes(
      WebServerDeps(
        storage: storage,
        db: db,
        auth: AuthService(db),
        settingsFacade: SettingsFacade(storage, FakeLLMProvider()),
      ),
      router,
    );
    Future<Map<String, dynamic>> call(String method, [Object? body]) async {
      final res = await router.call(
        shelf.Request(
          method,
          Uri.parse(
            'http://localhost/api/settings/existing-chats'
            '${method == 'GET' ? '?feature=needs' : ''}',
          ),
          headers: {'content-type': 'application/json'},
          body: body == null ? null : jsonEncode(body),
        ),
      );
      expect(res.statusCode, 200);
      return jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    }

    expect(await call('GET'), {'count': 1});
    await storage.realismSettings.setNeedsSimDefault(false);
    expect(await call('POST', {'feature': 'needs'}), {'changed': 0});
    await storage.realismSettings.setNeedsSimDefault(true);
    expect(await call('POST', {'feature': 'needs'}), {'changed': 1});
    expect(await call('GET'), {'count': 0});
  });

  Future<void> realismSessions() async {
    await db.insertGroup(GroupsCompanion.insert(id: 'g-r', name: 'R'));
    Future<void> session(
      String id, {
      required bool realism,
      String? group,
      bool deleted = false,
    }) => db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: id,
            characterId: Value(group == null ? 'char-a' : null),
            groupId: Value(group),
            realismEnabled: Value(realism),
            characterEmotion: const Value('wistful'),
            deletedAt: Value(deleted ? DateTime(2026, 10, 1) : null),
          ),
        );
    await session('solo-off', realism: false);
    await session('group-off', realism: false, group: 'g-r');
    await session('solo-on', realism: true);
    await session('group-on', realism: true, group: 'g-r');
    await session('trash-off', realism: false, deleted: true);
  }

  test('Realism: counts the 1:1 and group chats with their own switch off, '
      "never the trash, and turning them on changes only those chats' "
      'Realism switch', () async {
    await realismSessions();
    const realism = ExistingChatsFeature.realism;
    final offer = ExistingChatsOffer(db, null);
    expect(await offer.countOff(realism), 2);

    final before = await rows();
    expect(await offer.turnOn(realism), 2);
    final after = await rows();
    for (final id in before.keys) {
      final changed = {
        for (final k in before[id]!.keys)
          if (before[id]![k] != after[id]![k]) k,
      };
      expect(
        changed,
        ['solo-off', 'group-off'].contains(id) ? {'realism_enabled'} : isEmpty,
        reason: id,
      );
    }
    expect(after['solo-off']!['realism_enabled'], 1);
    expect(after['group-off']!['realism_enabled'], 1);
    expect(await offer.countOff(realism), 0);
  });

  test('Realism: the open chat is read and switched live, so its next save '
      'keeps it on', () async {
    final storage = StorageService();
    final chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage));
    addTearDown(() => disposeChatThenCloseDb(chat, null));
    final previous = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) {};
    addTearDown(() => debugPrint = previous);
    await storage.initialized;
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Mara',
        firstMessage: 'The porch light hums.',
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: false),
      )..dbId = 'char-offer-realism',
    );
    final open = chat.currentSessionId!;
    final offer = ExistingChatsOffer(db, chat);
    expect(await offer.countOff(ExistingChatsFeature.realism), 1);

    await offer.turnOn(ExistingChatsFeature.realism);
    expect(chat.realismChatSwitch, isTrue);
    expect(chat.realismEnabled, isTrue);
    await chat.flushPendingSaves();
    final stored = await db
        .customSelect(
          'SELECT realism_enabled AS r FROM sessions WHERE id = ?',
          variables: [Variable(open)],
        )
        .getSingle();
    expect(stored.read<bool>('r'), isTrue);
  });

  test("the phone's relay asks about Realism too, and turns it on only while "
      'Porch Life allows it', () async {
    await realismSessions();
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialized;
    final router = Router();
    WebSettingsRoutes(
      WebServerDeps(
        storage: storage,
        db: db,
        auth: AuthService(db),
        settingsFacade: SettingsFacade(storage, FakeLLMProvider()),
      ),
      router,
    );
    Future<Map<String, dynamic>> call(String method, [Object? body]) async {
      final res = await router.call(
        shelf.Request(
          method,
          Uri.parse(
            'http://localhost/api/settings/existing-chats'
            '${method == 'GET' ? '?feature=realism' : ''}',
          ),
          headers: {'content-type': 'application/json'},
          body: body == null ? null : jsonEncode(body),
        ),
      );
      expect(res.statusCode, 200);
      return jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    }

    expect(await call('GET'), {'count': 2});
    await storage.realismSettings.setRealismAllowed(false);
    expect(await call('POST', {'feature': 'realism'}), {'changed': 0});
    expect(await call('GET'), {'count': 2}, reason: 'nothing changed');
    await storage.realismSettings.setRealismAllowed(true);
    expect(await call('POST', {'feature': 'realism'}), {'changed': 2});
    expect(await call('GET'), {'count': 0});
  });

  test("while Realism is blocked the phone's relay has nothing to ask about "
      'Needs or Afterglow: an older phone gets a count of 0, not an error, '
      'and nothing changes', () async {
    await seed();
    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: 'needs-off',
            characterId: const Value('char-n'),
            needsSimEnabled: const Value(false),
            needsVector: const Value('{"hunger":70}'),
          ),
        );
    FlutterSecureStorage.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialized;
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    final router = Router();
    WebSettingsRoutes(
      WebServerDeps(
        storage: storage,
        db: db,
        auth: AuthService(db),
        settingsFacade: SettingsFacade(storage, FakeLLMProvider()),
      ),
      router,
    );
    Future<Map<String, dynamic>> call(String method, String feature) async {
      final res = await router.call(
        shelf.Request(
          method,
          Uri.parse(
            'http://localhost/api/settings/existing-chats'
            '${method == 'GET' ? '?feature=$feature' : ''}',
          ),
          headers: {'content-type': 'application/json'},
          body: method == 'GET' ? null : jsonEncode({'feature': feature}),
        ),
      );
      expect(res.statusCode, 200);
      return jsonDecode(await res.readAsString()) as Map<String, dynamic>;
    }

    expect((await call('GET', 'needs'))['count'], greaterThan(0));
    expect((await call('GET', 'afterglow'))['count'], greaterThan(0));
    await storage.realismSettings.setRealismAllowed(false);
    final before = await rows();
    for (final f in ['needs', 'afterglow']) {
      expect(await call('GET', f), {'count': 0}, reason: f);
      expect(await call('POST', f), {'changed': 0}, reason: f);
    }
    expect(await rows(), before, reason: 'nothing changed');
  });
}
