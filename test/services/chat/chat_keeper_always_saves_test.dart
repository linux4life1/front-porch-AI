// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The open chat's slot is forced, never judged (maintainer ruling,
// 2026-10-06): every reply is saved and the next one loads it back, however
// long the save takes. The rule this replaced let a chat go when waiting for
// its save looked dearer than reading it again at the speed KoboldCpp
// printed, a speed that came mostly from short judge prompts, which read
// faster per token than a long chat. Through the real chat service on the
// engine stand-in, with Realism on so the turn's checks go first in line:
// KoboldCpp says it reads 1,000 tokens a second, so this chat of a few
// hundred tokens would be read again in well under a second, each save after
// the first takes a whole second, and the next message is sent while one is
// still running, so the user waits for it.

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
    // What KoboldCpp prints after a request: 1,000 tokens read a second.
    h.kobold.debugEngineSaid(
      'Processed:2000 in 2.00s (1000.00T/s), '
      'Generated:16/16 in 0.50s (32.00T/s)\n',
    );
    var saves = 0;
    h.engine.beforeAdmin = (r) {
      if (r.kind != 'save' || ++saves == 1) return Future<void>.value();
      saving?.complete();
      saving = null;
      return Future<void>.delayed(const Duration(seconds: 1));
    };
    final bea = CharacterCard(
      name: 'Bea',
      description: 'Keeps the porch.',
      firstMessage: 'Evening.',
      imagePath: p.join(Directory.systemTemp.path, 'bea-always-saves.png'),
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        needsSimEnabled: false,
      ),
    );
    await CharacterRepository(h.db, h.base.storage).addCharacter(bea);
    await h.chat.setActiveCharacter(bea);
    h.engine.forgetLog();
  });

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 2000 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(done(), isTrue, reason: 'waited 10 s');
  }

  test('a save slower than reading the chat again keeps the chat all the '
      'same, and the next reply loads it back', () async {
    await h.chat.sendMessage('Good evening.');
    await h.settle();
    final started = (saving = Completer<void>()).future;
    final second = h.chat.sendMessage('Did the rain stop?');
    await started.timeout(const Duration(seconds: 20));
    await until(() => !h.chat.isGenerating);
    expect(
      h.engine.of('save').last.endedAt,
      isNull,
      reason: 'the save ended too soon to test',
    );

    // The next message while that save still runs: its turn waits for it.
    final third = h.chat.sendMessage('Shall we sit a while?');
    await second;
    await third;
    await h.settle();

    expect(h.kobold.debugKeeper.kept, 1, reason: 'the open chat was let go');
    h.engine.forgetLog();
    await h.chat.sendMessage('And the swing?');
    await h.settle();
    expect(
      h.engine.kinds,
      containsAllInOrder(['load', 'chat', 'save']),
      reason: 'the next reply did not load the chat back',
    );
    expect(h.kobold.logs.where((l) => l.contains('not kept ready')), isEmpty);
  });
}
