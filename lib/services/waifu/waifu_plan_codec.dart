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

import 'package:front_porch_ai/services/waifu/waifu_plan.dart';
import 'package:front_porch_ai/services/waifu/waifu_plan_yaml.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';
import 'package:front_porch_ai/services/waifu/waifu_todos.dart';
import 'package:path/path.dart' as p;

const kWaifuPlanJsonFence = 'waifu-plan';

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
  final meta = <String, dynamic>{
    'id': plan.id,
    'slug': plan.slug,
    'title': plan.title,
    'goal': plan.goal,
    'status': plan.status.name,
    'assumptions': plan.assumptions,
    'constraints': plan.constraints,
    'risks': plan.risks,
    'openQuestions': plan.openQuestions,
    'steps': [
      for (final step in plan.steps)
        {
          'id': step.id,
          'title': step.title,
          'detail': step.detail,
          'verify': step.verify,
          'status': step.status,
          'files': step.files,
        },
    ],
  };
  final buf = StringBuffer()
    ..writeln('```$kWaifuPlanJsonFence')
    ..writeln(const JsonEncoder.withIndent('  ').convert(meta))
    ..writeln('```')
    ..writeln()
    ..write(plan.body.trimRight());
  if (plan.body.isNotEmpty && !plan.body.endsWith('\n')) buf.writeln();
  return buf.toString();
}

({Map<String, dynamic> meta, String body})? waifuPlanJsonFence(String raw) {
  final match = RegExp(
    r'^```(?:waifu-plan|json)\s*\n(.*?)\n```',
    dotAll: true,
  ).firstMatch(raw.trimLeft());
  if (match == null) return null;
  try {
    final decoded = jsonDecode(match.group(1)!);
    if (decoded is! Map) return null;
    final body = raw
        .trimLeft()
        .substring(match.end)
        .replaceFirst(RegExp(r'^\n'), '');
    return (meta: Map<String, dynamic>.from(decoded), body: body);
  } catch (_) {
    return null;
  }
}

WaifuPlan waifuPlanParse(String raw, {String relativePath = ''}) {
  final trimmed = raw.replaceFirst(RegExp(r'^\uFEFF'), '');
  var matter = <String, dynamic>{};
  var body = trimmed;
  final jsonHit = waifuPlanJsonFence(trimmed);
  if (jsonHit != null) {
    matter = jsonHit.meta;
    body = jsonHit.body;
  } else if (trimmed.startsWith('---')) {
    final end = trimmed.indexOf(RegExp(r'\n---\s*(?:\n|$)'), 3);
    if (end > 0) {
      matter = waifuPlanParseYamlMap(trimmed.substring(3, end));
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
    if (hit != null && hit.status != WaifuPlanStatus.discarded) return hit;
  }
  return waifuDiscoverLatestPlan(session.folderRoot);
}

Future<WaifuPlan?> waifuDiscoverLatestPlan(String root) async {
  final dir = Directory(waifuPlansDir(root));
  if (!await dir.exists()) return null;
  final found = <({WaifuPlan plan, DateTime stamp})>[];
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File || !entity.path.toLowerCase().endsWith('.md')) {
      continue;
    }
    final rel = p.relative(entity.path, from: root).replaceAll('\\', '/');
    final plan = waifuPlanParse(await entity.readAsString(), relativePath: rel);
    if (plan.status == WaifuPlanStatus.discarded) continue;
    found.add((plan: plan, stamp: await entity.lastModified()));
  }
  if (found.isEmpty) return null;
  final accepted = [
    for (final e in found)
      if (e.plan.status == WaifuPlanStatus.accepted) e,
  ];
  final pool = accepted.isNotEmpty ? accepted : found;
  pool.sort((a, b) => a.stamp.compareTo(b.stamp));
  return pool.last.plan;
}

void waifuSyncPlanTodos(WaifuTodos todos, WaifuPlan plan) {
  final have = {for (final t in todos.items) t.id: t};
  for (final step in plan.steps) {
    final existing = have[step.id];
    if (existing != null) continue;
    todos.items.add(
      WaifuTodo(id: step.id, content: step.title, status: step.status),
    );
  }
}

class WaifuPlanTodoSync {
  const WaifuPlanTodoSync({this.wroteFile = false, this.blockedDone = false});

  final bool wroteFile;
  final bool blockedDone;
}

/// Build progress: write todo statuses back onto the accepted plan file.
/// Completed/done stamps require [allowCompleted] (mutate+verify this turn).
Future<WaifuPlanTodoSync> waifuSyncTodosOntoPlan({
  required WaifuSession session,
  required WaifuTodos todos,
  bool allowCompleted = true,
}) async {
  if (session.mode != WaifuMode.build) return const WaifuPlanTodoSync();
  final path = session.activePlanPath?.trim();
  if (path == null || path.isEmpty) return const WaifuPlanTodoSync();
  final plan = await waifuReadPlanFile(session.folderRoot, path);
  if (plan == null || plan.status != WaifuPlanStatus.accepted) {
    return const WaifuPlanTodoSync();
  }
  if (plan.steps.isEmpty) return const WaifuPlanTodoSync();
  final byId = {for (final todo in todos.items) todo.id: todo.status};
  var changed = false;
  var blockedDone = false;
  final steps = <WaifuPlanStep>[];
  for (final step in plan.steps) {
    final next = byId[step.id];
    if (next != null && next != step.status) {
      if (waifuTodoStatusIsDone(next) && !allowCompleted) {
        steps.add(step);
        blockedDone = true;
        for (final todo in todos.items) {
          if (todo.id == step.id) todo.status = step.status;
        }
        continue;
      }
      steps.add(step.copyWith(status: next));
      changed = true;
    } else {
      steps.add(step);
    }
  }
  if (!changed) return WaifuPlanTodoSync(blockedDone: blockedDone);
  await waifuWritePlanFile(session.folderRoot, plan.copyWith(steps: steps));
  return WaifuPlanTodoSync(wroteFile: true, blockedDone: blockedDone);
}

Future<WaifuPlan?> waifuAcceptPlan({
  required WaifuSession session,
  required WaifuTodos todos,
  String? editedBody,
}) async {
  var plan = await waifuLoadActivePlan(session);
  if (editedBody != null && editedBody.trim().isNotEmpty) {
    var rel = plan?.relativePath ?? '';
    if (rel.isEmpty) rel = session.activePlanPath?.trim() ?? '';
    plan = waifuPlanParse(editedBody, relativePath: rel);
  }
  if (plan == null) return null;
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
    buf.writeln(
      'A pending step is not done until a project mutate and a verify '
      '(re-read AND test/analyze) land this turn.',
    );
  }
  if (encoded.length <= 8000) {
    buf
      ..writeln()
      ..writeln(encoded);
  }
  return buf.toString().trimRight();
}
