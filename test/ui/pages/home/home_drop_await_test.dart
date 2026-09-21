// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// HOLD: sandbox bookmarks and HomeDropZone._busy must stay up until the
// Future that *reads* dropped paths completes. Fire-and-forget
// `_runBulkProgressImport` returns while IO is still running.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/home/home_drop_zone.dart';

void main() {
  late String drop;
  late String importPart;
  late String ops;

  setUpAll(() {
    drop = File('lib/ui/pages/home/home_page_drop.dart').readAsStringSync();
    importPart = File(
      'lib/ui/pages/home/home_page_dialogs.import.dart',
    ).readAsStringSync();
    ops = File('lib/ui/pages/home/home_page_char_ops.dart').readAsStringSync();
  });

  test('mixed drop awaits the batch that reads both kinds', () {
    expect(drop, contains('await _importPngAndByafBatch('));
  });

  test('multi-PNG import awaits bulk progress IO', () {
    expect(importPart, contains('await _runBulkImport('));
    expect(ops, contains('Future<void> _runBulkImport('));
    expect(ops, contains('return _runBulkProgressImport('));
  });

  test('multi-BYAF import awaits bulk progress IO after confirm', () {
    expect(importPart, contains('await _runBulkProgressImport('));
    expect(ops, contains('Future<void> _runBulkProgressImport('));
    expect(ops, contains('Future<void> _importPngAndByafBatch('));
  });

  test('bulk progress Future completes when runImport finishes', () {
    expect(ops, contains('Completer<void>'));
    expect(ops, contains('whenComplete'));
  });

  testWidgets('HomeDropZone keeps _busy until onDrop Future finishes', (
    tester,
  ) async {
    var calls = 0;
    final gate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeDropZone(
          onDrop: (_) async {
            calls++;
            await gate.future;
          },
          child: const Text('library'),
        ),
      ),
    );

    final state = tester.state<HomeDropZoneState>(find.byType(HomeDropZone));
    const first = HomeDropSource(label: 'a.png', path: '/tmp/a.png');
    const second = HomeDropSource(label: 'b.png', path: '/tmp/b.png');
    final pending = state.debugDrop([first]);
    await tester.pump();
    expect(calls, 1);

    await state.debugDrop([second]);
    expect(calls, 1, reason: 'second drop must wait until the first IO ends');

    gate.complete();
    await pending;
    await state.debugDrop([second]);
    expect(calls, 2);
  });
}
