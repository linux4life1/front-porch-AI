// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Opening a long chat paints the newest window first, then older rows page
// in backward from that window. Hydrating 0→current on open (or reloading
// the whole list during backfill) dumps the user at first_message.
//
// Proven red: open via getMessagesForSession (full list) fails the tail
// test; dropping the isBackfilling guard in loadOlderHistory fails the
// scroll-up test; a backfill that reloads 0→current in one go fails the
// paging test.

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show kSessionOlderPage, kSessionOpenWindow;
import 'package:front_porch_ai/services/services.dart';
import '../../helpers/chat_db_teardown.dart';

const _rows = 500;

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_open_order_').path;
        }
        return null;
      });
}

class _SilentLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'OpenOrder';
}

List<String> _texts(ChatService chat) =>
    chat.messages.map((m) => m.text).toList();

List<String> _suffix(int length) => [
  for (var i = _rows - length; i < _rows; i++) 'm$i',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  AppDatabase? db;
  ChatService? chat;

  tearDown(() => disposeChatThenCloseDb(chat, db));

  /// A 1:1 chat whose session holds [_rows] rows `m0`…`m{_rows-1}`, held
  /// behind a picker-owned overlay right after `loadSession` returns.
  Future<String> openHeld() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    final storage = StorageService();
    final repo = CharacterRepository(db!, storage);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db!),
            storage,
            WorldRepository(storage, db!),
          )
          ..setDatabase(db!)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = _SilentLlm();
    await storage.initialized;
    final card = CharacterCard(
      name: 'Wren',
      firstMessage: 'm0',
      imagePath: '/tmp/wren-open-order.png',
    );
    await repo.addCharacter(card);
    await chat!.setActiveCharacter(card);
    await chat!.flushPendingSaves();
    final sid = chat!.currentSessionId!;
    await db!.deleteMessagesForSession(sid);
    await db!.insertMessages([
      for (var i = 0; i < _rows; i++)
        MessagesCompanion.insert(
          id: 'oo$i',
          sessionId: sid,
          position: i,
          sender: i.isEven ? 'Wren' : 'You',
          isUser: i.isOdd,
          swipes: Value(jsonEncode(['m$i'])),
        ),
    ]);
    chat!.beginSessionLoad();
    await chat!.loadSession(sid);
    return sid;
  }

  Future<List<int>> releaseAndWatchBackfill() async {
    final seen = <int>[chat!.messages.length];
    chat!.endSessionLoad();
    for (var i = 0; i < 2000 && chat!.isBackfillingHistory; i++) {
      await Future<void>.delayed(Duration.zero);
      final n = chat!.messages.length;
      expect(
        _texts(chat!),
        _suffix(n),
        reason: 'every backfill step is a contiguous suffix of the chat',
      );
      if (n != seen.last) seen.add(n);
    }
    expect(chat!.isBackfillingHistory, isFalse);
    return seen;
  }

  test('open paints the newest window, not the 0→current list', () async {
    await openHeld();
    expect(chat!.isLoadingSession, isTrue);
    expect(
      _texts(chat!),
      _suffix(kSessionOpenWindow),
      reason: 'a full hydrate on open dumps the user at first_message',
    );
    expect(chat!.hasOlderHistory, isTrue);
    expect(chat!.isBackfillingHistory, isTrue);
  });

  test('backfill pages older rows backward from the window', () async {
    await openHeld();
    final seen = await releaseAndWatchBackfill();
    expect(seen, [
      for (var n = kSessionOpenWindow; n < _rows; n += kSessionOlderPage) n,
      _rows,
    ], reason: 'one older page at a time, never a 0→current reload');
    expect(_texts(chat!), _suffix(_rows));
    expect(chat!.hasOlderHistory, isFalse);
  });

  test('scroll-up does not race the backfill or re-add rows', () async {
    await openHeld();
    await chat!.loadOlderHistory();
    expect(
      _texts(chat!),
      _suffix(kSessionOpenWindow),
      reason: 'loadOlderHistory is a no-op while the archive loop pages',
    );
    await releaseAndWatchBackfill();
    await chat!.loadOlderHistory();
    expect(_texts(chat!), _suffix(_rows));
  });
}
