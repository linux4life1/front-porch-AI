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

import 'dart:convert';
import 'dart:io';

import 'package:front_porch_ai/services/waifu/waifu_brand.dart';
import 'package:front_porch_ai/services/waifu/waifu_skills.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

const kWaifuAnthropicSkillsApi =
    'https://api.github.com/repos/anthropics/skills/contents/skills';
const kWaifuAnthropicSkillsRaw =
    'https://raw.githubusercontent.com/anthropics/skills/main';

/// Allowlisted HTTPS catalogs only. No git clone, no random GitHub.
class WaifuSkillSource {
  const WaifuSkillSource({
    required this.id,
    required this.label,
    required this.repo,
    this.folder = 'skills',
    this.branch = 'main',
  });

  final String id;
  final String label;
  final String repo;
  final String folder;
  final String branch;

  String get api =>
      'https://api.github.com/repos/$repo/contents${folder.isEmpty ? '' : '/$folder'}';

  String get raw =>
      'https://raw.githubusercontent.com/$repo/$branch${folder.isEmpty ? '' : '/$folder'}';
}

const kWaifuSkillSources = <WaifuSkillSource>[
  WaifuSkillSource(
    id: 'anthropic',
    label: 'Anthropic',
    repo: 'anthropics/skills',
  ),
  WaifuSkillSource(
    id: 'vercel',
    label: 'Vercel',
    repo: 'vercel-labs/agent-skills',
  ),
  WaifuSkillSource(
    id: 'superpowers',
    label: 'Superpowers',
    repo: 'obra/superpowers',
  ),
];

const _skipDirs = {
  'scripts',
  'packages',
  'docs',
  'tests',
  'assets',
  'hooks',
  'spec',
  'template',
  'node_modules',
};

const _ua = {
  'User-Agent': 'FrontPorchAI-WaifuCoder',
  'Accept': 'application/vnd.github+json',
};

class WaifuMarketSkill {
  const WaifuMarketSkill({
    required this.name,
    required this.apiPath,
    this.sourceId = 'anthropic',
    this.sourceLabel = 'Anthropic',
  });

  final String name;
  final String apiPath;
  final String sourceId;
  final String sourceLabel;
}

typedef WaifuHttpGet = Future<http.Response> Function(Uri uri);

/// Official Claude skills marketplace: github.com/anthropics/skills.
/// HTTPS only — no git clone, no plugin CLI.
class WaifuSkillMarket {
  WaifuSkillMarket({WaifuHttpGet? get}) : _get = get ?? _defaultGet;

  final WaifuHttpGet _get;
  List<WaifuMarketSkill> catalog = const [];

  static Future<http.Response> _defaultGet(Uri uri) =>
      http.get(uri, headers: _ua);

  Future<List<WaifuMarketSkill>> refresh() async {
    final seen = <String>{};
    final out = <WaifuMarketSkill>[];
    final errors = <String>[];
    for (final src in kWaifuSkillSources) {
      try {
        for (final skill in await _list(src)) {
          if (!seen.add(skill.name)) continue;
          out.add(skill);
        }
      } catch (e) {
        errors.add('${src.id}: $e');
      }
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    catalog = out;
    if (out.isEmpty && errors.isNotEmpty) {
      throw StateError(errors.join('; '));
    }
    return catalog;
  }

  Future<List<WaifuMarketSkill>> _list(WaifuSkillSource src) async {
    final res = await _get(Uri.parse(src.api));
    if (res.statusCode != 200) {
      throw StateError('HTTP ${res.statusCode}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! List) return const [];
    final out = <WaifuMarketSkill>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      if (item['type'] != 'dir') continue;
      final name = item['name']?.toString() ?? '';
      final path = item['path']?.toString() ?? '';
      if (!waifuSkillNameOk(name) ||
          name.startsWith('.') ||
          _skipDirs.contains(name)) {
        continue;
      }
      out.add(
        WaifuMarketSkill(
          name: name,
          apiPath: path,
          sourceId: src.id,
          sourceLabel: src.label,
        ),
      );
    }
    return out;
  }

  /// Download SKILL.md (and sibling files) into [destDir]/[name].
  Future<String> install({
    required String name,
    required String destDir,
  }) async {
    if (!waifuSkillNameOk(name)) return 'skill_install: bad name';
    WaifuSkillSource? preferred;
    for (final s in catalog) {
      if (s.name != name) continue;
      for (final src in kWaifuSkillSources) {
        if (src.id == s.sourceId) preferred = src;
      }
      break;
    }
    final order = [
      ?preferred,
      for (final src in kWaifuSkillSources)
        if (src.id != preferred?.id) src,
    ];
    String last = 'skill_install: $name not on the allowlisted catalogs';
    for (final src in order) {
      last = await _installFrom(src, name, destDir);
      if (last.startsWith('installed')) return last;
    }
    return last;
  }

  Future<String> _installFrom(
    WaifuSkillSource src,
    String name,
    String destDir,
  ) async {
    final listing = await _get(Uri.parse('${src.api}/$name'));
    if (listing.statusCode != 200) {
      return 'skill_install: $name not on ${src.repo} '
          '(HTTP ${listing.statusCode})';
    }
    final decoded = jsonDecode(listing.body);
    if (decoded is! List) return 'skill_install: unexpected listing';
    final dir = Directory(p.join(destDir, name));
    await dir.create(recursive: true);
    var wrote = 0;
    var hasSkill = false;
    for (final item in decoded) {
      if (item is! Map) continue;
      if (item['type'] != 'file') continue;
      final fileName = item['name']?.toString() ?? '';
      if (fileName.isEmpty || fileName.contains('..')) continue;
      final url = item['download_url']?.toString();
      if (url == null || url.isEmpty) continue;
      final body = await _get(Uri.parse(url));
      if (body.statusCode != 200) continue;
      if (body.bodyBytes.length > 512 * 1024) continue;
      await File(p.join(dir.path, fileName)).writeAsBytes(body.bodyBytes);
      wrote++;
      if (fileName == 'SKILL.md') hasSkill = true;
    }
    if (!hasSkill) {
      final raw = await _get(Uri.parse('${src.raw}/$name/SKILL.md'));
      if (raw.statusCode == 200) {
        await File(p.join(dir.path, 'SKILL.md')).writeAsString(raw.body);
        wrote++;
        hasSkill = true;
      }
    }
    if (!hasSkill) return 'skill_install: no SKILL.md for $name';
    return 'installed $name ($wrote files) to ${dir.path}';
  }
}

/// Local install list + official catalog. Shared by the harness, /skills,
/// and the sidebar marketplace.
class WaifuSkillHub {
  WaifuSkillHub({
    required this.projectRoot,
    this.userSkillsDir,
    WaifuSkillMarket? market,
  }) : market = market ?? WaifuSkillMarket();

  final String projectRoot;
  final String? userSkillsDir;
  final WaifuSkillMarket market;
  List<WaifuSkillMeta> installed = const [];
  String error = '';

  String get destDir {
    final user = userSkillsDir?.trim() ?? '';
    if (user.isNotEmpty) return user;
    return p.join(projectRoot, kWaifuDotDir, 'skills');
  }

  String get catalogPrompt =>
      waifuSkillCatalogPrompt(installed, oursDir: destDir);

  Set<String> get installedNames => {for (final s in installed) s.name};

  bool _ours(WaifuSkillMeta s) => waifuSkillIsOurs(s.filePath);

  List<WaifuSkillMeta> get porchInstalled => [
    for (final s in installed)
      if (_ours(s)) s,
  ];

  List<WaifuSkillMeta> get diskInstalled => [
    for (final s in installed)
      if (!_ours(s)) s,
  ];

  Future<void> refreshLocal() async {
    await waifuEnsureSkillsDir(destDir);
    final projectDir = p.join(projectRoot, kWaifuDotDir, 'skills');
    if (destDir != projectDir) {
      await Directory(projectDir).create(recursive: true);
    }
    installed = await waifuListLocalSkills(projectRoot, storeDir: userSkillsDir);
  }

  Future<void> refreshMarket() async {
    error = '';
    try {
      await market.refresh();
    } catch (e) {
      error = '$e';
    }
  }

  Future<String> install(String name) async {
    final out = await market.install(name: name.trim(), destDir: destDir);
    await refreshLocal();
    return out;
  }

  Future<String> load(String name) =>
      waifuLoadSkill(projectRoot, name, storeDir: userSkillsDir);

  String listing() {
    final buf = StringBuffer()
      ..writeln(
        'Skills — allowlisted HTTPS catalogs: anthropics/skills, '
        'vercel-labs/agent-skills, obra/superpowers.',
      )
      ..writeln('$kWaifuCoderName skills folder: $destDir')
      ..writeln(
        'Say “install the pdf skill”, type /skills pdf, or tap Install '
        'in the sidebar.',
      )
      ..writeln();
    if (installed.isEmpty) {
      buf.writeln('Installed: none');
    } else {
      buf.writeln('Installed:');
      for (final s in installed) {
        buf.writeln('  ${s.name}');
      }
    }
    buf.writeln();
    if (error.isNotEmpty) {
      buf.writeln('Catalog: $error');
    } else if (market.catalog.isEmpty) {
      buf.writeln(
        'Official catalog not loaded. /skills or Refresh in the sidebar.',
      );
    } else {
      buf.writeln('Official catalog:');
      for (final s in market.catalog) {
        final mark = installedNames.contains(s.name) ? ' (installed)' : '';
        buf.writeln('  ${s.name}$mark');
      }
    }
    return buf.toString().trimRight();
  }
}
