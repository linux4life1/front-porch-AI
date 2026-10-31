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

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/group_member_realism_editor.dart';
import 'package:front_porch_ai/ui/widgets/group_realism_dynamics_editor.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';
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

  // Edit group's member editor showed and saved Long-Term Bond through the
  // seed's trust. A seed it already wrote that way reads back as Long-Term
  // Bond, and the next move un-mixes it.
  testWidgets('the member editor keeps Long-Term Bond out of trust', (
    tester,
  ) async {
    final storage = FakeStorageService();
    addTearDown(storage.dispose);
    final deltas = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GroupMemberRealismEditor(
                seed: const {'affection': 35, 'trust': 250},
                needsEnabled: false,
                onNeedsEnabledChanged: (_) {},
                onUpdate: deltas.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final form = tester.widget<RealismFormSection>(
      find.byType(RealismFormSection),
    );
    expect((form.longTermBond, form.trustLevel), (250, 50));

    form.onLongTermBondChanged(100);
    expect(deltas.single, {'affection': 35, 'longTermScore': 100, 'trust': 50});
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
}
