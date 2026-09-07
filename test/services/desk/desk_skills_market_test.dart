// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

DeskHttpGet _fakeGet({
  List<String> names = const ['pdf', 'docx'],
  String body = '---\nname: pdf\ndescription: PDF forms\n---\n# PDF\n',
}) {
  return (uri) async {
    final u = uri.toString();
    if (u == kDeskAnthropicSkillsApi) {
      return http.Response(
        jsonEncode([
          for (final n in names)
            {'type': 'dir', 'name': n, 'path': 'skills/$n'},
          {'type': 'file', 'name': 'README.md', 'path': 'skills/README.md'},
        ]),
        200,
      );
    }
    for (final n in names) {
      if (u == '$kDeskAnthropicSkillsApi/$n') {
        return http.Response(
          jsonEncode([
            {
              'type': 'file',
              'name': 'SKILL.md',
              'download_url': 'https://example.invalid/$n/SKILL.md',
            },
          ]),
          200,
        );
      }
    }
    if (u.endsWith('SKILL.md')) return http.Response(body, 200);
    return http.Response('no', 404);
  };
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desk_skills_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('marketplace lists official dirs and installs SKILL.md', () async {
    final hub = DeskSkillHub(
      projectRoot: root.path,
      market: DeskSkillMarket(get: _fakeGet()),
    );
    await hub.refreshMarket();
    expect(hub.market.catalog.map((s) => s.name), ['docx', 'pdf']);
    final out = await hub.install('pdf');
    expect(out, startsWith('installed pdf'));
    expect(
      await File(
        p.join(root.path, '.waifu', 'skills', 'pdf', 'SKILL.md'),
      ).exists(),
      isTrue,
    );
    expect(hub.catalogPrompt, contains('pdf'));
    expect(hub.listing(), contains('pdf (installed)'));
  });

  test(
    'harness skill_install writes the skill and the next prompt sees it',
    () async {
      final hub = DeskSkillHub(
        projectRoot: root.path,
        market: DeskSkillMarket(get: _fakeGet()),
      );
      final llm = ScriptedDeskLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'skill_install', arguments: {'name': 'pdf'}),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'Installed pdf.'),
      ]);
      final session = DeskSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
        mode: DeskMode.yolo,
      );
      final harness = DeskHarness(session: session, llm: llm, skills: hub);
      await harness.send('install the pdf skill');
      expect(
        await File(
          p.join(root.path, '.waifu', 'skills', 'pdf', 'SKILL.md'),
        ).exists(),
        isTrue,
      );
      expect(llm.calls, hasLength(2));
      expect(llm.calls.last.prompt, contains('pdf'));
      expect(llm.calls.last.prompt, contains('PDF forms'));
      expect(session.toolChips.single.name, 'skill_install');
    },
  );
}
