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
// on, both write the setting, and a drag writes the volume once, when it
// ends, not once per step.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage/settings/appearance_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/appearance_tab/scene_sound_controls.dart';

/// The real preferences, counting each write by key.
class _CountingPrefs implements SharedPreferences {
  _CountingPrefs(this._real);
  final SharedPreferences _real;
  final Map<String, int> writes = {};

  void _count(String key) => writes[key] = (writes[key] ?? 0) + 1;

  @override
  String? getString(String key) => _real.getString(key);
  @override
  bool? getBool(String key) => _real.getBool(key);
  @override
  double? getDouble(String key) => _real.getDouble(key);
  @override
  int? getInt(String key) => _real.getInt(key);
  @override
  Future<bool> setString(String key, String value) {
    _count(key);
    return _real.setString(key, value);
  }

  @override
  Future<bool> setBool(String key, bool value) {
    _count(key);
    return _real.setBool(key, value);
  }

  @override
  Future<bool> setDouble(String key, double value) {
    _count(key);
    return _real.setDouble(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(AppearanceSettings, _CountingPrefs)> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = _CountingPrefs(await SharedPreferences.getInstance());
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
  return (appearance, prefs);
}

final _slider = find.byKey(const ValueKey('appearance-scene-sound-volume'));
final _switch = find.byKey(const ValueKey('appearance-scene-sound'));

void main() {
  testWidgets('the volume moves only with Scene sound on', (tester) async {
    final (appearance, prefs) = await _pump(tester);

    expect(find.text('SCENE SOUND'), findsOneWidget);
    expect(tester.widget<Slider>(_slider).onChanged, isNull);
    expect(tester.widget<Slider>(_slider).value, 0.5);

    // Dragging a disabled slider changes nothing.
    await tester.drag(_slider, const Offset(60, 0));
    await tester.pump();
    expect(appearance.sceneSoundVolume, 0.5);

    await tester.tap(_switch);
    await tester.pump();
    expect(appearance.sceneSound, isTrue);
    expect(prefs.getBool(appearance.k('scene_sound')), isTrue);
    expect(tester.widget<Slider>(_slider).onChanged, isNotNull);

    await tester.tapAt(tester.getCenter(_slider) + const Offset(60, 0));
    await tester.pump();
    expect(appearance.sceneSoundVolume, greaterThan(0.7));
    expect(prefs.getDouble(appearance.k('scene_sound_volume')), isNotNull);
  });

  testWidgets('a drag writes the volume once, when it ends', (tester) async {
    final (appearance, prefs) = await _pump(tester);
    await tester.tap(_switch);
    await tester.pump();
    final key = appearance.k('scene_sound_volume');

    final gesture = await tester.startGesture(tester.getCenter(_slider));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump();
    }
    // Mid-drag the thumb follows, nothing is written.
    expect(tester.widget<Slider>(_slider).value, greaterThan(0.5));
    expect(prefs.writes[key], isNull);
    expect(appearance.sceneSoundVolume, 0.5);

    await gesture.up();
    await tester.pump();
    expect(prefs.writes[key], 1);
    expect(appearance.sceneSoundVolume, greaterThan(0.5));
    expect(prefs.getDouble(key), appearance.sceneSoundVolume);
  });
}
