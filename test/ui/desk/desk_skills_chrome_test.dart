// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/ui/desk/desk.dart';
import 'package:http/http.dart' as http;

DeskHttpGet _fakeGet() {
  return (uri) async {
    final u = uri.toString();
    if (u == kDeskAnthropicSkillsApi) {
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
    root = await Directory.systemTemp.createTemp('desk_skills_ui_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('sidebar shows skills marketplace; / lists code-review', (
    tester,
  ) async {
    final hub = DeskSkillHub(
      projectRoot: root.path,
      market: DeskSkillMarket(get: _fakeGet()),
    );
    final session = DeskSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DeskPage(session: session, skills: hub),
      ),
    );
    await tester.pump();
    expect(find.text('Skills'), findsOneWidget);
    await tester.tap(find.text('Skills'));
    await tester.pump();
    expect(find.byKey(const Key('desk-skills-panel')), findsOneWidget);
    expect(find.byKey(const Key('desk-skills-refresh')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('desk-composer')), '/');
    await tester.pump();
    expect(find.byKey(const Key('desk-slash-skills')), findsOneWidget);
    expect(find.byKey(const Key('desk-slash-review')), findsOneWidget);
    expect(find.textContaining('Code review this folder'), findsWidgets);

    await tester.enterText(find.byKey(const Key('desk-composer')), '/code');
    await tester.pump();
    expect(find.byKey(const Key('desk-slash-code-review')), findsOneWidget);
  });

  testWidgets('Refresh loads catalog; Install writes SKILL.md', (tester) async {
    final hub = DeskSkillHub(
      projectRoot: root.path,
      market: DeskSkillMarket(get: _fakeGet()),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: DeskSkillsPanel(hub: hub)),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('desk-skills-refresh')));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    expect(find.byKey(const Key('desk-skill-install-pdf')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('desk-skill-install-pdf')));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    expect(hub.installedNames, contains('pdf'));
    expect(find.byKey(const Key('desk-skill-installed-pdf')), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.textContaining('never auto-approves'), findsNothing);
  });

  testWidgets('/skills lists the marketplace in chat', (tester) async {
    final hub = DeskSkillHub(
      projectRoot: root.path,
      market: DeskSkillMarket(get: _fakeGet()),
    );
    final session = DeskSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DeskPage(session: session, skills: hub),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byKey(const Key('desk-composer')), '/skills');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('desk-slash-skills')));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
    expect(session.transcript, isNotEmpty);
    expect(session.transcript.last.text, contains('anthropics/skills'));
    expect(session.transcript.last.text, contains('pdf'));
  });
}
