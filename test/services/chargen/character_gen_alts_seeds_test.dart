// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chargen / enhance alt rewrite must compact against empty when seeds are
// not authored with the new alts. Leftover source [furious] must not land
// on Get out.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';

void main() {
  final furious = GreetingRealismSeed(characterEmotion: 'furious');

  test(
    'character_gen_service assign new alts without authored seeds drops leftover furious',
    () {
      final card = CharacterCard(
        name: 'Nina',
        alternateGreetings: ['Stay.'],
        frontPorchExtensions: FrontPorchExtensions(greetingSeeds: [furious]),
      );
      // Same assign character_gen_service uses after rewriting alts.
      card.assignRewrittenAlternateGreetings(['Get out.']);
      expect(card.alternateGreetings, ['Get out.']);
      expect(
        card.frontPorchExtensions!.greetingSeeds,
        isEmpty,
        reason:
            "['Get out.'] omit seeds must not reuse unpaired source [furious]",
      );
      expect(
        greetingOverlayAt(card.frontPorchExtensions!.greetingSeeds, 1),
        isNull,
        reason: 'Get out overlay is not leftover furious',
      );
    },
  );

  test(
    'character_gen_service assign keeps a seed authored with the new alts',
    () {
      final card = CharacterCard(
        name: 'Nina',
        alternateGreetings: ['Stay.'],
        frontPorchExtensions: FrontPorchExtensions(greetingSeeds: [furious]),
      );
      card.assignRewrittenAlternateGreetings(
        ['Get out.'],
        authoredSeeds: [GreetingRealismSeed(characterEmotion: 'cold')],
      );
      expect(card.alternateGreetings, ['Get out.']);
      expect(
        card.frontPorchExtensions!.greetingSeeds.single!.characterEmotion,
        'cold',
      );
    },
  );
}
