// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group Settings → Memory & RAG showed its switch on with no memory model
// installed, and nothing said every memory search was being skipped. The
// tab now says so and offers the one-tap download; it also no longer tells
// users about "a future extension". A real group through the real
// ChatService door the tab reads.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/embedding/native_embedding_engine.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_grp_mem_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late GroupChatRepository repo;

  Future<void> boot() async {
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
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
    repo = GroupChatRepository(storage, db);
    await db.insertGroup(
      GroupsCompanion.insert(id: 'grp-mem', name: 'The Porch'),
    );
    for (final m in [('mem-ada', 'Ada'), ('mem-bex', 'Bex')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: m.$1,
          groupId: 'grp-mem',
          name: m.$2,
          firstMessage: const Value('Evening.'),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(id: 'grp-mem', name: 'The Porch'),
      groupRepo: repo,
    );
  }

  testWidgets('memory on with no memory model says it does nothing yet and '
      'offers the download', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    if (NativeEmbeddingEngine.resolveModelFiles(storage.rootPath) != null) {
      markTestSkipped('this machine has the memory model installed');
      return;
    }
    final embeddings = EmbeddingService(storage);

    await tester.pumpWidget(
      ChangeNotifierProvider<EmbeddingService>.value(
        value: embeddings,
        child: MaterialApp(
          home: Scaffold(
            body: GroupMemoryRAGTab(chatService: chat, groupRepo: repo),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    final warning = find.textContaining('none is installed, so this does');
    expect(chat.groupRagEnabled, isTrue, reason: 'groups start with it on');
    expect(warning, findsOneWidget);
    expect(find.text('Download model (~550 MB)'), findsOneWidget);
    expect(find.textContaining('future extension'), findsNothing);

    // Switched off, there is nothing to warn about.
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(chat.groupRagEnabled, isFalse);
    expect(warning, findsNothing);
    expect(find.text('Download model (~550 MB)'), findsNothing);
  });

  testWidgets('a memory model on disk that will not start says memory '
      'search isn\'t running and offers Retry', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));
    final root = storage.rootPath;
    expect(root, isNotNull);

    // A model file of the right size that is not a model: what a torn
    // download leaves behind. Sparse, so it costs no real disk.
    final embeddings = EmbeddingService(storage);
    await tester.runAsync(() async {
      final dir = Directory(p.join(root!, 'models', 'embeddings', 'nomic-v1_5'))
        ..createSync(recursive: true);
      final raf = File(
        p.join(dir.path, 'model.onnx'),
      ).openSync(mode: FileMode.write);
      raf.truncateSync(101 * 1024 * 1024);
      raf.closeSync();
      File(p.join(dir.path, 'tokenizer.json')).writeAsStringSync('{}');
      await embeddings.checkAvailability().timeout(const Duration(seconds: 60));
    });
    expect(embeddings.modelOnDisk, isTrue);
    expect(embeddings.isAvailable, isFalse);
    expect(embeddings.lastEngineError, isNotNull, reason: 'the engine failed');

    await tester.pumpWidget(
      ChangeNotifierProvider<EmbeddingService>.value(
        value: embeddings,
        child: MaterialApp(
          home: Scaffold(
            body: GroupMemoryRAGTab(chatService: chat, groupRepo: repo),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    expect(find.textContaining('isn\'t running'), findsOneWidget);
    expect(find.text('Retry setup'), findsOneWidget);
  });
}
