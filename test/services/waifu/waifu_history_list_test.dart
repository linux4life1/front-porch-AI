// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  test('read then wrap-up puts a tool kind in the next prompt', () async {
    final root = await Directory.systemTemp.createTemp('waifu_hist_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await File(p.join(root.path, 'notes.txt')).writeAsString('hello notes');
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'read', arguments: {'path': 'notes.txt'}),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Hmph. I read it.'),
      const LlmToolResponse(calls: [], text: 'Still here.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    final harness = WaifuHarness(session: session, llm: llm);
    await harness.send('read the notes');
    await harness.send('keep going');
    expect(session.transcript.any((m) => m.kind == WaifuMsgKind.tool), isTrue);
    expect(llm.calls.last.prompt, contains('[tool read ok]'));
    expect(
      llm.calls.last.prompt,
      isNot(contains('Tool results for this turn')),
    );
  });

  test('old toolTraces JSON loads as tool messages', () async {
    final dir = await Directory.systemTemp.createTemp('waifu_traces_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final folder = '${dir.path}/proj';
    await Directory('${dir.path}/sessions').create(recursive: true);
    final slug = waifuSessionSlug(folder);
    await File('${dir.path}/sessions/$slug.json').writeAsString(
      '{"title":"t","folderRoot":"$folder","mode":"build",'
      '"coworker":{"name":"Iris","personality":"","description":"",'
      '"systemPrompt":""},"transcript":[],'
      '"toolTraces":["[read] ok\\nhello notes"]}',
    );
    final loaded = await WaifuStore(dir.path).loadSession(folder);
    expect(loaded, isNotNull);
    expect(loaded!.transcript, isNotEmpty);
    expect(loaded.transcript.first.kind, WaifuMsgKind.tool);
    expect(loaded.transcript.first.text, contains('hello notes'));
  });

  test(
    'second read of an unchanged path stubs; write then read is fresh',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_dup_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      await File(p.join(root.path, 'notes.txt')).writeAsString('v1');
      const read = LlmToolCall(name: 'read', arguments: {'path': 'notes.txt'});
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(calls: [read], text: ''),
        const LlmToolResponse(calls: [read], text: ''),
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: 'write',
              arguments: {'path': 'notes.txt', 'contents': 'v2'},
            ),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [read], text: ''),
        const LlmToolResponse(calls: [], text: 'Caught up.'),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
        mode: WaifuMode.yolo,
      );
      await WaifuHarness(
        session: session,
        llm: llm,
      ).send('read twice then rewrite');
      final reads = session.transcript
          .where((m) => m.kind == WaifuMsgKind.tool && m.toolName == 'read')
          .toList();
      expect(reads.length, greaterThanOrEqualTo(2));
      expect(reads[1].text, contains('already in history, unchanged'));
      expect(reads.last.text, contains('v2'));
      expect(session.transcript.where((m) => m.text.contains('v1')).length, 1);
    },
  );

  test('second glob with no writes stubs', () async {
    final root = await Directory.systemTemp.createTemp('waifu_glob_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await File(p.join(root.path, 'a.txt')).writeAsString('a');
    const glob = LlmToolCall(name: 'glob', arguments: {'pattern': '*'});
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(calls: [glob], text: ''),
      const LlmToolResponse(calls: [glob], text: ''),
      const LlmToolResponse(calls: [], text: 'Listed.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    await WaifuHarness(session: session, llm: llm).send('list files');
    final globs = session.transcript
        .where((m) => m.kind == WaifuMsgKind.tool && m.toolName == 'glob')
        .toList();
    expect(globs, isNotEmpty);
    expect(globs.last.text, contains('already in history, unchanged'));
  });
}
