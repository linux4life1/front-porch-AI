// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// User-last / retry regen (AI reply deleted, last line is the user) must
// skip the group realism dance the same way 1:1 skips sendMessage evals.
// A normal new group turn still dances. Continue still LOADs scalars.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user-last regen passes skipSpeakerEval; a new group turn does not', () {
    final reprocess = File(
      'lib/services/chat/chat_service_reprocess.dart',
    ).readAsStringSync();
    final userLast = reprocess.indexOf('else if (_messages.last.isUser)');
    expect(userLast, greaterThanOrEqualTo(0));
    final userLastBlock = reprocess.substring(userLast);
    expect(
      userLastBlock,
      contains('skipSpeakerEval: true'),
      reason: 'retry regen in group must not re-run the dance / re-tick needs',
    );

    final gen = File(
      'lib/services/chat/chat_service_generation.dart',
    ).readAsStringSync();
    expect(gen, contains('skipSpeakerEval'));
    expect(
      gen,
      contains('GenerationMode.continue_ || skipSpeakerEval'),
      reason: 'Continue and retry regen load scalars; they do not evaluate',
    );

    final turn = File(
      'lib/services/chat/chat_service_turn_flow.dart',
    ).readAsStringSync();
    expect(
      turn,
      isNot(contains('skipSpeakerEval')),
      reason: 'triggerNextCharacter is a normal new group turn — it must dance',
    );
    final send = File(
      'lib/services/chat/chat_service_send.dart',
    ).readAsStringSync();
    expect(
      send,
      isNot(contains('skipSpeakerEval')),
      reason: 'a fresh send must still run the group dance',
    );
  });
}
