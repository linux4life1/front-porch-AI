// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('desk_skill_roots_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('install writes ~/.waifu-style dest, not .desk', () async {
    final store = Directory(p.join(root.path, 'user-skills'));
    final hub = DeskSkillHub(
      projectRoot: p.join(root.path, 'proj'),
      userSkillsDir: store.path,
    );
    await Directory(hub.projectRoot).create(recursive: true);
    await hub.refreshLocal();
    expect(hub.destDir, store.path);
    expect(await File(p.join(store.path, 'README.md')).exists(), isTrue);
    expect(hub.catalogPrompt, contains(store.path));
    expect(hub.catalogPrompt, isNot(contains('.desk/skills')));
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
    final body = await deskLoadSkill(root.path, 'mac-session-ops');
    expect(body, contains('nested hermes'));
  });

  test('legacy .desk/skills still lists as ours', () async {
    final dir = Directory(p.join(root.path, '.desk', 'skills', 'review'));
    await dir.create(recursive: true);
    await File(p.join(dir.path, 'SKILL.md')).writeAsString(
      '---\nname: review\ndescription: Be terse.\n---\nBe terse.\n',
    );
    final listed = await deskListLocalSkills(root.path);
    expect(listed.map((s) => s.name), contains('review'));
    expect(deskSkillIsOurs(listed.single.filePath), isTrue);
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
      final listed = await deskListLocalSkills(root.path);
      expect(listed.map((s) => s.name), isEmpty);
    },
  );

  test('empty catalog names the waifu folder, not desk', () {
    final prompt = deskSkillCatalogPrompt(
      const [],
      oursDir: '/tmp/.waifu/skills',
    );
    expect(prompt, contains('/tmp/.waifu/skills'));
    expect(prompt, contains(kWaifuCoderName));
    expect(prompt, isNot(contains('.desk')));
  });
}
