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

// Mood on the character, the maths (`mood_atmosphere.dart`): strength by
// intensity, drama and hold; a need in trouble, with hygiene inverted for a
// character who enjoys it low; the ring's weight from trust; the bond halo;
// and the setting's levels and Drama range. The web port
// (`web_ui/src/theme/moodAtmosphere.test.ts`) pins the same numbers.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/mood_atmosphere.dart';
import 'package:front_porch_ai/services/chat/mood_physics.dart';
import 'package:front_porch_ai/services/storage/settings/appearance_settings.dart';
import 'package:front_porch_ai/ui/theme/appearance_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('strength', () {
    test('grows with intensity and drama, eases with hold, never below the '
        'floor, and caps', () {
      expect(
        moodStrength(tone: MoodTone.lifted, rank: 1, held: 0, drama: 1),
        closeTo(0.3, 1e-9),
      );
      expect(
        moodStrength(tone: MoodTone.lifted, rank: 2, held: 0, drama: 1),
        closeTo(0.55, 1e-9),
      );
      expect(
        moodStrength(tone: MoodTone.lifted, rank: 3, held: 0, drama: 1),
        closeTo(0.85, 1e-9),
      );
      expect(
        moodStrength(tone: MoodTone.lifted, rank: 3, held: 0, drama: 1.6),
        closeTo(1.2, 1e-9),
      );
      expect(
        moodStrength(tone: MoodTone.lifted, rank: 3, held: 2, drama: 1),
        closeTo(0.85 / 1.16, 1e-9),
      );
      expect(
        moodStrength(tone: MoodTone.lifted, rank: 3, held: 40, drama: 1),
        closeTo(0.85 * 0.6, 1e-9),
      );
      expect(moodStrength(tone: null, rank: 3, held: 0, drama: 1), 0);
    });

    test('a stamped mood with no intensity word still paints, as mild', () {
      final m = MoodAtmosphere.of(const MoodState(label: 'joy'), drama: 1);
      expect(m.tone, MoodTone.lifted);
      expect(m.rank, 1);
      expect(m.strength, closeTo(0.3, 1e-9));
      expect(m.isOn, isTrue);
    });

    test('neutral and an unknown label paint nothing', () {
      expect(MoodAtmosphere.of(MoodState.neutral, drama: 1).isOn, isFalse);
      expect(
        MoodAtmosphere.of(
          const MoodState(label: 'bewilderment', intensity: 'strong'),
          drama: 1,
        ).tone,
        isNull,
      );
      expect(MoodAtmosphere.none.isOn, isFalse);
    });
  });

  group('needs in trouble', () {
    test('a need at 25 or under throbs and under 10 hammers', () {
      expect(
        needTrouble(need: 'energy', level: 30, enjoysLowHygiene: false).low,
        isFalse,
      );
      final low = needTrouble(
        need: 'energy',
        level: 25,
        enjoysLowHygiene: false,
      );
      expect((low.low, low.critical, low.inverted), (true, false, false));
      final crit = needTrouble(
        need: 'energy',
        level: 9,
        enjoysLowHygiene: false,
      );
      expect((crit.low, crit.critical), (true, true));
    });

    test('hygiene inverts for a character who enjoys it low', () {
      final quiet = needTrouble(
        need: 'hygiene',
        level: 12,
        enjoysLowHygiene: true,
      );
      expect((quiet.low, quiet.inverted), (false, true));
      final high = needTrouble(
        need: 'hygiene',
        level: 75,
        enjoysLowHygiene: true,
      );
      expect((high.low, high.critical), (true, false));
      final filthy = needTrouble(
        need: 'hygiene',
        level: 92,
        enjoysLowHygiene: true,
      );
      expect((filthy.low, filthy.critical), (true, true));
      // The flag touches hygiene alone.
      expect(
        needTrouble(need: 'energy', level: 92, enjoysLowHygiene: true).low,
        isFalse,
      );
      expect(
        needTrouble(need: 'hygiene', level: 12, enjoysLowHygiene: false).low,
        isTrue,
      );
    });

    test('finds the first need in trouble', () {
      expect(
        anyNeedInTrouble({'hunger': 80, 'energy': 12}, enjoysLowHygiene: false),
        isTrue,
      );
      expect(
        firstNeedInTrouble({
          'hunger': 80,
          'energy': 12,
        }, enjoysLowHygiene: false),
        'energy',
      );
      expect(
        firstNeedInTrouble({
          'hunger': 80,
          'hygiene': 90,
        }, enjoysLowHygiene: true),
        'hygiene',
      );
      expect(
        firstNeedInTrouble({
          'hunger': 80,
          'hygiene': 90,
        }, enjoysLowHygiene: false),
        isNull,
      );
    });
  });

  group('trust and bond', () {
    test('the ring is heavy, settled or broken by trust', () {
      expect(ringWeightForTrust(55), MoodRingWeight.heavy);
      expect(ringWeightForTrust(0), MoodRingWeight.settled);
      expect(ringWeightForTrust(-40), MoodRingWeight.broken);
    });

    test('the halo widens with the bond and chills below zero', () {
      expect(bondHalo(40), (share: 0.4, warm: true));
      expect(bondHalo(-100), (share: 1.0, warm: false));
      expect(bondHalo(0).share, 0);
    });
  });

  group('the setting', () {
    test(
      'levels: off paints nothing, portrait the ring, all the bubbles too',
      () {
        expect(MoodOnCharacter.fromKey('all').bubblesOn, isTrue);
        expect(MoodOnCharacter.fromKey('portrait').portraitOn, isTrue);
        expect(MoodOnCharacter.fromKey('portrait').bubblesOn, isFalse);
        expect(MoodOnCharacter.fromKey('loud'), MoodOnCharacter.off);
        expect(MoodOnCharacter.off.portraitOn, isFalse);
      },
    );

    test(
      'the store keeps the level and holds the Drama to its range',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final appearance = AppearanceSettings();
        appearance.initializeBase(prefs, () {});
        appearance.load();
        expect(appearance.moodOnCharacter, MoodOnCharacter.off);
        expect(appearance.moodDrama, kMoodDramaDefault);
        await appearance.setMoodOnCharacter(MoodOnCharacter.all);
        await appearance.setMoodDrama(9);
        expect(appearance.moodDrama, kMoodDramaMax);
        await appearance.setMoodDrama(0.1);
        expect(appearance.moodDrama, kMoodDramaMin);
        await appearance.setMoodDrama(1.2);
        final again = AppearanceSettings();
        again.initializeBase(prefs, () {});
        again.load();
        expect(again.moodOnCharacter, MoodOnCharacter.all);
        expect(again.moodDrama, 1.2);
      },
    );
  });
}
