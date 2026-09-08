// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_live_chips_');
    await File(p.join(root.path, 'notes.txt')).writeAsString('old notes');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('tool attempt emits a pending chip before the tool settles', () async {
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
    );
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'read', arguments: {'path': 'notes.txt'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Hmph. I read it.'),
    ]);
    final harness = WaifuHarness(session: session, llm: llm);
    var sawPending = false;
    var sawOk = false;
    harness.onChanged = () {
      for (final c in session.toolChips) {
        if (c.name != 'read') continue;
        if (c.pending) sawPending = true;
        if (!c.pending && c.ok) sawOk = true;
      }
    };

    await harness.send('read the notes');

    expect(sawPending, isTrue);
    expect(sawOk, isTrue);
    expect(session.toolChips, hasLength(1));
    expect(session.toolChips.single.pending, isFalse);
    expect(session.toolChips.single.ok, isTrue);
    expect(session.toolChips.single.detail, 'notes.txt');
  });

  test('failed tool flips the same pending chip to fail', () async {
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Mira', personality: 'tsundere'),
    );
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'read', arguments: {'path': 'missing.txt'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Gone.'),
    ]);
    final harness = WaifuHarness(session: session, llm: llm);
    var sawPending = false;
    var sawFail = false;
    harness.onChanged = () {
      for (final c in session.toolChips) {
        if (c.name != 'read') continue;
        if (c.pending) sawPending = true;
        if (!c.pending && !c.ok) sawFail = true;
      }
    };

    await harness.send('read missing');

    expect(sawPending, isTrue);
    expect(sawFail, isTrue);
    expect(session.toolChips, hasLength(1));
    expect(session.toolChips.single.pending, isFalse);
    expect(session.toolChips.single.ok, isFalse);
  });
}
