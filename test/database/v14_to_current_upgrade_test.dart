// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Schema-52 library written by shipped v1.4.0 ChatService / session
// save. Tip must migrate to 53, hydrate clocks/messages/swipes/Needs,
// and do it again without rewriting the story clock.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_v14_pin_').path;
        }
        return null;
      });
}

Map<String, Object?> _sqliteMeta(String path) {
  final out = Process.runSync('python3', [
    '-c',
    'import sqlite3,json;c=sqlite3.connect(r"""$path""");'
        'cols=[r[1] for r in c.execute("PRAGMA table_info(sessions)")];'
        'print(json.dumps({'
        '"user_version":c.execute("PRAGMA user_version").fetchone()[0],'
        '"has_gate":"passage_of_time_gate_migrated" in cols'
        '}))',
  ]);
  return (jsonDecode(out.stdout as String) as Map).cast<String, Object?>();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test('a v1.4.0 schema-52 library opens twice on current', () async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({'update_auto_check': false});

    final expected =
        jsonDecode(
              File(
                'test/fixtures/v14_upgrade/expected.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final chats = (expected['chats'] as List).cast<Map<String, dynamic>>();

    final dir = Directory.systemTemp.createTempSync('fpai_v14_pin_db_');
    final work = File('${dir.path}/library.db');
    File('test/fixtures/v14_upgrade/library.db').copySync(work.path);

    final pre = _sqliteMeta(work.path);
    expect(pre['user_version'], 52);
    expect(pre['has_gate'], isFalse);

    Future<Map<String, Map<String, Object?>>> hydrateOnce() async {
      final db = AppDatabase.forReunification(work);
      await db.ensureSchemaIsRepaired();
      final storage = StorageService();
      final repo = CharacterRepository(db, storage);
      final chat =
          ChatService(
              KoboldService(storage),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(repo)
            ..setGroupChatRepository(GroupChatRepository(storage, db));
      await storage.initialized;
      await repo.loadCharacters();
      final out = <String, Map<String, Object?>>{};
      for (final spec in chats) {
        if (spec['isGroup'] == true) {
          await chat.setActiveGroup(
            GroupChat(
              id: spec['groupId'] as String,
              name: spec['groupName'] as String,
            ),
            groupRepo: GroupChatRepository(storage, db),
          );
        } else {
          final card = repo.characters.firstWhere(
            (c) => c.name == spec['character'],
          );
          await chat.setActiveCharacter(card);
        }
        await chat.loadSession(spec['sessionId'] as String);
        out[spec['label'] as String] = {
          'clock': chat.timeService.storyClockIso,
          'day': chat.timeService.dayCount,
          'tod': chat.timeService.timeOfDay,
          'msgs': chat.messages.length,
          'senders': chat.messages.map((m) => m.sender).toList(),
          'swipes': chat.messages.map((m) => m.swipes.length).toList(),
          'needsOn': chat.needsSimEnabled,
          'hunger': chat.needsSimulation.vector['hunger'],
          'pot': storage.realismSettings.passageOfTimeDefault,
        };
      }
      chat.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final ver = await db.customSelect('PRAGMA user_version').get();
      final cols = await db.customSelect('PRAGMA table_info(sessions)').get();
      final names = [for (final c in cols) c.data['name'] as String];
      final gates = await db
          .customSelect(
            'SELECT id, passage_of_time_gate_migrated, story_clock '
            'FROM sessions ORDER BY id',
          )
          .get();
      await db.close();
      out['_meta'] = {
        'user_version': ver.first.data.values.first,
        'has_gate': names.contains('passage_of_time_gate_migrated'),
        'gates': [for (final r in gates) Map<String, Object?>.from(r.data)],
      };
      return out;
    }

    final first = await hydrateOnce();
    expect(first['_meta']!['user_version'], 53);
    expect(first['_meta']!['has_gate'], isTrue);
    for (final spec in chats) {
      final label = spec['label'] as String;
      final row = first[label]!;
      expect(row['clock'], spec['clock'], reason: '$label clock');
      expect(row['day'], spec['dayCount'], reason: '$label day');
      expect(row['tod'], spec['timeOfDay'], reason: '$label period');
      expect(row['msgs'], spec['messageCount'], reason: '$label messages');
      expect(
        (row['senders'] as List).join(','),
        (spec['senders'] as List).join(','),
        reason: '$label names',
      );
      expect(
        (row['swipes'] as List).join(','),
        (spec['swipeCounts'] as List).join(','),
        reason: '$label swipes',
      );
      expect(row['needsOn'], spec['needsOn'], reason: '$label needs gate');
      expect(row['hunger'], spec['hunger'], reason: '$label lived-in hunger');
      expect(row['pot'], isTrue, reason: 'never-touched 1.4 PoT default');
    }

    final second = await hydrateOnce();
    expect(second['_meta']!['user_version'], 53);
    for (final spec in chats) {
      final label = spec['label'] as String;
      expect(second[label]!['clock'], first[label]!['clock']);
      expect(second[label]!['msgs'], first[label]!['msgs']);
      expect(second[label]!['hunger'], first[label]!['hunger']);
    }
    final gates = second['_meta']!['gates'] as List;
    expect(
      gates.every((g) => (g as Map)['passage_of_time_gate_migrated'] == 1),
      isTrue,
    );

    dir.deleteSync(recursive: true);
  });
}
