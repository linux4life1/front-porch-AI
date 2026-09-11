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
import 'package:path/path.dart' as p;

const kWaifuPlansDir = '$kWaifuDotDir/plans';

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

bool waifuPlanStepIsOpen(WaifuPlanStep step) {
  switch (step.status.trim().toLowerCase()) {
    case 'completed':
    case 'complete':
    case 'done':
      return false;
    default:
      return true;
  }
}

WaifuPlanStep? waifuNextPendingPlanStep(WaifuPlan? plan) {
  if (plan == null) return null;
  for (final step in plan.steps) {
    if (waifuPlanStepIsOpen(step)) return step;
  }
  return null;
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
