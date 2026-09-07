// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu_home_view.dart';
import 'package:front_porch_ai/ui/waifu/waifu_project_card.dart';
import 'package:front_porch_ai/ui/waifu/waifu_wizard_page.dart';

void main() {
  List<WaifuProject> three() => [
    WaifuProject(
      folderRoot: '/tmp/folder3',
      title: 'latest',
      coworker: CharacterCard(name: 'Mira'),
      touchedMs: 3,
    ),
    WaifuProject(
      folderRoot: '/tmp/folder2',
      title: 'mid',
      coworker: CharacterCard(name: 'Nina'),
      touchedMs: 2,
    ),
    WaifuProject(
      folderRoot: '/tmp/folder1',
      title: 'oldest',
      coworker: CharacterCard(name: 'Ada'),
      touchedMs: 1,
    ),
  ];

  testWidgets('three used folders render three porch cards plus New porch', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WaifuHomeView(projects: three())),
      ),
    );
    await tester.pump();
    expect(find.text('folder1'), findsOneWidget);
    expect(find.text('folder2'), findsOneWidget);
    expect(find.text('folder3'), findsOneWidget);
    expect(find.byType(WaifuProjectCard), findsNWidgets(3));
    expect(find.byKey(const Key('waifu-sit-down')), findsOneWidget);
    expect(find.text('New porch'), findsOneWidget);
    expect(find.text('New'), findsNothing);
    expect(find.byKey(const Key('waifu-resume')), findsOneWidget);
  });

  testWidgets('New porch starts the folder-then-character flow', (
    tester,
  ) async {
    var started = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaifuHomeView(projects: three(), onSitDown: () => started++),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('waifu-sit-down')));
    await tester.pump();
    expect(started, 1);
  });

  testWidgets('delete session asks before forgetting', (tester) async {
    var forgotten = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 360,
            child: WaifuProjectCard(
              project: three().first,
              onResume: () {},
              onNewSession: () {},
              onForget: () => forgotten++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('waifu-project-menu-folder3')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete this session'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this session?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('waifu-delete-session-cancel')));
    await tester.pumpAndSettle();
    expect(forgotten, 0);
    await tester.tap(find.byKey(const Key('waifu-project-menu-folder3')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete this session'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('waifu-delete-session-confirm')));
    await tester.pumpAndSettle();
    expect(forgotten, 1);
  });

  testWidgets('New session asks to reuse the last coworker', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WaifuHomeView(projects: three())),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('waifu-project-menu-folder3')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New session'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mira'), findsWidgets);
    expect(find.byKey(const Key('waifu-new-session-same')), findsOneWidget);
    expect(find.byKey(const Key('waifu-new-session-pick')), findsOneWidget);
  });

  testWidgets('New porch without onSitDown opens the folder wizard', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WaifuHomeView(projects: three())),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('waifu-sit-down')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(WaifuWizardPage), findsOneWidget);
    expect(find.text('Project folder'), findsOneWidget);
  });

  testWidgets('skipProject wizard opens on coworker, not folder', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuWizardPage(
          skipProject: true,
          initialFolder: '/tmp/folder3',
          characters: [CharacterCard(name: 'Mira')],
          onSatDown: (_) {},
          listDirectory: (path) async => WaifuFolderListing(
            path: path,
            parentPath: null,
            directories: const [],
            projectHints: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mira'), findsOneWidget);
    expect(find.text('Use this folder'), findsNothing);
    expect(find.text('Coworker'), findsWidgets);
  });
}
