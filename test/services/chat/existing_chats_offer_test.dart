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
}
