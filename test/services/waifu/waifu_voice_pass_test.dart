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

/// The wrap-up is spoken from a recap and her own recent lines, and a turn
/// whose wrap-up never comes still ends with a line in the transcript.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_voice_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  const idle =
      'data: {"type":"session.idle","properties":{"sessionID":"ses_1"}}\n\n';
  String delta(String text) =>
      'data: ${jsonEncode({
        'type': 'message.part.delta',
        'properties': {'sessionID': 'ses_1', 'field': 'text', 'delta': text},
      })}\n\n';

  WaifuHarness harnessFor(WaifuSession session, String events) => WaifuHarness(
    session: session,
    sessionId: 'ses_1',
    client: OpenCodeClient(
      baseUri: Uri.parse('http://127.0.0.1:4096'),
      directory: root.path,
      voiceSettle: const Duration(milliseconds: 200),
      clientFactory: () => MockClient.streaming((req, body) async {
        if (req.url.path == '/event') {
          return http.StreamedResponse(
            Stream.value(utf8.encode(events)),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        if (req.url.path.endsWith('/prompt_async')) {
          return http.StreamedResponse(const Stream.empty(), 204);
        }
        return http.StreamedResponse(const Stream.empty(), 404);
      }),
    ),
  );

  WaifuSession sessionFor() => WaifuSession(
    folderRoot: root.path,
    coworker: CharacterCard(name: 'Mira'),
  );

  test('a turn with no wrap-up ends on a quiet-finish stage line', () async {
    final session = sessionFor();
    await harnessFor(session, idle).send('add a score');
    expect(session.running, isFalse);
    final last = session.transcript.last;
    expect(last.kind, WaifuMsgKind.stage);
    expect(last.text, 'Mira finishes up without a word.');
  });

  test('a spoken wrap-up gets no quiet-finish line', () async {
    final session = sessionFor();
    await harnessFor(
      session,
      idle + delta('Score is in. Try to beat ten.') + idle,
    ).send('add a score');
    expect(session.transcript.last.kind, WaifuMsgKind.assistant);
    expect(session.transcript.last.text, 'Score is in. Try to beat ten.');
  });

  test('the wrap-up cue is data; the rules live only in the voice prompt', () {
    expect(kWaifuVoicePluginSource, contains('waifuTurnRecap(list)'));
    expect(kWaifuVoicePluginSource, contains('Your last lines to the user'));
    expect(kWaifuVoicePluginSource, isNot(contains('Speak as this character')));
    expect(kWaifuVoicePreamble, contains('recap'));
  });
}
