// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  test('structured patch applies exact context and rejects ambiguity', () {
    const before = 'alpha\nold value\nomega\n';
    const patch = '''
*** Begin Patch
*** Update File: sample.txt
@@
 alpha
-old value
+new value
 omega
*** End Patch
''';
    final applied = waifuApplyPatch(before: before, patch: patch);
    expect(applied.ok, isTrue);
    expect(applied.text, 'alpha\nnew value\nomega\n');

    final ambiguous = waifuApplyPatch(
      before: 'same\nsame\n',
      patch: '@@\n-same\n+changed\n',
    );
    expect(ambiguous.ok, isFalse);
    expect(ambiguous.error, contains('exactly once'));
  });

  test('apply_patch obeys folder-jail and whole-disk scope', () async {
    final sandbox = await Directory.systemTemp.createTemp('waifu_patch_scope_');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });
    final root = await Directory(p.join(sandbox.path, 'project')).create();
    final outside = File(p.join(sandbox.path, 'outside.txt'));
    await outside.writeAsString('before\n');
    const args = {'path': '../outside.txt', 'patch': '@@\n-before\n+after\n'};

    final jailed = await WaifuFs(
      root.path,
      pathMode: WaifuPathMode.folderJail,
    ).dispatch(kWaifuToolApplyPatch, args);
    expect(jailed.ok, isFalse);
    expect(await outside.readAsString(), 'before\n');

    final open = await WaifuFs(
      root.path,
      pathMode: WaifuPathMode.wholeDisk,
    ).dispatch(kWaifuToolApplyPatch, args);
    expect(open.ok, isTrue);
    expect(open.write, isNotNull);
    expect(await outside.readAsString(), 'after\n');
  });

  test('Plan blocks apply_patch and the model sees its schema', () {
    final permissions = WaifuPermissions(mode: WaifuMode.plan);
    expect(
      permissions.hardBlock(
        name: kWaifuToolApplyPatch,
        args: const {'path': 'a.txt', 'patch': '@@\n-a\n+b\n'},
      ),
      isNotNull,
    );
    final names = [
      for (final tool in waifuFileToolsFor(WaifuPathMode.folderJail))
        (tool['function'] as Map)['name'],
    ];
    expect(names, contains(kWaifuToolApplyPatch));
  });
}
