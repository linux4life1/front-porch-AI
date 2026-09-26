// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// AI ENHANCE'S "BRING YOUR CHATS ALONG" — the copy loop is a round-trip
// through the .fpchat exporter/importer (maintainer direction, 2026-08-13),
// so what this suite pins is the LOOP's own contract, not the codec's
// (which has its own suites): every base chat arrives under the enhanced
// card as a FULL restore, the base character's chats are untouched, and
// the newest chat is the one left open under the enhanced card.
//
// Guard proven to fail before passing: with the mismatch callback answering
// false (transcript-only), the full-restore count goes to zero and the
// first assert goes red.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_encopy_').path;
        }
        return null;
      });
}

class _InertLlm extends LLMService {
  @override
  Stream<String> generateStream(GenerationParams params) async* {
    yield '';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'InertLlm';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late CharacterRepository repo;
  late ChatService chat;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    repo = CharacterRepository(db, storage);
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(repo)
          ..testLlmServiceOverride = _InertLlm();
    await storage.initialized;
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<CharacterCard> seedCard(String name) async {
    final card = CharacterCard(
      name: name,
      description: 'Exists only inside the enhance-copy test.',
      firstMessage: 'The porch light hums.',
    );
    final tmpDir = Directory.systemTemp.createTempSync('encopy_card_');
    final pngPath = '${tmpDir.path}/$name.png';
    await V2CardService().saveCardAsPng(card, pngPath, null);
    card.imagePath = pngPath;
    await repo.addCharacter(card);
    return card;
  }

  Future<void> seedSession(
    CharacterCard card,
    String sessionId,
    String marker,
  ) async {
    await db.insertSession(
      SessionsCompanion.insert(id: sessionId, characterId: Value(card.dbId)),
    );
    for (final (i, line) in ['Hello there.', marker].indexed) {
      await db.insertMessage(
        MessagesCompanion.insert(
          id: '$sessionId-m$i',
          sessionId: sessionId,
          position: i,
          sender: i.isEven ? 'You' : card.name,
          isUser: i.isEven,
          swipes: Value('["$line"]'),
        ),
      );
    }
  }

  test('every base chat lands on the enhanced card as a full restore, base '
      'untouched, newest chat left open', () async {
    final base = await seedCard('Mara');
    // Session ids double as creation timestamps in the list view; createdAt
    // (which getSessionsForCharacter orders by) is the insert time, so the
    // older chat is seeded first.
    await seedSession(base, '1700000000001', 'OLDER-CHAT-MARKER');
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await seedSession(base, '1700000000002', 'NEWEST-CHAT-MARKER');

    final enhanced = await repo.duplicateCharacter(
      base,
      newNameOverride: 'Mara (Enhanced)',
    );
    expect(enhanced, isNotNull);

    final copied = await chat.copyChatsForEnhance(from: base, to: enhanced!);
    expect(
      copied,
      2,
      reason:
          'both chats must arrive as FULL restores — '
          'transcript-only would strip stamps, journal and growth',
    );

    // The enhanced card owns copies…
    final enhancedSessions = await chat.getSessionsForId(
      enhanced.stableGroupId,
    );
    expect(enhancedSessions.length, greaterThanOrEqualTo(2));

    // …the base character's chats are exactly as they were…
    final baseSessions = await chat.getSessionsForId(base.stableGroupId);
    expect(baseSessions, hasLength(2));

    // …and the user lands in the enhanced character with the NEWEST chat
    // open, right where they left the original.
    expect(chat.activeCharacter?.name, 'Mara (Enhanced)');
    expect(
      chat.messages.map((m) => m.text).join('\n'),
      contains('NEWEST-CHAT-MARKER'),
    );
  });

  test(
    'a character with no chats copies nothing and touches nothing',
    () async {
      final base = await seedCard('Rui');
      final enhanced = await repo.duplicateCharacter(
        base,
        newNameOverride: 'Rui (Enhanced)',
      );
      expect(await chat.copyChatsForEnhance(from: base, to: enhanced!), 0);
    },
  );

  test('the same character on both sides is refused — it would re-import '
      'every chat onto its own owner', () async {
    final base = await seedCard('Solo');
    await seedSession(base, '1700000000009', 'ONLY-CHAT');
    await expectLater(
      chat.copyChatsForEnhance(from: base, to: base),
      throwsArgumentError,
    );
    // Nothing was duplicated by the refusal.
    expect(await chat.getSessionsForId(base.stableGroupId), hasLength(1));
  });
}
