// Letting go of a deleted chat's saved cache happens as the database deletes
// the chat, inside the delete. Whatever goes wrong there is said in the log
// and goes no further: the delete is done, and nothing escapes into the app.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../helpers/chat_db_teardown.dart';
import '../../helpers/kobold_chat_harness.dart';

class _Broken extends KoboldService {
  _Broken(super.storage);

  @override
  void forgetChat(String chat) => throw StateError('the keeper broke');
}

void main() {
  test('a keeper that breaks while it lets a deleted chat go breaks nothing '
      'else: the chat is deleted and no error escapes', () async {
    final h = await KoboldChatHarness.start();
    final db = AppDatabase.forTesting();
    final storage = h.base.storage;
    final chat = ChatService(
      _Broken(storage),
      UserPersonaService(db),
      storage,
      WorldRepository(storage, db),
    )..setDatabase(db);
    addTearDown(() => disposeChatThenCloseDb(chat, db));
    await db.insertSession(SessionsCompanion.insert(id: 'old-chat'));

    await chat.deleteSession('old-chat', startReplacement: false);

    expect(await db.getSessionById('old-chat'), isNull);
  });
}
