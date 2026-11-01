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

// Settings → Appearance: the Background weather section holds the weather
// controls and is not shown while Porch Life's Story Weather is off; Mood
// on the character sits under Chat Appearance, is not shown while the
// Realism Engine is off, and its Drama only moves while the row is on. A
// change writes the setting once.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/appearance_settings.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/appearance_tab/background_weather_section.dart';
import 'package:front_porch_ai/ui/settings/tabs/appearance_tab/mood_on_character_controls.dart';
import 'package:front_porch_ai/ui/theme/appearance_options.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Only the two settings objects the sections read; the rest throws.
class _Storage extends ChangeNotifier implements StorageService {
  _Storage() {
    appearance.initializeBase(null, notifyListeners);
    appearance.load();
    realismSettings.initializeBase(null, notifyListeners);
    realismSettings.load();
  }

  @override
  final AppearanceSettings appearance = AppearanceSettings();

  @override
  final RealismSettings realismSettings = RealismSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_Storage> _pump(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final storage = _Storage();
  addTearDown(storage.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<StorageService>.value(
      value: storage,
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 900, child: child),
          ),
        ),
      ),
    ),
  );
  return storage;
}

void main() {
  testWidgets('Background weather goes away with Story Weather off', (
    tester,
  ) async {
    final storage = await _pump(tester, const BackgroundWeatherSection());
    expect(find.text('Background weather'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('appearance-ambient-scene')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('appearance-ambient-pause')),
      findsOneWidget,
    );
    expect(find.text(BackgroundWeatherSection.caption), findsOneWidget);
    expect(find.byTooltip(BackgroundWeatherSection.tooltip), findsOneWidget);

    await storage.realismSettings.setWeatherEnabled(false);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('background-weather-off')),
      findsOneWidget,
    );
    expect(find.text('Background weather'), findsNothing);
    expect(
      find.byKey(const ValueKey('appearance-ambient-scene')),
      findsNothing,
    );
    // The setting itself is kept for when the weather comes back.
    expect(storage.appearance.ambientScene, AmbientScene.off);
  });

  testWidgets('Mood on the character goes away with the Realism Engine off', (
    tester,
  ) async {
    final storage = await _pump(tester, const MoodOnCharacterControls());
    expect(find.text('MOOD ON THE CHARACTER'), findsOneWidget);
    expect(find.text(MoodOnCharacterControls.caption), findsOneWidget);

    await storage.realismSettings.setRealismAllowed(false);
    await tester.pump();
    expect(find.byKey(const ValueKey('mood-on-character-off')), findsOneWidget);
    expect(find.text('MOOD ON THE CHARACTER'), findsNothing);
  });

  testWidgets('the Drama moves only while the row is on, and a pick writes '
      'the level once', (tester) async {
    final storage = await _pump(tester, const MoodOnCharacterControls());
    final slider = find.byKey(const ValueKey('appearance-mood-drama'));
    expect(tester.widget<Slider>(slider).onChanged, isNull);
    expect(storage.appearance.moodOnCharacter, MoodOnCharacter.off);

    await tester.tap(find.text('Portrait and needs'));
    await tester.pump();
    expect(storage.appearance.moodOnCharacter, MoodOnCharacter.portrait);
    expect(tester.widget<Slider>(slider).onChanged, isNotNull);

    final before = storage.appearance.moodDrama;
    await tester.drag(slider, const Offset(60, 0));
    await tester.pump();
    expect(storage.appearance.moodDrama, isNot(before));
    expect(
      storage.appearance.moodDrama,
      inInclusiveRange(kMoodDramaMin, kMoodDramaMax),
    );

    await tester.tap(find.text('Off'));
    await tester.pump();
    expect(storage.appearance.moodOnCharacter, MoodOnCharacter.off);
    expect(tester.widget<Slider>(slider).onChanged, isNull);
  });
}
