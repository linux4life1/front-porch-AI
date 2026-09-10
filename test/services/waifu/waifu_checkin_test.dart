// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Proven red: 7 writes in one send never ended the turn, so a second
// in-character speech landed in the same bubble (OpenCode blender).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

import 'waifu_analyze_bash.dart';

CharacterCard _mira() => CharacterCard(
  name: 'Mira',
  personality: 'tsundere, dry, teases then does the work anyway',
);

WaifuSession _session(String folder) =>
    WaifuSession(folderRoot: folder, coworker: _mira());

List<LlmToolCall> _writes(int n) => [
  for (var i = 1; i <= n; i++)
    LlmToolCall(
      name: 'write',
      arguments: {'path': 'f$i.txt', 'contents': 'body $i'},
    ),
];

void main() {
  test('due at the spoken turn end, not before', () {
    expect(waifuCheckInDue(kWaifuCheckInEvery - 1), isFalse);
    expect(waifuCheckInDue(kWaifuCheckInEvery), isTrue);
    expect(waifuCheckInCounts('write'), isTrue);
    expect(waifuCheckInCounts('read'), isFalse);
  });

  test('constitution ends the turn with speech, not a keep-going dialog', () {
    expect(kWaifuPreamble, contains('end of the turn'));
    expect(kWaifuPreamble, isNot(contains('Keep going')));
    expect(kWaifuPreamble.length, lessThan(1000));
    expect(kWaifuCheckInCue, contains('ends this turn'));
    expect(kWaifuCheckInCue, isNot(contains('Keep going')));
    final prompt = waifuLoopUserPrompt(
      folderName: 'app',
      coworkerName: 'Mira',
      transcript: const [],
      todos: '',
      mentionBlock: '',
      toolTrace: '',
    );
    expect(prompt, contains(kWaifuCheckInCue));
  });

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_checkin_');
    for (var i = 1; i <= kWaifuCheckInEvery + 1; i++) {
      await File(p.join(root.path, 'f$i.txt')).writeAsString('old $i');
    }
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'seven writes in one model response all land; she speaks once',
    () async {
      final reads = [
        for (var i = 1; i <= kWaifuCheckInEvery + 1; i++)
          LlmToolCall(name: 'read', arguments: {'path': 'f$i.txt'}),
      ];
      final llm = ScriptedWaifuLlm([
        LlmToolResponse(calls: _writes(kWaifuCheckInEvery + 1), text: ''),
        LlmToolResponse(calls: reads, text: ''),
        const LlmToolResponse(calls: [kWaifuAnalyzeCall], text: ''),
        const LlmToolResponse(
          calls: [],
          text: 'Hmph. Scaffold is up. Parser is next unless you want the UI.',
        ),
      ]);
      final session = _session(root.path);
      await WaifuHarness(
        session: session,
        llm: llm,
        bash: WaifuAnalyzeBash(root.path),
      ).send('build the app');
      expect(
        await File(
          p.join(root.path, 'f$kWaifuCheckInEvery.txt'),
        ).readAsString(),
        'body $kWaifuCheckInEvery',
      );
      expect(
        await File(
          p.join(root.path, 'f${kWaifuCheckInEvery + 1}.txt'),
        ).readAsString(),
        'body ${kWaifuCheckInEvery + 1}',
      );
      final spoken = session.transcript
          .where((m) => m.kind == WaifuMsgKind.assistant)
          .toList();
      expect(spoken, hasLength(1));
      expect(spoken.single.text, contains('Scaffold is up'));
      expect(spoken.single.text, isNot(contains('---')));
    },
  );

  test('five writes still finish the small job in one send', () async {
    final reads = [
      for (var i = 1; i <= kWaifuCheckInEvery - 1; i++)
        LlmToolCall(name: 'read', arguments: {'path': 'f$i.txt'}),
    ];
    final llm = ScriptedWaifuLlm([
      LlmToolResponse(calls: _writes(kWaifuCheckInEvery - 1), text: ''),
      LlmToolResponse(calls: reads, text: ''),
      const LlmToolResponse(calls: [kWaifuAnalyzeCall], text: ''),
      const LlmToolResponse(calls: [], text: 'Hmph. The files are on disk.'),
    ]);
    final session = _session(root.path);
    await WaifuHarness(
      session: session,
      llm: llm,
      bash: WaifuAnalyzeBash(root.path),
    ).send('build the app');
    expect(
      await File(
        p.join(root.path, 'f${kWaifuCheckInEvery - 1}.txt'),
      ).readAsString(),
      'body ${kWaifuCheckInEvery - 1}',
    );
    expect(session.transcript.last.text, contains('on disk'));
  });
}
