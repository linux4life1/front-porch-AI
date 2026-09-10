// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/ui/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Build whole-disk still asks off-porch writes; Yolo allows', () {
    const root = '/tmp/waifu-porch';
    final build = WaifuPermissions(
      mode: WaifuMode.build,
      workingDirectory: root,
      pathMode: WaifuPathMode.wholeDisk,
    );
    expect(
      build.needsAsk(
        name: 'write',
        args: {'path': '../sibling/file.txt', 'contents': 'x'},
      ),
      isTrue,
    );
    expect(
      build.needsAsk(name: 'write', args: {'path': 'in.txt', 'contents': 'x'}),
      isFalse,
    );
    final yolo = WaifuPermissions(
      mode: WaifuMode.yolo,
      workingDirectory: root,
      pathMode: WaifuPathMode.wholeDisk,
    );
    expect(
      yolo.needsAsk(
        name: 'write',
        args: {'path': '../sibling/file.txt', 'contents': 'x'},
      ),
      isFalse,
    );
    expect(
      yolo.needsAsk(name: 'write', args: {'path': '.env', 'contents': 'x'}),
      isFalse,
    );
    expect(
      yolo.hardBlock(name: 'write', args: {'path': '.env', 'contents': 'x'}),
      isNotNull,
    );
  });

  test(r'$PWD is rewritten then jailed; leftover $ is denied', () async {
    final root = await Directory.systemTemp.createTemp('waifu_pwd_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await Directory(p.join(root.path, 'src')).create();
    for (final command in [
      r'cd $PWD/.. && pwd',
      r'cd ${PWD}/.. && pwd',
      r'cat $PWD/../outside.txt',
      r'cd $HOME && pwd',
    ]) {
      expect(
        await waifuBashScopeBlock(command, root.path, WaifuPathMode.folderJail),
        isNotNull,
        reason: command,
      );
    }
    expect(
      await waifuBashScopeBlock(
        'cd src && ls',
        root.path,
        WaifuPathMode.folderJail,
      ),
      isNull,
    );
    expect(waifuRewriteBashPathAliases(r'cd $PWD/..'), 'cd ./..');
  });

  testWidgets('Jail/Disk chips stay enabled while the turn is running', (
    tester,
  ) async {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    )..running = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WaifuModeBar(
            mode: session.mode,
            pathMode: session.pathMode,
            enabled: !session.running,
            pathEnabled: true,
            onChanged: (_) {},
            onPathMode: (scope) => session.pathMode = scope,
          ),
        ),
      ),
    );
    final disk = tester.widget<ChoiceChip>(
      find.byKey(const Key('waifu-path-mode-wholeDisk')),
    );
    expect(disk.onSelected, isNotNull);
    final plan = tester.widget<ChoiceChip>(
      find.byKey(const Key('waifu-mode-plan')),
    );
    expect(plan.onSelected, isNull);
  });

  test('Yolo still does not ask on the 3rd identical tool', () {
    final p = WaifuPermissions(mode: WaifuMode.yolo);
    const args = {'path': 'a.txt', 'contents': 'x'};
    p.record(name: 'write', args: args);
    p.record(name: 'write', args: args);
    expect(p.needsAsk(name: 'write', args: args), isFalse);
  });
}
