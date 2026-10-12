// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';
import 'package:path/path.dart' as p;

class _BrokenStore extends WaifuStore {
  _BrokenStore() : super(Directory.systemTemp.path);

  @override
  Future<void> saveLast(WaifuSession session) async =>
      throw const FileSystemException('disk full');
}

WaifuSession _session(String folder) => WaifuSession(
  folderRoot: folder,
  coworker: CharacterCard(name: 'Mira'),
);

void main() {
  late Directory storeDir;

  setUp(() async {
    storeDir = await Directory.systemTemp.createTemp('waifu_sit_save_');
  });

  tearDown(() async {
    if (await storeDir.exists()) await storeDir.delete(recursive: true);
  });

  testWidgets('sitting down parks the folder before any chat turn', (
    tester,
  ) async {
    final store = WaifuStore(storeDir.path);
    final session = WaifuSession(
      folderRoot: '/tmp/new-project',
      coworker: CharacterCard(name: 'Iris'),
    );
    late List<WaifuProject> list;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: WaifuPage(session: session, store: store),
        ),
      );
      // Saves are flushed and renamed into place; wait for the first one.
      list = await store.listProjects();
      for (var i = 0; i < 100 && list.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        list = await store.listProjects();
      }
    });
    await tester.pump();
    expect(list, hasLength(1));
    expect(list.single.folderName, 'new-project');
    expect(list.single.coworker.name, 'Iris');
  });

  group('every session change goes through the controller', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('waifu_controller_');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('each setting change is saved', () async {
      final store = WaifuStore(p.join(root.path, 'waifu'));
      final folder = p.join(root.path, 'toy');
      final c = WaifuSessionController(
        session: _session(folder),
        store: store,
        releaseTools: () async {},
      );
      addTearDown(c.dispose);
      await c.setMode(WaifuMode.plan);
      await c.setPreserveThinking(true);
      await c.setToolsOptIn(true);
      await c.setThemeOverrides(ChatThemeOverrides(fontFamily: 'Lora'));
      final back = (await store.loadSession(folder))!;
      expect(back.mode, WaifuMode.plan);
      expect(back.preserveThinking, isTrue);
      expect(back.mcpOptIn, isTrue);
      expect(back.themeOverrides.fontFamily, 'Lora');
    });

    test('with no model, send keeps the words and says so', () async {
      final c = WaifuSessionController(
        session: _session('/tmp/waifu-none'),
        releaseTools: () async {},
      );
      addTearDown(c.dispose);
      var taken = false;
      final sent = await c.send('fix it', onAccepted: () => taken = true);
      expect(sent, isFalse);
      expect(taken, isFalse, reason: 'the box keeps the words');
      expect(c.session.transcript.single.kind, WaifuMsgKind.stage);
    });

    test('queue, receipt and photo changes go through the controller', () {
      final c = WaifuSessionController(
        session: _session('/tmp/waifu-q'),
        releaseTools: () async {},
      );
      addTearDown(c.dispose);
      var repaints = 0;
      c.addListener(() => repaints++);
      c.session.queued.addAll(const [
        WaifuQueuedFollowUp(text: 'one'),
        WaifuQueuedFollowUp(text: 'two'),
      ]);
      c.removeQueued(0);
      expect(c.session.queued.single.text, 'two');

      c.session.turnWrites.add(
        const WaifuWriteRecord(relativePath: 'a.dart', before: '', after: 'x'),
      );
      c.dismissReceipt();
      expect(c.session.turnWrites, isEmpty);

      final first = Uint8List.fromList([1]);
      final second = Uint8List.fromList([2]);
      c.holdImage(first);
      c.holdImage(second);
      c.setVision(first, ok: false, blindReason: 'stale');
      expect(c.blindReason, isNull, reason: 'a late check for an old photo');
      c.setVision(second, ok: true);
      expect(c.visionOk, isTrue);
      expect(repaints, 5);
    });

    testWidgets('a failed save shows a snackbar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WaifuPage(
            session: _session('/tmp/waifu-broken'),
            store: _BrokenStore(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('Could not save this session'),
        findsOneWidget,
      );
      expect(find.textContaining('disk full'), findsOneWidget);
    });

    testWidgets(
      'resuming a damaged session reports it instead of opening blank',
      (tester) async {
        final store = WaifuStore(p.join(root.path, 'waifu'));
        final toy = p.join(root.path, 'toy');
        await tester.runAsync(() async {
          await Directory(
            p.join(store.directory, 'sessions'),
          ).create(recursive: true);
          await File(
            p.join(
              store.directory,
              'sessions',
              '${waifuSessionSlug(toy)}.json',
            ),
          ).writeAsString('{"folderRoot": "$toy", "transcript": [');
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WaifuHomeView(
                store: store,
                projects: [
                  WaifuProject(
                    folderRoot: toy,
                    title: '',
                    coworker: CharacterCard(name: 'Mira'),
                    touchedMs: 1,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => tester.tap(find.byKey(const Key('waifu-resume'))),
        );
        for (
          var i = 0;
          i < 50 && find.byType(SnackBar).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(find.textContaining('could not be read'), findsOneWidget);
        expect(find.byType(WaifuPage), findsNothing);
      },
    );
  });
}
