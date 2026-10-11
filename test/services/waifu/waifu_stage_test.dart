// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

/// What happens to a turn is narrated around the coworker, never put in
/// their mouth as a reply bubble.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_stage_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  WaifuHarness harnessFor(WaifuSession session) => WaifuHarness(
    session: session,
    sessionId: 'ses_1',
    client: OpenCodeClient(
      baseUri: Uri.parse('http://127.0.0.1:4096'),
      directory: root.path,
      clientFactory: () => MockClient(
        (req) async => http.Response(req.method == 'GET' ? '[]' : 'true', 200),
      ),
    ),
  );

  WaifuSession sessionFor(String name) => WaifuSession(
    folderRoot: root.path,
    coworker: CharacterCard(name: name),
  );

  test('Stop, undo and redo are stage rows that use her name', () async {
    final session = sessionFor('Mira');
    final harness = harnessFor(session);

    await harness.undo();
    expect(session.transcript.last.kind, WaifuMsgKind.stage);
    expect(session.transcript.last.text, startsWith('Mira '));
    expect(session.transcript.last.detail, kWaifuUndoNeedsTurn);

    harness.onTextDelta('Hmph.', messageId: 'msg_a');
    await harness.undo();
    expect(session.transcript.last.kind, WaifuMsgKind.stage);
    expect(session.transcript.last.text, contains('Mira'));
    await harness.redo();
    expect(session.transcript.last.kind, WaifuMsgKind.stage);

    session.running = true;
    harness.abort();
    expect(session.transcript.last.kind, WaifuMsgKind.stage);
    expect(session.transcript.last.text, startsWith('Mira '));
    expect(
      session.transcript.where((m) => m.kind == WaifuMsgKind.assistant),
      hasLength(1),
      reason: 'only the line she actually said is a bubble',
    );
  });

  test('an OpenCode error keeps the plain text as the detail', () {
    final session = sessionFor('Mira');
    harnessFor(session).onError('ProviderAuthError: bad key');
    final last = session.transcript.last;
    expect(last.kind, WaifuMsgKind.stage);
    expect(last.text, 'Mira hit a snag.');
    expect(last.detail, 'ProviderAuthError: bad key');
  });

  test('an unnamed card still reads as a sentence', () {
    final line = WaifuStage.of(sessionFor('  ')).stopped().text;
    expect(line, startsWith('Your coworker '));
  });

  test('stage rows and their detail survive save and load', () async {
    final store = WaifuStore(p.join(root.path, 'store'));
    final folder = p.join(root.path, 'porch');
    final session = WaifuSession(
      folderRoot: folder,
      coworker: CharacterCard(name: 'Mira'),
      transcript: [
        const WaifuMessage.user('go'),
        WaifuStage.of(sessionFor('Mira')).snag('boom'),
      ],
    );
    await store.saveLast(session);
    final back = (await store.loadSession(folder))!.transcript.last;
    expect(back.kind, WaifuMsgKind.stage);
    expect(back.text, 'Mira hit a snag.');
    expect(back.detail, 'boom');
  });
}
