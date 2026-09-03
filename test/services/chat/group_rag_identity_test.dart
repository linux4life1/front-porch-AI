// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group Data Bank / memory-sources key by the library portrait basename
// (originStableId), never the group-private avatar UUID. A member shim's
// CharacterCard.stableGroupId is that UUID, so retrieve used to search
// ids that match nothing — 1:1 Data Bank and Sources were dead in groups.
//
// Proven red: libraryRagIdentity ignoring originStableId returns the
// unique-name fallback only after a deleted stamp (not the stamp itself),
// and the call-site scan fails when _getMemorySourceIds still walks
// _groupCharacters via _getCharacterIdFromCard.

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_grp_rag_').path;
        }
        return null;
      });
}

class _FakeEmbed extends EmbeddingService {
  _FakeEmbed(super.storage);

  @override
  bool get isAvailable => true;

  @override
  Future<void> checkAvailability() async {}

  @override
  Future<List<double>?> embed(String text) async => List<double>.filled(4, 0.1);
}

CharacterCard _lib(String name, {required String id, String? dbId}) =>
    CharacterCard(name: name, imagePath: '/lib/$id.png', dbId: dbId);

Uint8List _vec() {
  final floats = Float32List.fromList(const [0.1, 0.1, 0.1, 0.1]);
  return Uint8List.view(floats.buffer);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _mockPathProvider();

  group('libraryRagIdentity', () {
    final jennifer = _lib('Jennifer', id: 'Jennifer_123', dbId: 'lib-db');
    final library = [jennifer];

    test('stamped origin is the Data Bank key, never the member UUID', () {
      final ident = MemberOriginResolver.libraryRagIdentity(
        originStableId: 'Jennifer_123',
        originLibraryDbId: 'lib-db',
        memberName: 'Jennifer',
        libraryCharacters: library,
      );
      expect(ident.sourceId, 'Jennifer_123');
      expect(ident.sourceId, isNot('mem-uuid-aaaa'));
      expect(ident.libraryDbId, 'lib-db');
    });

    test('deleted library card still returns the stamped filename', () {
      final ident = MemberOriginResolver.libraryRagIdentity(
        originStableId: 'Jennifer_123',
        originLibraryDbId: 'lib-db',
        memberName: 'Jennifer',
        libraryCharacters: const [],
      );
      expect(ident.sourceId, 'Jennifer_123');
      expect(ident.libraryDbId, 'lib-db');
    });

    test('legacy member with unique name falls back to library filename', () {
      final ident = MemberOriginResolver.libraryRagIdentity(
        originStableId: null,
        originLibraryDbId: null,
        memberName: 'Jennifer',
        libraryCharacters: library,
      );
      expect(ident.sourceId, 'Jennifer_123');
      expect(ident.libraryDbId, 'lib-db');
    });

    test('two Rachels without a stamp are unresolvable', () {
      final ident = MemberOriginResolver.libraryRagIdentity(
        originStableId: null,
        originLibraryDbId: null,
        memberName: 'Rachel',
        libraryCharacters: [
          _lib('Rachel', id: 'Rachel_111', dbId: 'a'),
          _lib('Rachel', id: 'Rachel_222', dbId: 'b'),
        ],
      );
      expect(ident.sourceId, isNull);
      expect(ident.libraryDbId, isNull);
    });
  });

  test(
    'retrieve finds Data Bank under library filename, not member UUID',
    () async {
      SharedPreferences.setMockInitialValues({'rag_enabled': true});
      final db = AppDatabase.forTesting(sameIsolate: true);
      final storage = StorageService();
      await storage.initialized;
      final memory = MemoryService(_FakeEmbed(storage), storage, db);
      addTearDown(() async {
        memory.dispose();
        await db.close();
      });

      await db.insertDataBankEntry(
        DataBankEntriesCompanion.insert(
          id: 'bank-1',
          characterId: 'Jennifer_123',
          title: 'keys',
          content: 'Spare under the mat.',
          embedding: Value(_vec()),
          dimensions: const Value(4),
        ),
      );

      Future<List<RetrievedMemory>> search(List<String> ids) => memory.retrieve(
        queryText: 'where are the keys',
        sourceCharacterIds: ids,
        currentSessionId: 'group-session',
        inContextStart: 10,
      );

      final miss = await search(const ['group_abc', 'mem-uuid-aaaa']);
      expect(
        miss.where((m) => m.sessionId == 'databank'),
        isEmpty,
        reason: 'member UUID must not find library Data Bank rows',
      );

      final hit = await search(const ['group_abc', 'Jennifer_123']);
      expect(
        hit.any((m) => m.content.contains('Spare under the mat.')),
        isTrue,
      );
    },
  );

  test(
    'group retrieve keys Data Bank by originStableId, not member shim id',
    () {
      final src = File(
        'lib/services/chat/chat_service_generation_rag.dart',
      ).readAsStringSync();
      expect(src, contains('MemberOriginResolver.libraryRagIdentity'));
      expect(src, contains('originStableId: m.originStableId'));
      expect(src, contains('originLibraryDbId: m.originLibraryDbId'));
      expect(
        src,
        isNot(contains('final mid = _getCharacterIdFromCard(c);')),
        reason: 'member shim stableGroupId is the private-avatar UUID',
      );
      expect(src, contains('getCharacterById(libraryDbId)'));
    },
  );
}
