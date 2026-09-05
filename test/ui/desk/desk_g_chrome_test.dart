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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/ui/desk/desk_home_view.dart';
import 'package:front_porch_ai/ui/desk/desk_page.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory storeDir;

  setUp(() async {
    storeDir = await Directory.systemTemp.createTemp('desk_g_chrome_');
  });

  tearDown(() async {
    if (await storeDir.exists()) await storeDir.delete(recursive: true);
  });

  DeskSession _miraSession({String title = 'fix emails'}) => DeskSession(
    folderRoot: '/tmp/throwaway-desk',
    coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
    title: title,
  );
  testWidgets('Desk home Resume appears when a last session is provided', (
    tester,
  ) async {
    var resumed = false;
    final last = DeskSession(
      folderRoot: '/tmp/throwaway-desk',
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
      title: 'fix emails',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeskHomeView(lastSession: last, onResume: () => resumed = true),
        ),
      ),
    );
    expect(find.byKey(const Key('desk-resume')), findsOneWidget);
    expect(find.textContaining('fix emails'), findsOneWidget);
    await tester.tap(find.byKey(const Key('desk-resume')));
    await tester.pump();
    expect(resumed, isTrue);
  });

  testWidgets('session chrome shows the title', (tester) async {
    final session = DeskSession(
      folderRoot: '/tmp/throwaway-desk',
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
      title: 'fix emails',
    );
    await tester.pumpWidget(MaterialApp(home: DeskPage(session: session)));
    expect(find.text('fix emails'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('Resume loads last_desk.json when lastSession is not passed', (
    tester,
  ) async {
    final store = DeskStore(storeDir.path);
    await tester.runAsync(() async {
      await store.saveLast(_miraSession());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DeskHomeView(store: store)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byKey(const Key('desk-resume')), findsOneWidget);
    expect(find.textContaining('fix emails'), findsOneWidget);
  });

  testWidgets('Resume appears after popping back onto a saved last desk', (
    tester,
  ) async {
    final store = DeskStore(storeDir.path);
    final navKey = GlobalKey<NavigatorState>();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: DeskHomeView(store: store),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byKey(const Key('desk-resume')), findsNothing);

    await tester.runAsync(() async {
      await store.saveLast(_miraSession());
      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('away')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      navKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byKey(const Key('desk-resume')), findsOneWidget);
  });

  testWidgets('DeskPage created harness saves last_desk.json', (tester) async {
    late Directory root;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('desk_g_page_');
    });
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final store = DeskStore(storeDir.path);
    final session = DeskSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
    );
    final llm = ScriptedDeskLlm([
      const LlmToolResponse(calls: [], text: 'Hmph. Fine.'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: DeskPage(session: session, llm: llm, store: store),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('desk-composer')),
      'add a hello.txt please',
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('desk-send')));
      await tester.pump();
      for (var i = 0; i < 80; i++) {
        if (!session.running && session.transcript.length >= 2) break;
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
    });
    await tester.pump();
    late DeskSession? loaded;
    await tester.runAsync(() async {
      loaded = await store.loadLast();
    });
    expect(loaded, isNotNull);
    expect(loaded!.title, contains('hello'));
    expect(loaded!.coworker.name, 'Mira');
    expect(File(p.join(storeDir.path, kDeskLastFile)).existsSync(), isTrue);
  });
}
