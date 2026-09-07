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

import 'package:path/path.dart' as p;

/// Result of resolving a model-supplied path against the sit-down cwd.
class DeskJailHit {
  const DeskJailHit.ok(this.path) : error = null;
  const DeskJailHit.denied(this.error) : path = null;

  final String? path;
  final String? error;
  bool get ok => error == null && path != null;
}

/// Path resolver, not a prison. Relative paths are against [root] (the
/// sit-down folder, default cwd). Absolute paths, `..`, and `~` are allowed
/// so she can walk the disk like Claude Code / OpenCode. `.env`,
/// destructive git, and `rm -rf /` stay hard-denied in permissions.
class DeskJail {
  static DeskJailHit resolve(String root, String requested) {
    final trimmed = requested.trim();
    if (trimmed.isEmpty) {
      return const DeskJailHit.denied('path is empty');
    }
    final expanded = _expandHome(trimmed);
    final rootAbs = p.normalize(p.absolute(root));
    final candidate = p.isAbsolute(expanded)
        ? p.normalize(expanded)
        : p.normalize(p.join(rootAbs, expanded));
    return DeskJailHit.ok(candidate);
  }

  /// [resolve] plus realpath so we read/write the file a symlink points at.
  ///
  /// Models often prefix the sit-down folder name (`Kabbage/pubspec.yaml`
  /// while cwd is already `.../Kabbage`). If the doubled path misses and
  /// the stripped path hits, use the stripped one.
  static Future<DeskJailHit> resolveLive(String root, String requested) async {
    final hit = resolve(root, requested);
    if (!hit.ok) return hit;
    final existing = await _liveIfExists(hit.path!);
    if (existing != null) return existing;

    final stripped = deskStripRedundantProjectPrefix(root, requested);
    if (stripped == requested.trim()) return hit;
    final again = resolve(root, stripped);
    if (!again.ok) return hit;
    final live = await _liveIfExists(again.path!);
    if (live != null) return live;
    if (await _parentExists(again.path!) && !await _parentExists(hit.path!)) {
      return again;
    }
    return hit;
  }

  static Future<String> canonicalRoot(String root) async {
    var current = p.normalize(p.absolute(root));
    try {
      if (await Directory(current).exists()) {
        return await Directory(current).resolveSymbolicLinks();
      }
    } catch (_) {}
    return current;
  }

  static String _expandHome(String path) {
    if (path == '~' || path.startsWith('~/') || path.startsWith(r'~\')) {
      final home =
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '';
      if (home.isEmpty) return path;
      if (path.length == 1) return home;
      return p.join(home, path.substring(2));
    }
    return path;
  }

  static Future<DeskJailHit?> _liveIfExists(String abs) async {
    try {
      final asFile = File(abs);
      if (await asFile.exists()) {
        return DeskJailHit.ok(await asFile.resolveSymbolicLinks());
      }
      final asDir = Directory(abs);
      if (await asDir.exists()) {
        return DeskJailHit.ok(await asDir.resolveSymbolicLinks());
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> _parentExists(String abs) async {
    try {
      return await Directory(p.dirname(abs)).exists();
    } catch (_) {
      return false;
    }
  }
}

/// Drop a redundant first segment that repeats the sit-down folder name.
String deskStripRedundantProjectPrefix(String root, String requested) {
  final trimmed = requested.trim();
  if (trimmed.isEmpty) return trimmed;
  if (p.isAbsolute(trimmed)) return trimmed;
  if (trimmed == '~' || trimmed.startsWith('~/') || trimmed.startsWith(r'~\')) {
    return trimmed;
  }
  final posix = trimmed.replaceAll('\\', '/');
  if (posix == '.' || posix == '..' || posix.startsWith('../')) {
    return trimmed;
  }
  final base = p.basename(p.normalize(p.absolute(root)));
  if (base.isEmpty || base == '.' || base == '..') return trimmed;
  final first = posix.split('/').first;
  if (!_sameFolderName(first, base)) return trimmed;
  if (posix.length == first.length) return '.';
  if (posix.startsWith('$first/')) {
    final rest = posix.substring(first.length + 1);
    return rest.isEmpty ? '.' : rest;
  }
  return trimmed;
}

bool _sameFolderName(String a, String b) {
  if (Platform.isWindows || Platform.isMacOS) {
    return a.toLowerCase() == b.toLowerCase();
  }
  return a == b;
}
