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

import 'package:front_porch_ai/services/waifu/waifu_plan.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';
import 'package:front_porch_ai/services/waifu/waifu_todos.dart';
import 'package:path/path.dart' as p;

WaifuPlanStatus waifuPlanStatusFrom(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'accepted':
      return WaifuPlanStatus.accepted;
    case 'superseded':
      return WaifuPlanStatus.superseded;
    case 'discarded':
      return WaifuPlanStatus.discarded;
    default:
      return WaifuPlanStatus.draft;
  }
}

String waifuPlanEncode(WaifuPlan plan) {
  final buf = StringBuffer()
    ..writeln('---')
    ..writeln('id: ${plan.id}')
    ..writeln('slug: ${plan.slug}')
    ..writeln('title: ${plan.title}')
    ..writeln('goal: ${plan.goal}')
    ..writeln('status: ${plan.status.name}');
  _yamlList(buf, 'assumptions', plan.assumptions);
  _yamlList(buf, 'constraints', plan.constraints);
  _yamlList(buf, 'risks', plan.risks);
  _yamlList(buf, 'openQuestions', plan.openQuestions);
  buf.writeln('steps:');
  if (plan.steps.isEmpty) {
    buf.writeln('  []');
  }
  for (final step in plan.steps) {
    buf
      ..writeln('- id: ${step.id}')
      ..writeln('  title: ${step.title}')
      ..writeln('  detail: ${step.detail}')
      ..writeln('  verify: ${step.verify}')
      ..writeln('  status: ${step.status}')
      ..writeln('  files:');
    if (step.files.isEmpty) {
      buf.writeln('    []');
    } else {
      for (final f in step.files) {
        buf.writeln('    - $f');
      }
    }
  }
  buf
    ..writeln('---')
    ..writeln()
    ..write(plan.body.trimRight());
  if (plan.body.isNotEmpty && !plan.body.endsWith('\n')) buf.writeln();
  return buf.toString();
}

void _yamlList(StringBuffer buf, String key, List<String> items) {
  buf.writeln('$key:');
  if (items.isEmpty) {
    buf.writeln('  []');
    return;
  }
  for (final item in items) {
    buf.writeln('- $item');
  }
}

WaifuPlan waifuPlanParse(String raw, {String relativePath = ''}) {
  final trimmed = raw.replaceFirst(RegExp(r'^\uFEFF'), '');
  var matter = <String, dynamic>{};
  var body = trimmed;
  if (trimmed.startsWith('---')) {
    final end = trimmed.indexOf(RegExp(r'\n---\s*(?:\n|$)'), 3);
    if (end > 0) {
      matter = _parseYamlMap(trimmed.substring(3, end));
      body = trimmed.substring(end).replaceFirst(RegExp(r'^\n---\s*\n?'), '');
    }
  }
  final slugRaw = matter['slug']?.toString() ?? '';
  final title = matter['title']?.toString().trim().isNotEmpty == true
      ? matter['title'].toString().trim()
      : _heading(body);
  final slug = waifuPlanSlug(slugRaw.isEmpty ? title : slugRaw);
  final id = matter['id']?.toString().trim().isNotEmpty == true
      ? matter['id'].toString().trim()
      : slug;
  return WaifuPlan(
    id: id,
    slug: slug,
    title: title.isEmpty ? slug : title,
    goal: matter['goal']?.toString().trim() ?? '',
    status: waifuPlanStatusFrom(matter['status']?.toString() ?? 'draft'),
    assumptions: _stringList(matter['assumptions']),
    constraints: _stringList(matter['constraints']),
    risks: _stringList(matter['risks']),
    openQuestions: _stringList(
      matter['openQuestions'] ?? matter['open_questions'],
    ),
    steps: _steps(matter['steps']),
    body: body.trim(),
    relativePath: relativePath.isEmpty
        ? waifuPlanRelativePath(slug)
        : relativePath,
  );
}

String _heading(String body) {
  for (final line in body.split('\n')) {
    final t = line.trim();
    if (t.startsWith('# ')) return t.substring(2).trim();
  }
  return '';
}

List<String> _stringList(Object? raw) {
  if (raw is List) {
    return [
      for (final e in raw)
        if (e != null && e.toString().trim().isNotEmpty) e.toString().trim(),
    ];
  }
  if (raw is String && raw.trim().isNotEmpty && raw.trim() != '[]') {
    return raw
        .split(RegExp(r'\s*\|\s*'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return const [];
}

List<WaifuPlanStep> _steps(Object? raw) {
  if (raw is! List) return const [];
  final out = <WaifuPlanStep>[];
  for (var i = 0; i < raw.length; i++) {
    final e = raw[i];
    if (e is String && e.trim().isNotEmpty) {
      out.add(WaifuPlanStep(id: 's${i + 1}', title: e.trim()));
      continue;
    }
    if (e is! Map) continue;
    final files = _stringList(e['files']);
    final id = e['id']?.toString().trim();
    final title = e['title']?.toString().trim() ?? '';
    if ((id == null || id.isEmpty) && title.isEmpty) continue;
    out.add(
      WaifuPlanStep(
        id: (id == null || id.isEmpty) ? 's${i + 1}' : id,
        title: title.isEmpty ? (id ?? 's${i + 1}') : title,
        detail: e['detail']?.toString() ?? '',
        files: files,
        verify: e['verify']?.toString() ?? '',
        status: e['status']?.toString() ?? 'pending',
      ),
    );
  }
  return out;
}

Map<String, dynamic> _parseYamlMap(String raw) => _YamlMini(raw).parseMap(0);

class _YamlMini {
  _YamlMini(String raw) : lines = raw.split('\n');

  final List<String> lines;
  var i = 0;

  int _indentOf(String line) => line.length - line.trimLeft().length;

  Object? parseScalar(String text) {
    final t = text.trim();
    if (t.isEmpty || t == '[]') return <dynamic>[];
    if (t.startsWith('[') && t.endsWith(']')) {
      return [
        for (final part in t.substring(1, t.length - 1).split(','))
          if (part.trim().isNotEmpty) part.trim(),
      ];
    }
    return t;
  }

  List<dynamic> parseList(int minIndent) {
    final list = <dynamic>[];
    while (i < lines.length) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        i++;
        continue;
      }
      final indent = _indentOf(line);
      if (indent < minIndent) break;
      final trimmed = line.trimLeft();
      if (!trimmed.startsWith('- ')) break;
      final rest = trimmed.substring(2);
      i++;
      if (rest.contains(':')) {
        final colon = rest.indexOf(':');
        final map = <String, dynamic>{
          rest.substring(0, colon).trim(): parseScalar(
            rest.substring(colon + 1),
          ),
        };
        map.addAll(parseMap(indent + 1));
        list.add(map);
      } else {
        list.add(rest.trim());
      }
    }
    return list;
  }

  Map<String, dynamic> parseMap(int minIndent) {
    final map = <String, dynamic>{};
    while (i < lines.length) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        i++;
        continue;
      }
      final indent = _indentOf(line);
      if (indent < minIndent) break;
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('- ')) break;
      final colon = trimmed.indexOf(':');
      if (colon < 0) {
        i++;
        continue;
      }
      final key = trimmed.substring(0, colon).trim();
      final rest = trimmed.substring(colon + 1);
      i++;
      if (rest.trim().isNotEmpty) {
        map[key] = parseScalar(rest);
        continue;
      }
      if (i < lines.length && lines[i].trimLeft().startsWith('- ')) {
        map[key] = parseList(indent);
      } else if (i < lines.length && _indentOf(lines[i]) > indent) {
        map[key] = parseMap(indent + 1);
      } else {
        map[key] = '';
      }
    }
    return map;
  }
}

Future<void> waifuWritePlanFile(String root, WaifuPlan plan) async {
  final rel = plan.relativePath.isEmpty
      ? waifuPlanRelativePath(plan.slug)
      : plan.relativePath;
  final file = File(p.join(root, rel));
  await file.parent.create(recursive: true);
  await file.writeAsString(waifuPlanEncode(plan.copyWith(relativePath: rel)));
}

Future<WaifuPlan?> waifuReadPlanFile(String root, String relative) async {
  final file = File(p.join(root, relative));
  if (!await file.exists()) return null;
  return waifuPlanParse(
    await file.readAsString(),
    relativePath: relative.replaceAll('\\', '/'),
  );
}

Future<WaifuPlan?> waifuLoadActivePlan(WaifuSession session) async {
  final pinned = session.activePlanPath?.trim();
  if (pinned != null && pinned.isNotEmpty) {
    final hit = await waifuReadPlanFile(session.folderRoot, pinned);
    if (hit != null) return hit;
  }
  return waifuDiscoverLatestPlan(session.folderRoot);
}

Future<WaifuPlan?> waifuDiscoverLatestPlan(String root) async {
  final dir = Directory(waifuPlansDir(root));
  if (!await dir.exists()) return null;
  final files = <File>[];
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.md')) {
      files.add(entity);
    }
  }
  if (files.isEmpty) return null;
  DateTime newestStamp = DateTime.fromMillisecondsSinceEpoch(0);
  File? newest;
  for (final file in files) {
    final stamp = await file.lastModified();
    if (newest == null || stamp.isAfter(newestStamp)) {
      newest = file;
      newestStamp = stamp;
    }
  }
  if (newest == null) return null;
  final rel = p.relative(newest.path, from: root).replaceAll('\\', '/');
  return waifuPlanParse(await newest.readAsString(), relativePath: rel);
}

void waifuSyncPlanTodos(WaifuTodos todos, WaifuPlan plan) {
  todos.write([
    for (final step in plan.steps)
      {'id': step.id, 'content': step.title, 'status': step.status},
  ]);
}

Future<WaifuPlan?> waifuAcceptPlan({
  required WaifuSession session,
  required WaifuTodos todos,
  String? editedBody,
}) async {
  var plan = await waifuLoadActivePlan(session);
  if (plan == null) return null;
  if (editedBody != null) {
    plan = waifuPlanParse(editedBody, relativePath: plan.relativePath);
  }
  final next = plan.copyWith(status: WaifuPlanStatus.accepted);
  await waifuWritePlanFile(session.folderRoot, next);
  session.activePlanPath = next.relativePath;
  session.mode = WaifuMode.build;
  waifuSyncPlanTodos(todos, next);
  return next;
}

Future<WaifuPlan?> waifuRevisePlan({
  required WaifuSession session,
  String? editedBody,
}) async {
  var plan = await waifuLoadActivePlan(session);
  if (plan == null) return null;
  if (editedBody != null) {
    plan = waifuPlanParse(editedBody, relativePath: plan.relativePath);
  }
  final next = plan.copyWith(status: WaifuPlanStatus.draft);
  await waifuWritePlanFile(session.folderRoot, next);
  session.activePlanPath = next.relativePath;
  session.mode = WaifuMode.plan;
  return next;
}

Future<void> waifuDiscardPlan(WaifuSession session) async {
  final plan = await waifuLoadActivePlan(session);
  if (plan != null) {
    await waifuWritePlanFile(
      session.folderRoot,
      plan.copyWith(status: WaifuPlanStatus.discarded),
    );
  }
  session.activePlanPath = null;
}

Future<String> waifuPlanPromptBlock({
  required String root,
  required WaifuMode mode,
  String? activePlanPath,
}) async {
  if (mode == WaifuMode.plan) return '';
  if (activePlanPath == null || activePlanPath.trim().isEmpty) return '';
  final plan = await waifuReadPlanFile(root, activePlanPath);
  if (plan == null || plan.status != WaifuPlanStatus.accepted) return '';
  final encoded = waifuPlanEncode(plan);
  final digest = waifuPlanDigest(encoded);
  final buf = StringBuffer()
    ..writeln('ACCEPTED PLAN: ${plan.relativePath}')
    ..writeln('digest: $digest')
    ..writeln('title: ${plan.title}')
    ..writeln('goal: ${plan.goal}');
  if (plan.steps.isNotEmpty) {
    buf.writeln('steps:');
    for (final step in plan.steps) {
      buf.writeln('- ${step.id} [${step.status}] ${step.title}');
      if (step.detail.isNotEmpty) buf.writeln('  ${step.detail}');
      if (step.files.isNotEmpty) {
        buf.writeln('  files: ${step.files.join(', ')}');
      }
      if (step.verify.isNotEmpty) buf.writeln('  verify: ${step.verify}');
    }
  }
  if (encoded.length <= 8000) {
    buf
      ..writeln()
      ..writeln(encoded);
  }
  return buf.toString().trimRight();
}
