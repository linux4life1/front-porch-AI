// A chat that is deleted lets go of the cache KoboldCpp holds for it, at once:
// the keeper no longer keeps it, and its slot is the first one the next chat
// takes. Every way of deleting a chat ends in one cascade in the database, so
// each way is run for real: one chat (from the app, and from the phone), a
// character with its chats, and a group with its chat.

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/chat_session_facade.dart';

import '../../helpers/kobold_chat_harness.dart';

void main() {
  late KoboldChatHarness h;

  setUp(() async => h = await KoboldChatHarness.start());

  /// One reply in a new chat, saved by the keeper; the chat's id.
  Future<String> aChat(String line) async {
    await h.chat.startNewChat();
    await h.chat.sendMessage(line);
    await h.settle();
    return h.chat.currentSessionId!;
  }

  int kept() => h.kobold.debugKeeper.kept;

  test('deleting a chat lets go of its saved cache: the next chat takes its '
      'slot', () async {
    final first = await aChat('Good evening, Ada.');
    await aChat('Is the swing fixed?');
    expect(kept(), 2);

    await h.chat.deleteSession(first, startReplacement: false);
    expect(kept(), 1, reason: 'the deleted chat is still kept');

    await aChat('A third chat.');
    expect(
      h.engine.of('save').last.slot,
      0,
      reason: 'the slot of the deleted chat was the first one free',
    );
    expect(kept(), 2);
  });

  test('the phone\'s delete reaches the same service', () async {
    final first = await aChat('Good evening, Ada.');
    await aChat('Is the swing fixed?');
    final facade = ChatSessionFacade(
      h.chat,
      CharacterRepository(h.db, h.base.storage),
      () {},
    );

    await facade.apply(
      action: 'delete',
      sessionId: first,
      startReplacement: false,
    );

    expect(kept(), 1);
  });

  test(
    'a character deleted with its chats: every one of them is let go',
    () async {
      await aChat('Good evening, Ada.');
      await aChat('Is the swing fixed?');
      expect(kept(), 2);

      await CharacterRepository(h.db, h.base.storage).deleteCharacter(
        h.chat.activeCharacter!,
        chatsDir: h.base.storage.chatsDir,
      );

      expect(kept(), 0);
    },
  );

  test('a group deleted with its chat: let go', () async {
    await h.db.insertGroup(GroupsCompanion.insert(id: 'grp', name: 'The Cast'));
    for (final (id, name) in [('m-ada', 'Ada'), ('m-bea', 'Bea')]) {
      await h.db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'grp',
          name: name,
          personality: Value('$name keeps the porch.'),
          avatarFilename: Value('${name.toLowerCase()}.png'),
          frontPorchExtensions: const Value(
            '{"realism_engine":{"realism_enabled":false}}',
          ),
        ),
      );
    }
    final groups = GroupChatRepository(h.base.storage, h.db);
    await h.chat.setActiveGroup(
      GroupChat(id: 'grp', name: 'The Cast'),
      groupRepo: groups,
    );
    h.chat.setNextCharacter(
      h.chat.groupCharacters.firstWhere((c) => c.name == 'Ada'),
    );
    await h.chat.sendMessage('I bring you both a cup of tea.');
    await h.settle();
    expect(kept(), 1);

    await groups.delete('grp');

    expect(kept(), 0);
  });
}
