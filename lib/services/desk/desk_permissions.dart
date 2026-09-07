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

import 'package:front_porch_ai/services/desk/desk_sit_down.dart';
import 'package:front_porch_ai/services/desk/desk_tools.dart';
import 'package:path/path.dart' as p;

enum DeskAskDecision { allowOnce, allowAlways, deny }

class DeskAskRequest {
  const DeskAskRequest({
    required this.toolName,
    required this.summary,
    this.doomLoop = false,
  });

  final String toolName;
  final String summary;
  final bool doomLoop;
}

typedef DeskAskFn = Future<DeskAskDecision> Function(DeskAskRequest request);

bool deskToolMutates(String name) {
  switch (canonicalDeskToolName(name)) {
    case kDeskToolEdit:
    case kDeskToolWrite:
    case kDeskToolBash:
    case kDeskToolTodoWrite:
    case kDeskToolSkillInstall:
      return true;
    default:
      return false;
  }
}

bool deskIsEnvPath(String path) {
  final base = p.basename(path.trim()).toLowerCase();
  return base == '.env' || base.startsWith('.env.');
}

/// Hard-deny list. Yolo does not skip this. Bash uses the same gate.
String? deskDeniedCommand(String command) {
  final raw = command.trim();
  final lower = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (lower.isEmpty) return null;
  if (RegExp(r'\bgit checkout\b').hasMatch(lower) && lower.contains(' --')) {
    return 'denied: git checkout -- would discard uncommitted work';
  }
  if (RegExp(r'\bgit restore\b').hasMatch(lower)) {
    return 'denied: git restore would discard uncommitted work';
  }
  if (RegExp(r'\bgit reset --hard\b').hasMatch(lower)) {
    return 'denied: git reset --hard would discard uncommitted work';
  }
  if (RegExp(r'\bgit push\b').hasMatch(lower) &&
      (lower.contains('--force') || RegExp(r'(^| )-f( |$)').hasMatch(lower))) {
    return 'denied: force-push is not allowed';
  }
  final packed = raw.replaceAll(RegExp(r'\s+'), '');
  if (packed.contains(':(){:|:&};:')) {
    return 'denied: fork bomb is not allowed';
  }
  if (RegExp(r'\bmkfs(\.\w+)?\b').hasMatch(lower)) {
    return 'denied: mkfs is not allowed';
  }
  if (RegExp(r'\bdd\b').hasMatch(lower) && lower.contains('of=/dev')) {
    return 'denied: dd to a device is not allowed';
  }
  if (lower.contains('diskutil erase')) {
    return 'denied: diskutil erase is not allowed';
  }
  if (RegExp(r'\bsudo\b').hasMatch(lower) &&
      RegExp(r'\brm\b').hasMatch(lower)) {
    return 'denied: sudo rm is not allowed';
  }
  if (_rmDangerous(lower)) {
    return 'denied: recursive rm of /, home, ., or * is not allowed';
  }
  return null;
}

bool _rmDangerous(String lower) {
  if (!RegExp(r'\brm\b').hasMatch(lower)) return false;
  final recursive =
      lower.contains('--recursive') || RegExp(r'(^| )-[a-z]*r').hasMatch(lower);
  final force =
      lower.contains('--force') || RegExp(r'(^| )-[a-z]*f').hasMatch(lower);
  if (!recursive || !force) return false;
  const bad = {
    '/',
    '/*',
    '/.',
    '//',
    '.',
    './',
    '*',
    './*',
    '~',
    '~/',
    '~/*',
    '\$home',
    '\$home/',
    '\$home/*',
    '**',
  };
  for (final token in lower.split(' ')) {
    if (token.startsWith('-') || token == 'rm') continue;
    if (bad.contains(token)) return true;
  }
  return false;
}

/// Plan / Build / Yolo gears plus doom-loop and .env. Null [DeskHarness.onAsk]
/// auto-allows Build (headless / slice B tests); DeskPage installs the modal.
class DeskPermissions {
  DeskPermissions({this.mode = DeskMode.build});

  DeskMode mode;
  bool _alwaysMutate = false;
  final _counts = <String, int>{};

  String fingerprint(String name, Map<String, dynamic> args) =>
      '${canonicalDeskToolName(name)}:${jsonEncode(args)}';

  String? hardBlock({
    required String name,
    required Map<String, dynamic> args,
  }) {
    final canon = canonicalDeskToolName(name);
    final path = deskToolPathArg(args);
    if (path != null && deskIsEnvPath(path)) {
      return 'denied: .env files are not readable or writable by Desk';
    }
    if (canon == kDeskToolBash) {
      final cmd = args['command']?.toString() ?? args['cmd']?.toString() ?? '';
      final denied = deskDeniedCommand(cmd);
      if (denied != null) return denied;
    }
    if (mode == DeskMode.plan && deskToolMutates(canon)) {
      return 'plan mode cannot $canon: switch to Build or Yolo to change files';
    }
    return null;
  }

  bool isDoom(String name, Map<String, dynamic> args) =>
      (_counts[fingerprint(name, args)] ?? 0) >= 2;

  bool needsAsk({required String name, required Map<String, dynamic> args}) {
    if (!deskToolMutates(name)) return false;
    if (mode == DeskMode.plan) return false;
    if (isDoom(name, args)) return true;
    if (_alwaysMutate) return false;
    return mode == DeskMode.build;
  }

  void record({required String name, required Map<String, dynamic> args}) {
    final fp = fingerprint(name, args);
    _counts[fp] = (_counts[fp] ?? 0) + 1;
  }

  void allowAlways() => _alwaysMutate = true;

  String summaryFor(String name, Map<String, dynamic> args) {
    final path = deskToolPathArg(args);
    if (path != null) return path;
    final cmd = args['command']?.toString() ?? args['cmd']?.toString();
    if (cmd != null && cmd.isNotEmpty) return cmd;
    return canonicalDeskToolName(name);
  }
}
