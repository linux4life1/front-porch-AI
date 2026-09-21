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

void main() {
  test('undo posts OpenCode revert for the last assistant message', () async {
    final root = await Directory.systemTemp.createTemp('waifu_oc_undo_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final hits = <http.Request>[];
    final client = OpenCodeClient(
      baseUri: Uri.parse('http://127.0.0.1:4096'),
      directory: root.path,
      clientFactory: () => MockClient((req) async {
        hits.add(req);
        return http.Response('true', 200);
      }),
    );
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira'),
    );
    final harness = WaifuHarness(
      session: session,
      client: client,
      sessionId: 'ses_1',
    );
    harness.onTextDelta('Hmph.', messageId: 'msg_a');
    expect(harness.canUndo, isTrue);
    expect(harness.canRedo, isFalse);
    await harness.undo();
    expect(hits, isNotEmpty);
    expect(hits.first.url.path, '/session/ses_1/revert');
    expect(jsonDecode(hits.first.body)['messageID'], 'msg_a');
    expect(harness.canRedo, isTrue);
    expect(harness.canUndo, isFalse);
    await harness.redo();
    expect(hits.last.url.path, '/session/ses_1/unrevert');
    expect(harness.canRedo, isFalse);
  });
}
