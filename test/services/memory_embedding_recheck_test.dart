// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// MemoryService used to check embedding availability once and latch.
// A retrieve during download then never saw files land (audit P1.8).
// ChatService and StoryPipeline must share the app EmbeddingService —
// a second engine cannot see the UI download.

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
          return Directory.systemTemp.createTempSync('fpai_embedre_').path;
        }
        return null;
      });
}

class _FakeEmbed extends EmbeddingService {
  _FakeEmbed(super.storage);

  bool live = false;
  bool filesLandNextCheck = false;
  int checks = 0;
  int embeds = 0;

  @override
  bool get isAvailable => live;

  @override
  Future<void> checkAvailability() async {
    checks++;
    if (filesLandNextCheck) live = true;
  }

  @override
  Future<List<double>?> embed(String text) async {
    embeds++;
    if (!live) return null;
    return List<double>.filled(4, 0.1);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _mockPathProvider();

  late AppDatabase db;
  late StorageService storage;
  late _FakeEmbed embed;
  late MemoryService memory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'rag_enabled': true});
    db = AppDatabase.forTesting();
    storage = StorageService();
    await storage.initialized;
    embed = _FakeEmbed(storage);
    memory = MemoryService(embed, storage, db);
  });

  tearDown(() async {
    memory.dispose();
    await db.close();
  });

  test('retrieve re-checks while the engine is down, then proceeds', () async {
    embed.live = false;
    embed.filesLandNextCheck = false;

    final first = await memory.retrieve(
      queryText: 'where did we leave the keys',
      sourceCharacterIds: const ['c1'],
      currentSessionId: 's1',
      inContextStart: 50,
    );
    expect(first, isEmpty);
    expect(embed.checks, 1);
    expect(embed.embeds, 0, reason: 'still down after the first check');

    // Files landed on disk. Old latch skipped checkAvailability forever.
    embed.filesLandNextCheck = true;
    final second = await memory.retrieve(
      queryText: 'where did we leave the keys',
      sourceCharacterIds: const ['c1'],
      currentSessionId: 's1',
      inContextStart: 50,
    );
    expect(embed.checks, 2);
    expect(embed.live, isTrue);
    expect(second, isEmpty); // no stored windows — search ran, found none
    expect(embed.embeds, 1);
    expect(memory.lastRetrieveError, isNull);
  });

  test(
    'a failed query embed stamps lastRetrieveError, not a silent empty',
    () async {
      embed.live = true;
      embed.filesLandNextCheck = false;
      final failing = _FailingEmbed(storage);
      final mem = MemoryService(failing, storage, db);
      addTearDown(mem.dispose);

      final got = await mem.retrieve(
        queryText: 'porch swing',
        sourceCharacterIds: const ['c1'],
        currentSessionId: 's1',
        inContextStart: 50,
      );
      expect(got, isEmpty);
      expect(mem.lastRetrieveError, 'query embed failed');
    },
  );
}

class _FailingEmbed extends EmbeddingService {
  _FailingEmbed(super.storage);

  @override
  bool get isAvailable => true;

  @override
  Future<void> checkAvailability() async {}

  @override
  Future<List<double>?> embed(String text) async => null;
}
