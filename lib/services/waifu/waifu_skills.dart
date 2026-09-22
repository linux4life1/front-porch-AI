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

/// One OpenCode-style skill folder: `<library>/skills/<name>/SKILL.md`.
class LibrarySkill {
  const LibrarySkill({
    required this.name,
    required this.description,
    required this.directory,
    required this.skillFile,
  });

  final String name;
  final String description;
  final Directory directory;
  final File skillFile;
}

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

/// Discover `*/SKILL.md` (any language). Frontmatter is optional.
List<LibrarySkill> listLibrarySkills(Directory skillsDir) {
  ensureSkillsDir(skillsDir);
  List<FileSystemEntity> entries;
  try {
    entries = skillsDir.listSync(followLinks: false);
  } catch (e) {
    debugPrint('[Skills] could not list ${skillsDir.path}: $e');
    return const [];
  }
  final out = <LibrarySkill>[];
  for (final entity in entries) {
    if (entity is! Directory) continue;
    final skillFile = File(p.join(entity.path, 'SKILL.md'));
    if (!skillFile.existsSync()) continue;
    String raw;
    try {
      raw = skillFile.readAsStringSync();
    } catch (e) {
      debugPrint('[Skills] skip ${p.basename(entity.path)}: $e');
      continue;
    }
    final parsed = _frontmatter(raw);
    final folder = p.basename(entity.path);
    out.add(
      LibrarySkill(
        name: parsed.name.isEmpty ? folder : parsed.name,
        description: parsed.description,
        directory: entity,
        skillFile: skillFile,
      ),
    );
  }
  return out;
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

({String name, String description}) _frontmatter(String raw) {
  var name = '';
  var description = '';
  if (!raw.startsWith('---')) return (name: name, description: description);
  final end = raw.indexOf('\n---', 3);
  if (end < 0) return (name: name, description: description);
  final block = raw.substring(3, end);
  for (final line in block.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('name:')) {
      name = trimmed.substring(5).trim();
    } else if (trimmed.startsWith('description:')) {
      description = trimmed.substring(12).trim();
    }
  }
  return (name: name, description: description);
}
