// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// #345: folder tiles and group cards follow the library sort. Name is A→Z;
// under the data sorts a folder takes the value of everything inside it
// (subfolders included): newest chat, newest card added, total messages.
// Folders with no characters inside go last; every tie falls back to name.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/utils.dart';

typedef _Folder = ({String name, List<CharacterCard> cards});

CharacterCard _card(String name, {DateTime? createdAt}) =>
    CharacterCard(name: name, imagePath: '/library/$name.png')
      ..createdAt = createdAt;

List<String> _order(
  List<_Folder> folders,
  CharacterSortMode mode, {
  Map<String, DateTime> lastActivity = const {},
  Map<String, int> messageCount = const {},
}) => sortFolders<_Folder>(
  folders,
  mode,
  nameOf: (f) => f.name,
  cardsIn: (f) => f.cards,
  lastActivity: lastActivity,
  messageCount: messageCount,
).map((f) => f.name).toList();

void main() {
  test('name sorts folders A→Z, ignoring case and creation order', () {
    // The issue's own example: made in the order C, A, B.
    final folders = <_Folder>[
      (name: 'C', cards: const []),
      (name: 'a', cards: const []),
      (name: 'B', cards: const []),
    ];
    expect(_order(folders, CharacterSortMode.name), ['a', 'B', 'C']);
    // The input list is left alone (the grid hands over the service's list).
    expect(folders.map((f) => f.name), ['C', 'a', 'B']);
  });

  test('recent: newest chat inside wins, empty folders last, ties by name', () {
    final old = _card('Old');
    final fresh = _card('Fresh');
    final quiet = _card('Quiet'); // never chatted
    final activity = {
      old.stableGroupId: DateTime(2026, 9, 1),
      fresh.stableGroupId: DateTime(2026, 10, 4),
    };
    final folders = <_Folder>[
      (name: 'Empty B', cards: const []),
      (name: 'Mixed', cards: [old, quiet]),
      (name: 'Empty A', cards: const []),
      (name: 'Never', cards: [quiet]),
      (name: 'Hot', cards: [fresh]),
    ];
    expect(_order(folders, CharacterSortMode.recent, lastActivity: activity), [
      'Hot',
      'Mixed',
      'Never',
      'Empty A',
      'Empty B',
    ]);
  });

  test('import date: the newest card added inside decides', () {
    final folders = <_Folder>[
      (name: 'Spring', cards: [_card('S', createdAt: DateTime(2026, 4, 1))]),
      (name: 'Empty', cards: const []),
      (
        name: 'Autumn',
        cards: [
          _card('A1', createdAt: DateTime(2026, 1, 1)),
          _card('A2', createdAt: DateTime(2026, 10, 1)),
        ],
      ),
    ];
    expect(_order(folders, CharacterSortMode.importDate), [
      'Autumn',
      'Spring',
      'Empty',
    ]);
  });

  test('messages: the total of everything inside decides', () {
    final a = _card('A');
    final b = _card('B');
    final c = _card('C');
    final counts = {a.stableGroupId: 4, b.stableGroupId: 5, c.stableGroupId: 7};
    final folders = <_Folder>[
      (name: 'Seven', cards: [c]),
      (name: 'Nine', cards: [a, b]),
      (name: 'Zero', cards: [_card('Silent')]),
      (name: 'Empty', cards: const []),
    ];
    expect(_order(folders, CharacterSortMode.messages, messageCount: counts), [
      'Nine',
      'Seven',
      'Zero',
      'Empty',
    ]);
  });

  test('group chats sort A→Z (they keep no dates or counts to sort by)', () {
    final groups = [
      GroupChat(id: 'group_2', name: 'zeta crew'),
      GroupChat(id: 'group_1', name: 'Alpha Crew'),
      GroupChat(id: 'group_3', name: 'Middle Crew'),
    ];
    expect(sortGroups(groups).map((g) => g.name), [
      'Alpha Crew',
      'Middle Crew',
      'zeta crew',
    ]);
    expect(groups.first.name, 'zeta crew', reason: 'input left alone');
  });
}
