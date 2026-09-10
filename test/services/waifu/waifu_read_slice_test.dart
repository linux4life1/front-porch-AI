// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

String _nLines(int n) => List.generate(n, (i) => 'L${i + 1}').join('\n');

void main() {
  test('small file stays the whole body with no paging trailer', () {
    expect(
      waifuSliceReadText(
        'hello world',
        offset: 1,
        limit: kWaifuReadDefaultLines,
      ),
      'hello world',
    );
  });

  test('default window hides the rest and names the next offset', () {
    final n = kWaifuReadDefaultLines + 50;
    final out = waifuSliceReadText(
      _nLines(n),
      offset: 1,
      limit: kWaifuReadDefaultLines,
    );
    expect(out, startsWith('lines 1-$kWaifuReadDefaultLines of $n\n'));
    expect(out, contains('\nL1\n'));
    expect(out, contains('\nL$kWaifuReadDefaultLines\n'));
    expect(out, isNot(contains('L${kWaifuReadDefaultLines + 1}')));
    expect(
      out,
      contains('…(50 more lines; next offset=${kWaifuReadDefaultLines + 1})'),
    );
  });

  test('later offset returns that window, not the first lines', () {
    final n = kWaifuReadDefaultLines + 50;
    final start = kWaifuReadDefaultLines + 1;
    final out = waifuSliceReadText(
      _nLines(n),
      offset: start,
      limit: kWaifuReadDefaultLines,
    );
    expect(out, startsWith('lines $start-$n of $n\n'));
    expect(out, contains('L$start'));
    expect(out, contains('L$n'));
    expect(out, isNot(contains('L1\n')));
    expect(out, isNot(contains('next offset=')));
  });

  test('offset past the end does not dump the file', () {
    final out = waifuSliceReadText(
      _nLines(10),
      offset: 80,
      limit: kWaifuReadDefaultLines,
    );
    expect(out, contains('past the end'));
    expect(out, isNot(contains('L1')));
  });

  test('limit above the max is clamped', () {
    expect(waifuReadLimitArg({'limit': 5000}), kWaifuReadDefaultLines);
    expect(waifuReadLimitArg({'limit': 20}), 20);
    expect(waifuReadLimitArg({}), kWaifuReadDefaultLines);
    expect(waifuReadOffsetArg({}), 1);
    expect(waifuReadOffsetArg({'offset': 0}), 1);
    expect(
      waifuReadWindowKey({'path': 'a.swift'}),
      waifuReadWindowKey({'path': 'a.swift', 'limit': 5000}),
    );
  });

  test('read schema tells the model the window, not whole-file', () {
    final tools = waifuFileToolsFor(WaifuPathMode.folderJail).toString();
    expect(tools, contains('line window'));
    expect(tools, contains('Default and max $kWaifuReadDefaultLines'));
    expect(tools, contains('more lines remain'));
    expect(
      kWaifuBuiltinsCue,
      contains('read returns at most $kWaifuReadDefaultLines lines'),
    );
    expect(kWaifuBuiltinsCue, contains('more lines remain'));
  });

  test('duplicate stub is per window, not per path', () {
    const path = 'big.swift';
    final first = WaifuMessage.tool(
      name: kWaifuToolRead,
      output: 'lines 1-$kWaifuReadDefaultLines of 400\nL1',
      ok: true,
      path: path,
      args: const {'path': path},
    );
    expect(
      waifuDuplicateReadStub(
        transcript: [first],
        path: path,
        args: const {'path': path},
      ),
      kWaifuDuplicateInHistory,
    );
    expect(
      waifuDuplicateReadStub(
        transcript: [first],
        path: path,
        args: const {'path': path, 'offset': 201},
      ),
      isNull,
    );
  });

  test('edit of one file does not expire reads of a sibling', () {
    const touched = 'a.swift';
    const sibling = 'b.swift';
    final history = [
      WaifuMessage.tool(
        name: kWaifuToolRead,
        output: 'class B {}',
        ok: true,
        path: sibling,
        args: const {'path': sibling},
      ),
      WaifuMessage.tool(
        name: kWaifuToolRead,
        output: 'class A {}',
        ok: true,
        path: touched,
        args: const {'path': touched},
      ),
      WaifuMessage.tool(
        name: kWaifuToolEdit,
        output: 'edited a.swift',
        ok: true,
        path: touched,
        args: const {
          'path': touched,
          'old_string': 'class A {}',
          'new_string': 'class A { }',
        },
      ),
    ];
    expect(
      waifuDuplicateReadStub(
        transcript: history,
        path: sibling,
        args: const {'path': sibling},
      ),
      kWaifuDuplicateInHistory,
    );
    expect(
      waifuDuplicateReadStub(
        transcript: history,
        path: touched,
        args: const {'path': touched},
      ),
      isNull,
    );
  });

  test(
    'fs read of a long file pages; a later offset is a new window',
    () async {
      final sandbox = await Directory.systemTemp.createTemp('waifu_slice_');
      addTearDown(() async {
        if (await sandbox.exists()) await sandbox.delete(recursive: true);
      });
      final n = kWaifuReadDefaultLines + 50;
      await File(p.join(sandbox.path, 'big.txt')).writeAsString(_nLines(n));
      final fs = WaifuFs(sandbox.path);

      final first = await fs.dispatch('read', {'path': 'big.txt'});
      expect(first.ok, isTrue);
      expect(first.output, contains('lines 1-$kWaifuReadDefaultLines of $n'));
      expect(first.output, isNot(contains('L${kWaifuReadDefaultLines + 1}')));
      expect(
        first.output,
        contains('next offset=${kWaifuReadDefaultLines + 1}'),
      );

      final huge = await fs.dispatch('read', {
        'path': 'big.txt',
        'limit': 5000,
      });
      expect(huge.output, isNot(contains('L${kWaifuReadDefaultLines + 1}')));

      final next = await fs.dispatch('read', {
        'path': 'big.txt',
        'offset': kWaifuReadDefaultLines + 1,
      });
      expect(next.ok, isTrue);
      expect(next.output, contains('L${kWaifuReadDefaultLines + 1}'));
      expect(next.output, isNot(contains('\nL1\n')));
    },
  );

  test(
    'harness sibling read after edit is stubbed; edited path is fresh',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_sib_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      await File(p.join(root.path, 'a.swift')).writeAsString('class A {}');
      await File(p.join(root.path, 'b.swift')).writeAsString('class B {}');
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'read', arguments: {'path': 'a.swift'}),
            LlmToolCall(name: 'read', arguments: {'path': 'b.swift'}),
          ],
          text: '',
        ),
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: 'edit',
              arguments: {
                'path': 'a.swift',
                'old_string': 'class A {}',
                'new_string': 'class A { }',
              },
            ),
          ],
          text: '',
        ),
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'read', arguments: {'path': 'b.swift'}),
            LlmToolCall(name: 'read', arguments: {'path': 'a.swift'}),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'Patched.'),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
        mode: WaifuMode.yolo,
      );
      await WaifuHarness(session: session, llm: llm).send('patch a, not b');
      final reads = session.transcript
          .where((m) => m.kind == WaifuMsgKind.tool && m.toolName == 'read')
          .toList();
      expect(reads.length, 4);
      expect(reads[0].text, contains('class A {}'));
      expect(reads[1].text, contains('class B {}'));
      expect(reads[2].text, kWaifuDuplicateInHistory);
      expect(reads[3].text, contains('class A { }'));
      expect(reads[3].text, isNot(contains(kWaifuDuplicateInHistory)));
    },
  );

  test('harness later offset is not stubbed as already in history', () async {
    final root = await Directory.systemTemp.createTemp('waifu_page_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final n = kWaifuReadDefaultLines + 50;
    await File(p.join(root.path, 'big.txt')).writeAsString(_nLines(n));
    const path = 'big.txt';
    final first = LlmToolCall(name: 'read', arguments: {'path': path});
    final page = LlmToolCall(
      name: 'read',
      arguments: {'path': path, 'offset': kWaifuReadDefaultLines + 1},
    );
    final llm = ScriptedWaifuLlm([
      LlmToolResponse(calls: [first], text: ''),
      LlmToolResponse(calls: [page], text: ''),
      LlmToolResponse(calls: [page], text: ''),
      const LlmToolResponse(calls: [], text: 'Paged.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
      mode: WaifuMode.yolo,
    );
    await WaifuHarness(session: session, llm: llm).send('page the file');
    final reads = session.transcript
        .where((m) => m.kind == WaifuMsgKind.tool && m.toolName == 'read')
        .toList();
    expect(reads.length, greaterThanOrEqualTo(3));
    expect(reads[0].text, contains('L1\n'));
    expect(reads[0].text, isNot(contains('already in history')));
    expect(reads[1].text, contains('L${kWaifuReadDefaultLines + 1}'));
    expect(reads[1].text, isNot(contains('already in history')));
    expect(reads[2].text, contains('already in history, unchanged'));
  });
}
