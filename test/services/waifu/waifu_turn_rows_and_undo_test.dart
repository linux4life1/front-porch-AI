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

/// One tool call is one row, and Undo reverts the coding work of the turn,
/// not only the voice wrap-up that came after it.
void main() {
  late Directory root;
  late List<http.Request> hits;
  late WaifuSession session;
  late WaifuHarness harness;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_turn_rows_');
    hits = [];
    session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira'),
    );
    harness = WaifuHarness(
      session: session,
      sessionId: 'ses_1',
      client: OpenCodeClient(
        baseUri: Uri.parse('http://127.0.0.1:4096'),
        directory: root.path,
        clientFactory: () => MockClient((req) async {
          hits.add(req);
          return http.Response('true', 200);
        }),
      ),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  void tool(String status, {String messageId = 'msg_code'}) {
    dispatchOpenCodeEvent(
      openCodeEventFromJson({
        'type': 'message.part.updated',
        'properties': {
          'sessionID': 'ses_1',
          'part': {
            'type': 'tool',
            'tool': 'bash',
            'callID': 'call_1',
            'messageID': messageId,
            'state': {'status': status, 'title': 'npm test'},
          },
        },
      })!,
      harness,
    );
  }

  test('pending, running, completed for one call is one saved row', () async {
    harness.beginCodingPass();
    tool('pending');
    tool('running');
    tool('completed');
    final rows = session.transcript
        .where((m) => m.kind == WaifuMsgKind.tool)
        .toList();
    expect(rows, hasLength(1));
    expect(rows.single.toolCallId, 'call_1');
    expect(rows.single.toolOk, isTrue);
    expect(session.toolChips, hasLength(1));
    expect(session.toolChips.single.pending, isFalse);

    final store = WaifuStore(root.path);
    await store.saveLast(session);
    final back = await store.loadSession(root.path);
    expect(
      back!.transcript.where((m) => m.kind == WaifuMsgKind.tool),
      hasLength(1),
    );
  });

  test('undo reverts the first coding message, not the wrap-up', () async {
    harness.beginCodingPass();
    harness.onTextDelta('look', messageId: 'msg_code', thinking: true);
    harness.onTextDelta('more', messageId: 'msg_code_2', thinking: true);
    harness.onIdle();
    harness.onTextDelta('Hmph. Done.', messageId: 'msg_voice');
    await harness.undo();
    final revert = hits.firstWhere((r) => r.url.path.endsWith('/revert'));
    expect(jsonDecode(revert.body)['messageID'], 'msg_code');
  });

  test('a tool-only coding pass still reverts the coding message', () async {
    harness.beginCodingPass();
    tool('completed', messageId: 'msg_tool');
    harness.onIdle();
    harness.onTextDelta('All set.', messageId: 'msg_voice');
    await harness.undo();
    final revert = hits.firstWhere((r) => r.url.path.endsWith('/revert'));
    expect(jsonDecode(revert.body)['messageID'], 'msg_tool');
  });

  test('turn start from the message list skips the voice wrap-up', () {
    const list = [
      OpenCodeMessageInfo(id: 'u0', role: 'user'),
      OpenCodeMessageInfo(id: 'a0', role: 'assistant', agent: 'voice'),
      OpenCodeMessageInfo(id: 'u1', role: 'user'),
      OpenCodeMessageInfo(id: 'a1', role: 'assistant', agent: 'waifu'),
      OpenCodeMessageInfo(id: 'a2', role: 'assistant', agent: 'waifu'),
      OpenCodeMessageInfo(id: 'u2', role: 'user'),
      OpenCodeMessageInfo(id: 'v2', role: 'assistant', agent: 'voice'),
    ];
    expect(waifuTurnStartAssistantId(list), 'a1');
    expect(waifuTurnStartAssistantId(const []), isNull);
  });
}
