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

// Mood on the character's colours: the need hues the web wire sends are the
// ones the desktop bar paints with in each brightness, the tone hues are
// the sidebar's emotion-ring legend, and the wire carries every tone and
// need as a CSS colour for both modes.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/mood_physics.dart';
import 'package:front_porch_ai/services/chat/needs_simulation/needs_tables.dart';
import 'package:front_porch_ai/ui/theme/realism_colors.dart';

final _css = RegExp(r'^(#[0-9a-f]{6}|rgba\(\d+, \d+, \d+, [0-9.]+\))$');

void main() {
  for (final light in [false, true]) {
    testWidgets(
      'the wire need hues are the bar hues in ${light ? 'light' : 'dark'} mode',
      (tester) async {
        late BuildContext ctx;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: light ? Brightness.light : Brightness.dark,
            ),
            home: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
          ),
        );
        for (final need in NeedsTables.needKeys) {
          expect(
            RealismColors.needHueFor(need, dark: !light),
            RealismColors.needHueOf(ctx, need),
            reason: need,
          );
        }
        expect(
          RealismColors.needHueOf(ctx, 'hunger'),
          RealismColors.hungerOf(ctx),
        );
        expect(
          RealismColors.needHueOf(ctx, 'energy'),
          RealismColors.energyBarOf(ctx),
        );
        expect(
          RealismColors.needHueOf(ctx, 'hygiene'),
          RealismColors.hygieneOf(ctx),
        );
        expect(
          RealismColors.bondHaloFor(warm: true, dark: !light),
          RealismColors.bondHaloOf(ctx, warm: true),
        );
        expect(
          RealismColors.bondHaloFor(warm: false, dark: !light),
          RealismColors.bondHaloOf(ctx, warm: false),
        );
      },
    );
  }

  test('the tone hues are the emotion ring legend', () {
    expect(
      RealismColors.moodToneColor(MoodTone.sour),
      RealismColors.emotionRing('anger'),
    );
    expect(
      RealismColors.moodToneColor(MoodTone.low),
      RealismColors.emotionRing('grief'),
    );
    expect(
      RealismColors.moodToneColor(MoodTone.anxious),
      RealismColors.emotionRing('fear'),
    );
    expect(
      RealismColors.moodToneColor(MoodTone.lifted),
      RealismColors.emotionRing('joy'),
    );
    expect(
      RealismColors.moodToneColor(MoodTone.warm),
      RealismColors.emotionRing('love'),
    );
    expect(
      RealismColors.moodToneColor(MoodTone.charged),
      RealismColors.emotionRing('desire'),
    );
  });

  test(
    'the wire carries every tone and need for both modes as CSS colours',
    () {
      final wire = RealismColors.moodPaintsWire();
      final tones = wire['tones'] as Map;
      expect(tones.keys, unorderedEquals(MoodTone.values.map((t) => t.name)));
      for (final v in tones.values) {
        expect(v, matches(_css));
      }
      for (final mode in ['dark', 'light']) {
        final m = wire[mode] as Map;
        final needs = m['needs'] as Map;
        expect(needs.keys, unorderedEquals(NeedsTables.needKeys));
        for (final v in [...needs.values, m['haloWarm'], m['haloChill']]) {
          expect(v, matches(_css));
        }
      }
      expect(
        (wire['dark'] as Map)['needs'],
        isNot((wire['light'] as Map)['needs']),
      );
    },
  );
}
