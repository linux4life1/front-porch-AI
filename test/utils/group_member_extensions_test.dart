// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A new group member's Starts Away: the wizard's per-member pick lands in
// the member row's extensions through the one shared committer/relay
// helper, so a member made on either surface starts held in every chat
// the group creates (docs/design/group-initial-presence.md).

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/utils.dart';

CharacterCard cardWithExt(FrontPorchExtensions ext) =>
    CharacterCard(name: 'Alice')..frontPorchExtensions = ext;

void main() {
  group("the member's Starts Away pick, written as the committer folds it", () {
    test('a card with extensions: the pick wins over the card', () {
      final ext = groupMemberExtensions(
        cardWithExt(FrontPorchExtensions(startsAway: true)),
        const {},
        realismEnabled: true,
        startsAway: false,
      );
      expect(ext?.startsAway, isFalse);
      expect(
        ext?.afterglowEnabled,
        isTrue,
        reason: 'the existing fold is untouched',
      );
    });

    test('a card with extensions and no pick: the card carries through', () {
      final on = groupMemberExtensions(
        cardWithExt(FrontPorchExtensions(startsAway: true)),
        const {},
        realismEnabled: true,
      );
      final off = groupMemberExtensions(
        cardWithExt(FrontPorchExtensions()),
        const {},
        realismEnabled: true,
      );
      expect(on?.startsAway, isTrue);
      expect(off?.startsAway, isFalse);
    });

    test('a card without extensions: the pick seeds the switch', () {
      final on = groupMemberExtensions(
        CharacterCard(name: 'Alice'),
        const {},
        realismEnabled: true,
        startsAway: true,
      );
      expect(on?.startsAway, isTrue);
      expect(on?.stableId, isNotEmpty);
      final off = groupMemberExtensions(
        CharacterCard(name: 'Alice'),
        const {},
        realismEnabled: true,
      );
      expect(off?.startsAway, isFalse);
    });

    test('Realism off and no extensions: still null, the old contract', () {
      final off = groupMemberExtensions(
        CharacterCard(name: 'Alice'),
        const {},
        realismEnabled: false,
        startsAway: true,
      );
      expect(off, isNull);
    });
  });
}
