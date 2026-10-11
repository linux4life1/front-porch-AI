// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

/// A relaunch must reach the same OpenCode session, or the model forgets
/// the whole conversation the transcript still shows.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('waifu_resume_oc_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('the OpenCode session id survives save and load', () async {
    final folder = p.join(dir.path, 'porch');
    final store = WaifuStore(p.join(dir.path, 'store'));
    await store.saveLast(
      WaifuSession(
        folderRoot: folder,
        coworker: CharacterCard(name: 'Mira'),
      )..openCodeSessionId = 'ses_keep',
    );
    final back = await store.loadSession(folder);
    expect(back!.openCodeSessionId, 'ses_keep');

    await store.saveLast(
      WaifuSession(
        folderRoot: folder,
        coworker: CharacterCard(name: 'Mira'),
      ),
    );
    expect((await store.loadSession(folder))!.openCodeSessionId, isNull);
  });

  test(
    'getSession returns a known session and null for an unknown one',
    () async {
      final client = OpenCodeClient(
        baseUri: Uri.parse('http://127.0.0.1:4096'),
        directory: dir.path,
        clientFactory: () => MockClient((req) async {
          if (req.url.path == '/session/ses_keep') {
            return http.Response(
              jsonEncode({'id': 'ses_keep', 'title': 'Mira'}),
              200,
            );
          }
          return http.Response('{"name":"NotFoundError"}', 404);
        }),
      );
      final known = await client.getSession('ses_keep');
      expect(known?.id, 'ses_keep');
      expect(await client.getSession('ses_gone'), isNull);
    },
  );
}
