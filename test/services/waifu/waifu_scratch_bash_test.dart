// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Whole-disk inspect in /tmp was denied as a protected-root wipe because
// mkdir/cd paths were treated as rm -r targets.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'mkdir/cd in /tmp plus rm of a relative child is not a protected wipe',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_scratch_proj_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      const command =
          'mkdir -p /tmp/epub_inspect && cd /tmp/epub_inspect && rm -r META-INF';
      expect(await waifuBashResolvedWipeBlock(command, root.path), isNull);

      final result = await WaifuBash(
        root.path,
        pathMode: WaifuPathMode.wholeDisk,
      ).run({'command': command});
      expect(result.output, isNot(contains('protected root')));
      expect(result.output, isNot(contains('sit-down ancestor')));
    },
  );

  test('named /tmp extract folders may be removed; /tmp itself may not', () {
    const cwd = '/Users/me/Desktop/new project';
    expect(
      waifuDeniedCommand('rm -r /tmp/epub_inspect', workingDirectory: cwd),
      isNull,
    );
    expect(
      waifuDeniedCommand(
        'rm -rf /private/tmp/epub_inspect',
        workingDirectory: cwd,
      ),
      isNull,
    );
    expect(waifuDeniedCommand('rm -rf /tmp', workingDirectory: cwd), isNotNull);
    expect(
      waifuDeniedCommand('rm -rf /tmp/*', workingDirectory: cwd),
      isNotNull,
    );
  });

  test('recursive wipe of the sit-down parent is still denied', () async {
    final sandbox = await Directory.systemTemp.createTemp('waifu_scratch_sbx_');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });
    final root = await Directory(p.join(sandbox.path, 'project')).create();
    expect(
      await waifuBashResolvedWipeBlock('rm -r "${sandbox.path}"', root.path),
      isNotNull,
    );
  });
}
