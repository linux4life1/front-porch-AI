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
// 2026-10-06, needs-on-the-clock v2: the opening turn is a flag, not
// "remaining >= total - 1". The refractory now counts story minutes, so a
// same-moment reply would never move the count; the climax sets the flag
// unspoken and the first reply after the climax reply marks it spoken. The
// cases below are the same turns expressed as minutes and that flag.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';

NsfwService _svc({Refractory refractory = Refractory.none}) {
  return NsfwService(
    getGroupInt: (_, _) => 0,
    getGroupValue: (_, _) => null,
    setGroupValue: (_, _, _) {},
  )..loadNsfwScalars(
    nsfwCooldownEnabled: true,
    arousalLevel: 0,
    refractory: refractory,
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

  group(
    'opening-turn flag (spent by the first reply after the climax reply)',
    () {
      test('climax leaves it unspoken, time alone does not spend it, the first '
          'reply after the climax reply does', () {
        final svc = _svc();
        svc.setNsfwCooldownEnabled(true);
        svc.applyClimaxEffects(turns: 6);

        expect(
          svc.isOpeningAfterglowTurn,
          isTrue,
          reason: 'right after climax, before the next reply',
        );

        svc.setRefractory(svc.refractory.elapse(15, arousal: 0).refractory);
        expect(
          svc.isOpeningAfterglowTurn,
          isTrue,
          reason: 'a quarter hour passed (90 → 75); still turn 1',
        );

        svc.setRefractory(svc.refractory.markOpened());
        expect(
          svc.isOpeningAfterglowTurn,
          isFalse,
          reason: 'that reply spoke it; Needs must drive tired/comfort',
        );

        svc.setRefractory(svc.refractory.elapse(0, arousal: 0).refractory);
        expect(
          svc.isOpeningAfterglowTurn,
          isFalse,
          reason: 'a same-moment second reply is not the opening turn',
        );
      });
    },
  );

  group('Body line', () {
    test('turn 1 (before and after time passes) may force limp/tired', () {
      for (final r in [
        const Refractory(minutes: 90, total: 90),
        const Refractory(minutes: 75, total: 90),
      ]) {
        final txt = _inject(_svc(refractory: r)).buildNsfwCooldownInjection();
        expect(
          txt,
          contains('just climaxed'),
          reason: '$r is the opening turn',
        );
        expect(txt, contains('wrecked'));
      }
    });

    test('turn 2+ keeps afterglow closeness but does not override Needs', () {
      for (final r in [
        const Refractory(minutes: 60, total: 90, opened: true),
        const Refractory(minutes: 45, total: 90, opened: true),
        const Refractory(minutes: 30, total: 90, opened: true),
        const Refractory(minutes: 15, total: 90, opened: true),
        // The same moment as the opening reply: no time, but turn 2.
        const Refractory(minutes: 90, total: 90, opened: true),
      ]) {
        final txt = _inject(_svc(refractory: r)).buildNsfwCooldownInjection();
        expect(txt, contains('afterglow'), reason: '$r is still Afterglow');
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
            reason: '$r must not re-assert "$lock"',
          );
        }
      }
    });

    test('group later-turn uses the upcoming speaker, same contract', () {
      final txt = _inject(
        _svc(
          refractory: const Refractory(minutes: 60, total: 90, opened: true),
        ),
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
