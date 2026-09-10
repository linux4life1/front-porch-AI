// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

import 'waifu_analyze_bash.dart';

void main() {
  late Directory root;
  late File source;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_turn_contract_');
    source = File(p.join(root.path, 'parser.dart'));
    await source.writeAsString('String parse() => "old";\n');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  CharacterCard iris() => CharacterCard(
    name: 'Iris',
    personality: 'proud, sharp, and teasing',
    description:
        'A meticulous parser engineer with no patience for sloppy code.',
    systemPrompt: 'End a successful work report with “Obviously.”',
    mesExample: '{{char}}: Hmph. Try to keep up.\n{{user}}: I will.',
  );

  test('file-change intent catches ordinary coding asks, not lookups', () {
    expect(waifuTaskRequestsFileChange('add a button'), isTrue);
    expect(waifuTaskRequestsFileChange('fix parser.dart'), isTrue);
    expect(waifuTaskRequestsFileChange('refactor this'), isTrue);
    expect(waifuTaskRequestsFileChange('list files'), isFalse);
    expect(waifuTaskRequestsFileChange('explain this function'), isFalse);
    expect(waifuTaskRequestsFileChange('create an issue'), isFalse);
  });

  test(
    'apply_patch lands on disk and the final bubble keeps card diction',
    () async {
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: 'apply_patch',
              arguments: {
                'path': 'parser.dart',
                'patch':
                    '@@\n-String parse() => "old";\n'
                    '+String parse() => "fixed";\n',
              },
            ),
          ],
          text: '',
        ),
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'read', arguments: {'path': 'parser.dart'}),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [kWaifuAnalyzeCall], text: ''),
        const LlmToolResponse(
          calls: [],
          text: 'Hmph. Your parser is fixed. Try to keep up. Obviously.',
        ),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: iris(),
        mode: WaifuMode.yolo,
      );

      await WaifuHarness(
        session: session,
        llm: llm,
        bash: WaifuAnalyzeBash(root.path),
      ).send('fix parser.dart');

      expect(await source.readAsString(), 'String parse() => "fixed";\n');
      final reply = session.transcript
          .where((message) => message.kind == WaifuMsgKind.assistant)
          .single;
      expect(reply.chips.map((chip) => chip.name), [
        kWaifuToolApplyPatch,
        kWaifuToolRead,
        kWaifuToolBash,
      ]);
      expect(reply.chips.every((chip) => chip.ok), isTrue);
      expect(reply.text, contains('Hmph.'));
      expect(reply.text, contains('Try to keep up.'));
      expect(reply.text, contains('Obviously.'));
      expect(reply.text, isNot(anyOf('Done.', 'done', 'I could not work.')));
      expect(llm.calls.first.systemPrompt, contains('Persona: proud, sharp'));
      expect(llm.calls.first.systemPrompt, contains('Vibe: A meticulous'));
      expect(
        llm.calls.first.systemPrompt,
        contains('<card_author_voice_rules>'),
      );
    },
  );

  test(
    'sass without a requested code change receipt is a red failure',
    () async {
      final llm = ScriptedWaifuLlm([
        for (var i = 0; i < 3; i++)
          const LlmToolResponse(calls: [], text: 'Hmph. Consider it fixed.'),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: iris(),
        mode: WaifuMode.yolo,
      );

      await WaifuHarness(
        session: session,
        llm: llm,
      ).send('fix lib/widget.dart');

      expect(session.lastWrite, isNull);
      final reply = session.transcript
          .where((message) => message.kind == WaifuMsgKind.assistant)
          .single;
      expect(reply.chips, isNotEmpty);
      expect(reply.chips.last.ok, isFalse);
      expect(reply.chips.last.detail, contains('no file change landed'));
      expect(reply.text, contains('could not put a real change on disk'));
      expect(reply.text, isNot(contains('Consider it fixed')));
      expect(
        llm.calls
            .skip(1)
            .every(
              (call) => call.prompt.contains('personality without a patch'),
            ),
        isTrue,
      );
    },
  );

  test(
    'successful tools replace generic Done with a card-voice retry',
    () async {
      await File(p.join(root.path, 'new.dart')).writeAsString('old\n');
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: 'write',
              arguments: {'path': 'new.dart', 'contents': 'final value = 1;\n'},
            ),
          ],
          text: '',
        ),
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'read', arguments: {'path': 'new.dart'}),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [kWaifuAnalyzeCall], text: ''),
        const LlmToolResponse(calls: [], text: 'Done.'),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: iris(),
        mode: WaifuMode.yolo,
      );

      await WaifuHarness(
        session: session,
        llm: llm,
        bash: WaifuAnalyzeBash(root.path),
      ).send('create new.dart');

      expect(await File(p.join(root.path, 'new.dart')).exists(), isTrue);
      expect(llm.calls.length, greaterThanOrEqualTo(4));
      final reply = session.transcript
          .where((message) => message.kind == WaifuMsgKind.assistant)
          .single;
      expect(reply.text, isNot('Done.'));
      expect(waifuLooksGenericCompletion(reply.text), isFalse);
    },
  );

  test(
    'character speech beside a patch survives an empty final response',
    () async {
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: 'apply_patch',
              arguments: {
                'path': 'parser.dart',
                'patch':
                    '@@\n-String parse() => "old";\n'
                    '+String parse() => "kept";\n',
              },
            ),
          ],
          text: 'Hmph. I am cleaning up your parser. Obviously.',
        ),
        const LlmToolResponse(
          calls: [
            LlmToolCall(name: 'read', arguments: {'path': 'parser.dart'}),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [kWaifuAnalyzeCall], text: ''),
        const LlmToolResponse(calls: [], text: ''),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: iris(),
        mode: WaifuMode.yolo,
      );

      await WaifuHarness(
        session: session,
        llm: llm,
        bash: WaifuAnalyzeBash(root.path),
      ).send('patch parser.dart');

      expect(await source.readAsString(), 'String parse() => "kept";\n');
      final reply = session.transcript
          .where((message) => message.kind == WaifuMsgKind.assistant)
          .single;
      expect(reply.text, 'Hmph. I am cleaning up your parser. Obviously.');
      expect(llm.calls, hasLength(4));
    },
  );

  test(
    'Build mode sass without a requested code change receipt is a red failure',
    () async {
      final llm = ScriptedWaifuLlm([
        for (var i = 0; i < 3; i++)
          const LlmToolResponse(calls: [], text: 'Hmph. Consider it fixed.'),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: iris(),
        mode: WaifuMode.build,
      );

      await WaifuHarness(
        session: session,
        llm: llm,
        onAsk: (_) async => WaifuAskDecision.allowAlways,
      ).send('fix lib/widget.dart');

      expect(session.lastWrite, isNull);
      final reply = session.transcript
          .where((message) => message.kind == WaifuMsgKind.assistant)
          .single;
      expect(reply.chips.last.ok, isFalse);
      expect(reply.chips.last.detail, contains('no file change landed'));
      expect(reply.text, contains('could not put a real change on disk'));
      expect(reply.text, isNot(contains('Consider it fixed')));
    },
  );
}
