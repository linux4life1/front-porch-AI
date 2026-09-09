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

import 'package:crypto/crypto.dart';
import 'package:front_porch_ai/services/waifu/waifu_brand.dart';
import 'package:front_porch_ai/services/waifu/waifu_jail.dart';
import 'package:front_porch_ai/services/waifu/waifu_tools.dart';
import 'package:path/path.dart' as p;

const kWaifuPlansDir = '$kWaifuDotDir/plans';

const kWaifuPlanModeCue =
    'PLAN MODE: Explore the sit-down folder with read, glob, grep, and '
    'read-only bash, then author a plan markdown file under '
    '$kWaifuPlansDir/<slug>.md. write, edit, and apply_patch may only touch '
    'that plans folder. Do not change project source. Session todos are '
    'allowed. A Plan turn is incomplete without that plan-file receipt.';

const kWaifuPlanBuiltinsCue =
    'Prefer built-in read, glob, grep, todowrite, and plan-folder write / '
    'edit / apply_patch. Bash is a read-only allowlist in Plan. Do not call '
    'source-tree mutators.';

const kWaifuPlanBashAllow = {
  'ls',
  'pwd',
  'cat',
  'head',
  'tail',
  'wc',
  'git',
  'rg',
  'ripgrep',
  'grep',
  'egrep',
  'fgrep',
  'file',
  'stat',
  'which',
  'type',
  'test',
  'true',
  'false',
  'date',
  'uname',
  'whoami',
  'echo',
  'printf',
  'tree',
  'du',
  'id',
  'basename',
  'dirname',
  'realpath',
  'readlink',
  'md5sum',
  'sha256sum',
  'awk',
  'sed',
  'sort',
  'uniq',
  'cut',
  'tr',
  'column',
};

const _kWaifuPlanGitMutate = {
  'add',
  'commit',
  'checkout',
  'restore',
  'reset',
  'clean',
  'push',
  'pull',
  'rebase',
  'merge',
  'cherry-pick',
  'stash',
  'tag',
  'rm',
  'mv',
  'init',
  'clone',
};

const kWaifuPlanFileTools = {
  kWaifuToolRead,
  kWaifuToolGlob,
  kWaifuToolGrep,
  kWaifuToolEdit,
  kWaifuToolApplyPatch,
  kWaifuToolWrite,
  kWaifuToolBash,
  kWaifuToolTodoRead,
  kWaifuToolTodoWrite,
  kWaifuToolQuestion,
  kWaifuToolSkill,
};

enum WaifuPlanStatus { draft, accepted, superseded, discarded }

class WaifuPlanStep {
  const WaifuPlanStep({
    required this.id,
    required this.title,
    this.detail = '',
    this.files = const [],
    this.verify = '',
    this.status = 'pending',
  });

  final String id;
  final String title;
  final String detail;
  final List<String> files;
  final String verify;
  final String status;

  WaifuPlanStep copyWith({String? status}) => WaifuPlanStep(
    id: id,
    title: title,
    detail: detail,
    files: files,
    verify: verify,
    status: status ?? this.status,
  );
}

class WaifuPlan {
  const WaifuPlan({
    required this.id,
    required this.slug,
    required this.title,
    required this.goal,
    required this.status,
    this.assumptions = const [],
    this.constraints = const [],
    this.risks = const [],
    this.openQuestions = const [],
    this.steps = const [],
    this.body = '',
    this.relativePath = '',
  });

  final String id;
  final String slug;
  final String title;
  final String goal;
  final WaifuPlanStatus status;
  final List<String> assumptions;
  final List<String> constraints;
  final List<String> risks;
  final List<String> openQuestions;
  final List<WaifuPlanStep> steps;
  final String body;
  final String relativePath;

  WaifuPlan copyWith({
    WaifuPlanStatus? status,
    String? body,
    String? relativePath,
    List<WaifuPlanStep>? steps,
  }) => WaifuPlan(
    id: id,
    slug: slug,
    title: title,
    goal: goal,
    status: status ?? this.status,
    assumptions: assumptions,
    constraints: constraints,
    risks: risks,
    openQuestions: openQuestions,
    steps: steps ?? this.steps,
    body: body ?? this.body,
    relativePath: relativePath ?? this.relativePath,
  );
}

String waifuPlansDir(String root) =>
    p.normalize(p.join(p.absolute(root), kWaifuDotDir, 'plans'));

String waifuPlanRelativePath(String slug) =>
    p.posix.join(kWaifuDotDir, 'plans', '$slug.md');

String waifuPlanSlug(String title) {
  final s = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return s.isEmpty ? 'plan' : s;
}

String waifuPlanDigest(String body) =>
    sha256.convert(utf8.encode(body)).toString();

bool waifuRelativeIsPlanArtifact(String relative) {
  final posix = relative.trim().replaceAll('\\', '/');
  if (!posix.toLowerCase().endsWith('.md')) return false;
  return posix == kWaifuPlansDir ||
      posix.startsWith('$kWaifuPlansDir/') ||
      posix.contains('/$kWaifuPlansDir/');
}

bool waifuIsPlanArtifactPath(String root, String resolvedAbs) {
  final plans = waifuPlansDir(root);
  final abs = p.normalize(resolvedAbs);
  if (p.equals(abs, plans)) return false;
  if (!p.isWithin(plans, abs)) return false;
  return p.extension(abs).toLowerCase() == '.md';
}

/// Lexical Plan-write gate. Always folder-jail — Whole-disk does not apply.
String? waifuPlanMutationBlock({
  required String name,
  required Map<String, dynamic> args,
  required String? root,
}) {
  final canon = canonicalWaifuToolName(name);
  if (canon == kWaifuToolTodoWrite || canon == kWaifuToolTodoRead) {
    return null;
  }
  if (canon == kWaifuToolBash) {
    return waifuPlanBashDenied(
      args['command']?.toString() ?? args['cmd']?.toString() ?? '',
    );
  }
  if (canon == kWaifuToolWrite ||
      canon == kWaifuToolEdit ||
      canon == kWaifuToolApplyPatch) {
    final path = waifuToolPathArg(args);
    if (path == null || root == null || root.isEmpty) {
      return 'plan mode can only write under $kWaifuPlansDir';
    }
    final hit = WaifuJail.resolve(
      root,
      path,
      pathMode: WaifuPathMode.folderJail,
    );
    if (!hit.ok) {
      return 'plan mode cannot $canon outside $kWaifuPlansDir: ${hit.error}';
    }
    if (!waifuIsPlanArtifactPath(root, hit.path!)) {
      return 'plan mode can only write under $kWaifuPlansDir';
    }
    return null;
  }
  if (canon == kWaifuToolSkillInstall) {
    return 'plan mode cannot $canon: switch to Build or Yolo to change files';
  }
  return null;
}

/// Live realpath check. Catches symlink-out and leftover absolute escapes.
Future<String?> waifuPlanWriteLiveBlock(String root, String requested) async {
  final hit = await WaifuJail.resolveLive(
    root,
    requested,
    pathMode: WaifuPathMode.folderJail,
  );
  if (!hit.ok) {
    return 'plan mode cannot write outside $kWaifuPlansDir: ${hit.error}';
  }
  final rootReal = await WaifuJail.canonicalRoot(root);
  final plans = p.normalize(p.join(rootReal, kWaifuDotDir, 'plans'));
  final resolved = p.normalize(hit.path!);
  String peel(String raw) {
    var s = p.normalize(raw);
    if (s.startsWith('/private/')) s = s.substring('/private'.length);
    return s;
  }

  final plansPeeled = peel(plans);
  final resolvedPeeled = peel(resolved);
  if (p.equals(resolvedPeeled, plansPeeled) ||
      !p.isWithin(plansPeeled, resolvedPeeled)) {
    return 'plan mode can only write under $kWaifuPlansDir '
        '(realpath escaped the plans folder)';
  }
  if (p.extension(resolved).toLowerCase() != '.md') {
    return 'plan files must be markdown (.md) under $kWaifuPlansDir';
  }
  return null;
}

String? waifuPlanBashDenied(String command) {
  final raw = command.trim();
  if (raw.isEmpty) return 'plan mode bash is read-only: command is empty';
  if (raw.contains('>>') ||
      raw.contains('>') ||
      RegExp(r'\btee\b').hasMatch(raw.toLowerCase())) {
    return 'plan mode bash is read-only (no redirects or tee)';
  }
  for (final segment in raw.split(RegExp(r'(?:&&|\|\||[;|\n])'))) {
    final words = segment
        .toLowerCase()
        .replaceAll(RegExp(r'''["'`(){}\[\],;|&<>]'''), ' ')
        .split(RegExp(r'\s+'))
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) continue;
    var cmd = words.first;
    if (cmd.contains('/')) cmd = cmd.split('/').last;
    if (!kWaifuPlanBashAllow.contains(cmd)) {
      return 'plan mode bash is read-only: $cmd is not on the allowlist';
    }
    if (cmd == 'git' && _gitMutates(words)) {
      return 'plan mode bash is read-only: git ${words.length > 1 ? words[1] : ''}';
    }
    if (cmd == 'sed' &&
        words.any((w) => w == '-i' || w.startsWith('-i') && w != '-i')) {
      return 'plan mode bash is read-only: sed -i would change files';
    }
  }
  return null;
}

bool _gitMutates(List<String> words) {
  if (words.length < 2) return false;
  final sub = words[1];
  if (_kWaifuPlanGitMutate.contains(sub)) return true;
  return words.any(
    (w) =>
        w == '-d' ||
        w == '-D' ||
        w == '-m' ||
        w == '--delete' ||
        w == '--force',
  );
}

List<Map<String, dynamic>> waifuPlanAdvertisedTools(
  List<Map<String, dynamic>> fileTools,
) {
  const help =
      'Plan mode only: path must resolve inside $kWaifuPlansDir as a .md file. '
      'Project source stays read-only.';
  return [
    for (final tool in fileTools)
      if (kWaifuPlanFileTools.contains(
        ((tool['function'] as Map?)?['name'] ?? '').toString(),
      ))
        _planToolHelp(tool, help),
  ];
}

Map<String, dynamic> _planToolHelp(Map<String, dynamic> tool, String help) {
  final fn = Map<String, dynamic>.from(tool['function'] as Map);
  final name = fn['name']?.toString() ?? '';
  if (name == kWaifuToolWrite ||
      name == kWaifuToolEdit ||
      name == kWaifuToolApplyPatch) {
    fn['description'] = '${fn['description']} $help';
  }
  if (name == kWaifuToolBash) {
    fn['description'] =
        'Read-only shell allowlist in Plan (ls, cat, git status/diff/log, '
        'grep, rg, …). find is denied. Redirects, tee, and mutating git '
        'are denied.';
  }
  return {'type': 'function', 'function': fn};
}
