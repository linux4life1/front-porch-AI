// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late Directory root;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('waifu_security_');
    root = await Directory(p.join(sandbox.path, 'project')).create();
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test(
    'both path modes stop a recursive wipe of the sit-down parent',
    () async {
      final sentinel = File(p.join(sandbox.path, 'keep.txt'));
      await sentinel.writeAsString('still here');
      for (final mode in WaifuPathMode.values) {
        final result = await WaifuBash(
          root.path,
          pathMode: mode,
        ).run({'command': 'rm -r "${sandbox.path}"'});
        expect(result.ok, isFalse, reason: mode.name);
        expect(result.output, contains('denied'), reason: mode.name);
        expect(await sentinel.exists(), isTrue, reason: mode.name);
      }
    },
  );

  test('whole-disk wipe checks the real target behind a path alias', () async {
    final sentinel = File(p.join(sandbox.path, 'keep.txt'));
    await sentinel.writeAsString('still here');
    final alias = Link(p.join(root.path, 'outside-root'));
    await alias.create(sandbox.parent.path);
    final command = 'rm -r outside-root/${p.basename(sandbox.path)}';

    final result = await WaifuBash(
      root.path,
      pathMode: WaifuPathMode.wholeDisk,
    ).run({'command': command});

    expect(result.ok, isFalse);
    expect(result.output, contains('resolves to a protected root'));
    expect(await sentinel.exists(), isTrue);
  });

  test(
    'file and bash reads cannot follow aliases into secret stores',
    () async {
      final env = File(p.join(sandbox.path, '.env'));
      final ssh = File(p.join(sandbox.path, '.ssh', 'id_key'));
      final aws = File(p.join(sandbox.path, '.aws', 'credentials'));
      await env.writeAsString('ENV_SECRET');
      await ssh.parent.create();
      await ssh.writeAsString('SSH_SECRET');
      await aws.parent.create();
      await aws.writeAsString('AWS_SECRET');
      final aliases = <String, File>{
        'notes': env,
        'identity': ssh,
        'cloud': aws,
      };
      for (final entry in aliases.entries) {
        await Link(p.join(root.path, entry.key)).create(entry.value.path);
      }

      for (final mode in WaifuPathMode.values) {
        final fs = WaifuFs(root.path, pathMode: mode);
        final bash = WaifuBash(root.path, pathMode: mode);
        final directEnv = await bash.run({'command': 'cat ../.env'});
        expect(directEnv.ok, isFalse, reason: mode.name);
        expect(directEnv.output, isNot(contains('ENV_SECRET')));
        for (final entry in aliases.entries) {
          final read = await fs.dispatch('read', {'path': entry.key});
          expect(read.ok, isFalse, reason: '${mode.name}/${entry.key}');
          expect(read.output, isNot(contains('SECRET')));
          final cat = await bash.run({'command': 'cat ${entry.key}'});
          expect(cat.ok, isFalse, reason: '${mode.name}/${entry.key}');
          expect(cat.output, isNot(contains('SECRET')));
        }
      }
    },
  );

  test('bash keeps development paths but drops Front Porch secrets', () async {
    final bash = WaifuBash(
      root.path,
      pathMode: WaifuPathMode.wholeDisk,
      sourceEnvironment: {
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        'HOME': root.path,
        'FRONT_PORCH_API_KEY': 'MUST_NOT_LEAK',
        'OPENROUTER_API_KEY': 'ALSO_SECRET',
      },
    );
    final result = await bash.run({
      'command':
          r'''printf '%s|%s|%s' "${FRONT_PORCH_API_KEY-unset}" '''
          r'''"${OPENROUTER_API_KEY-unset}" "${PATH:+set}"''',
    });
    expect(result.ok, isTrue);
    expect(result.output, contains('unset|unset|set'));
    expect(result.output, isNot(contains('MUST_NOT_LEAK')));
    expect(result.output, isNot(contains('ALSO_SECRET')));
  });

  test('parent Abort kills bash running inside a nested task', () async {
    final marker = File(p.join(root.path, 'should_not_exist'));
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'task',
            arguments: {'subagent': 'general', 'prompt': 'run the check'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'bash',
            arguments: {
              'command': 'while true; do :; done; touch should_not_exist',
            },
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: 'child should not finish'),
      const LlmToolResponse(calls: [], text: 'parent should not finish'),
    ]);
    final harness = WaifuHarness(
      session: WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Iris'),
        mode: WaifuMode.yolo,
      ),
      llm: llm,
    );

    final running = harness.send('delegate a long check');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    harness.abort();
    await running.timeout(const Duration(seconds: 3));

    expect(await marker.exists(), isFalse);
    expect(harness.isRunning, isFalse);
    expect(
      harness.session.transcript.map((message) => message.text),
      contains('Stopped.'),
    );
  });
}
