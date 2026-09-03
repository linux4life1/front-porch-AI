// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Gallery "Replace portrait" used to write a new Name_<timestamp>.png and
// store that filename as the character's portable ID. Objectives, RAG
// embeddings, Data Bank, Journal, and Growth all key off that filename.
// After the replace, lookups missed; Database Cleanup then treated the
// old-filename rows as orphans and deleted them. The chat transcript
// survived (UUID). The memories, quests, and diary did not.
//
// These tests pin both halves: (1) changing image_path without a re-key
// still looks like the old landmine to cleanup, (2) rekey + path update
// keeps every filename-keyed row, (3) CharacterRepository.setCharacterImagePath
// is the call site that must fire the re-key.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/database/database_cleanup.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(sameIsolate: true);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedKeyedRows({
    required String uuid,
    required String imagePath,
    required String name,
    required String sessionId,
  }) async {
    final sgid = stableGroupIdFrom(imagePath, name);
    await db
        .into(db.characters)
        .insert(
          CharactersCompanion.insert(
            id: uuid,
            name: name,
            imagePath: Value(imagePath),
          ),
        );
    await db
        .into(db.sessions)
        .insert(
          SessionsCompanion.insert(id: sessionId, characterId: Value(uuid)),
        );
    await db
        .into(db.objectives)
        .insert(
          ObjectivesCompanion.insert(
            id: 'obj-$sessionId',
            characterId: sgid,
            objective: 'Share porch lemonade',
            chatId: Value(sessionId),
          ),
        );
    await db.insertDataBankEntry(
      DataBankEntriesCompanion.insert(
        id: 'bank-$sessionId',
        characterId: sgid,
        title: 'keys',
        content: 'Spare under the mat.',
      ),
    );
    await db
        .into(db.messageEmbeddings)
        .insert(
          MessageEmbeddingsCompanion.insert(
            id: 'emb-$sessionId',
            sessionId: sessionId,
            characterId: Value(sgid),
            positionStart: 0,
            positionEnd: 1,
            content: 'we sat on the porch',
            embedding: Uint8List.fromList(const [1, 2, 3, 4]),
            dimensions: 1,
          ),
        );
    await db
        .into(db.journalMemories)
        .insert(
          JournalMemoriesCompanion.insert(
            id: 'jrnl-$sessionId',
            sessionId: sessionId,
            characterId: sgid,
            content: 'I left my keys on the table.',
          ),
        );
    await db
        .into(db.growthRings)
        .insert(
          GrowthRingsCompanion.insert(
            id: 'ring-$sessionId',
            sessionId: sessionId,
            characterId: sgid,
            content: 'She started leaving the porch light on.',
          ),
        );
  }

  test(
    'updating image_path without a re-key makes live filename-keyed rows look orphaned',
    () async {
      await seedKeyedRows(
        uuid: 'uuid-aerin',
        imagePath: '/library/Aerin_111.png',
        name: 'Aerin',
        sessionId: 'sess-aerin',
      );

      await (db.update(
        db.characters,
      )..where((c) => c.id.equals('uuid-aerin'))).write(
        const CharactersCompanion(imagePath: Value('/library/Aerin_222.png')),
      );

      final report = await DatabaseCleanup.checkOrphans(db);
      expect(
        report.orphanCounts['objectives'],
        1,
        reason:
            'old-filename objectives must look orphaned after a path change',
      );
      expect(report.orphanCounts['data_bank_entries'], 1);
      expect(report.orphanCounts['message_embeddings'], 1);

      final cleaned = await DatabaseCleanup.cleanOrphans(db);
      expect(cleaned.removedCounts['objectives'], 1);
      expect(cleaned.removedCounts['data_bank_entries'], 1);
      expect(cleaned.removedCounts['message_embeddings'], 1);
      expect(await db.select(db.objectives).get(), isEmpty);
    },
  );

  test(
    'rekey then image_path update: cleanup keeps objectives, Data Bank, RAG, Journal, Growth',
    () async {
      await seedKeyedRows(
        uuid: 'uuid-aerin',
        imagePath: '/library/Aerin_111.png',
        name: 'Aerin',
        sessionId: 'sess-aerin',
      );
      const fromId = 'Aerin_111';
      const toId = 'Aerin_222';

      await db.rekeyStableCharacterId(fromId, toId);
      await (db.update(
        db.characters,
      )..where((c) => c.id.equals('uuid-aerin'))).write(
        const CharactersCompanion(imagePath: Value('/library/Aerin_222.png')),
      );

      final report = await DatabaseCleanup.checkOrphans(db);
      expect(report.orphanCounts['objectives'], 0);
      expect(report.orphanCounts['data_bank_entries'], 0);
      expect(report.orphanCounts['message_embeddings'], 0);
      expect(
        report.orphanCounts['journal_memories'],
        0,
        reason: 'journal is session-scoped; the session is still live',
      );
      expect(report.orphanCounts['growth_rings'], 0);

      final cleaned = await DatabaseCleanup.cleanOrphans(db);
      expect(cleaned.removedCounts['objectives'] ?? 0, 0);
      expect(cleaned.removedCounts['data_bank_entries'] ?? 0, 0);
      expect(cleaned.removedCounts['message_embeddings'] ?? 0, 0);

      expect((await db.select(db.objectives).get()).single.characterId, toId);
      expect(
        (await db.select(db.dataBankEntries).get()).single.characterId,
        toId,
      );
      expect(
        (await db.select(db.messageEmbeddings).get()).single.characterId,
        toId,
      );
      expect(
        (await db.select(db.journalMemories).get()).single.characterId,
        toId,
      );
      expect((await db.select(db.growthRings).get()).single.characterId, toId);
    },
  );

  test(
    'setCharacterImagePath re-keys so cleanup does not wipe the diary',
    () async {
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final tmp = Directory.systemTemp.createTempSync('fpai_portrait_id_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tmp.path;
            }
            return null;
          });
      SharedPreferences.setMockInitialValues({});
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });

      final storage = StorageService();
      await storage.initialized;
      final repo = CharacterRepository(db, storage);
      await Future<void>.delayed(Duration.zero);

      final card = CharacterCard(name: 'Aerin');
      final v2 = V2CardService();
      await storage.charactersDir.create(recursive: true);
      final oldPath = '${storage.charactersDir.path}/Aerin_111.png';
      await v2.saveCardAsPng(card, oldPath, null);
      card.imagePath = oldPath;
      await repo.addCharacter(card);
      expect(card.dbId, isNotNull);

      final oldSgid = stableGroupIdFrom(oldPath, 'Aerin');
      expect(oldSgid, 'Aerin_111');
      await db
          .into(db.objectives)
          .insert(
            ObjectivesCompanion.insert(
              id: 'obj-live',
              characterId: oldSgid,
              objective: 'Keep the porch light on',
            ),
          );

      final newPath = '${storage.charactersDir.path}/Aerin_222.png';
      await v2.saveCardAsPng(CharacterCard(name: 'Aerin'), newPath, null);
      await repo.setCharacterImagePath(card, newPath);

      final report = await DatabaseCleanup.checkOrphans(db);
      expect(
        report.orphanCounts['objectives'],
        0,
        reason:
            'setCharacterImagePath must re-key before cleanup can see a new filename',
      );
      final left = await db.select(db.objectives).get();
      expect(left, hasLength(1));
      expect(left.single.characterId, 'Aerin_222');
    },
  );
}
