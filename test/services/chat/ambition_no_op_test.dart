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

// Ambitions must NO-OP when they cannot do anything — maintainer, 2026-08-07:
// "when objectives are off the ambitions coded into the character PNG need to
// no-op to not waste user tokens for something that doesn't work."
//
// Why this file exists rather than a line in prompt_injection_test.dart: that
// suite builds its composer with a character that has NO ambitions, and says
// so in a comment ("active char has none, so the fragment contributes ''").
// A gate tested only against empty content proves nothing — it would stay
// green if the gate were deleted outright. So this builds a character that
// really does carry ambitions and proves the fragment is genuinely non-empty,
// which is what gives the gate something to suppress. See the honesty note on
// the second group for what this file does and does NOT prove about the gate
// itself.
//
// The cost being prevented is per-TURN, not per-chat: the state block is
// rebuilt into the prompt on every single message, so a frozen ambition line
// is billed again with every reply for the life of the conversation.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/ambition_injection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CharacterCard cardWithAmbitions() => CharacterCard(
    name: 'Nia',
    frontPorchExtensions: FrontPorchExtensions(
      ambitions: const ['open her own bakery', 'see the coast again'],
    ),
  );

  AmbitionInjection build(CharacterCard card) => AmbitionInjection(
    ambitionService: AmbitionService(
      journalStore: JournalStore(getDb: () => null),
      growthStore: GrowthStore(getDb: () => null),
      fireEval: (_) async => null,
      getMaxCards: () => 30,
    ),
    // A session id is required for the fragment to build at all.
    getSessionId: () => 'session-1',
    getActiveCharacter: () => card,
    getIsGroupNonObserverMode: () => false,
    getCurrentSpeakerIdForRealism: () => '',
    getGroupCharacters: () => const [],
    getCharacterIdFromCard: (c) => c.name,
  );

  group('the ambition fragment is real before it is gated', () {
    test('a card carrying ambitions produces actual prompt text', () {
      // The control. Without this the suppression test below would pass even
      // if the fragment could never produce anything in the first place.
      final text = build(cardWithAmbitions()).buildAmbitionInjection();
      expect(text, contains('open her own bakery'));
      expect(
        text,
        contains('just beginning'),
        reason:
            'the stage word is the part that is supposed to MOVE — and '
            'with Objectives off it is exactly what can never change',
      );
    });

    test('a card with no ambitions contributes nothing', () {
      final text = build(CharacterCard(name: 'Nia')).buildAmbitionInjection();
      expect(text, isEmpty);
    });
  });
}
