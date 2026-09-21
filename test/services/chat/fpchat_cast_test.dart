// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Thin fpai.cast encode/parse/match. Proven red: drop the lite tier
// write, or match only dbId, and these fail.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

void main() {
  test('encode omits tier for full, writes lite for guests', () {
    expect(encodeFpchatCastMember(id: 'Aria', name: 'Aria', lite: false), {
      'id': 'Aria',
      'name': 'Aria',
    });
    expect(encodeFpchatCastMember(id: 'Mara', name: 'Mara', lite: true), {
      'id': 'Mara',
      'name': 'Mara',
      'tier': 'lite',
    });
  });

  test('parse treats missing cast as empty (legacy packages)', () {
    expect(parseFpchatCast(null), isEmpty);
    expect(parseFpchatCast({'id': 'x'}), isEmpty);
    expect(parseFpchatCast([]), isEmpty);
  });

  test('parse reads id + name + lite', () {
    final cast = parseFpchatCast([
      {'id': 'Soft0', 'name': 'Soft0', 'tier': 'lite'},
      {'id': 'Full0', 'name': 'Full0'},
      {'stable_group_id': 'Alt', 'name': 'Alt', 'tier': 'lite'},
    ]);
    expect(cast, hasLength(3));
    expect(cast[0].lite, isTrue);
    expect(cast[1].lite, isFalse);
    expect(cast[2].id, 'Alt');
  });

  test('match prefers portable stable id, then name', () {
    final mara = CharacterCard(name: 'Mara')..dbId = 'uuid-mara';
    final aria = CharacterCard(name: 'Aria');
    expect(
      matchFpchatCastMember([
        mara,
        aria,
      ], const FpchatCastMember(id: 'Mara', name: 'Nope')),
      mara,
    );
    expect(
      matchFpchatCastMember([
        mara,
        aria,
      ], const FpchatCastMember(id: 'uuid-mara', name: 'Nope')),
      mara,
    );
    expect(
      matchFpchatCastMember([
        mara,
        aria,
      ], const FpchatCastMember(id: '', name: 'Aria')),
      aria,
    );
    expect(
      matchFpchatCastMember([
        mara,
      ], const FpchatCastMember(id: 'ghost', name: 'Ghost')),
      isNull,
    );
  });
}
