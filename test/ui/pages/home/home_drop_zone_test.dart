// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/home/home_drop_zone.dart';

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
}
