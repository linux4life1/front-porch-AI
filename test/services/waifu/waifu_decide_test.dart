// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  WaifuPermissions perms(
    WaifuMode mode, {
    String? root,
    WaifuPathMode pathMode = WaifuPathMode.folderJail,
  }) =>
      WaifuPermissions(mode: mode, workingDirectory: root, pathMode: pathMode);

  test('yolo still denies rm -rf /', () {
    final d = perms(
      WaifuMode.yolo,
    ).decide(WaifuCall.parse('bash', {'command': 'rm -rf /'}));
    expect(d.kind, WaifuDecisionKind.deny);
    expect(d.reason, contains('recursive rm'));
  });

  test('build ls is allow, not ask', () {
    final d = perms(
      WaifuMode.build,
    ).decide(WaifuCall.parse('bash', {'command': 'ls'}));
    expect(d.kind, WaifuDecisionKind.allow);
  });

  test('build in-porch write is allow', () async {
    final root = await Directory.systemTemp.createTemp('waifu_decide_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await File(p.join(root.path, 'notes.txt')).writeAsString('old');
    final d = perms(WaifuMode.build, root: root.path).decide(
      WaifuCall.parse('write', {'path': 'notes.txt', 'contents': 'new'}),
    );
    expect(d.kind, WaifuDecisionKind.allow);
  });

  test('build rm inside porch is ask', () async {
    final root = await Directory.systemTemp.createTemp('waifu_rm_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final d = perms(
      WaifuMode.build,
      root: root.path,
    ).decide(WaifuCall.parse('bash', {'command': 'rm notes.txt'}));
    expect(d.kind, WaifuDecisionKind.ask);
  });

  test('plan MCP create_issue is deny', () {
    final d = perms(
      WaifuMode.plan,
    ).decide(WaifuCall.parse('create_issue', {'title': 'x'}, mcpMutates: true));
    expect(d.kind, WaifuDecisionKind.deny);
  });

  test('plan unknown MCP name is deny, not allow', () {
    final d = perms(
      WaifuMode.plan,
    ).decide(WaifuCall.parse('not_a_tool', {}, mcpMutates: null));
    expect(d.kind, WaifuDecisionKind.deny);
  });

  test('dispatch not_a_tool is an error, not a file write', () async {
    final root = await Directory.systemTemp.createTemp('waifu_unknown_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'not_a_tool', arguments: {'path': 'pwn.txt'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Stopped.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
      mode: WaifuMode.yolo,
    );
    await WaifuHarness(session: session, llm: llm).send('hey');
    expect(File(p.join(root.path, 'pwn.txt')).existsSync(), isFalse);
    expect(
      session.transcript.any(
        (m) => m.chips.any((c) => c.detail.contains('unknown tool')),
      ),
      isTrue,
    );
  });

  test('wipe list unions Windows System32 and /tmp recursive', () {
    expect(waifuDeniedCommand(r'rm -rf C:\Windows\System32'), isNotNull);
    expect(waifuDeniedCommand('rm -rf /tmp'), isNotNull);
  });

  test('waifuBashMutates does not call the Plan allowlist function', () {
    expect(waifuBashMutates('ls'), isFalse);
    expect(waifuBashMutates('rm notes.txt'), isTrue);
    expect(waifuBashMutates('unknown_bin --flag'), isTrue);
  });
}
