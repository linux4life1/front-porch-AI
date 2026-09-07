// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('waifu_skill_roots_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('install writes ~/.waifu-style dest, not the legacy folder', () async {
    final store = Directory(p.join(root.path, 'user-skills'));
    final hub = WaifuSkillHub(
      projectRoot: p.join(root.path, 'proj'),
      userSkillsDir: store.path,
    );
    await Directory(hub.projectRoot).create(recursive: true);
    await hub.refreshLocal();
    expect(hub.destDir, store.path);
    expect(await File(p.join(store.path, 'README.md')).exists(), isTrue);
    expect(hub.catalogPrompt, contains(store.path));
    expect(
      hub.catalogPrompt,
      isNot(contains('$kWaifuLegacyDotDir/skills')),
    );
    expect(hub.listing(), contains(store.path));
  });

  test('nested category/name/SKILL.md loads by leaf name', () async {
    final skillDir = Directory(
      p.join(root.path, '.hermes', 'skills', 'apple', 'mac-session-ops'),
    );
    await skillDir.create(recursive: true);
    await File(
      p.join(skillDir.path, 'SKILL.md'),
    ).writeAsString('---\nname: mac-session-ops\n---\n# nested hermes\n');
    final body = await waifuLoadSkill(root.path, 'mac-session-ops');
    expect(body, contains('nested hermes'));
  });

  test('legacy on-disk skills still list as ours', () async {
    final dir = Directory(
      p.join(root.path, kWaifuLegacyDotDir, 'skills', 'review'),
    );
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'SKILL.md')).writeAsString(
      '---\nname: review\ndescription: Be terse.\n---\nBe terse.\n',
    );
    final listed = await waifuListLocalSkills(root.path);
    expect(listed.map((s) => s.name), contains('review'));
    expect(waifuSkillIsOurs(listed.single.filePath), isTrue);
  });

  test(
    '.archive and other-harness dumps stay out of the catalog list',
    () async {
      final archive = Directory(
        p.join(root.path, '.waifu', 'skills', '.archive', 'old'),
      );
      await archive.create(recursive: true);
      await File(p.join(archive.path, 'SKILL.md')).writeAsString('# old\n');
      final hermes = Directory(
        p.join(root.path, '.hermes', 'skills', 'devops', 'kanban-worker'),
      );
      await hermes.create(recursive: true);
      await File(p.join(hermes.path, 'SKILL.md')).writeAsString('# hermes\n');
      final listed = await waifuListLocalSkills(root.path);
      expect(listed.map((s) => s.name), isEmpty);
    },
  );

  test('empty catalog names the waifu folder, not waifu', () {
    final prompt = waifuSkillCatalogPrompt(
      const [],
      oursDir: '/tmp/.waifu/skills',
    );
    expect(prompt, contains('/tmp/.waifu/skills'));
    expect(prompt, contains(kWaifuCoderName));
    expect(prompt, isNot(contains(kWaifuLegacyDotDir)));
  });
}
