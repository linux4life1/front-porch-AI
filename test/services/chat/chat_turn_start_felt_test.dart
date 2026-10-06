// The keeper counts what is left of a chat's save when the user starts the
// next turn (maintainer ruling, 2026-10-05, "count only the wait felt"), so
// the chat service says a turn has started before any of it waits in the
// line. Through the real service on the engine stand-in: a send, a
// regenerate, a Continue and an impersonate, each started while the last
// reply's save is still running, are held up by that save, whichever of
// their requests goes first; a message sent once the save is done waited for
// nothing, though the passes after the reply waited for the save.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../helpers/kobold_chat_harness.dart';

void main() {
  late KoboldChatHarness h;

  /// Completed when the next save reaches the engine.
  Completer<void>? saving;

  setUp(() async {
    h = await KoboldChatHarness.start();
    // What KoboldCpp prints after a request: 1,000 tokens read a second, so
    // a chat of a few hundred tokens is read again in well under a second.
    h.kobold.debugEngineSaid(
      'Processed:2000 in 2.00s (1000.00T/s), '
      'Generated:16/16 in 0.50s (32.00T/s)\n',
    );
    // Each save after the first takes a second, as a slow copy would.
    var saves = 0;
    h.engine.beforeAdmin = (r) {
      if (r.kind != 'save' || ++saves == 1) return Future<void>.value();
      saving?.complete();
      saving = null;
      return Future<void>.delayed(const Duration(seconds: 1));
    };
  });

  List<String> letGo() => [
    for (final l in h.kobold.logs)
      if (l.contains('to read it again')) l,
  ];

  bool saveRunning() => h.engine.of('save').last.endedAt == null;

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  /// The second send, which ends with its turn.
  late Future<void> second;

  /// The first reply, whose save only makes the chat's slot, then a second
  /// one: when this returns the reply is on screen and its save is running.
  Future<void> secondReplySaving() async {
    await h.chat.sendMessage('Good evening.');
    await h.settle();
    final started = (saving = Completer<void>()).future;
    second = h.chat.sendMessage('Did the rain stop?');
    await started.timeout(const Duration(seconds: 20));
    await until(() => !h.chat.isGenerating);
    expect(saveRunning(), isTrue, reason: 'the save ended too soon to test');
  }

  group('with Realism on, the turn\'s own checks go first in line', () {
    setUp(() async {
      final bea = CharacterCard(
        name: 'Bea',
        description: 'Keeps the porch.',
        firstMessage: 'Evening.',
        imagePath: p.join(Directory.systemTemp.path, 'bea-felt-wait.png'),
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: true,
          needsSimEnabled: false,
        ),
      );
      await CharacterRepository(h.db, h.base.storage).addCharacter(bea);
      await h.chat.setActiveCharacter(bea);
      h.engine.forgetLog();
    });

    test(
      'a message sent while the last reply\'s save still runs: what was '
      'left of the save was the wait, more than reading the chat again',
      () async {
        await secondReplySaving();

        final third = h.chat.sendMessage('Shall we sit a while?');
        await second;
        await third;
        await h.settle();

        expect(letGo(), hasLength(1));
      },
    );

    test('a message sent once the save is done waited for nothing: the chat '
        'is kept', () async {
      await secondReplySaving();
      await second;
      await h.settle();

      h.engine.forgetLog();
      await h.chat.sendMessage('Shall we sit a while?');
      await h.settle();

      expect(letGo(), isEmpty);
      expect(
        h.engine.kinds,
        containsAllInOrder(['load', 'chat', 'save']),
        reason: 'kept: loaded back for the reply and saved after it',
      );
    });

    test('a regenerate while the save still runs waits for it, though its '
        'checks run again first', () async {
      await secondReplySaving();

      final regenerating = h.chat.regenerateLastMessage();
      await second;
      await regenerating;
      await h.settle();

      expect(letGo(), hasLength(1));
    });
  });

  group('with the story clock off, nothing runs after a reply', () {
    setUp(() => h.base.storage.realismSettings.setPassageOfTimeDefault(false));

    /// The second reply's turn is over and its save still runs.
    Future<void> settledWhileSaving() async {
      await secondReplySaving();
      await second;
      await until(() => !h.chat.isSettlingTurn);
      expect(saveRunning(), isTrue, reason: 'the turn waited for the save');
    }

    test('Continue at once waits for the save', () async {
      await settledWhileSaving();

      await h.chat.continueGeneration();
      await h.settle();

      expect(letGo(), hasLength(1));
    });

    test('a line in the user\'s voice at once waits for the save', () async {
      await settledWhileSaving();

      await h.chat.impersonateUser(onToken: (_) {});
      await h.settle();

      expect(letGo(), hasLength(1));
    });
  });
}
