// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

import 'waifu_analyze_bash.dart';

void main() {
  WaifuToolResult writeOk(String path) => WaifuToolResult(
    ok: true,
    output: 'wrote $path',
    write: WaifuWriteRecord(relativePath: path, before: 'old', after: 'new'),
  );

  WaifuTurn afterWrite() {
    final turn = WaifuTurn.start('fix parser.dart', null, mode: WaifuMode.yolo);
    turn.noteAttempt(kWaifuToolWrite);
    turn.noteResult(
      kWaifuToolWrite,
      writeOk('parser.dart'),
      writeOk('parser.dart').write,
      args: {'path': 'parser.dart', 'contents': 'new'},
    );
    return turn;
  }

  void verifyTurn(WaifuTurn turn) {
    turn.noteResult(
      kWaifuToolRead,
      const WaifuToolResult(ok: true, output: 'new'),
      writeOk('parser.dart').write,
      args: {'path': 'parser.dart'},
    );
    turn.noteResult(
      kWaifuToolBash,
      const WaifuToolResult(ok: true, output: 'No issues found!'),
      writeOk('parser.dart').write,
      args: {'command': 'dart analyze'},
    );
  }

  test('mutate without verify cannot accept wrap-up', () {
    final turn = afterWrite();
    expect(turn.verified, isFalse);
    expect(turn.onEmptyCalls('Hmph. Parser is fixed.'), WaifuTurnStep.retry);
    expect(turn.phase, WaifuPhase.verify);
    expect(turn.onEmptyCalls('Hmph. Parser is fixed.'), WaifuTurnStep.retry);
    expect(turn.onEmptyCalls('Hmph. Parser is fixed.'), WaifuTurnStep.fail);
    expect(turn.failReason, contains('verify'));
  });

  test('write, re-read, and passing analyze accept a short spoken line', () {
    final turn = afterWrite();
    verifyTurn(turn);
    expect(turn.verified, isTrue);
    expect(turn.onEmptyCalls('Hmph. It’s in.'), WaifuTurnStep.accept);
    expect(turn.pendingSpeech, 'Hmph. It’s in.');
    expect(turn.phase, WaifuPhase.done);
  });

  test('done is accept when receipts are complete', () {
    final turn = afterWrite();
    verifyTurn(turn);
    expect(turn.onEmptyCalls('Done.'), WaifuTurnStep.accept);
  });

  test('please write hello.txt with no write retries then fails', () {
    final turn = WaifuTurn.start('please write hello.txt', null);
    expect(turn.mutationRequired, isTrue);
    expect(turn.onEmptyCalls('I will write it.'), WaifuTurnStep.retry);
    expect(turn.phase, WaifuPhase.tools);
    expect(turn.onEmptyCalls('Still thinking.'), WaifuTurnStep.retry);
    expect(turn.onEmptyCalls('All set.'), WaifuTurnStep.fail);
    expect(turn.failReason, contains('file change'));
  });

  test('todo claim without todowrite retries then fails', () {
    final turn = WaifuTurn.start('track the work', null);
    expect(turn.onEmptyCalls('I updated the todo list.'), WaifuTurnStep.retry);
    expect(turn.onEmptyCalls('I updated the todo list.'), WaifuTurnStep.retry);
    expect(turn.onEmptyCalls('I updated the todo list.'), WaifuTurnStep.fail);
  });

  test('harness write plus verify accepts Hmph. It’s in.', () async {
    final root = await Directory.systemTemp.createTemp('waifu_receipt_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await File(p.join(root.path, 'parser.dart')).writeAsString('old\n');
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'parser.dart', 'contents': 'ok\n'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'read', arguments: {'path': 'parser.dart'}),
          kWaifuAnalyzeCall,
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'Hmph. It’s in.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
      mode: WaifuMode.build,
    );
    await WaifuHarness(
      session: session,
      llm: llm,
      bash: WaifuAnalyzeBash(root.path),
      onAsk: (_) async => WaifuAskDecision.allowAlways,
    ).send('fix parser.dart');
    expect(session.transcript.last.text, 'Hmph. It’s in.');
    expect(await File(p.join(root.path, 'parser.dart')).readAsString(), 'ok\n');
  });

  test('harness implement with no write fails after retries', () async {
    final root = await Directory.systemTemp.createTemp('waifu_nowrite_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(calls: [], text: 'I will scaffold it.'),
      const LlmToolResponse(calls: [], text: 'Still planning.'),
      const LlmToolResponse(calls: [], text: 'Done.'),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: CharacterCard(name: 'Iris'),
    );
    await WaifuHarness(
      session: session,
      llm: llm,
    ).send('please write hello.txt');
    expect(File(p.join(root.path, 'hello.txt')).existsSync(), isFalse);
    expect(
      session.transcript.last.text.toLowerCase(),
      contains('could not put a real change'),
    );
  });

  test(
    'check-in after 6 writes blocks the 7th; verify still allowed',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_checkin_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      await File(p.join(root.path, 'notes.txt')).writeAsString('old\n');
      final llm = ScriptedWaifuLlm([
        LlmToolResponse(
          calls: List.generate(
            7,
            (i) => LlmToolCall(
              name: 'write',
              arguments: {'path': 'notes.txt', 'contents': 'v$i\n'},
            ),
          ),
          text: '',
        ),
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'read', arguments: {'path': 'notes.txt'}),
            kWaifuAnalyzeCall,
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: 'Paused after a handful.'),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
        mode: WaifuMode.build,
      );
      await WaifuHarness(
        session: session,
        llm: llm,
        bash: WaifuAnalyzeBash(root.path),
        onAsk: (_) async => WaifuAskDecision.allowAlways,
      ).send('implement seven files');
      expect(await File(p.join(root.path, 'notes.txt')).readAsString(), 'v5\n');
      expect(session.transcript.last.text, 'Paused after a handful.');
    },
  );
}
