// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/home/home_drop_zone.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

void main() {
  testWidgets('HomeDropHighlight uses the library drop copy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: HomeDropHighlight())),
    );
    expect(find.text(kHomeDropOverlayLabel), findsOneWidget);
  });

  testWidgets('HomeDropZone wraps the library in a DropTarget', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeDropZone(onDrop: (_) async {}, child: const Text('library')),
      ),
    );
    expect(find.text('library'), findsOneWidget);
    expect(find.byType(DropTarget), findsOneWidget);
    expect(find.byType(HomeDropHighlight), findsNothing);
  });

  testWidgets('HomeDropZone routes a drop through onDrop', (tester) async {
    List<HomeDropSource>? received;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeDropZone(
          onDrop: (sources) async => received = sources,
          child: const Text('library'),
        ),
      ),
    );

    final state = tester.state<HomeDropZoneState>(find.byType(HomeDropZone));
    await state.debugDrop([
      const HomeDropSource(label: 'Ada.png', path: '/tmp/Ada.png'),
      const HomeDropSource(label: 'notes.txt', path: '/tmp/notes.txt'),
    ]);
    await tester.pump();

    expect(received, isNotNull);
    expect(received!.map((s) => s.path), ['/tmp/Ada.png', '/tmp/notes.txt']);
  });

  testWidgets('the drop label sits on a solid card it reads on, in every '
      'theme', (tester) async {
    for (final theme in AppThemeId.values) {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(
              palettes: theme.palettes,
              brightness: brightness,
            ),
            home: const Scaffold(body: HomeDropHighlight()),
          ),
        );
        final why = '${theme.key} ${brightness.name}';
        final card = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('home-drop-label')),
        );
        final fill = (card.decoration as BoxDecoration).color!;
        expect(fill.a, greaterThanOrEqualTo(0.9), reason: why);
        final ink = tester
            .widget<Text>(find.text(kHomeDropOverlayLabel))
            .style!
            .color!;
        expect(
          contrastRatio(ink, fill.withValues(alpha: 1)),
          greaterThanOrEqualTo(4.5),
          reason: why,
        );
      }
    }
  });
}
