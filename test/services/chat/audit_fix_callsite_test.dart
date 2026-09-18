// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Call-site pins. Pure helper tests stay green if the wiring is deleted;
// these fail if the Continue/think/judge call sites revert. Companion to
// close_open_think_test and recent_exchange_last_user_test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Continue does not consume one-shots', () {
    final plan = File(
      'lib/services/chat/chat_service_generation_plan.dart',
    ).readAsStringSync();
    expect(plan, contains('skipOneShots'));
    expect(
      plan,
      contains('final skipOneShots = t.mode == GenerationMode.continue_'),
    );
    expect(plan, contains('skipOneShots ? \'\' : _getChanceTimeInjection()'));
    expect(plan, contains('!skipOneShots &&'));
  });

  test('closeOpenThink is wired at Continue prefix, cancel, and merge', () {
    final stream = File(
      'lib/services/chat/chat_service_generation_stream.dart',
    ).readAsStringSync();
    expect(stream, contains('closeOpenThink(t.streamTarget.text)'));
    expect(stream, contains('closeOpenThink(last.text)'));
    final post = File(
      'lib/services/chat/chat_service_generation_postgen.dart',
    ).readAsStringSync();
    expect(post, contains('closeOpenThink(t.continuePrefix)'));
  });

  test('pre-gen judges cut at last user; scene-time keeps full window', () {
    final calls = File(
      'lib/services/chat/realism_evals.calls.dart',
    ).readAsStringSync();
    expect(
      RegExp(
        r'recentExchangeThroughLastUser\(getMessages\(\), take: 4\)',
      ).allMatches(calls).length,
      greaterThanOrEqualTo(2),
    );
    expect(calls, contains('recentExchange(getMessages(), take: 6)'));
    final one = File(
      'lib/services/chat/realism_evals.one_shot.dart',
    ).readAsStringSync();
    expect(
      one,
      contains('recentExchangeThroughLastUser(getMessages(), take: 6)'),
    );
  });

  test('pickup retires item cards for the whole session', () {
    final cards = File(
      'lib/services/chat/chat_service_item_cards.dart',
    ).readAsStringSync();
    expect(cards, contains('retireItemCardsInSession'));
  });

  test('follow-up speakers stay on the clock bucket brigade', () {
    final turn = File(
      'lib/services/chat/chat_service_turn_flow.dart',
    ).readAsStringSync();
    expect(turn, isNot(contains('skipClockAdvance: true')));
    expect(turn, contains('Bucket brigade'));
    final speak = File(
      'lib/services/chat/chat_service_wiring_memory.dart',
    ).readAsStringSync();
    expect(speak, isNot(contains('skipClockAdvance: true')));
    final gen = File(
      'lib/services/chat/chat_service_generation.dart',
    ).readAsStringSync();
    expect(gen, contains('_maybeAdvanceStoryClockAfterReply'));
    final regen = File(
      'lib/services/chat/chat_service_reprocess.dart',
    ).readAsStringSync();
    expect(regen, contains('story_clock_before'));
    expect(regen, isNot(contains('beginUserTurnClock()')));
    final send = File(
      'lib/services/chat/chat_service_send.dart',
    ).readAsStringSync();
    expect(send, isNot(contains('beginUserTurnClock()')));
    final time = File('lib/services/chat/time_service.dart').readAsStringSync();
    expect(time, isNot(contains('_clockMovedThisUserTurn')));
  });

  test('fork journal cursor starts at the kept prefix, not zero', () {
    final manage = File(
      'lib/services/chat/chat_service_session_manage.dart',
    ).readAsStringSync();
    expect(manage, contains('_summaryLastIndex = _messages.length'));
  });
}
