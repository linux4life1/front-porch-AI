// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  test('send records the user line before any await', () async {
    final root = await Directory.systemTemp.createTemp('waifu_send_sync_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira'),
    );
    final harness = WaifuHarness(
      session: session,
      llm: ScriptedWaifuLlm(const [LlmToolResponse(calls: [], text: 'Hmph.')]),
    );
    final done = harness.send('count');
    expect(session.running, isTrue);
    expect(session.transcript, isNotEmpty);
    expect(session.transcript.first.isUser, isTrue);
    expect(session.transcript.first.text, 'count');
    await done;
  });
}
