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

import 'package:front_porch_ai/services/desk/desk_brand.dart';
import 'package:front_porch_ai/services/desk/desk_jail.dart';
import 'package:front_porch_ai/services/desk/desk_tools.dart';
import 'package:path/path.dart' as p;

const kDeskSkillScanMaxDepth = 4;

const _skipSkillDirs = {
  'node_modules',
  'scripts',
  'packages',
  'docs',
  'tests',
  'assets',
  'hooks',
  'spec',
  'template',
};

const kDeskAgentsTemplate =
    '# AGENTS.md\n\n'
    'This is a Waifu Coder project. Prefer small diffs. Stay in character.\n'
    'Do not invent files you did not read.\n';

const kDeskAgentsPath = 'AGENTS.md';

class DeskSkillMeta {
  const DeskSkillMeta({
    required this.name,
    required this.description,
    required this.filePath,
  });

  final String name;
  final String description;
  final String filePath;
}

bool deskSkillNameOk(String name) {
  final t = name.trim();
  if (t.isEmpty || t.contains('..') || t.contains('/') || t.contains('\\')) {
    return false;
  }
  return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(t);
}

/// YAML frontmatter name + description. Progressive disclosure.
(String name, String description) deskParseSkillFrontmatter(String body) {
  var name = '';
  var description = '';
  if (!body.startsWith('---')) return (name, description);
  final end = body.indexOf('\n---', 3);
  if (end < 0) return (name, description);
  final yaml = body.substring(3, end);
  for (final raw in yaml.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('name:')) {
      name = line.substring(5).trim().replaceAll('"', '');
    } else if (line.startsWith('description:')) {
      description = line.substring(12).trim().replaceAll('"', '');
    }
  }
  return (name, description);
}

String? deskHomeDir() =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

/// `~/.waifu/skills`. Null under `flutter test` so widget tests do not
/// mkdir the real home directory.
String? deskUserSkillsDir({String? home}) {
  if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
  final h = home ?? deskHomeDir();
  if (h == null || h.isEmpty) return null;
  return p.join(h, kWaifuDotDir, 'skills');
}

bool deskSkillIsOurs(String filePath) {
  final n = filePath.replaceAll('\\', '/');
  return n.contains('/$kWaifuDotDir/skills/') ||
      n.contains('/$kWaifuLegacyDotDir/skills/');
}

bool _skipSkillDir(String name) =>
    name.startsWith('.') || _skipSkillDirs.contains(name);

/// Waifu Coder's own folders. Catalog and sidebar list these.
List<String> deskOursSkillRoots(String projectRoot, {String? storeDir}) {
  final user = storeDir ?? deskUserSkillsDir();
  return [
    p.join(projectRoot, kWaifuDotDir, 'skills'),
    p.join(projectRoot, kWaifuLegacyDotDir, 'skills'),
    if (user != null && user.isNotEmpty) user,
  ];
}

/// Other harnesses on this machine. Load-by-name, not the every-turn list
/// (Hermes alone can be a thousand SKILL.md files).
List<String> deskOtherSkillRoots(String projectRoot, {String? home}) {
  final h = home ?? deskHomeDir();
  return [
    p.join(projectRoot, '.claude', 'skills'),
    p.join(projectRoot, '.opencode', 'skills'),
    p.join(projectRoot, '.grok', 'skills'),
    p.join(projectRoot, '.hermes', 'skills'),
    p.join(projectRoot, 'skills'),
    if (h != null && h.isNotEmpty) ...[
      p.join(h, '.claude', 'skills'),
      p.join(h, '.agents', 'skills'),
      p.join(h, '.grok', 'skills'),
      p.join(h, '.grok', 'bundled', 'skills'),
      p.join(h, '.hermes', 'skills'),
      p.join(h, '.hermes', 'hermes-agent', 'skills'),
    ],
  ];
}

List<String> deskSkillSearchRoots(
  String projectRoot, {
  String? storeDir,
  bool others = true,
}) {
  final seen = <String>{};
  final out = <String>[];
  for (final root in [
    ...deskOursSkillRoots(projectRoot, storeDir: storeDir),
    if (others) ...deskOtherSkillRoots(projectRoot),
  ]) {
    final n = p.normalize(root);
    if (seen.add(n)) out.add(n);
  }
  return out;
}

Future<void> deskEnsureSkillsDir(String dir) async {
  await Directory(dir).create(recursive: true);
  final readme = File(p.join(dir, 'README.md'));
  if (await readme.exists()) return;
  await readme.writeAsString(
    '# $kWaifuCoderName skills\n\n'
    'Install from the sidebar lands here. Drop a folder that contains '
    'SKILL.md to add one. This project also reads '
    '$kWaifuDotDir/skills in the sit-down folder.\n',
  );
}

Future<List<DeskSkillMeta>> deskListLocalSkills(
  String projectRoot, {
  String? storeDir,
}) async {
  final seen = <String>{};
  final out = <DeskSkillMeta>[];
  for (final root in deskOursSkillRoots(projectRoot, storeDir: storeDir)) {
    await _walkSkillDir(Directory(root), seen: seen, out: out, depth: 0);
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

Future<void> _walkSkillDir(
  Directory dir, {
  required Set<String> seen,
  required List<DeskSkillMeta> out,
  required int depth,
}) async {
  if (depth > kDeskSkillScanMaxDepth) return;
  if (!await dir.exists()) return;
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! Directory) continue;
    final name = p.basename(entity.path);
    if (_skipSkillDir(name)) continue;
    final file = File(p.join(entity.path, 'SKILL.md'));
    if (await file.exists()) {
      if (!deskSkillNameOk(name) || seen.contains(name)) continue;
      String body;
      try {
        body = await file.readAsString();
      } catch (_) {
        continue;
      }
      final (frontName, description) = deskParseSkillFrontmatter(body);
      seen.add(name);
      out.add(
        DeskSkillMeta(
          name: frontName.isEmpty ? name : frontName,
          description: description,
          filePath: file.path,
        ),
      );
      continue;
    }
    await _walkSkillDir(entity, seen: seen, out: out, depth: depth + 1);
  }
}

String deskSkillCatalogPrompt(List<DeskSkillMeta> skills, {String? oursDir}) {
  final where = oursDir ?? '~/$kWaifuDotDir/skills';
  final otherCue =
      'Claude, Grok, and Hermes SKILL.md files on this machine also '
      'load with skill by name.';
  if (skills.isEmpty) {
    return 'No $kWaifuCoderName skills installed yet. Your skills folder is '
        '$where. Use skill_install, type /skills, or tap Skills in the '
        'sidebar. Drop SKILL.md folders there or in this project\'s '
        '$kWaifuDotDir/skills. $otherCue';
  }
  final buf = StringBuffer()
    ..writeln('$kWaifuCoderName skills folder: $where')
    ..writeln(
      'Installed skills (call skill with name=… to load the full SKILL.md):',
    );
  for (final s in skills) {
    final desc = s.description.isEmpty ? 'installed' : s.description;
    buf.writeln('- ${s.name}: $desc');
  }
  buf.writeln(otherCue);
  return buf.toString().trimRight();
}

/// Load a skill file from Waifu Coder folders or other harnesses on disk.
Future<String> deskLoadSkill(
  String root,
  String name, {
  String? storeDir,
}) async {
  final trimmed = name.trim();
  if (!deskSkillNameOk(trimmed)) {
    return 'skill not found: $name';
  }
  for (final base in deskSkillSearchRoots(root, storeDir: storeDir)) {
    final file = await _locateSkillFile(base, trimmed);
    if (file == null) continue;
    try {
      var body = await file.readAsString();
      if (body.length > kDeskReadClipChars) {
        body = '${body.substring(0, kDeskReadClipChars)}\n…(clipped)';
      }
      return body;
    } catch (_) {}
  }
  final legacy = [
    p.join(kWaifuDotDir, 'skills', trimmed, 'SKILL.md'),
    p.join(kWaifuLegacyDotDir, 'skills', trimmed, 'SKILL.md'),
    p.join('.opencode', 'skills', trimmed, 'SKILL.md'),
    p.join('skills', trimmed, 'SKILL.md'),
    'SKILL.md',
  ];
  for (final rel in legacy) {
    final hit = await DeskJail.resolveLive(root, rel);
    if (!hit.ok) continue;
    final file = File(hit.path!);
    if (!await file.exists()) continue;
    final body = await file.readAsString();
    if (body.length > kDeskReadClipChars) {
      return '${body.substring(0, kDeskReadClipChars)}\n…(clipped)';
    }
    return body;
  }
  return 'skill not found: $name';
}

Future<File?> _locateSkillFile(String base, String name) async {
  final direct = File(p.join(base, name, 'SKILL.md'));
  if (await direct.exists()) return direct;
  final dir = Directory(base);
  if (!await dir.exists()) return null;
  return _locateNamed(dir, name, 0);
}

Future<File?> _locateNamed(Directory dir, String name, int depth) async {
  if (depth > kDeskSkillScanMaxDepth) return null;
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! Directory) continue;
    final bn = p.basename(entity.path);
    if (_skipSkillDir(bn)) continue;
    if (bn == name) {
      final f = File(p.join(entity.path, 'SKILL.md'));
      if (await f.exists()) return f;
    }
    final nested = await _locateNamed(entity, name, depth + 1);
    if (nested != null) return nested;
  }
  return null;
}
