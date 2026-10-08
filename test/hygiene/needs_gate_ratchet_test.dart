// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// Needs run behind one gate. `_needsActive` (lib/services/chat/
// chat_service_needs_pass.dart) is the Realism engine AND the chat's Needs
// switch AND the global Needs switch read live; every way Needs run (the
// pre-turn stamp, the prompt lines, the judge, the clock's wear, the chip,
// Reprocess Needs) reads it, so off means off. Needs v2 added the clock's
// wear with its own check of the stored switch alone, and a v1.5.0 user
// with Realism off saw "Bladder −1" under a reply. This guard keeps a
// new Needs pass from doing that again.
//
// The stored switch, `_needsSimEnabled`, may still be read as a condition
// where it means "this chat keeps Needs state", not "run Needs now": the
// files below, each with its reason. Anywhere else in the ChatService
// library, a condition on it is a Needs pass that bypassed the gate. The
// public `needsSimEnabled` is the same switch for the UI and the web
// facades to show; a leaf service must not run from it either.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ratchet.dart';

const _pass = 'lib/services/chat/chat_service_needs_pass.dart';

/// The ChatService library: the shell and its parts.
List<String> _chatServiceLibrary() => [
  'lib/services/chat_service.dart',
  ...dartFiles('lib/services/chat'),
];

/// Files that read the stored switch as a condition, and why that is right.
const _stateAndRewinds = <String, String>{
  _pass: 'the gate itself',
  'lib/services/chat/chat_service_needs_rewinds.dart':
      'rewinds (restore, refund) of a stamp a reply carries',
  'lib/services/chat/chat_service_chat_entry.dart': 'seeds the bars at open',
  'lib/services/chat/chat_service_group_entry.dart': 'seeds the bars at open',
  'lib/services/chat/chat_service_group_lite.dart':
      'seeds a soft member who becomes full',
  'lib/services/chat/chat_service_group_members.dart':
      'seeds a member who joins',
  'lib/services/chat/chat_service_greeting_seed.dart': 'seeds from a greeting',
  'lib/services/chat/chat_service_import_seed.dart': 'seeds from an import',
  'lib/services/chat/chat_service_session_hydrate.dart':
      'restores the bars from a session',
  'lib/services/chat/chat_service_session_manage.dart':
      'saves the bars with a session',
  'lib/services/chat/chat_service_group_realism_helpers.dart':
      'restores a speaker\'s bars from a snapshot, refunds a delete',
  'lib/services/chat/chat_service_speaker_objectives.dart':
      'restores the bars from a message\'s snapshot on rewind',
  'lib/services/chat/chat_service_regen_revert.dart':
      'rewinds a regen to its stamp',
  'lib/services/chat/chat_service_message_ops.dart':
      'rewinds a delete to its stamp',
  'lib/services/chat/chat_service_mood.dart':
      'reads the bars into the realism snapshot',
};

/// [name] used as a condition: in an `if` / `while` / `assert` head,
/// beside `&&` / `||` (on either line of a wrapped condition), or before
/// `?`.
RegExp _asCondition(String name) => RegExp(
  '(?:if|while|assert)\\s*\\([^;{\\n]*$name\\b'
  '|$name\\s*(?:&&|\\|\\||\\?)'
  '|(?:&&|\\|\\|)\\s*!?$name\\b',
);

/// Inside the library the switch is read as the field or as the bare
/// public getter (an extension that keeps to public members, for the
/// golden fake); `card.needsSimEnabled` is the card's seed, not the chat's.
final _storedSwitchAsCondition = _asCondition(r'(?<![.\w])_?needsSimEnabled');
final _publicSwitchAsCondition = _asCondition(r'\.needsSimEnabled');
final _gateDefinition = RegExp(r'bool get _needsActive\b');

void main() {
  test('the Needs gate is defined once, in the Needs pass', () {
    final where = <String>[];
    for (final path in dartFiles('lib')) {
      if (DartSource.read(path).hits(_gateDefinition).isNotEmpty) {
        where.add(path);
      }
    }
    expect(where, [_pass]);
  });

  test('a condition on the stored Needs switch outside the state and rewind '
      'files is a Needs pass that bypassed the gate', () {
    final problems = <String>[];
    for (final path in _chatServiceLibrary()) {
      if (_stateAndRewinds.containsKey(path)) continue;
      for (final hit in DartSource.read(path).hits(_storedSwitchAsCondition)) {
        problems.add('$path:${hit.line}: ${hit.text.trim()}');
      }
    }
    expect(
      problems,
      isEmpty,
      reason:
          'Needs run behind _needsActive ($_pass). A pass that reads '
          '_needsSimEnabled runs with the Realism engine off and with the '
          'global Needs switch off. Use _needsActive, or, if the line '
          'seeds or rewinds Needs state rather than running Needs, add the '
          'file to _stateAndRewinds with its reason.\n${problems.join('\n')}',
    );
  });

  test('a leaf service does not run Needs from the public switch', () {
    // Leaves that read the public switch as a condition, and why that is
    // right: showing is not running, and a card's own `needsSimEnabled`
    // is a seed.
    const showsOrSeeds = <String, String>{
      'lib/services/web/facade/chat_realism_read.dart':
          'shows the bars the desktop sidebar shows (display parity)',
    };
    final problems = <String>[];
    for (final path in dartFiles('lib/services')) {
      if (path.startsWith('lib/services/chat/') ||
          showsOrSeeds.containsKey(path)) {
        continue;
      }
      for (final hit in DartSource.read(path).hits(_publicSwitchAsCondition)) {
        problems.add('$path:${hit.line}: ${hit.text.trim()}');
      }
    }
    expect(
      problems,
      isEmpty,
      reason:
          'needsSimEnabled is the chat\'s switch, for showing. Needs run '
          'behind _needsActive in $_pass; give the leaf a callback from '
          'there. If the line shows state or reads a card\'s seed, add the '
          'file to showsOrSeeds with its reason.\n${problems.join('\n')}',
    );
  });

  test('every file allowed to read the stored switch still does', () {
    // A stale entry would quietly widen the allow-list.
    final unused = <String>[];
    for (final path in _stateAndRewinds.keys) {
      if (DartSource.read(path).hits(_storedSwitchAsCondition).isEmpty) {
        unused.add(path);
      }
    }
    expect(unused, isEmpty, reason: 'drop these from _stateAndRewinds');
  });
}
