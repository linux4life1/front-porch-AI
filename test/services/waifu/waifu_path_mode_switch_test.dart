// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  const jail = WaifuPorchConsent(
    pathMode: WaifuPathMode.folderJail,
    honestyAccepted: true,
  );
  const disk = WaifuPorchConsent(
    pathMode: WaifuPathMode.wholeDisk,
    honestyAccepted: true,
  );

  test('honesty skip is per scope; jail is always skippable after consent', () {
    expect(
      waifuHideHonestyForScope(
        consent: jail,
        pathMode: WaifuPathMode.folderJail,
      ),
      isTrue,
    );
    expect(
      waifuHideHonestyForScope(
        consent: jail,
        pathMode: WaifuPathMode.wholeDisk,
      ),
      isFalse,
    );
    expect(
      waifuHideHonestyForScope(
        consent: disk,
        pathMode: WaifuPathMode.wholeDisk,
      ),
      isTrue,
    );
    expect(
      waifuHideHonestyForScope(
        consent: disk,
        pathMode: WaifuPathMode.folderJail,
      ),
      isTrue,
    );
    expect(
      waifuHideHonestyForScope(
        consent: null,
        pathMode: WaifuPathMode.folderJail,
      ),
      isFalse,
    );
  });

  test('fs pathMode can leave jail and return', () async {
    final sandbox = await Directory.systemTemp.createTemp('waifu_switch_fs_');
    addTearDown(() async {
      if (await sandbox.exists()) await sandbox.delete(recursive: true);
    });
    final root = await Directory(p.join(sandbox.path, 'project')).create();
    final outside = File(p.join(sandbox.path, 'outside.txt'));
    await outside.writeAsString('ordinary outside file');
    final fs = WaifuFs(root.path);
    expect(fs.pathMode, WaifuPathMode.folderJail);
    expect((await fs.dispatch('read', {'path': '../outside.txt'})).ok, isFalse);
    fs.pathMode = WaifuPathMode.wholeDisk;
    final open = await fs.dispatch('read', {'path': '../outside.txt'});
    expect(open.ok, isTrue);
    expect(open.output, contains('ordinary outside file'));
    fs.pathMode = WaifuPathMode.folderJail;
    expect((await fs.dispatch('read', {'path': '../outside.txt'})).ok, isFalse);
  });

  test('applyPathMode writes session, fs, bash, and permissions', () {
    final session = WaifuSession(
      folderRoot: '/tmp/throwaway-waifu',
      coworker: CharacterCard(name: 'Iris'),
    );
    final harness = WaifuHarness(
      session: session,
      llm: ScriptedWaifuLlm(const [LlmToolResponse(calls: [], text: 'idle')]),
    );
    expect(session.pathMode, WaifuPathMode.folderJail);
    harness.applyPathMode(WaifuPathMode.wholeDisk);
    expect(session.pathMode, WaifuPathMode.wholeDisk);
    expect(harness.fs.pathMode, WaifuPathMode.wholeDisk);
    expect(harness.bash.pathMode, WaifuPathMode.wholeDisk);
    expect(harness.permissions.pathMode, WaifuPathMode.wholeDisk);
    harness.applyPathMode(WaifuPathMode.folderJail);
    expect(session.pathMode, WaifuPathMode.folderJail);
    expect(harness.fs.pathMode, WaifuPathMode.folderJail);
  });
}
