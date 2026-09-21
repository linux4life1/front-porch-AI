// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Scene Guest reply target (Discord 2026-08-15): a guest chiming in after
// the host was answering an older "Magus, tell me about the spell" instead
// of the line just sent. Two floors: overflow history must keep the latest
// user line, and the guest-turn note must pin that line by name.
//
// Proven red: overflowHistoryStart on [user, host] returning last index
// (old `_messages.last` floor) → first test fails; buildGuestTurnNote
// without MOST RECENT → second test fails.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

ChatMessage _user(String text) =>
    ChatMessage(text: text, sender: 'User', isUser: true);

ChatMessage _bot(String sender, String text) =>
    ChatMessage(text: text, sender: sender, isUser: false);

void main() {
  test(
    'overflow history starts at the latest user line, not the host reaction',
    () {
      final messages = [
        _user(
          'Magus, tell me more about this new spell you have been researching',
        ),
        _bot('Magus', 'I have been studying a binding of shadow and salt.'),
        _user(
          'What are the chances the academy will frown upon your use of dark magic, Magus?',
        ),
        _bot(
          'Narrator',
          "Magus's expression deepens as he considers your words.",
        ),
      ];
      expect(overflowHistoryStart(messages), 2);
      final kept = messages.sublist(overflowHistoryStart(messages));
      expect(kept.map((m) => m.text).toList(), [
        'What are the chances the academy will frown upon your use of dark magic, Magus?',
        "Magus's expression deepens as he considers your words.",
      ]);
      expect(
        kept.any((m) => m.text.contains('new spell')),
        isFalse,
        reason: 'the old Magus-only question must not be the overflow floor',
      );
    },
  );

  test('old last-message overflow drops the user question (the bug)', () {
    final messages = [
      _user('What are the chances, Magus?'),
      _bot('Narrator', 'He considers your words.'),
    ];
    final oldFloor = messages.last.text;
    expect(oldFloor, 'He considers your words.');
    expect(oldFloor, isNot(contains('chances')));
    expect(messages[overflowHistoryStart(messages)].text, contains('chances'));
  });

  test('guest-turn note pins the most recent user line', () {
    final note = buildGuestTurnNote(
      guestName: 'Magus',
      hostName: 'Narrator',
      userName: 'Alex',
      latestUserText:
          'What are the chances the academy will frown upon your use of dark magic, Magus?',
      latestHostText: "Magus's expression deepens as he considers your words.",
    );
    expect(note, contains('MOST RECENT'));
    expect(note, contains('academy will frown'));
    expect(note, isNot(contains('new spell')));
    expect(note, contains('Narrator just said:'));
    expect(note, contains('Reply ONLY as Magus'));
  });

  test('guest-turn note without a host reply still pins the user line', () {
    final note = buildGuestTurnNote(
      guestName: 'Magus',
      hostName: 'Narrator',
      userName: 'Alex',
      latestUserText: 'Magus, tell me about the spell.',
    );
    expect(note, contains('MOST RECENT'));
    expect(note, contains('tell me about the spell'));
    expect(note, isNot(contains('Narrator just said:')));
  });

  test('guest-turn note sanitizes brackets in the cited line', () {
    final note = buildGuestTurnNote(
      guestName: 'Magus',
      hostName: 'Narrator',
      userName: 'Alex',
      latestUserText: 'Magus, look at [the vault].',
    );
    expect(note, contains('look at (the vault).'));
    expect(note, isNot(contains('[the vault]')));
  });
}
