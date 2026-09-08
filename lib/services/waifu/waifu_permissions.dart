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

import 'package:front_porch_ai/services/waifu/waifu_plan.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';
import 'package:front_porch_ai/services/waifu/waifu_tools.dart';
import 'package:path/path.dart' as p;

enum WaifuAskDecision { allowOnce, allowAlways, deny }

class WaifuAskRequest {
  const WaifuAskRequest({
    required this.toolName,
    required this.summary,
    this.doomLoop = false,
  });

  final String toolName;
  final String summary;
  final bool doomLoop;
}

typedef WaifuAskFn = Future<WaifuAskDecision> Function(WaifuAskRequest request);

bool waifuToolMutates(String name) {
  switch (canonicalWaifuToolName(name)) {
    case kWaifuToolEdit:
    case kWaifuToolApplyPatch:
    case kWaifuToolWrite:
    case kWaifuToolBash:
    case kWaifuToolTodoWrite:
    case kWaifuToolSkillInstall:
      return true;
    default:
      return false;
  }
}

bool waifuIsEnvPath(String path) {
  final candidate = path.trim().split('=').last;
  final base = candidate
      .trim()
      .replaceAll(r'\', '/')
      .split('/')
      .last
      .toLowerCase();
  return base == '.env' || base.startsWith('.env.');
}

/// Secret-bearing files the harness never reads or changes, even in Yolo.
///
/// The segment check is portable: a Windows path can arrive while a test is
/// running on Unix (and vice versa), so this must not use the host separator.
bool waifuIsProtectedSecretPath(String path) {
  final normalized = path
      .trim()
      .split('=')
      .last
      .replaceAll(r'\', '/')
      .toLowerCase();
  final segments = normalized.split('/').where((part) => part.isNotEmpty);
  return waifuIsEnvPath(normalized) ||
      segments.contains('.ssh') ||
      segments.contains('.aws');
}

/// Refuse direct file-tool writes to operating-system trees. Reading remains
/// open-disk; ordinary writes elsewhere (including `..`) remain available.
bool waifuIsCriticalSystemMutationPath(
  String path, {
  String? workingDirectory,
}) {
  final normalized = path.trim().replaceAll(r'\', '/').toLowerCase();
  final cwd = workingDirectory;
  if (cwd != null &&
      !normalized.contains(RegExp(r'[$*?]')) &&
      !RegExp(r'^[a-z]+:').hasMatch(normalized)) {
    final cwdAbs = p.normalize(p.absolute(cwd));
    final resolved = p.isAbsolute(normalized)
        ? p.normalize(normalized)
        : p.normalize(p.join(cwdAbs, normalized));
    if (p.isWithin(cwdAbs, resolved)) return false;
  }
  if (RegExp(r'^[a-z]:/?$').hasMatch(normalized)) return true;
  final withoutDrive = normalized.replaceFirst(RegExp(r'^[a-z]:'), '');
  const roots = {
    '/bin',
    '/boot',
    '/dev',
    '/etc',
    '/lib',
    '/lib64',
    '/proc',
    '/run',
    '/sbin',
    '/sys',
    '/usr',
    '/var',
    '/applications',
    '/library',
    '/system',
    '/windows',
    '/program files',
    '/program files (x86)',
  };
  return roots.any(
    (root) => withoutDrive == root || withoutDrive.startsWith('$root/'),
  );
}

/// Hard-deny list. Yolo does not skip this. Bash uses the same gate.
String? waifuDeniedCommand(String command, {String? workingDirectory}) {
  final raw = command.trim();
  final lower = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (lower.isEmpty) return null;
  final commandWords = waifuShellWords(lower);
  if (commandWords.any(
        (word) =>
            word == 'env' ||
            word.endsWith('/env') ||
            word == 'printenv' ||
            word.endsWith('/printenv'),
      ) ||
      RegExp(r'(^|[;&|\s])export\s+-[a-z]*p').hasMatch(lower)) {
    return 'denied: dumping the process environment can expose API keys';
  }
  if (commandWords.any(waifuIsProtectedSecretPath)) {
    return 'denied: .env, .ssh, and .aws secrets stay off the workbench';
  }
  if (RegExp(r'\bgit checkout\b').hasMatch(lower) && lower.contains(' --')) {
    return 'denied: git checkout -- would discard uncommitted work';
  }
  if (RegExp(r'\bgit restore\b').hasMatch(lower)) {
    return 'denied: git restore would discard uncommitted work';
  }
  if (RegExp(r'\bgit reset --hard\b').hasMatch(lower)) {
    return 'denied: git reset --hard would discard uncommitted work';
  }
  if (RegExp(r'\bgit clean\b').hasMatch(lower) &&
      commandWords.any(
        (word) =>
            word == '--force' || (word.startsWith('-') && word.contains('f')),
      )) {
    return 'denied: git clean would discard untracked work';
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
  if (RegExp(r'\bwipefs\b').hasMatch(lower)) {
    return 'denied: wipefs is not allowed';
  }
  final unquoted = lower.replaceAll(RegExp(r'''["'\s]'''), '');
  if (RegExp(r'\bdd\b').hasMatch(lower) && unquoted.contains('of=/dev/')) {
    return 'denied: dd to a device is not allowed';
  }
  if (lower.contains('diskutil erase')) {
    return 'denied: diskutil erase is not allowed';
  }
  if (RegExp(r'''\bformat(?:\.com)?\s+["']?[a-z]:''').hasMatch(lower)) {
    return 'denied: formatting a drive is not allowed';
  }
  if (RegExp(r'\bsudo\b').hasMatch(lower) &&
      RegExp(r'\brm\b').hasMatch(lower)) {
    return 'denied: sudo rm is not allowed';
  }
  if (_rmDangerous(lower, workingDirectory: workingDirectory)) {
    return 'denied: recursive rm cannot wipe a root, home, system folder, '
        'or the sit-down folder and its parents';
  }
  for (final segment in lower.split(RegExp(r'(?:&&|\|\||[;\n])'))) {
    final words = waifuShellWords(segment);
    if (words.isEmpty) continue;
    final recursive =
        words.contains('--recursive') ||
        words.any(
          (word) =>
              word.startsWith('-') &&
              !word.startsWith('--') &&
              word.contains('r'),
        );
    if ((words.any((word) => word == 'chmod' || word.endsWith('/chmod')) ||
            words.any((word) => word == 'chown' || word.endsWith('/chown'))) &&
        recursive &&
        words.any((word) => _isDangerousWipeTarget(word, workingDirectory))) {
      return 'denied: recursive system-wide permission changes are not allowed';
    }
    if (words.any((word) => word == 'find' || word.endsWith('/find')) &&
        words.contains('-delete') &&
        words.any((word) => _isDangerousWipeTarget(word, workingDirectory))) {
      return 'denied: find -delete needs a tightly scoped child folder';
    }
    if (segment.contains('shutil.rmtree') &&
        words.any((word) => _isDangerousWipeTarget(word, workingDirectory))) {
      return 'denied: recursive Python deletion cannot target roots or parents';
    }
  }
  return null;
}

bool _rmDangerous(String lower, {String? workingDirectory}) {
  for (final segment in lower.split(RegExp(r'(?:&&|\|\||[;\n])'))) {
    final words = waifuShellWords(segment);
    final rmAt = words.indexWhere(
      (word) => word == 'rm' || word.endsWith('/rm'),
    );
    if (rmAt < 0) continue;
    final args = words.skip(rmAt + 1).toList();
    final recursive =
        args.contains('--recursive') ||
        args.any(
          (word) =>
              word.startsWith('-') &&
              !word.startsWith('--') &&
              word.contains('r'),
        );
    if (!recursive) continue;
    if (segment.contains('dirname') &&
        RegExp(r'\$\{?pwd\}?').hasMatch(segment)) {
      return true;
    }
    if (args.any((word) => _isDangerousWipeTarget(word, workingDirectory))) {
      return true;
    }
  }
  return false;
}

/// Conservative shell-word scan for permission checks, including commands
/// nested inside `bash -c` quotes. It is not used to execute or rewrite input.
List<String> waifuShellWords(String command) {
  var normalized = command.toLowerCase();
  for (final home in [
    r'${home}',
    r'$home',
    r'${userprofile}',
    r'$userprofile',
    '%userprofile%',
  ]) {
    normalized = normalized.replaceAll(home, '~');
  }
  return normalized
      .replaceAll(RegExp(r'''["'`(){}\[\],;|&<>]'''), ' ')
      .split(RegExp(r'\s+'))
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .toList();
}

bool _isDangerousWipeTarget(String raw, String? workingDirectory) {
  final target = raw.trim().replaceAll(r'\', '/').toLowerCase();
  if (target.isEmpty || target == '--' || target.startsWith('-')) return false;
  const exact = {
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
  if (exact.contains(target) ||
      target == '..' ||
      target == '../' ||
      target.startsWith('../') ||
      target.contains('/../') ||
      target.endsWith('/..') ||
      target.startsWith('~')) {
    return true;
  }
  if (RegExp(r'^[a-z]:/?(?:\*)?$').hasMatch(target)) return true;

  final cwd = workingDirectory;
  if (cwd != null &&
      !target.contains(RegExp(r'[$*?]')) &&
      !RegExp(r'^[a-z]+:').hasMatch(target)) {
    final cwdAbs = p.normalize(p.absolute(cwd));
    final resolved = p.isAbsolute(target)
        ? p.normalize(target)
        : p.normalize(p.join(cwdAbs, target));
    if (p.isWithin(cwdAbs, resolved)) return false;
    if (p.equals(resolved, cwdAbs) || p.isWithin(resolved, cwdAbs)) return true;
  }

  const criticalRoots = {
    '/applications',
    '/bin',
    '/boot',
    '/dev',
    '/etc',
    '/home',
    '/library',
    '/lib',
    '/lib64',
    '/opt',
    '/proc',
    '/root',
    '/run',
    '/sbin',
    '/sys',
    '/system',
    '/tmp',
    '/usr',
    '/users',
    '/var',
    '/private',
  };
  final withoutDrive = target.replaceFirst(RegExp(r'^[a-z]:'), '');
  return criticalRoots.any(
    (root) => withoutDrive == root || withoutDrive.startsWith('$root/'),
  );
}

/// Plan / Build / Yolo gears plus doom-loop and .env. Plan may write only
/// under `.waifu/plans/`; source mutate stays denied. Null
/// [WaifuHarness.onAsk] auto-allows Build (headless / slice B tests);
/// WaifuPage installs the modal.
class WaifuPermissions {
  WaifuPermissions({this.mode = WaifuMode.build, this.workingDirectory});

  WaifuMode mode;
  String? workingDirectory;
  bool _alwaysMutate = false;
  final _counts = <String, int>{};

  String fingerprint(String name, Map<String, dynamic> args) =>
      '${canonicalWaifuToolName(name)}:${jsonEncode(args)}';

  String? hardBlock({
    required String name,
    required Map<String, dynamic> args,
    bool? mutates,
  }) {
    final canon = canonicalWaifuToolName(name);
    final path = waifuToolPathArg(args);
    if (path != null && waifuIsProtectedSecretPath(path)) {
      return 'denied: .env, .ssh, and .aws secrets stay off the workbench';
    }
    if (path != null &&
        (canon == kWaifuToolWrite ||
            canon == kWaifuToolEdit ||
            canon == kWaifuToolApplyPatch) &&
        waifuIsCriticalSystemMutationPath(
          path,
          workingDirectory: workingDirectory,
        )) {
      return 'denied: direct writes to operating-system files are not allowed';
    }
    if (canon == kWaifuToolBash) {
      final cmd = args['command']?.toString() ?? args['cmd']?.toString() ?? '';
      final denied = waifuDeniedCommand(
        cmd,
        workingDirectory: workingDirectory,
      );
      if (denied != null) return denied;
    }
    if (mode == WaifuMode.plan) {
      final planBlock = waifuPlanMutationBlock(
        name: canon,
        args: args,
        root: workingDirectory,
      );
      if (planBlock != null) return planBlock;
      if (mutates == true) {
        return 'plan mode cannot $canon: switch to Build or Yolo to change files';
      }
      return null;
    }
    return null;
  }

  bool isDoom(String name, Map<String, dynamic> args) =>
      (_counts[fingerprint(name, args)] ?? 0) >= 2;

  bool needsAsk({
    required String name,
    required Map<String, dynamic> args,
    bool? mutates,
  }) {
    if (!(mutates ?? waifuToolMutates(name))) return false;
    if (mode == WaifuMode.plan) return false;
    if (isDoom(name, args)) return true;
    if (_alwaysMutate) return false;
    return mode == WaifuMode.build;
  }

  void record({required String name, required Map<String, dynamic> args}) {
    final fp = fingerprint(name, args);
    _counts[fp] = (_counts[fp] ?? 0) + 1;
  }

  void allowAlways() => _alwaysMutate = true;

  String summaryFor(String name, Map<String, dynamic> args) {
    final path = waifuToolPathArg(args);
    if (path != null) return path;
    final cmd = args['command']?.toString() ?? args['cmd']?.toString();
    if (cmd != null && cmd.isNotEmpty) return cmd;
    return canonicalWaifuToolName(name);
  }
}
