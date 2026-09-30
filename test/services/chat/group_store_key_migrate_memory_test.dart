// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// R1: journal / growth / embeddings keyed by the display-name must
// re-key onto the member UUID after load. Panel sources and package
// export read them. A second session's Ana is untouched. Second load
// is a no-op.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_mem_mig_').path;
        }
        return null;
      });
}

Map<String, dynamic> _fpaiOf(Uint8List zip) {
  final archive = ZipDecoder().decodeBytes(zip);
  final file = archive.files.firstWhere(
    (f) => f.name.endsWith('.json') || f.name.contains('fpai'),
  );
  final root =
      jsonDecode(utf8.decode(file.content as List<int>))
          as Map<String, dynamic>;
  final inner = root['fpai'];
  if (inner is Map<String, dynamic>) return inner;
  if (inner is Map) return Map<String, dynamic>.from(inner);
  return root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  test(
    'name-keyed journal, growth and embeddings rekey to UUID once',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({
        'update_auto_check': false,
        'realism_default': true,
        'needs_sim_default': true,
      });
      final db = AppDatabase.forTesting();
      addTearDown(db.close);
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
      addTearDown(chat.dispose);
      await storage.initialized;

      await db.insertGroup(
        GroupsCompanion.insert(id: 'grp-mem', name: 'Memory'),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-ana',
          groupId: 'grp-mem',
          name: 'Ana',
          firstMessage: const Value('Evening.'),
        ),
      );
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-mem',
          characterId: const Value('group_grp-mem'),
          groupId: const Value('grp-mem'),
          realismEnabled: const Value(true),
          groupRealismState: Value(
            jsonEncode({
              'perChar': {'Ana': defaultGroupMemberRealismSeed()},
            }),
          ),
        ),
      );
      await db.insertMessage(
        MessagesCompanion.insert(
          id: 'm0',
          sessionId: 'sess-mem',
          position: 0,
          sender: 'Ana',
          isUser: false,
          swipes: Value(jsonEncode(['Evening.'])),
        ),
      );
      await db.insertJournalCard(
        JournalMemoriesCompanion.insert(
          id: 'j-ana',
          sessionId: 'sess-mem',
          characterId: 'Ana',
          content: 'Ana kept the porch lamp lit.',
        ),
      );
      await db.insertGrowthRing(
        GrowthRingsCompanion.insert(
          id: 'g-ana',
          sessionId: 'sess-mem',
          characterId: 'Ana',
          content: 'Ana is learning the street names.',
        ),
      );
      await db.insertEmbedding(
        MessageEmbeddingsCompanion.insert(
          id: 'e-ana',
          sessionId: 'sess-mem',
          characterId: const Value('Ana'),
          positionStart: 0,
          positionEnd: 0,
          content: 'Evening.',
          embedding: Uint8List.fromList(const [0, 1, 2, 3]),
          dimensions: 4,
        ),
      );

      await db.insertGroup(
        GroupsCompanion.insert(id: 'grp-other', name: 'Other'),
      );
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: 'mem-ana-b',
          groupId: 'grp-other',
          name: 'Ana',
          firstMessage: const Value('Hi.'),
        ),
      );
      await db.insertSession(
        SessionsCompanion.insert(
          id: 'sess-other',
          characterId: const Value('group_grp-other'),
          groupId: const Value('grp-other'),
        ),
      );
      await db.insertJournalCard(
        JournalMemoriesCompanion.insert(
          id: 'j-other',
          sessionId: 'sess-other',
          characterId: 'Ana',
          content: 'The other Ana is a different person.',
        ),
      );

      await chat.setActiveGroup(
        GroupChat(id: 'grp-mem', name: 'Memory'),
        groupRepo: GroupChatRepository(storage, db),
      );
      for (var i = 0; i < 40 && chat.groupCharacters.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final ana = chat.groupCharacters.firstWhere((c) => c.name == 'Ana');
      expect(groupMemberStoreId(ana), 'mem-ana');
      expect(ana.stableGroupId, 'Ana');

      final journal = await db.getJournalCards('sess-mem', 'mem-ana');
      expect(
        journal.map((c) => c.content),
        contains('Ana kept the porch lamp lit.'),
        reason: 'Journal panel reads the UUID store key',
      );
      expect(await db.getJournalCards('sess-mem', 'Ana'), isEmpty);

      expect(
        chat.growthRingsForOwner('mem-ana').map((r) => r.content),
        contains('Ana is learning the street names.'),
        reason: 'Growth panel reads the UUID store key',
      );
      expect(await db.getGrowthRings('sess-mem', 'Ana'), isEmpty);

      final embeds = await db.getEmbeddingsForCharacters(['mem-ana']);
      expect(embeds, isNotEmpty, reason: 'embeddings rekey onto the UUID');
      expect(await db.getEmbeddingsForCharacters(['Ana']), isEmpty);

      final zip = await chat.exportToFpchat();
      expect(zip, isNotNull);
      final fpai = _fpaiOf(zip!);
      final journalExport = fpai['journal'] as List? ?? const [];
      expect(
        journalExport.any(
          (c) =>
              c is Map &&
              c['character_id'] == 'mem-ana' &&
              '${c['content']}'.contains('Ana kept the porch lamp lit.'),
        ),
        isTrue,
        reason: 'package export includes the rekeyed journal card',
      );
      final growthExport = fpai['growth'];
      final rings = growthExport is Map
          ? growthExport['rings'] as List? ?? const []
          : const [];
      expect(
        rings.any(
          (r) =>
              r is Map &&
              r['character_id'] == 'mem-ana' &&
              '${r['content']}'.contains('Ana is learning the street names.'),
        ),
        isTrue,
        reason: 'package export includes the rekeyed growth ring',
      );

      final other = await db.getJournalCards('sess-other', 'Ana');
      expect(
        other.map((c) => c.content),
        contains('The other Ana is a different person.'),
        reason: 'a second session holding a different Ana is untouched',
      );
      expect(await db.getJournalCards('sess-other', 'mem-ana'), isEmpty);

      Future<List<String>> keys() async {
        final j = await db.getJournalCardsForSession('sess-mem');
        final g = await db.getGrowthRingsForSession('sess-mem');
        final e = await db.getEmbeddingsForCharacters(['mem-ana', 'Ana']);
        return [
          ...j.map((c) => '${c.id}:${c.characterId}'),
          ...g.map((c) => '${c.id}:${c.characterId}'),
          ...e.map((c) => '${c.id}:${c.characterId}'),
        ]..sort();
      }

      final first = await keys();
      await chat.setActiveGroup(
        GroupChat(id: 'grp-mem', name: 'Memory'),
        groupRepo: GroupChatRepository(storage, db),
      );
      for (var i = 0; i < 40 && chat.groupCharacters.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(
        await keys(),
        first,
        reason: 'second load is a no-op — same rows and keys',
      );
    },
  );
}
