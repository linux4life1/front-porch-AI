// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Create `<library>/skills/` if it is missing. Same on-demand rule as tools/.
Directory ensureSkillsDir(Directory skillsDir) {
  try {
    skillsDir.createSync(recursive: true);
  } catch (e) {
    debugPrint('[Skills] could not create ${skillsDir.path}: $e');
  }
  return skillsDir;
}

/// OpenCode isolated-config seat. Source (sst/opencode) reads `skills.paths`.
Map<String, dynamic> openCodeSkillsConfig(Directory skillsDir) {
  ensureSkillsDir(skillsDir);
  return {
    'paths': [skillsDir.path],
  };
}

/// Copy skill folders. A `SKILL.md` path copies its parent. Other files skip.
int copySkillSourcesIntoLibrary(
  Directory skillsDir,
  Iterable<String> sourcePaths,
) {
  ensureSkillsDir(skillsDir);
  var copied = 0;
  for (final rawPath in sourcePaths) {
    final file = File(rawPath);
    final name = p.basename(file.path);
    if (name.toLowerCase() != 'skill.md') continue;
    if (name.contains('..')) continue;
    if (!file.existsSync()) continue;
    final parent = file.parent;
    final folderName = p.basename(parent.path);
    if (folderName.isEmpty ||
        folderName == '.' ||
        folderName == '..' ||
        folderName.contains('/') ||
        folderName.contains('\\')) {
      continue;
    }
    final dest = Directory(p.join(skillsDir.path, folderName));
    try {
      _copyDir(parent, dest);
      copied++;
    } catch (e) {
      debugPrint('[Skills] copy $folderName failed: $e');
    }
  }
  return copied;
}

void _copyDir(Directory source, Directory dest) {
  dest.createSync(recursive: true);
  for (final entity in source.listSync(followLinks: false)) {
    final base = p.basename(entity.path);
    if (base == '.' || base == '..') continue;
    if (entity is File) {
      entity.copySync(p.join(dest.path, base));
    } else if (entity is Directory) {
      _copyDir(entity, Directory(p.join(dest.path, base)));
    }
  }
}
