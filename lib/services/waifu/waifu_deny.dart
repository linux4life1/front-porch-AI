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

import 'package:front_porch_ai/services/waifu/waifu_plan.dart';
import 'package:front_porch_ai/services/waifu/waifu_verify.dart';
import 'package:path/path.dart' as p;

/// Union of OS-write denials and recursive-wipe roots. Sit-down folder
/// children stay writable via [waifuIsCriticalSystemMutationPath].
const kWaifuProtectedTrees = {
  '/applications',
  '/bin',
  '/boot',
  '/dev',
  '/etc',
  '/home',
  '/lib',
  '/lib64',
  '/library',
  '/opt',
  '/private',
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
  '/windows',
  '/program files',
  '/program files (x86)',
};

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

bool waifuBashLooksRecursive(Iterable<String> words) =>
    words.any((word) => word.toLowerCase() == '--recursive') ||
    words.any((word) {
      final folded = word.toLowerCase();
      return folded.startsWith('-') &&
          !folded.startsWith('--') &&
          folded.contains('r');
    });

/// macOS `/var` is a symlink to `/private/var`; [p.isWithin] misses that.
bool waifuPathIsInsideRoot(String path, String root) {
  String peel(String raw) {
    var s = p.normalize(raw).replaceAll(r'\', '/').toLowerCase();
    if (s.startsWith('/private/')) s = s.substring('/private'.length);
    return s;
  }

  final child = peel(path);
  final parent = peel(root);
  return p.equals(parent, child) || p.isWithin(parent, child);
}

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
    if (waifuPathIsInsideRoot(resolved, cwdAbs)) return false;
    if (waifuIsNamedTempWipePath(resolved)) return false;
  }
  if (waifuIsNamedTempWipePath(normalized)) return false;
  if (RegExp(r'^[a-z]:/?$').hasMatch(normalized)) return true;
  final withoutDrive = normalized.replaceFirst(RegExp(r'^[a-z]:'), '');
  return kWaifuProtectedTrees.any(
    (root) => withoutDrive == root || withoutDrive.startsWith('$root/'),
  );
}

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
    final recursive = waifuBashLooksRecursive(words);
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
    if (!waifuBashLooksRecursive(args)) continue;
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

List<String> waifuShellWords(String command) {
  var normalized = command;
  for (final home in [
    r'\$\{home\}',
    r'\$home',
    r'\$\{userprofile\}',
    r'\$userprofile',
    '%userprofile%',
  ]) {
    normalized = normalized.replaceAll(RegExp(home, caseSensitive: false), '~');
  }
  for (final pwd in [r'\$\{pwd\}', r'\$pwd']) {
    normalized = normalized.replaceAll(RegExp(pwd, caseSensitive: false), '.');
  }
  return normalized
      .replaceAll(RegExp(r'''["'`(){}\[\],;|&<>]'''), ' ')
      .split(RegExp(r'\s+'))
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .toList();
}

/// `/tmp/extract` is a scratch folder. `/tmp` and `/tmp/*` are not.
bool waifuIsNamedTempWipePath(String path) {
  var n = path.trim().replaceAll(r'\', '/').toLowerCase();
  if (n.startsWith('/private/')) n = n.substring('/private'.length);
  const roots = ['/tmp', '/var/tmp'];
  for (final root in roots) {
    if (n == root || n == '$root/' || n == '$root/*' || n == '$root/.') {
      return false;
    }
    if (!n.startsWith('$root/')) continue;
    final rest = n.substring(root.length + 1);
    if (rest.isEmpty ||
        rest == '*' ||
        rest == '.' ||
        rest == '..' ||
        rest.startsWith('../') ||
        rest.contains('/../') ||
        rest.endsWith('/..')) {
      return false;
    }
    return true;
  }
  return false;
}

bool _waifuShellVerb(String word, String verb) {
  final folded = word.toLowerCase();
  return folded == verb || folded.endsWith('/$verb');
}

/// Paths the recursive command would actually delete — not mkdir/cd siblings.
/// Verb match is case-insensitive; path tokens keep the typed case so
/// symlink resolve can hit the real sit-down parent on a case-sensitive disk.
List<String> waifuBashRecursiveWipeTargets(String command) {
  final out = <String>[];
  for (final segment in command.split(RegExp(r'(?:&&|\|\||[;\n])'))) {
    final words = waifuShellWords(segment);
    if (words.isEmpty) continue;
    final rmAt = words.indexWhere((w) => _waifuShellVerb(w, 'rm'));
    var take = rmAt >= 0 && waifuBashLooksRecursive(words.skip(rmAt));
    take =
        take ||
        (words.any((w) => _waifuShellVerb(w, 'find')) &&
            words.any((w) => w.toLowerCase() == '-delete'));
    take =
        take ||
        ((words.any(
              (w) => _waifuShellVerb(w, 'chmod') || _waifuShellVerb(w, 'chown'),
            )) &&
            waifuBashLooksRecursive(words));
    take = take || segment.toLowerCase().contains('shutil.rmtree');
    if (!take) continue;
    final paths = <String>[];
    for (final word in words) {
      if (word.startsWith('-') ||
          word.contains(r'$') ||
          word.contains('*') ||
          word.contains('?') ||
          word.contains('=')) {
        continue;
      }
      if (_waifuShellVerb(word, 'rm') ||
          _waifuShellVerb(word, 'find') ||
          _waifuShellVerb(word, 'chmod') ||
          _waifuShellVerb(word, 'chown') ||
          word.toLowerCase() == 'python' ||
          word.toLowerCase() == 'python3') {
        continue;
      }
      paths.add(word);
    }
    if (paths.isEmpty && rmAt >= 0) {
      out.add('.');
    } else {
      out.addAll(paths);
    }
  }
  return out;
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
    if (p.equals(resolved, cwdAbs) ||
        waifuPathIsInsideRoot(cwdAbs, resolved) ||
        p.isWithin(resolved, cwdAbs)) {
      return true;
    }
    if (waifuPathIsInsideRoot(resolved, cwdAbs)) return false;
    if (waifuIsNamedTempWipePath(resolved)) return false;
  }
  if (waifuIsNamedTempWipePath(target)) return false;

  final withoutDrive = target.replaceFirst(RegExp(r'^[a-z]:'), '');
  return kWaifuProtectedTrees.any(
    (root) => withoutDrive == root || withoutDrive.startsWith('$root/'),
  );
}

/// Command class: redirect / write / rm / pkg / unknown mutate. Not the
/// Plan allowlist function — Plan still uses [waifuPlanBashDenied].
/// Verify-shaped non-mutating checks use the same [waifuLooksVerifyCommand]
/// receipt as `tested` — [context] must match the turn's verify context.
bool waifuBashMutates(String command, {WaifuVerifyContext? context}) {
  final raw = command.trim();
  if (raw.isEmpty) return false;
  final lower = raw.toLowerCase();
  if (raw.contains('>>') ||
      raw.contains('>') ||
      RegExp(r'\btee\b').hasMatch(lower)) {
    return true;
  }
  for (final segment in raw.split(RegExp(r'(?:&&|\|\||[;|\n])'))) {
    final words = waifuShellWords(segment);
    if (words.isEmpty) continue;
    var cmd = words.first.toLowerCase();
    if (cmd.contains('/')) cmd = cmd.split('/').last;
    if (cmd == 'cd' || cmd == 'pushd' || cmd == 'popd') continue;
    if (cmd == 'git' && words.length > 1) {
      const write = {
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
      };
      if (write.contains(words[1].toLowerCase())) return true;
    }
    if (cmd == 'sed' &&
        words.any((w) {
          final folded = w.toLowerCase();
          return folded == '-i' || folded.startsWith('-i') && folded != '-i';
        })) {
      return true;
    }
    if (waifuLooksVerifySegment(segment, context: context)) continue;
    if (!kWaifuPlanBashAllow.contains(cmd)) return true;
  }
  return false;
}
