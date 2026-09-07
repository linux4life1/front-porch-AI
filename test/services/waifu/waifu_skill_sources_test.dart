// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

void main() {
  test('allowlist is Anthropic, Vercel, Superpowers', () {
    expect(kWaifuSkillSources.map((s) => s.id), [
      'anthropic',
      'vercel',
      'superpowers',
    ]);
  });

  test('install can come from the Vercel catalog', () async {
    final root = await Directory.systemTemp.createTemp('waifu_src_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    Future<http.Response> get(Uri uri) async {
      final u = uri.toString();
      if (u.contains('anthropics/skills')) {
        return http.Response('[]', 200);
      }
      if (u.contains('obra/superpowers')) {
        return http.Response('[]', 200);
      }
      if (u.endsWith('/contents/skills')) {
        return http.Response(
          jsonEncode([
            {
              'type': 'dir',
              'name': 'react-best-practices',
              'path': 'skills/react-best-practices',
            },
            {'type': 'dir', 'name': 'scripts', 'path': 'skills/scripts'},
          ]),
          200,
        );
      }
      if (u.endsWith('/react-best-practices')) {
        return http.Response(
          jsonEncode([
            {
              'type': 'file',
              'name': 'SKILL.md',
              'download_url': 'https://example.invalid/rbp/SKILL.md',
            },
          ]),
          200,
        );
      }
      if (u.endsWith('SKILL.md')) {
        return http.Response(
          '---\nname: react-best-practices\ndescription: React\n---\n# R\n',
          200,
        );
      }
      return http.Response('no', 404);
    }

    final hub = WaifuSkillHub(
      projectRoot: root.path,
      market: WaifuSkillMarket(get: get),
    );
    await hub.refreshMarket();
    expect(hub.market.catalog.map((s) => s.name), ['react-best-practices']);
    expect(hub.market.catalog.single.sourceId, 'vercel');
    final out = await hub.install('react-best-practices');
    expect(out, startsWith('installed'));
    expect(
      await File(
        p.join(
          root.path,
          '.waifu',
          'skills',
          'react-best-practices',
          'SKILL.md',
        ),
      ).exists(),
      isTrue,
    );
  });
}
