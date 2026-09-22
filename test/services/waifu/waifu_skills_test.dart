// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Library skills/ is Waifu-only. OpenCode is seated via skills.paths.
//
// Proven red: skillsDir did not exist on AppDirectories / sandbox.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai_waifu_skills_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('sandbox and ensureSkillsDir create library/skills', () {
    final storage = StorageService.sandbox(root.path);
    expect(storage.skillsDir.existsSync(), isTrue);
    expect(storage.skillsDir.path, endsWith('${Platform.pathSeparator}skills'));

    final missing = Directory('${root.path}/moved-skills');
    expect(missing.existsSync(), isFalse);
    expect(ensureSkillsDir(missing).existsSync(), isTrue);
    expect(kRootDirsToMove, contains('skills'));
  });

  test(
    'a fixture SKILL.md is listed and seated on isolated OpenCode config',
    () {
      final dirs = AppDirectories(rootPath: root.path, customModelsPath: null);
      final skillDir = Directory('${dirs.skillsDir.path}/git-release');
      skillDir.createSync(recursive: true);
      File('${skillDir.path}/SKILL.md').writeAsStringSync(
        '---\n'
        'name: git-release\n'
        'description: Cut a tagged release.\n'
        '---\n'
        '\n'
        'Use the project tag script. Works from any language.\n',
      );

      final found = listLibrarySkills(dirs.skillsDir);
      expect(found, hasLength(1));
      expect(found.single.name, 'git-release');
      expect(found.single.description, contains('tagged release'));
      expect(found.single.skillFile.existsSync(), isTrue);

      final cfg = buildOpenCodeConfigMap(
        agentPrompt: 'Name: Mira',
        baseUrl: 'http://127.0.0.1:5001/v1',
        apiKey: 'x',
        modelId: 'local',
        permission: openCodePermissionMap(folderJail: true, yolo: false),
        skills: openCodeSkillsConfig(dirs.skillsDir),
      );
      expect((cfg['skills'] as Map)['paths'], [dirs.skillsDir.path]);
      expect(
        (cfg['permission'] as Map)['skill'],
        'ask',
        reason: 'ask stays honest unless YOLO',
      );
      expect(
        openCodePermissionMap(folderJail: true, yolo: true)['skill'],
        'allow',
      );
    },
  );

  test(
    'copySkillSourcesIntoLibrary copies the SKILL.md folder, not stray md',
    () {
      final src = Directory('${root.path}/src/polyglot-lint');
      src.createSync(recursive: true);
      File('${src.path}/SKILL.md').writeAsStringSync(
        '---\nname: polyglot-lint\ndescription: Lint any language.\n---\n',
      );
      File('${src.path}/notes.md').writeAsStringSync('not a skill');
      final stray = File('${root.path}/readme.md')..writeAsStringSync('nope');

      final dest = Directory('${root.path}/skills');
      final copied = copySkillSourcesIntoLibrary(dest, [
        File('${src.path}/SKILL.md').path,
        stray.path,
      ]);
      expect(copied, 1);
      expect(File('${dest.path}/polyglot-lint/SKILL.md').existsSync(), isTrue);
      expect(File('${dest.path}/readme.md').existsSync(), isFalse);
    },
  );
}
