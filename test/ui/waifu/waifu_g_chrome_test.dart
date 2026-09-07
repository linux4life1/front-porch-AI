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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory storeDir;

  setUp(() async {
    storeDir = await Directory.systemTemp.createTemp('waifu_g_chrome_');
  });

  tearDown(() async {
    if (await storeDir.exists()) await storeDir.delete(recursive: true);
  });

  WaifuSession _miraSession({String title = 'fix emails'}) => WaifuSession(
    folderRoot: '/tmp/throwaway-waifu',
    coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
    title: title,
  );
  testWidgets(
    'Waifu Coder home Resume appears when a last session is provided',
    (tester) async {
      var resumed = false;
      final last = WaifuSession(
        folderRoot: '/tmp/throwaway-waifu',
        coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
        title: 'fix emails',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaifuHomeView(
              lastSession: last,
              onResume: () => resumed = true,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('waifu-resume')), findsOneWidget);
      expect(find.textContaining('fix emails'), findsOneWidget);
      await tester.tap(find.byKey(const Key('waifu-resume')));
      await tester.pump();
      expect(resumed, isTrue);
    },
  );

  testWidgets('session chrome shows the title', (tester) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
      title: 'fix emails',
    );
    await tester.pumpWidget(MaterialApp(home: WaifuPage(session: session)));
    expect(find.text('fix emails'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('Resume loads last_waifu.json when lastSession is not passed', (
    tester,
  ) async {
    final store = WaifuStore(storeDir.path);
    await tester.runAsync(() async {
      await store.saveLast(_miraSession());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WaifuHomeView(store: store)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    for (
      var i = 0;
      i < 40 && find.byKey(const Key('waifu-resume')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    expect(find.byKey(const Key('waifu-resume')), findsOneWidget);
    expect(find.textContaining('fix emails'), findsOneWidget);
  });

  testWidgets('Resume appears after popping back onto a saved last waifu', (
    tester,
  ) async {
    final store = WaifuStore(storeDir.path);
    final navKey = GlobalKey<NavigatorState>();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: WaifuHomeView(store: store),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byKey(const Key('waifu-resume')), findsNothing);

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
    for (
      var i = 0;
      i < 40 && find.byKey(const Key('waifu-resume')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    expect(find.byKey(const Key('waifu-resume')), findsOneWidget);
  });

  testWidgets('WaifuPage created harness saves last_waifu.json', (
    tester,
  ) async {
    late Directory root;
    await tester.runAsync(() async {
      root = await Directory.systemTemp.createTemp('waifu_g_page_');
    });
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final store = WaifuStore(storeDir.path);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
    );
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(calls: [], text: 'Hmph. Fine.'),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuPage(session: session, llm: llm, store: store),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('waifu-composer')),
      'add a hello.txt please',
    );
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('waifu-send')));
      await tester.pump();
      for (var i = 0; i < 80; i++) {
        if (!session.running && session.transcript.length >= 2) break;
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
    });
    await tester.pump();
    late WaifuSession? loaded;
    await tester.runAsync(() async {
      loaded = await store.loadLast();
    });
    expect(loaded, isNotNull);
    expect(loaded!.title, contains('hello'));
    expect(loaded!.coworker.name, 'Mira');
    expect(File(p.join(storeDir.path, kWaifuLastFile)).existsSync(), isTrue);
  });
}
