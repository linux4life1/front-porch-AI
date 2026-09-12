// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// "Acts on desires" — a character ACTS on their intimate preferences instead of
// merely holding them.
//
// THE BET THAT STARTED THIS, and it was correct: intimate preferences did not
// guide the character into "I want this" or "I don't like that". The line they
// were given read, in full, "In intimate moments: warms to X; not interested in
// Y — only relevant when the scene is already there." That is a scope limiter.
// It says WHEN the facts apply and never what to do with them.
//
// Meanwhile the SCORING side had always been directive — weigh the exchange
// against these, name the one that moved a score — and it reaches the
// relationship AND emotional-state evals. So bond, trust and emotion were
// already moving on whether a scene hit their preferences while they never
// voiced them: silently rewarding and penalising the user over things they
// would not say out loud.
//
// The feature is a LOOP, and both ends are needed or neither works:
//   they ask  ->  the user answers  ->  being refused moves their mood
//             ->  that mood is what they carry into the next reply
// The judge that scores the answer is the Realism Engine, which is why this is
// a hard dependency rather than a chip, and why the gate resolves BOTH the
// switch and the engine at each call site.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/realism_prompt_builder.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/preferences_injection.dart';

void main() {
  CharacterCard spicy() => CharacterCard(
    name: 'Alice',
    frontPorchExtensions: FrontPorchExtensions(
      intimateInto: ['being held down'],
      intimateNotInto: ['an audience'],
    ),
  );

  String line({required bool agency, bool nsfw = true}) => PreferencesInjection(
    getActiveCharacter: spicy,
    getIsGroupNonObserverMode: () => false,
    getCurrentSpeakerIdForRealism: () => '',
    getGroupCharacters: () => const [],
    getCharacterIdFromCard: (c) => c.name,
    getNsfwEnabled: () => nsfw,
    getIntimateAgencyEnabled: () => agency,
  ).buildPreferencesInjection();

  group('with the switch on, they are told to ACT', () {
    late String txt;
    setUp(() => txt = line(agency: true));

    test('they pursue and may raise it themselves', () {
      expect(txt, contains('ACT on'));
      expect(
        txt,
        contains('can raise it themselves'),
        reason:
            'the old line forbade initiating outright; the maintainer '
            'asked for a character who demands snuggle time, which means they '
            'have to be able to bring it up',
      );
    });

    test('the register is their own, not one generic voice', () {
      // "A dominant character would force the issue, a soft spoken character
      // would softly suggest." Without this the desire is expressed in whatever
      // default voice the model reaches for, and every character asks the same
      // way.
      expect(txt, contains('in their own register'));
      expect(txt, contains('dominant character presses'));
      expect(txt, contains('soft-spoken one suggests'));
    });

    test('they decline what they are not into, rather than complying', () {
      expect(
        txt,
        contains('rather than going along with it'),
        reason:
            'a character who never turns anything down is a doormat, and '
            'an author who typed "not interested in an audience" meant they '
            'would say so',
      );
    });

    test('being refused colours their mood', () {
      expect(txt, contains('marks their mood'));
      expect(
        txt,
        contains('as fits who they are'),
        reason:
            'direction follows character — "refused, therefore angry" '
            'would make every character the same character',
      );
    });

    test('it keeps a proportionality guard', () {
      // They can initiate now, which is the point. A model told to pursue with
      // no counterweight steers every scene into the same place.
      expect(txt, contains('not the only thing they want'));
    });
  });

  group('with the switch off, the old passive line is unchanged', () {
    test('no licence to act', () {
      final txt = line(agency: false);

      expect(txt, contains('only relevant when the scene is already there'));
      expect(txt, isNot(contains('ACT on')));
      expect(txt, isNot(contains('can raise it themselves')));
    });

    test('the preferences themselves still reach the model', () {
      // Off means "they do not initiate", NOT "the card is ignored". They still
      // have tastes inside a scene they are already in.
      final txt = line(agency: false);

      expect(txt, contains('being held down'));
      expect(txt, contains('an audience'));
    });
  });

  test('18+ off hides the line entirely, switch or no switch', () {
    // The adult-themes master switch still wins. A card carrying intimate
    // preferences stays silent about them in a non-18+ install.
    final txt = line(agency: true, nsfw: false);

    expect(txt, isNot(contains('In intimate moments')));
    expect(txt, isNot(contains('being held down')));
  });

  group('the scorer is told the answer matters', () {
    String block({required bool agency}) =>
        RealismPromptBuilder.preferencesBlock(
          charName: 'Alice',
          intimateInto: const ['being held down'],
          intimateNotInto: const ['an audience'],
          intimateAgency: agency,
        );

    test('a refusal is scored as a real moment', () {
      final b = block(agency: true);

      expect(b, contains('was refused'));
      expect(b, contains('not a neutral exchange'));
      expect(
        b,
        contains('anger or cold distance in a dominant character'),
        reason:
            'this is the half that makes "refuse them and they get angry" '
            'actually happen — the emotional-state eval reads this block',
      );
    });

    test('with the switch off the clause is absent', () {
      // A judge told to weigh "they asked and were refused" against a character
      // who never asks is being asked to score something that did not happen.
      final b = block(agency: false);

      expect(b, isNot(contains('was refused')));
      expect(
        b,
        contains('Weigh the exchange against those'),
        reason: 'the rest of the preferences block is untouched by this switch',
      );
    });
  });
}
