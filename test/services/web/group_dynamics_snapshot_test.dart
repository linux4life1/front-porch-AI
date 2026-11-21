// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The web twin of Group Dynamics (docs/design/one-chat-ux.md, PR 2): the
// chat tools snapshot carries the focused member's feelings toward each other
// member, read off the same hidden relationships map the desktop section
// reads. A real group chat, so the Realism gate and the roster are real.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_tools_facade.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

import '../../helpers/chat_db_teardown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_grp_dyn_').path;
        }
        return null;
      });

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;

  Future<void> boot(int members) async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
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
    final names = ['Ana', 'Bea', 'Cy', 'Dot', 'Eve'].take(members).toList();
    final ids = [for (final n in names) 'mem-${n.toLowerCase()}'];
    final blobs = buildGroupRealismBlobs(
      seeds: {
        for (var i = 0; i < ids.length; i++)
          ids[i]: {
            ...defaultGroupMemberRealismSeed(),
            // Ana likes the others; Bea cannot stand them.
            'relationships': <String, int>{
              for (var j = 0; j < ids.length; j++)
                if (j != i) ids[j]: i == 0 ? 150 : -90,
            },
          },
      },
      needsEnabled: true,
      timeOfDay: 'morning',
      dayCount: 1,
    );
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-dyn',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    for (var i = 0; i < ids.length; i++) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: ids[i],
          groupId: 'grp-dyn',
          name: names[i],
          firstMessage: const Value('Evening.'),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(
        id: 'grp-dyn',
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: GroupChatRepository(storage, db),
    );
    await chat.setRealismEnabled(true);
  }

  String idOf(String name) => chat.cast.firstWhere((p) => p.name == name).id;

  Map? dynamicsFor(String name) =>
      ChatToolsFacade(
            chat,
            storage,
            null,
          ).state(participantId: idOf(name))['groupDynamics']
          as Map?;

  test(
    'the snapshot carries the focused member\'s feelings toward the rest',
    () async {
      await boot(3);
      addTearDown(() => disposeChatThenCloseDb(chat, db));

      final ana = dynamicsFor('Ana')!;
      expect(ana['member'], 'Ana');
      expect(ana['tracked'], isTrue);
      final toward = {
        for (final f in (ana['feelings'] as List).cast<Map>())
          f['name']: f['score'],
      };
      expect(toward, {'Bea': 150, 'Cy': 150});
      expect((ana['feelings'] as List).first as Map, contains('tier'));

      final bea = dynamicsFor('Bea')!;
      expect(bea['member'], 'Bea');
      expect(
        {
          for (final f in (bea['feelings'] as List).cast<Map>())
            f['name']: f['score'],
        },
        {'Ana': -90, 'Cy': -90},
      );
    },
  );

  test('five members: not tracked, no feelings listed', () async {
    await boot(5);
    addTearDown(() => disposeChatThenCloseDb(chat, db));
    final ana = dynamicsFor('Ana')!;
    expect(ana['tracked'], isFalse);
    expect(ana['feelings'], isEmpty);
  });

  test('Realism off: the card is absent', () async {
    await boot(2);
    addTearDown(() => disposeChatThenCloseDb(chat, db));
    await chat.setRealismEnabled(false);
    expect(dynamicsFor('Ana'), isNull);
  });
}
