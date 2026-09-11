// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

WaifuHttpGet _fakeGet({
  List<String> names = const ['pdf', 'docx'],
  String body = '---\nname: pdf\ndescription: PDF forms\n---\n# PDF\n',
}) {
  return (uri) async {
    final u = uri.toString();
    if (u == kWaifuAnthropicSkillsApi) {
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
      if (u == '$kWaifuAnthropicSkillsApi/$n') {
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
    root = await Directory.systemTemp.createTemp('waifu_skills_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('marketplace lists official dirs and installs SKILL.md', () async {
    final hub = WaifuSkillHub(
      projectRoot: root.path,
      market: WaifuSkillMarket(get: _fakeGet()),
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

}
