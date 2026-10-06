// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// KoboldCpp keeps the open chat ready, and by default only that one: when
// the user leaves a chat its saved cache is let go and the memory it took
// is given back. Run through the real chat service on the engine stand-in,
// for every way a chat is left: a new chat, another character, a group,
// the phone's switch through the web facade, and going back to the library
// (the chat page closing). Settings → Advanced → "Keep recent chats ready"
// keeps that many of the chats left behind as well, the oldest let go first.

import 'dart:async';

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

  /// One reply in the open chat, and everything queued after it.
  Future<void> reply(String line) async {
    await h.chat.sendMessage(line);
    await h.settle();
  }

  int kept() => h.kobold.debugKeeper.kept;

  /// The memory KoboldCpp holds in its save slots, in the stand-in's bytes.
  int held() => h.engine.slots.fold(0, (sum, s) => sum + s.bytes);

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 2000 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue, reason: 'waited 10 s');
  }

  CharacterCard card(String name) => CharacterCard(
    name: name,
    description: 'Keeps the porch.',
    firstMessage: 'Evening.',
    imagePath: '/tmp/$name-kobold-chat.png',
    frontPorchExtensions: FrontPorchExtensions(
      realismEnabled: false,
      needsSimEnabled: false,
    ),
  );

  group('by default only the open chat is kept', () {
    test('a new chat lets the one left go and gives its memory back', () async {
      await reply('Good evening, Ada.');
      expect(kept(), 1);
      expect(held(), greaterThan(0));

      await h.chat.startNewChat();
      await h.kobold.waitForIdle();

      expect(kept(), 0, reason: 'the chat left is still kept');
      expect(h.engine.kinds, contains('clear'));
      expect(held(), 0, reason: 'its memory was not given back');

      await reply('Is the swing fixed?');
      expect(kept(), 1);
      expect(h.engine.of('save').last.slot, 0);
    });

    test('another character: the chat left goes', () async {
      await reply('Good evening, Ada.');
      final bea = card('Bea');
      await CharacterRepository(h.db, h.base.storage).addCharacter(bea);

      await h.chat.setActiveCharacter(bea);
      await h.kobold.waitForIdle();

      expect(kept(), 0);
      expect(held(), 0);
    });

    test('a group and back: each chat left goes', () async {
      await reply('Good evening, Ada.');
      await h.db.insertGroup(
        GroupsCompanion.insert(id: 'grp', name: 'The Cast'),
      );
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
      final ada = h.chat.activeCharacter!;

      await h.chat.setActiveGroup(
        GroupChat(id: 'grp', name: 'The Cast'),
        groupRepo: GroupChatRepository(h.base.storage, h.db),
      );
      await h.kobold.waitForIdle();
      expect(kept(), 0, reason: 'the 1:1 chat is still kept');
      expect(held(), 0);

      h.chat.setNextCharacter(
        h.chat.groupCharacters.firstWhere((c) => c.name == 'Bea'),
      );
      await reply('I bring you both a cup of tea.');
      expect(kept(), 1, reason: "the group's chat is the open one");

      await h.chat.setActiveCharacter(ada);
      await h.kobold.waitForIdle();
      expect(kept(), 0, reason: "the group's chat is still kept");
      expect(held(), 0);
    });

    test(
      "the phone's switch through the web facade lets the chat go",
      () async {
        await reply('Good evening, Ada.');
        final phone = ChatSessionFacade(
          h.chat,
          CharacterRepository(h.db, h.base.storage),
          () {},
        );

        await phone.apply(action: 'new');
        await h.kobold.waitForIdle();

        expect(kept(), 0);
        expect(held(), 0);
      },
    );

    test('back to the library lets the chat go; opening it again keeps it '
        'again', () async {
      h.chat.chatScreenOpened();
      await reply('Good evening, Ada.');
      expect(kept(), 1);

      h.chat.chatScreenClosed();
      await h.kobold.waitForIdle();
      expect(kept(), 0);
      expect(held(), 0);

      h.chat.chatScreenOpened();
      await reply('Is the swing fixed?');
      expect(kept(), 1, reason: 'the chat opened again is not kept');
      h.chat.chatScreenClosed();
    });

    test('a reply still being written when the user goes back to the '
        'library is not saved, and the memory is given back', () async {
      h.chat.chatScreenOpened();
      await reply('Good evening, Ada.');
      final hold = Completer<void>();
      var writing = false;
      h.engine.beforeReply = (r) {
        if (!r.promptText.contains('One more thing') || hold.isCompleted) {
          return Future<void>.value();
        }
        writing = true;
        return hold.future;
      };

      final sending = h.chat.sendMessage('One more thing.');
      await until(() => writing);
      h.chat.chatScreenClosed();
      hold.complete();
      await sending;
      await h.settle();

      expect(h.engine.of('save'), hasLength(1), reason: 'saved after leaving');
      expect(kept(), 0);
      expect(held(), 0);
    });
  });

  group('Keep recent chats ready (Settings → Advanced)', () {
    /// One reply in each of [lines], a new chat for each; their ids.
    Future<List<String>> chats(List<String> lines) async {
      final ids = <String>[];
      for (final line in lines) {
        await h.chat.startNewChat();
        await reply(line);
        ids.add(h.chat.currentSessionId!);
      }
      return ids;
    }

    test('keeps that many chats left behind, the oldest let go first; going '
        'back to one loads it', () async {
      await h.base.storage.backendSettings.setKeepRecentChats(2);

      final ids = await chats(['One.', 'Two.', 'Three.', 'Four.']);

      expect(kept(), 3, reason: 'the open chat and two recent ones');
      expect(h.engine.kinds, isNot(contains('clear')));

      final slotOfTwo = h.engine.of('save').toList()[1].slot;
      await h.chat.loadSession(ids[1]);
      await h.kobold.waitForIdle();
      h.engine.forgetLog();
      await reply('Back to two.');
      expect(h.engine.of('load').map((r) => r.slot), [
        slotOfTwo,
      ], reason: 'a recent chat kept ready is loaded back');

      await h.chat.loadSession(ids[0]);
      await h.kobold.waitForIdle();
      h.engine.forgetLog();
      await reply('Back to one.');
      expect(
        h.engine.of('load'),
        isEmpty,
        reason: 'the oldest chat was let go',
      );
    });

    test(
      'back to the library keeps them; only one past the count goes',
      () async {
        await h.base.storage.backendSettings.setKeepRecentChats(1);
        h.chat.chatScreenOpened();
        await chats(['One.', 'Two.']);
        expect(kept(), 2);

        h.chat.chatScreenClosed();
        await h.kobold.waitForIdle();

        expect(kept(), 1, reason: 'the open chat became the one recent chat');
        expect(h.engine.kinds, isNot(contains('clear')));
      },
    );

    test('lowering it lets the extra chats go at the next switch, without a '
        'restart', () async {
      await h.base.storage.backendSettings.setKeepRecentChats(2);
      await chats(['One.', 'Two.', 'Three.']);
      expect(kept(), 3);

      await h.base.storage.backendSettings.setKeepRecentChats(0);
      await h.chat.startNewChat();
      await h.kobold.waitForIdle();

      expect(kept(), 0);
      expect(held(), 0);
    });
  });
}
