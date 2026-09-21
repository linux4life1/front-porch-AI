// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Soft group members (Approach A′): tier is preserved on the roster,
// feelings count full members only, and promote is the only clear path.
// Proven red: restore the toCharacterCard lite strip, or count soft in
// shouldTrackInterCharacterAmong, and these fail.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

CharacterCard _card(String name, {bool lite = false}) => CharacterCard(
  name: name,
  frontPorchExtensions: FrontPorchExtensions(tier: lite ? 'lite' : null),
);

void main() {
  group('group_lite helpers', () {
    test('isSoftGroupMember follows card.isLite', () {
      expect(isSoftGroupMember(_card('Aria')), isFalse);
      expect(isSoftGroupMember(_card('Mara', lite: true)), isTrue);
    });

    test('fullGroupCharacters drops soft, keeps the roster source intact', () {
      final roster = [_card('Aria'), _card('Mara', lite: true), _card('Bryn')];
      expect(fullGroupCharacters(roster).map((c) => c.name), ['Aria', 'Bryn']);
      expect(roster, hasLength(3));
    });

    test('feelings ≤4 gate ignores soft count', () {
      final fourFullPlusSoft = [
        _card('A'),
        _card('B'),
        _card('C'),
        _card('D'),
        _card('Guest', lite: true),
      ];
      expect(shouldTrackInterCharacterAmong(fourFullPlusSoft), isTrue);
      expect(
        shouldTrackInterCharacterAmong([...fourFullPlusSoft, _card('E')]),
        isFalse,
      );
      expect(
        shouldTrackInterCharacterAmong([_card('A'), _card('G', lite: true)]),
        isFalse,
      );
    });

    test('cloneFrontPorchTier can set and clear lite', () {
      final lite = cloneFrontPorchTier(null, lite: true);
      expect(lite.tier, 'lite');
      final cleared = cloneFrontPorchTier(lite, lite: false);
      expect(cleared.tier, isNull);
      expect(encodeMemberFrontPorch(cleared), isNotNull);
    });

    test('toCharacterCard preserves lite tier (no silent strip)', () {
      final gm = GroupMember(
        id: 'mem-mara',
        groupId: 'grp',
        name: 'Mara',
        frontPorchExtensions: FrontPorchExtensions(tier: 'lite').toJson(),
      );
      final card = gm.toCharacterCard(resolvedImagePath: '');
      expect(card.isLite, isTrue);
      expect(card.frontPorchExtensions?.tier, 'lite');
    });

    test('presentSceneNames unions members and guests', () {
      expect(
        presentSceneNames(
          members: [_card('Aria'), _card('Mara', lite: true)],
          guests: [_card('Pax', lite: true)],
        ),
        {'aria', 'mara', 'pax'},
      );
    });
  });
}
