// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The group Setting picker (Create Group, Edit Group, in-chat Group
// Settings): one world, the place new chats start at, lore-only worlds, and
// colours that follow the user's theme rather than Porch's amber.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/ui/theme/app_palette.dart';
import 'package:front_porch_ai/ui/theme/app_theme.dart';
import 'package:front_porch_ai/ui/theme/themes/high_contrast_theme.dart';
import 'package:front_porch_ai/ui/theme/themes/midnight_theme.dart';
import 'package:front_porch_ai/ui/widgets/group_setting_picker.dart';

World _w(String id, String name, {String? parent, bool climate = true}) =>
    World(
      id: id,
      name: name,
      lorebook: Lorebook(entries: []),
      parentWorldId: parent,
      climateEnabled: climate,
    );

final _vale = _w('vale', 'Green Vale')..defaultPlaceId = 'mill';
final _places = [
  _vale,
  _w('mill', 'The Mill', parent: 'vale', climate: false),
  _w('bridge', 'Old Bridge', parent: 'vale', climate: false),
  _w('reach', 'Salt Reach'),
];

Future<List<GroupWorldChoice>> _pump(
  WidgetTester tester,
  GroupWorldChoice start, {
  ThemeData? theme,
}) async {
  final emitted = <GroupWorldChoice>[];
  var value = start;
  await tester.binding.setSurfaceSize(const Size(1100, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => GroupSettingPicker(
              value: value,
              onChanged: (c) => setState(() {
                value = c;
                emitted.add(c);
              }),
              places: _places,
              weatherOf: (id) => id == 'reach' ? 'Coastal' : 'Temperate',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return emitted;
}

Color _edgeOf(WidgetTester tester, String key) {
  final material = tester.widget<Material>(
    find
        .descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(Material),
        )
        .first,
  );
  return (material.shape! as RoundedRectangleBorder).side.color;
}

void main() {
  group('follows the selected theme', () {
    for (final (name, palettes) in [
      ('Midnight', midnightTheme),
      ('High Contrast', highContrastTheme),
    ]) {
      for (final brightness in Brightness.values) {
        testWidgets('$name ${brightness.name}: the picked world wears the '
            "theme's accent", (tester) async {
          await _pump(
            tester,
            const GroupWorldChoice(settingId: 'vale'),
            theme: AppTheme.build(palettes: palettes, brightness: brightness),
          );
          final palette = brightness == Brightness.dark
              ? palettes.dark
              : palettes.light;
          expect(
            _edgeOf(tester, 'group-setting-world-vale'),
            palette.formAccent,
          );
          expect(
            _edgeOf(tester, 'group-setting-world-vale'),
            isNot(AppPalette.porchDark.formAccent),
            reason: 'Porch amber under another theme is the bug',
          );
          expect(_edgeOf(tester, 'group-setting-world-reach'), palette.border);
        });
      }
    }
  });

  testWidgets('one world at a time; a lore world picked as Setting stops '
      'being lore', (tester) async {
    final emitted = await _pump(
      tester,
      const GroupWorldChoice(settingId: 'vale', loreIds: ['reach']),
    );
    await tester.tap(find.byKey(const ValueKey('group-setting-world-reach')));
    await tester.pumpAndSettle();
    expect(emitted.last, const GroupWorldChoice(settingId: 'reach'));
  });

  testWidgets('the star is stored as the world; another place as itself', (
    tester,
  ) async {
    final emitted = await _pump(
      tester,
      const GroupWorldChoice(settingId: 'vale'),
    );
    expect(find.text('Default'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-setting-place-bridge')));
    await tester.pumpAndSettle();
    expect(emitted.last.settingId, 'bridge');
    await tester.tap(find.byKey(const ValueKey('group-setting-place-mill')));
    await tester.pumpAndSettle();
    expect(
      emitted.last.settingId,
      'vale',
      reason: 'the group follows the star if the author moves it later',
    );
  });

  testWidgets('lore-only worlds are listed apart and never include the '
      'Setting', (tester) async {
    final emitted = await _pump(
      tester,
      const GroupWorldChoice(settingId: 'vale'),
    );
    await tester.tap(find.byKey(const ValueKey('group-setting-lore-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-setting-lore-vale')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('group-setting-lore-reach')));
    await tester.pumpAndSettle();
    expect(
      emitted.last,
      const GroupWorldChoice(settingId: 'vale', loreIds: ['reach']),
    );
  });

  test('the summary names the start, the weather and the lore', () {
    World? lookup(String id) => _places.where((w) => w.id == id).firstOrNull;
    String? weather(String id) => id == 'reach' ? 'Coastal' : 'Temperate';
    expect(
      groupSettingSummary(
        const GroupWorldChoice(settingId: 'vale', loreIds: ['reach']),
        lookup,
        weather,
      ),
      'New chats start at The Mill in Green Vale. Weather: Temperate. '
      'Also reads lore from Salt Reach, with no weather from it.',
    );
    expect(
      groupSettingSummary(const GroupWorldChoice(), lookup, weather),
      'New chats start with no world.',
    );
  });
}
