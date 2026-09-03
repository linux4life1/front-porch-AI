// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A send during the 24-row tail-load used to number embed windows from the
// in-memory list (0, 1, 2…). Those ranges were then treated as "already
// embedded," so the real start of a long chat was never stored, and old
// lines got today's story-day. Live embed now waits for history backfill
// and stores basePosition + index.
//
// Proven red: with positionOffset ignored (ranges stored as list 0..N),
// the persist-position assertion fails (expected 976, actual 0).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/memory_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_embpos_').path;
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _mockPathProvider();

  late AppDatabase db;
  late MemoryService memory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'rag_enabled': true,
      'rag_window_size': 5,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    final storage = StorageService();
    await storage.initialized;
    memory = MemoryService(_FakeEmbed(storage), storage, db);
  });

  tearDown(() async {
    memory.dispose();
    await db.close();
  });

  test('positionOffset stores persist indices, not the 0..N tail', () async {
    await db.insertSession(SessionsCompanion.insert(id: 's1'));
    final lines = [for (var i = 0; i < 10; i++) 'Mara: tail line $i'];
    final pass = await memory.embedMessageWindow(
      sessionId: 's1',
      characterId: 'mara',
      formattedMessages: lines,
      totalMessageCount: lines.length,
      positionOffset: 976,
    );
    expect(pass.stored, greaterThan(0));
    final rows = await db.getEmbeddingsForCharacters(['mara']);
    expect(
      rows.map((r) => r.positionStart).toList()..sort(),
      isNot(contains(0)),
      reason: 'a 24-row tail must not occupy the real start of the chat',
    );
    expect(rows.first.positionStart, 976);
    expect(rows.first.positionEnd, 980);
  });

  test('live embed waits for backfill and passes basePosition', () {
    final src = File(
      'lib/services/chat/chat_service_turn_flow.dart',
    ).readAsStringSync();
    expect(src, contains('await _awaitHistoryHydrated()'));
    expect(src, contains('positionOffset: _history.basePosition'));
    expect(
      src,
      isNot(contains('totalMessageCount: _messages.length,')),
      reason: 'must not embed the unhydrated tail as 0..N',
    );
  });
}
