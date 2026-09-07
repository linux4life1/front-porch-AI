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
          calls: [],
          text: 'Hmph. Your parser is fixed. Try to keep up. Obviously.',
        ),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: iris(),
        mode: WaifuMode.yolo,
      );

      await WaifuHarness(session: session, llm: llm).send('fix parser.dart');

      expect(await source.readAsString(), 'String parse() => "fixed";\n');
      final reply = session.transcript
          .where((message) => !message.isUser)
          .single;
      expect(reply.chips.map((chip) => chip.name), [kWaifuToolApplyPatch]);
      expect(reply.chips.single.ok, isTrue);
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
          .where((message) => !message.isUser)
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
        const LlmToolResponse(calls: [], text: 'Done.'),
        const LlmToolResponse(
          calls: [],
          text: 'Hmph. The file is on disk. Obviously.',
        ),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: iris(),
        mode: WaifuMode.yolo,
      );

      await WaifuHarness(session: session, llm: llm).send('create new.dart');

      expect(await File(p.join(root.path, 'new.dart')).exists(), isTrue);
      expect(llm.calls, hasLength(3));
      expect(llm.calls.last.tools, isEmpty);
      final reply = session.transcript
          .where((message) => !message.isUser)
          .single;
      expect(reply.text, 'Hmph. The file is on disk. Obviously.');
      expect(reply.text, isNot(anyOf('', 'Done.', 'I could not work.')));
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
        const LlmToolResponse(calls: [], text: ''),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: iris(),
        mode: WaifuMode.yolo,
      );

      await WaifuHarness(session: session, llm: llm).send('patch parser.dart');

      expect(await source.readAsString(), 'String parse() => "kept";\n');
      final reply = session.transcript
          .where((message) => !message.isUser)
          .single;
      expect(reply.text, 'Hmph. I am cleaning up your parser. Obviously.');
      expect(llm.calls, hasLength(2));
    },
  );
}
