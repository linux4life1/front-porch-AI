// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';
import '../../helpers/chat_db_teardown.dart';

class _JournalChat extends FakeChatService {
  _JournalChat({required this.store}) {
    journalReview = JournalReview(
      store: store,
      getSessionId: () => 's1',
      setRecap: (_) {},
      setCursor: (_) {},
      onSaveChat: () async {},
      onNotify: () {},
      getMaxCards: () => 200,
    );
  }

  final JournalStore store;

  @override
  late final JournalReview journalReview;

  @override
  JournalStore get journalStore => store;

  @override
  String? get currentSessionId => 's1';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late AppDatabase db;
  late JournalStore store;
  late StorageService storage;
  late _JournalChat chat;
  late JournalWebSurface surface;
  late ChatParticipant owner;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(sameIsolate: true);
    store = JournalStore(getDb: () => db);
    storage = StorageService();
    chat = _JournalChat(store: store);
    owner = ChatParticipant(
      card: CharacterCard(name: 'Mara', imagePath: '/tmp/mara.png'),
      isHost: true,
    );
    surface = JournalWebSurface(
      chat: chat,
      storage: storage,
      notify: () {},
      resolveOwner: (_) => owner,
    );
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<JournalMemoryData> seed({
    required String content,
    String sessionId = 's1',
    String characterId = 'mara',
  }) async {
    await store.addCard(
      sessionId: sessionId,
      characterId: characterId,
      content: content,
      category: 'moment',
      maxCards: 200,
    );
    return (await store.cardsFor(sessionId, characterId)).last;
  }

  group('JournalWebSurface owner-scope', () {
    test('edit/pin/retire of the focused owner card works', () async {
      final card = await seed(content: 'hers');
      await surface.action(owner.id, 'edit', {
        'cardId': card.id,
        'text': 'hers, revised',
      });
      expect((await store.findCardById(card.id))!.content, 'hers, revised');

      await surface.action(owner.id, 'pin', {'cardId': card.id});
      expect((await store.findCardById(card.id))!.pinned, isTrue);

      await surface.action(owner.id, 'retire', {'cardId': card.id});
      expect(await store.findCardById(card.id), isNull);
    });

    test('edit/pin/retire of another owner or session is a no-op', () async {
      final otherOwner = await seed(content: 'liv', characterId: 'liv');
      final otherSession = await seed(
        content: 'other chat',
        sessionId: 's2',
        characterId: 'mara',
      );

      await surface.action(owner.id, 'edit', {
        'cardId': otherOwner.id,
        'text': 'stolen',
      });
      await surface.action(owner.id, 'pin', {'cardId': otherOwner.id});
      await surface.action(owner.id, 'retire', {'cardId': otherOwner.id});
      final stillLiv = await store.findCardById(otherOwner.id);
      expect(stillLiv, isNotNull);
      expect(stillLiv!.content, 'liv');
      expect(stillLiv.pinned, isFalse);

      await surface.action(owner.id, 'edit', {
        'cardId': otherSession.id,
        'text': 'stolen',
      });
      await surface.action(owner.id, 'pin', {'cardId': otherSession.id});
      await surface.action(owner.id, 'retire', {'cardId': otherSession.id});
      final stillOther = await store.findCardById(otherSession.id);
      expect(stillOther, isNotNull);
      expect(stillOther!.content, 'other chat');
      expect(stillOther.pinned, isFalse);
    });
  });
}
