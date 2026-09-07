// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';
import 'package:http/http.dart' as http;

WaifuHttpGet _fakeGet() {
  return (uri) async {
    final u = uri.toString();
    if (u == kWaifuAnthropicSkillsApi) {
      return http.Response(
        jsonEncode([
          {'type': 'dir', 'name': 'pdf', 'path': 'skills/pdf'},
        ]),
        200,
      );
    }
    if (u.endsWith('/pdf')) {
      return http.Response(
        jsonEncode([
          {
            'type': 'file',
            'name': 'SKILL.md',
            'download_url': 'https://example.invalid/pdf/SKILL.md',
          },
        ]),
        200,
      );
    }
    if (u.endsWith('SKILL.md')) {
      return http.Response(
        '---\nname: pdf\ndescription: PDF forms\n---\n# PDF\n',
        200,
      );
    }
    return http.Response('no', 404);
  };
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_skills_ui_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('sidebar shows skills marketplace; / lists code-review', (
    tester,
  ) async {
    final hub = WaifuSkillHub(
      projectRoot: root.path,
      market: WaifuSkillMarket(get: _fakeGet()),
    );
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuPage(session: session, skills: hub),
      ),
    );
    await tester.pump();
    expect(find.text('Skills'), findsOneWidget);
    await tester.tap(find.text('Skills'));
    await tester.pump();
    expect(find.byKey(const Key('waifu-skills-panel')), findsOneWidget);
    expect(find.byKey(const Key('waifu-skills-refresh')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('waifu-composer')), '/');
    await tester.pump();
    expect(find.byKey(const Key('waifu-slash-skills')), findsOneWidget);
    expect(find.byKey(const Key('waifu-slash-review')), findsOneWidget);
    expect(find.textContaining('Code review this folder'), findsWidgets);

    await tester.enterText(find.byKey(const Key('waifu-composer')), '/code');
    await tester.pump();
    expect(find.byKey(const Key('waifu-slash-code-review')), findsOneWidget);
  });

  testWidgets('Refresh loads catalog; Install writes SKILL.md', (tester) async {
    final hub = WaifuSkillHub(
      projectRoot: root.path,
      market: WaifuSkillMarket(get: _fakeGet()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: WaifuSkillsPanel(hub: hub)),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('waifu-skills-refresh')));
    });
    for (
      var i = 0;
      i < 40 &&
          find.byKey(const Key('waifu-skill-install-pdf')).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.byKey(const Key('waifu-skill-install-pdf')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('waifu-skill-install-pdf')));
    });
    for (var i = 0; i < 40 && !hub.installedNames.contains('pdf'); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(hub.installedNames, contains('pdf'));
    expect(find.byKey(const Key('waifu-skill-installed-pdf')), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.textContaining('never auto-approves'), findsNothing);
  });

  testWidgets('/skills lists the marketplace in chat', (tester) async {
    final hub = WaifuSkillHub(
      projectRoot: root.path,
      market: WaifuSkillMarket(get: _fakeGet()),
    );
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WaifuPage(session: session, skills: hub),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byKey(const Key('waifu-composer')), '/skills');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('waifu-slash-skills')));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    expect(session.transcript, isNotEmpty);
    expect(session.transcript.last.text, contains('anthropics/skills'));
    expect(session.transcript.last.text, contains('pdf'));
  });
}
