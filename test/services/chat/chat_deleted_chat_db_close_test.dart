// The word a database gives of each chat it deletes lives as long as the
// database: closing it ends the word, and the chat service that listened
// moves on to the next database, where deletes still let chats go.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../helpers/kobold_chat_harness.dart';

void main() {
  test(
    'closing a database ends its word on deleted chats; the chat service '
    'moves on to the next one, and a delete there still lets the chat go',
    () async {
      final h = await KoboldChatHarness.start();
      final other = AppDatabase.forTesting();
      final ended = Completer<void>();
      other.deletedSessions.listen((_) {}, onDone: ended.complete);
      h.chat.updateDatabase(other);

      await other.close();
      await ended.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('a closed database still had its word open'),
      );

      h.chat.updateDatabase(h.db);
      await h.chat.startNewChat();
      await h.chat.sendMessage('Good evening, Ada.');
      await h.settle();
      expect(h.kobold.debugKeeper.kept, 1);
      await h.chat.deleteSession(
        h.chat.currentSessionId!,
        startReplacement: false,
      );
      expect(h.kobold.debugKeeper.kept, 0);
    },
  );
}
