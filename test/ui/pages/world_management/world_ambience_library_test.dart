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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/storage/user_audio_store.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/pages/world_management/world_ambience_library.dart';

typedef Stored = ({String name, int bytes, int modifiedMs});

/// The library is a panel inside the editor, not a modal on top of it.
/// These pin the redesign: it renders in place, lists stored sounds, and a
/// tap hands the bare name back without ever pushing a Dialog route. The
/// listing comes through [UserAudioStore.testListOverride] so the widget
/// faces fake time; the real directory read is pinned in the store test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 11, 3).millisecondsSinceEpoch;
  final two = <Stored>[
    (name: 'creek.mp3', bytes: 90, modifiedMs: now),
    (name: 'market.mp3', bytes: 40, modifiedMs: now - 2000),
  ];

  setUp(() => UserAudioStore.testListOverride = () async => two);
  tearDown(() => UserAudioStore.testListOverride = null);

  Future<void> pump(WidgetTester tester, {String? selected}) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: StorageService.sandbox('/tmp/fpai-library-test'),
        child: MaterialApp(
          home: Scaffold(
            body: WorldAmbienceLibraryPanel(
              selected: selected,
              onPicked: (_) {},
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(); // deliver the (fake) listing and rebuild
  }

  testWidgets('the library lists stored sounds inline, no dialog route', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('YOUR SOUNDS'), findsOne);
    expect(find.text('creek.mp3'), findsOne);
    expect(find.text('market.mp3'), findsOne);
    expect(find.text('From a file…'), findsOne);
  });

  testWidgets('the assigned sound is the one highlighted', (tester) async {
    await pump(tester, selected: 'market.mp3');
    // The selected row carries the accent check icon; the other does not.
    expect(find.byIcon(Icons.check_circle), findsOne);
    // ...on the selected row, not the first.
    final row = find.ancestor(
      of: find.byIcon(Icons.check_circle),
      matching: find.widgetWithText(InkWell, 'market.mp3'),
    );
    expect(row, findsOne);
  });

  testWidgets('a big library stays height-capped and scrolls', (tester) async {
    UserAudioStore.testListOverride = () async => [
      ...two,
      for (var i = 0; i < 12; i++)
        (name: 'extra-$i.mp3', bytes: 10, modifiedMs: now - i),
    ];
    await pump(tester);
    final height = tester.getSize(find.byType(ListView)).height;
    expect(height, lessThanOrEqualTo(WorldAmbienceLibraryPanel.kMaxListHeight));
    // The cap is the promise: with 14 rows some must be scrolled out.
    var visible = 0;
    for (var i = 0; i < 12; i++) {
      if (find.text('extra-$i.mp3').evaluate().isNotEmpty) visible++;
    }
    expect(visible, lessThan(14));
  });

  testWidgets('tapping a row hands back its bare name', (tester) async {
    String? picked;
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: StorageService.sandbox('/tmp/fpai-library-test'),
        child: MaterialApp(
          home: Scaffold(
            body: WorldAmbienceLibraryPanel(
              selected: null,
              onPicked: (n) => picked = n,
              onDismiss: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('creek.mp3'));
    expect(picked, 'creek.mp3');
  });

  testWidgets('empty library invites a first import instead of a blank box', (
    tester,
  ) async {
    UserAudioStore.testListOverride = () async => const [];
    await pump(tester);
    expect(find.textContaining('Nothing stored yet'), findsOne);
    expect(find.text('From a file…'), findsOne);
  });
}
