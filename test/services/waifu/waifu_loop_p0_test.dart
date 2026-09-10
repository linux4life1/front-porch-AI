// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tip-loop P0s vs OpenCode-class behavior. New file so test-integrity
// does not touch the older glob / wrap / meter suites.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  test('second glob of a different pattern is a real listing', () async {
    final root = await Directory.systemTemp.createTemp('waifu_glob_pat_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await File(p.join(root.path, 'Page.swift')).writeAsString('swift');
    await File(p.join(root.path, 'notes.md')).writeAsString('md');
    const swift = LlmToolCall(name: 'glob', arguments: {'pattern': '*.swift'});
    const md = LlmToolCall(name: 'glob', arguments: {'pattern': '*.md'});
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(calls: [swift], text: ''),
      const LlmToolResponse(calls: [md], text: ''),
      const LlmToolResponse(calls: [], text: 'Listed both.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    await WaifuHarness(session: session, llm: llm).send('list files');
    final globs = session.transcript
        .where((m) => m.kind == WaifuMsgKind.tool && m.toolName == 'glob')
        .toList();
    expect(globs, hasLength(2));
    expect(globs.first.text, contains('Page.swift'));
    expect(globs.last.text, isNot(contains(kWaifuDuplicateInHistory)));
    expect(globs.last.text, contains('notes.md'));
  });

  test('same glob pattern still stubs when nothing mutated', () {
    const prior = WaifuMessage.tool(
      name: 'glob',
      output: 'Page.swift',
      ok: true,
      args: {'pattern': '*.swift'},
    );
    expect(
      waifuDuplicateGlobStub(transcript: const [prior], pattern: '*.swift'),
      kWaifuDuplicateInHistory,
    );
    expect(
      waifuDuplicateGlobStub(transcript: const [prior], pattern: '*.md'),
      isNull,
    );
  });

  test('a screenshot does not count as a 500k-token window', () {
    final huge = List.filled(800000, 'A').join();
    expect(waifuEstimateImageTokens([huge]), kWaifuImageTokenCap);
    expect(waifuEstimateImageTokens(['abcd']), kWaifuImageTokenFloor);
    final snap = waifuMeasureRequest(
      systemPrompt: 's',
      prompt: 'see this',
      budget: 277518,
      images: [huge],
    );
    expect(waifuShouldCompact(used: snap.used, budget: 277518), isFalse);
  });

  test('failed write on a code-change send is not wrap-up', () async {
    final root = await Directory.systemTemp.createTemp('waifu_fail_write_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': '../secret.txt', 'contents': 'x'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'I wrote the helper file.'),
      const LlmToolResponse(calls: [], text: 'I wrote the helper file.'),
      const LlmToolResponse(calls: [], text: 'I wrote the helper file.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    await WaifuHarness(session: session, llm: llm).send('write a helper file');
    expect(File(p.join(root.path, 'secret.txt')).existsSync(), isFalse);
    final spoken = session.transcript
        .where((m) => m.kind == WaifuMsgKind.assistant)
        .map((m) => m.text)
        .join('\n');
    expect(spoken, isNot(contains('I wrote the helper file.')));
    expect(spoken, contains('I could not put a real change on disk'));
  });

  test(
    'API fill wins over a fat photo guess so the live bubble stays',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_photo_fill_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      await File(p.join(root.path, 'Page.swift')).writeAsString('ok');
      final png = List.filled(200000, 1);
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'read', arguments: {'path': 'Page.swift'}),
          ],
          text: '',
          totalTokens: 9040,
        ),
        const LlmToolResponse(calls: [], text: 'Hmph. I see the page.'),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
      )..contextBudget = 277518;
      await WaifuHarness(
        session: session,
        llm: llm,
      ).send('what is on this page', imagePng: Uint8List.fromList(png));
      expect(session.compactPasses, 0);
      expect(
        session.transcript
            .where((m) => m.kind == WaifuMsgKind.assistant)
            .length,
        1,
      );
      expect(llm.calls.length, 2);
      expect(llm.calls[1].systemPrompt, contains(kWaifuPreamble));
    },
  );
}
