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

// COPYING CHATS ONTO A CARD WITH NONE ADDS ONLY THOSE CHATS. Opening a card
// that has no chats saves a greeting chat on the spot (chat_service_chat_
// entry.dart), and AI Enhance opens its fresh "(Enhanced)" copy to restore
// into it, so every copy also got an empty "New Conversation" beside the
// copied chats. `.porch` import restores the same way.
//
// Red-proved: without removing that greeting chat, the copy has two chats.

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
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        return Directory.systemTemp.createTempSync('fpai_enone_').path;
      });

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

  test('an Enhanced copy holds exactly the chats it copied', () async {
    final base = CharacterCard(
      name: 'Mara',
      description: 'Exists only inside the no-extra-chat test.',
      firstMessage: 'The porch light hums.',
    );
    final tmpDir = Directory.systemTemp.createTempSync('enone_card_');
    base.imagePath = '${tmpDir.path}/Mara.png';
    await V2CardService().saveCardAsPng(base, base.imagePath!, null);
    await repo.addCharacter(base);
    const sid = '1700000000777';
    await db.insertSession(
      SessionsCompanion.insert(id: sid, characterId: Value(base.dbId)),
    );
    for (final (i, line) in ['Hello there.', 'ONLY-CHAT'].indexed) {
      await db.insertMessage(
        MessagesCompanion.insert(
          id: '$sid-m$i',
          sessionId: sid,
          position: i,
          sender: i.isEven ? 'You' : base.name,
          isUser: i.isEven,
          swipes: Value('["$line"]'),
        ),
      );
    }

    final enhanced = await repo.duplicateCharacter(
      base,
      newNameOverride: 'Mara (Enhanced)',
    );
    expect(await chat.copyChatsForEnhance(from: base, to: enhanced!), 1);

    final chats = await chat.getSessionsForId(enhanced.stableGroupId);
    expect(chats, hasLength(1), reason: 'no empty greeting chat beside it');
    expect(chat.messages.map((m) => m.text), contains('ONLY-CHAT'));
  });
}
