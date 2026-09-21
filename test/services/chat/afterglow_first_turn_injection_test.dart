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

// Afterglow used to stamp limp / tired / exhausted for most of the
// cooldown: a three-phase ratio over remaining/total kept saying
// "wrecked", "heavy-limbed", or "sated tiredness" on every afterglow
// reply, and the first phase told the model other physical needs were
// "far away". That fights energy and comfort Needs for the whole arc.
//
// Desired contract:
//   * First afterglow generation may still force post-climax limp/tired.
//   * From the second afterglow generation on, closeness and "not yet"
//     stay, but tired / limp / exhausted do not override Needs.
//
// Decrement ticks at send start, so the first afterglow prompt usually
// sees remaining == total - 1. Remaining == total is Continue of the
// climax reply (no tick). Both are the opening turn.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';

NsfwService _svc({int remaining = 0, int total = 0}) {
  return NsfwService(
    getGroupInt: (_, _) => 0,
    getGroupValue: (_, _) => null,
    setGroupValue: (_, _, _) {},
  )..loadNsfwScalars(
    nsfwCooldownEnabled: true,
    arousalLevel: 0,
    cooldownTurnsRemaining: remaining,
    cooldownTurnsTotal: total,
  );
}

NsfwInjection _inject(
  NsfwService svc, {
  CharacterCard? active,
  bool group = false,
  String speakerId = 'c1',
  List<CharacterCard>? groupChars,
}) {
  return NsfwInjection(
    nsfwService: svc,
    getRealismEnabled: () => true,
    getActiveCharacter: () => active ?? CharacterCard(name: 'Nia'),
    getIsGroupNonObserverMode: () => group,
    getCurrentSpeakerIdForRealism: () => speakerId,
    getGroupCharacters: () => groupChars ?? const [],
    getCharacterIdFromCard: (c) => c.name,
  );
}

/// Phrases that force limp / tired / exhausted (or ignore Needs).
const _exhaustionLock = [
  'just climaxed',
  'blissfully wrecked',
  'heavy-limbed',
  'sated tiredness',
  'physical needs feeling far away',
  'still trembling',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('opening-turn math (tick happens before the prompt)', () {
    test(
      'apply + first decrement is still the opening turn; the second is not',
      () {
        final svc = _svc();
        svc.setNsfwCooldownEnabled(true);
        svc.applyClimaxEffects(turns: 6);

        expect(
          svc.isOpeningAfterglowTurn,
          isTrue,
          reason: 'right after climax, before any send tick',
        );

        svc.decrementCooldownIfActive();
        expect(
          svc.isOpeningAfterglowTurn,
          isTrue,
          reason: 'first user send ticks 6 → 5; that prompt is still turn 1',
        );

        svc.decrementCooldownIfActive();
        expect(
          svc.isOpeningAfterglowTurn,
          isFalse,
          reason: 'second send ticks 5 → 4; Needs must drive tired/comfort',
        );
      },
    );
  });

  group('Body line', () {
    test('turn 1 (pre-tick and first send) may force limp/tired', () {
      for (final pair in [(remaining: 6, total: 6), (remaining: 5, total: 6)]) {
        final txt = _inject(
          _svc(remaining: pair.remaining, total: pair.total),
        ).buildNsfwCooldownInjection();
        expect(
          txt,
          contains('just climaxed'),
          reason: '${pair.remaining}/${pair.total} is the opening turn',
        );
        expect(txt, contains('wrecked'));
      }
    });

    test('turn 2+ keeps afterglow closeness but does not override Needs', () {
      for (final pair in [
        (remaining: 4, total: 6),
        (remaining: 3, total: 6),
        (remaining: 2, total: 6),
        (remaining: 1, total: 6),
      ]) {
        final txt = _inject(
          _svc(remaining: pair.remaining, total: pair.total),
        ).buildNsfwCooldownInjection();
        expect(
          txt,
          contains('afterglow'),
          reason: '${pair.remaining}/${pair.total} is still Afterglow',
        );
        expect(
          txt.toLowerCase(),
          contains('energy'),
          reason:
              'later turns must hand tired/comfort back to Needs, '
              'not stay silent about the hand-off',
        );
        expect(txt.toLowerCase(), contains('comfort'));
        for (final lock in _exhaustionLock) {
          expect(
            txt,
            isNot(contains(lock)),
            reason:
                '${pair.remaining}/${pair.total} must not re-assert '
                '"$lock"',
          );
        }
      }
    });

    test('group later-turn uses the upcoming speaker, same contract', () {
      final txt = _inject(
        _svc(remaining: 4, total: 6),
        group: true,
        speakerId: 'Rue',
        groupChars: [
          CharacterCard(name: 'Nia'),
          CharacterCard(name: 'Rue'),
        ],
      ).buildNsfwCooldownInjection();
      expect(txt, contains('Rue'));
      expect(txt, isNot(contains('Nia')));
      expect(txt, contains('afterglow'));
      for (final lock in _exhaustionLock) {
        expect(txt, isNot(contains(lock)));
      }
    });
  });
}
