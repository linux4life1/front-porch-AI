// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// The group "Realism & Dynamics" scene-time picker may only ever offer periods
// StoryClock actually knows. It used to offer 'noon' and 'late night' — neither
// is in StoryClock.periods, so representativeTime() fell back to morning and an
// authored midday/late-night opening silently became 09:00. These pin both the
// offered list and the migration of an old blob that still carries one.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/group_realism_dynamics_editor.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../../golden/support/fakes_storage.dart';

/// A realism-on group blob whose stored scene time is [timeOfDay] — exactly the
/// shape buildGroupRealismBlobs writes (and parseGroupTimeSeed reads at runtime).
GroupRealismBlobs _blobs(String timeOfDay) => buildGroupRealismBlobs(
  seeds: {'m1': defaultGroupMemberRealismSeed()},
  needsEnabled: true,
  timeOfDay: timeOfDay,
  dayCount: 1,
);

Future<String> _pump(WidgetTester tester, GroupRealismBlobs blobs) async {
  var emittedDefault = '';
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GroupRealismDynamicsEditor(
          // Fresh element per pump — otherwise the second _pump in a test
          // updates the existing State and never re-reads the new blob.
          key: UniqueKey(),
          // No member cards: the scene-time card is what's under test, and
          // GroupMemberRealismEditor's ListTile trips an unrelated framework
          // ink assertion. The stored seed below still turns realism on.
          members: const [],
          initialDefaultMemberJson: blobs.defaultMemberJson,
          initialBaselineJson: blobs.baselineJson,
          onChanged: (d, b) => emittedDefault = d,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Bump the day counter: any edit re-emits the blobs, carrying the time seed.
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
  return emittedDefault;
}

void main() {
  testWidgets('every offered time-of-day is a real StoryClock period', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, _blobs('morning'));

    final dropdown = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>).first,
    );
    final offered = [for (final i in dropdown.items!) i.value];
    expect(offered, StoryClock.periods);
    for (final period in offered) {
      // Not the silent morning fallback: an unknown string lands on 09:00.
      final at = StoryClock.representativeTime(
        DateTime.utc(2026, 1, 1),
        period!,
      );
      if (period != 'morning') {
        expect(
          at,
          isNot(
            StoryClock.representativeTime(DateTime.utc(2026, 1, 1), 'morning'),
          ),
          reason: '$period must have its own representative time',
        );
      }
    }
  });

  testWidgets('a legacy noon/late-night blob is migrated, never re-emitted', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final emitted = jsonDecode(await _pump(tester, _blobs('noon'))) as Map;
    expect(emitted['timeOfDay'], 'late_morning');
    expect(StoryClock.periods, contains(emitted['timeOfDay']));

    final lateNight =
        jsonDecode(await _pump(tester, _blobs('late night'))) as Map;
    expect(lateNight['timeOfDay'], 'night');
  });

  testWidgets("Edit group's Afterglow switch sets how the group's new chats "
      'start it', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final storage = FakeStorageService();
    addTearDown(storage.dispose);

    final blobs = buildGroupRealismBlobs(
      seeds: {'m1': defaultGroupMemberRealismSeed()},
      needsEnabled: true,
      afterglowEnabled: false,
      timeOfDay: 'morning',
      dayCount: 1,
    );
    var emitted = blobs.defaultMemberJson;
    Future<void> pumpEditor() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: MaterialApp(
            home: Scaffold(
              body: GroupRealismDynamicsEditor(
                members: const [],
                initialDefaultMemberJson: blobs.defaultMemberJson,
                initialBaselineJson: blobs.baselineJson,
                onChanged: (d, b) => emitted = d,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpEditor();
    expect(
      find.text('Afterglow'),
      findsNothing,
      reason: 'Porch Life Afterglow off: absent, not greyed',
    );

    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    await pumpEditor();
    final tile = find.widgetWithText(SwitchListTile, 'Afterglow');
    expect(
      tester.widget<SwitchListTile>(tile).value,
      isFalse,
      reason: 'read from the group',
    );
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(groupAfterglowIn(emitted), isTrue);
    expect((jsonDecode(emitted) as Map)['timeOfDay'], 'morning');

    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(groupAfterglowIn(emitted), isFalse);
  });

  // Turning Edit group's Realism on gave every member with no seed the
  // neutral 35 / 40. A member now starts from their own row's card, as a
  // new group's members do; a member with a saved seed keeps it.
  testWidgets("Edit group's Realism switch starts a member with no seed from "
      'their card', (tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final storage = FakeStorageService();
    addTearDown(storage.dispose);
    var emitted = '';
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GroupRealismDynamicsEditor(
                members: [
                  GroupRealismMember(
                    mid: 'mem-n',
                    name: 'Nia',
                    extensions: FrontPorchExtensions(
                      shortTermBond: 90,
                      longTermBond: 150,
                      trustLevel: -30,
                      characterEmotion: 'wary',
                      needsBaselineHunger: 35,
                    ),
                  ),
                ],
                initialDefaultMemberJson: '{}',
                initialBaselineJson: '{}',
                onChanged: (d, b) => emitted = d,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Realism & Needs Engine'),
    );
    await tester.pumpAndSettle();
    final nia = parseGroupRealismSeeds(emitted)['mem-n']!;
    expect(
      [nia['affection'], nia['longTermScore'], nia['trust'], nia['emotion']],
      [90, 150, -30, 'wary'],
      reason: 'THE BUG: the member came on at the neutral 35 / 40',
    );
    expect(nia['needs'], containsPair('hunger', 35));
  });

  // Each member was a cut-down copy of the member editor here (bonds, needs,
  // a verifier the chat never read). Now it is a summary, and Edit opens the
  // member's own editor.
  testWidgets("Edit group's Realism tab shows each member as a summary whose "
      'Edit opens their editor', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final storage = FakeStorageService();
    addTearDown(storage.dispose);
    await storage.realismSettings.setAdultThemesEnabled(true);
    await storage.realismSettings.setNsfwCooldownDefault(true);
    final blobs = buildGroupRealismBlobs(
      seeds: {
        'mem-n': {
          ...defaultGroupMemberRealismSeed(),
          'longTermScore': 25,
          'trust': 30,
        },
      },
      needsEnabled: true,
      timeOfDay: 'morning',
      dayCount: 1,
    );
    final opened = <String>[];
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(
            body: GroupRealismDynamicsEditor(
              members: [
                GroupRealismMember(
                  mid: 'mem-n',
                  name: 'Nia',
                  extensions: FrontPorchExtensions(afterglowEnabled: false),
                ),
              ],
              initialDefaultMemberJson: blobs.defaultMemberJson,
              initialBaselineJson: blobs.baselineJson,
              onChanged: (_, _) {},
              onEditMember: opened.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const ValueKey('member-summary-mem-n'));
    expect(
      find.descendant(
        of: row,
        matching: find.text(' · Close / Trusting · Afterglow off'),
      ),
      findsOneWidget,
    );
    expect(find.text('Short-Term Bond'), findsNothing);
    await tester.tap(find.descendant(of: row, matching: find.text('Edit')));
    await tester.pumpAndSettle();
    expect(opened, ['mem-n']);
  });

  testWidgets("Edit group's Needs switch for new chats is the group's own", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final blobs = _blobs('morning');
    var emitted = blobs.defaultMemberJson;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupRealismDynamicsEditor(
            members: const [GroupRealismMember(mid: 'm1', name: 'Ada')],
            initialDefaultMemberJson: blobs.defaultMemberJson,
            initialBaselineJson: blobs.baselineJson,
            onChanged: (d, _) => emitted = d,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.widgetWithText(SwitchListTile, 'Needs');
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(groupTemplateRealismOf(emitted).needsOn, isFalse);
    expect(
      groupTemplateRealismOf(emitted).realismOn,
      isTrue,
      reason: 'the members keep their seeds',
    );
  });

  testWidgets("Edit group's Needs switch greys at the group's own choice while "
      "Porch Life's Needs is off", (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final storage = FakeStorageService();
    addTearDown(storage.dispose);
    await storage.realismSettings.setNeedsSimDefault(false);
    final blobs = _blobs('morning');
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(
            body: GroupRealismDynamicsEditor(
              members: const [GroupRealismMember(mid: 'm1', name: 'Ada')],
              initialDefaultMemberJson: blobs.defaultMemberJson,
              initialBaselineJson: blobs.baselineJson,
              onChanged: (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Needs'),
    );
    expect(tile.value, isTrue, reason: "the group's own choice");
    expect(tile.onChanged, isNull);
    expect(
      find.text(
        'Off in Porch Life, so no chat runs Needs. This group\'s choice for '
        'new chats is kept.',
      ),
      findsOneWidget,
    );
  });
}
