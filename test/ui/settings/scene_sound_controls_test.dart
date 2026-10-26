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

// Settings → Appearance → Scene sound (docs/design/ambient-stage.md §5):
// off to start with, the volume slider does nothing until the switch is
// on, and both write the setting.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage/settings/appearance_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/appearance_tab/scene_sound_controls.dart';

void main() {
  testWidgets('the volume moves only with Scene sound on', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final appearance = AppearanceSettings();
    late StateSetter rebuild;
    appearance.initializeBase(prefs, () => rebuild(() {}));
    appearance.load();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return SceneSoundControls(appearance: appearance);
            },
          ),
        ),
      ),
    );

    expect(find.text('SCENE SOUND'), findsOneWidget);
    final slider = find.byKey(const ValueKey('appearance-scene-sound-volume'));
    expect(tester.widget<Slider>(slider).onChanged, isNull);
    expect(tester.widget<Slider>(slider).value, 0.5);

    // Dragging a disabled slider changes nothing.
    await tester.drag(slider, const Offset(60, 0));
    await tester.pump();
    expect(appearance.sceneSoundVolume, 0.5);

    await tester.tap(find.byKey(const ValueKey('appearance-scene-sound')));
    await tester.pump();
    expect(appearance.sceneSound, isTrue);
    expect(tester.widget<Slider>(slider).onChanged, isNotNull);

    await tester.tapAt(tester.getCenter(slider) + const Offset(60, 0));
    await tester.pump();
    expect(appearance.sceneSoundVolume, greaterThan(0.7));
    expect(prefs.getDouble(appearance.k('scene_sound_volume')), isNotNull);
    expect(prefs.getBool(appearance.k('scene_sound')), isTrue);
  });
}
