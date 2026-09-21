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

// An authored wardrobe has to be in the prompt for TURN 1.
//
// Numbering, so this file and the code agree: the greeting is turn 0, and turn
// 1 is the character's first real reply — the answer to the user's first
// message.
//
// THE BUG. The card seed lived only inside `_runPocketsPass`, which runs AFTER
// a reply has been generated. So the sequence was: user sends their first
// message -> the prompt is built with NO inventory fragment, because no record
// exists yet -> the model writes turn 1 knowing nothing about the flour-dusted
// apron its author put on her -> only THEN does the pass seed the record. She
// was dressed from turn 2 onward and bare for the one turn that sets the scene.
//
// The sidebar had the same hole: blank until after the first reply, which is
// exactly when an author who has just set a wardrobe goes looking to check it
// saved.
//
// Nobody could hit this before there was an editor, because nothing wrote the
// field. Authoring made it reachable, so it is fixed with authoring.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/inventory_injection.dart';

InventoryInjection make({
  CharacterCard? active,
  List<CharacterCard> group = const [],
  String speakerId = '',
  Map<String, Pockets> records = const {},
}) => InventoryInjection(
  getActiveCharacter: () => active,
  getIsGroupNonObserverMode: () => group.isNotEmpty,
  getCurrentSpeakerIdForRealism: () => speakerId,
  getGroupCharacters: () => group,
  getCharacterIdFromCard: (c) => c.name,
  getCurrentDay: () => 0,
  getPockets: (id) => records[id],
);

/// A card whose author dressed her, exactly as the editor now writes it.
CharacterCard authored() => CharacterCard(
  name: 'Jennifer',
  frontPorchExtensions: FrontPorchExtensions(
    inventory: Pockets.cardJsonFrom(
      worn: const ['flour-dusted apron (well-worn)'],
      carrying: const ['shop keys'],
    ),
  ),
);

void main() {
  group('what turn 1 actually gets', () {
    test('with the record seeded, the prompt names her wardrobe', () {
      final card = authored();
      // What seedPocketsFromCards puts in place before generation.
      final seeded = Pockets.fromJson(card.frontPorchExtensions!.inventory);

      final txt = make(
        active: card,
        records: {'Jennifer': seeded},
      ).buildInventoryInjection();

      expect(txt, contains('flour-dusted apron (well-worn)'));
      expect(txt, contains('shop keys'));
      expect(
        txt,
        startsWith('Jennifer is'),
        reason: 'stated as fact, so the model can simply write her wearing it',
      );
    });

    test('WITHOUT the seed the prompt is silent — the bug, stated', () {
      // This is precisely what turn 1 looked like: a card with a wardrobe, and
      // a prompt that never mentions it, because the record does not exist
      // until the post-generation pass has run once.
      final txt = make(
        active: authored(),
        records: const {},
      ).buildInventoryInjection();

      expect(txt, isEmpty);
    });

    test('the seed carries condition into that first prompt', () {
      // A wardrobe that arrives freshly laundered on turn 1 and rain-soaked on
      // turn 2 is worse than one that arrives late.
      final card = CharacterCard(
        name: 'Jennifer',
        frontPorchExtensions: FrontPorchExtensions(
          inventory: Pockets.cardJsonFrom(
            worn: const ['sundress (rain-soaked)'],
            carrying: const [],
          ),
        ),
      );

      final txt = make(
        active: card,
        records: {
          'Jennifer': Pockets.fromJson(card.frontPorchExtensions!.inventory),
        },
      ).buildInventoryInjection();

      expect(txt, contains('sundress (rain-soaked)'));
    });

    test('a card with no wardrobe still says nothing', () {
      final txt = make(
        active: CharacterCard(name: 'Jennifer'),
        records: {
          'Jennifer': Pockets.fromJson(
            CharacterCard(name: 'Jennifer').frontPorchExtensions?.inventory,
          ),
        },
      ).buildInventoryInjection();

      expect(
        txt,
        isEmpty,
        reason:
            'seeding must not turn "nothing authored" into a fragment '
            'claiming she is carrying nothing, which reads as a fact about her',
      );
    });

    test('in a group each member gets THEIR OWN starting kit', () {
      // The seed loops over every speaker, so this is the case where a
      // one-record-fits-all mistake would show: both members dressed as the
      // first one.
      final jen = authored();
      final sam = CharacterCard(
        name: 'Sam',
        frontPorchExtensions: FrontPorchExtensions(
          inventory: Pockets.cardJsonFrom(
            worn: const ['leather jacket'],
            carrying: const [],
          ),
        ),
      );
      final records = {
        for (final c in [jen, sam])
          c.name: Pockets.fromJson(c.frontPorchExtensions!.inventory),
      };

      final txt = make(
        group: [jen, sam],
        speakerId: 'Sam',
        records: records,
      ).buildInventoryInjection();

      expect(txt, contains('leather jacket'));
      expect(
        txt,
        isNot(contains('apron')),
        reason: 'Sam must not be narrated wearing Jennifer\'s apron',
      );
    });
  });
}
