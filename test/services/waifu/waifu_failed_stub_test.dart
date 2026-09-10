// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Failed writes must stay FAILED after prune, and compile is not verify.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  test('pruned failed write stays FAILED, not ok', () {
    final fail = WaifuMessage(
      kind: WaifuMsgKind.tool,
      text: 'denied: path is outside the folder jail\n${'x' * 40000}',
      toolName: 'write',
    );
    final older = WaifuMessage(
      kind: WaifuMsgKind.tool,
      text: 'denied: still jail\n${'y' * 40000}',
      toolName: 'write',
      toolOk: false,
    );
    const newest = WaifuMessage.tool(name: 'read', output: 'ok', ok: true);
    final msgs = [fail, older, newest];
    waifuPruneOldToolMessages(msgs, budget: 8192);
    expect(msgs.first.toolOk, isFalse);
    expect(waifuToolPromptLine(msgs.first), contains('[tool write FAILED]'));
    expect(waifuToolPromptLine(msgs.first), contains('Disk was not changed'));
    expect(waifuToolPromptLine(msgs[1]), contains('[tool write FAILED]'));
  });

  test('swift test verifies; swift build does not', () {
    expect(waifuLooksVerifyCommand('swift test'), isTrue);
    expect(waifuLooksVerifyCommand('swift build'), isFalse);
    expect(waifuLooksVerifyCommand('test -f Foo.swift'), isFalse);
  });

  test('sit-down save is armed, not 0 / N', () async {
    final dir = await Directory.systemTemp.createTemp('waifu_arm_save_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final folder = p.join(dir.path, 'Porch');
    await Directory(folder).create(recursive: true);
    final session = WaifuSession(
      folderRoot: folder,
      coworker: CharacterCard(name: 'Iris', personality: 'does the work'),
    );
    expect(session.tokensUsed, 0);
    WaifuHarness(
      session: session,
      llm: ScriptedWaifuLlm(const [LlmToolResponse(calls: [], text: 'idle')]),
    );
    expect(session.tokensUsed, greaterThan(0));
    final store = WaifuStore(dir.path);
    await store.saveLast(session);
    final loaded = await store.loadLast();
    expect(loaded, isNotNull);
    expect(loaded!.tokensUsed, greaterThan(0));
    expect(loaded.tokensUsed, session.tokensUsed);
  });
}
