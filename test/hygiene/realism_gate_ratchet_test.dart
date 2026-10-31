// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// Realism runs behind one gate. `_realismEnabled` (a getter in
// lib/services/chat/chat_service_controls.dart) is Porch Life's Realism
// permission AND the chat's own switch; every reader in the ChatService
// library, and every leaf through its RealismScope, reads it, so Porch Life
// off stops Realism in every open chat from its next turn.
//
// The chat's own switch, `_realismChatSwitch`, is what a chat stores: saves,
// seeds and carries read and write it, and nothing else may. A save that
// wrote the gate would replace a chat's own choice with whatever Porch Life
// said at that moment, the bug PR 0 fixed for Afterglow's 1:1 save. A pass
// that read the raw switch would run Realism with Porch Life off.
//
// The allow-list pins how many times each file names the raw switch, so a
// new read cannot hide in a file that already has one, and a carry that
// went back to the gate (a package export, a cast collapse) shows as a
// count that dropped. realism_permission_test.dart pins those carries by
// behaviour too.

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ratchet.dart';

const _gateFile = 'lib/services/chat/chat_service_controls.dart';

/// The ChatService library (the shell and its parts) and its chat leaves.
List<String> _chatServiceLibrary() => [
  'lib/services/chat_service.dart',
  ...dartFiles('lib/services/chat'),
];

/// Files that read or write the chat's own switch: how many times, and why
/// each is right.
const _ownSwitch = <String, (int, String)>{
  'lib/services/chat_service.dart': (1, 'the public switch, for test doubles'),
  'lib/services/chat/chat_service_fields.dart': (1, 'declares it'),
  _gateFile: (2, 'the gate; the switch\'s setter'),
  'lib/services/chat/chat_service_session_hydrate.dart': (
    1,
    'restores it from the session row',
  ),
  'lib/services/chat/chat_service_session_state_save.dart': (
    1,
    'saves it, never the gate',
  ),
  'lib/services/chat/chat_service_chat_entry.dart': (
    4,
    'resets it; seeds a new 1:1 chat from the card, then ORs the default',
  ),
  'lib/services/chat/chat_service_session_manage.dart': (
    1,
    'seeds a new chat from the card',
  ),
  'lib/services/chat/chat_service_import_seed.dart': (
    3,
    'seeds an import; exports and imports it in a chat package',
  ),
  'lib/services/chat/chat_service_import_walk.dart': (
    2,
    'keeps it across a fork walk-back',
  ),
  'lib/services/chat/chat_service_group_entry.dart': (
    2,
    'resets it; seeds a group chat from its group',
  ),
  'lib/services/chat/chat_service_group_membership.dart': (
    2,
    'carries a 1:1 chat\'s choice, and its state, into the group it becomes',
  ),
  'lib/services/chat/chat_service_cast_shrink.dart': (
    3,
    'carries the choice back through a cast collapse',
  ),
  'lib/services/chat/chat_service_wiring_realism.dart': (
    1,
    'a silent card seeds Needs from the chat\'s own choice',
  ),
};

/// Outside the library, files that show the switch's position, and why.
const _ownSwitchShown = <String, String>{
  'lib/services/chat/existing_chats_offer.dart':
      'counts the open chat when its own switch is off',
  'lib/ui/chat_components/sidebar/character_state/character_state_group.dart':
      'the 1:1 switch, greyed while Porch Life blocks Realism',
  'lib/ui/dialogs/group_settings/realism_needs_tab/group_realism_controller.dart':
      'the group chat\'s switch in Group Settings',
  'lib/services/web/facade/chat_tools/chat_tools_snapshot.dart':
      'the phone\'s switch',
  'lib/services/web/facade/chat_realism_read.dart':
      'the insight panel says a change waits for the reply',
};

final _rawSwitch = RegExp(r'(?<![\w.])_realismChatSwitch\b');
final _publicSwitch = RegExp(r'\.realismChatSwitch\b');
final _gateDefinition = RegExp(r'bool get _realismEnabled\b');

/// A setter would let a seed or a save write through the gate.
final _gateSetter = RegExp(
  r'set _realismEnabled\b|_realismEnabled\s*=(?![=>])',
);

/// The ChatService library itself: the shell and its parts. A leaf keeps its
/// own private `_realismEnabled`, read from the gate its scope is handed.
bool _isLibraryFile(String path, DartSource source) =>
    path == 'lib/services/chat_service.dart' ||
    source.source.contains("part of '../chat_service.dart';");

/// A closure handing the raw switch to a leaf, whatever it is named; the
/// name, when it is a named argument, is read from just before it.
final _rawClosure = RegExp(r'\(\)\s*=>\s*_realismChatSwitch\b');
final _argName = RegExp(r'(\w+)\s*:\s*$');

String? _argumentNameBefore(String code, int offset) {
  final from = offset < 80 ? 0 : offset - 80;
  return _argName.firstMatch(code.substring(from, offset))?[1];
}

/// The one leaf input that is the chat's own choice, not the gate.
const _rawLeafInputs = {'chatRealism'};

void main() {
  test('the Realism gate is defined once, with no setter', () {
    final where = <String>[];
    final setters = <String>[];
    for (final path in dartFiles('lib')) {
      final source = DartSource.read(path);
      if (!_isLibraryFile(path, source)) continue;
      if (source.hits(_gateDefinition).isNotEmpty) where.add(path);
      for (final hit in source.hits(_gateSetter)) {
        setters.add('$path:${hit.line}: ${hit.text.trim()}');
      }
    }
    expect(where, [_gateFile]);
    expect(
      setters,
      isEmpty,
      reason:
          'write the chat\'s own switch, _realismChatSwitch; the gate is '
          'read-only.\n${setters.join('\n')}',
    );
  });

  test("the chat's own Realism switch is named exactly where, and as often "
      'as, a chat stores, seeds or carries it', () {
    final problems = <String>[];
    for (final path in _chatServiceLibrary()) {
      final hits = DartSource.read(path).hits(_rawSwitch);
      final pinned = _ownSwitch[path]?.$1 ?? 0;
      if (hits.length == pinned) continue;
      problems.add(
        '$path: $pinned pinned, ${hits.length} found\n'
        '${hits.map((h) => '  ${h.line}: ${h.text.trim()}').join('\n')}',
      );
    }
    expect(
      problems,
      isEmpty,
      reason:
          'Realism runs behind _realismEnabled ($_gateFile): Porch Life '
          'allows it AND the chat\'s switch. A pass reading '
          '_realismChatSwitch runs with Porch Life off; a save, seed or '
          'carry reading the gate overwrites the chat\'s choice. Fix the '
          'line, or, if it really stores, seeds or carries the chat\'s '
          'choice, change its count in _ownSwitch with the reason.'
          '\n${problems.join('\n')}',
    );
  });

  test('every leaf is handed the gate, except its one own-choice input', () {
    final problems = <String>[];
    for (final path in _chatServiceLibrary()) {
      final source = DartSource.read(path);
      for (final m in _rawClosure.allMatches(source.code)) {
        final name = _argumentNameBefore(source.code, m.start);
        if (_rawLeafInputs.contains(name)) continue;
        problems.add('$path:${source.lineOf(m.start) + 1}: ${m[0]}');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('the public switch is read only to show its position', () {
    final problems = <String>[];
    for (final path in [...dartFiles('lib/services'), ...dartFiles('lib/ui')]) {
      if (_ownSwitchShown.containsKey(path)) continue;
      if (path == 'lib/services/chat_service.dart' ||
          path.startsWith('lib/services/chat/chat_service_')) {
        continue;
      }
      for (final hit in DartSource.read(path).hits(_publicSwitch)) {
        problems.add('$path:${hit.line}: ${hit.text.trim()}');
      }
    }
    expect(
      problems,
      isEmpty,
      reason:
          'realismChatSwitch is the chat\'s own choice, for its toggle. '
          'Whether Realism runs is realismEnabled. If the line shows the '
          'switch, add the file to _ownSwitchShown with its reason.'
          '\n${problems.join('\n')}',
    );
  });

  test('every file allowed to show the switch still does', () {
    // A stale entry would quietly widen the allow-list.
    final unused = [
      for (final path in _ownSwitchShown.keys)
        if (DartSource.read(path).hits(_publicSwitch).isEmpty) path,
    ];
    expect(unused, isEmpty, reason: 'drop these from _ownSwitchShown');
  });
}
