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

/// Result of resolving a model-supplied path against the project jail.
class DeskJailHit {
  const DeskJailHit.ok(this.path) : error = null;
  const DeskJailHit.denied(this.error) : path = null;

  final String? path;
  final String? error;
  bool get ok => error == null && path != null;
}

/// Folder jail. `..`, absolute paths outside [root], and `/etc` are tool
/// errors returned to the model — never thrown at the UI.
class DeskJail {
  static const denied = 'jail: path is outside the project folder';
  static const dots = 'jail: path must not contain ..';

  /// Resolve [requested] under [root]. Sync: syntactic only (no symlink
  /// follow). Callers that touch disk must also run [resolveLive].
  static DeskJailHit resolve(String root, String requested) {
    final trimmed = requested.trim();
    if (trimmed.isEmpty) {
      return const DeskJailHit.denied('jail: path is empty');
    }
    final parts = p.split(trimmed);
    if (parts.contains('..')) {
      return const DeskJailHit.denied(dots);
    }
    final rootAbs = p.normalize(p.absolute(root));
    final candidate = p.isAbsolute(trimmed)
        ? p.normalize(trimmed)
        : p.normalize(p.join(rootAbs, trimmed));
    if (!_inside(rootAbs, candidate)) {
      return const DeskJailHit.denied(denied);
    }
    return DeskJailHit.ok(candidate);
  }

  /// [resolve] plus a realpath check so a symlink inside the jail cannot
  /// read `/etc` or a sibling folder. The root itself is canonicalized so
  /// macOS `/var` → `/private/var` temp dirs are not false-denied.
  static Future<DeskJailHit> resolveLive(String root, String requested) async {
    final hit = resolve(root, requested);
    if (!hit.ok) return hit;
    final rootReal = await canonicalRoot(root);
    final abs = hit.path!;
    final asFile = File(abs);
    final asDir = Directory(abs);
    final fileExists = await asFile.exists();
    final dirExists = await asDir.exists();
    if (!fileExists && !dirExists) {
      final parent = p.dirname(abs);
      final parentReal = await canonicalRoot(parent);
      if (!_inside(rootReal, parentReal)) {
        return const DeskJailHit.denied(denied);
      }
      return hit;
    }
    try {
      final real = fileExists
          ? await asFile.resolveSymbolicLinks()
          : await asDir.resolveSymbolicLinks();
      if (!_inside(rootReal, real)) {
        return const DeskJailHit.denied(denied);
      }
      return DeskJailHit.ok(real);
    } catch (_) {
      return hit;
    }
  }

  static Future<String> canonicalRoot(String root) async {
    var current = p.normalize(p.absolute(root));
    final missing = <String>[];
    while (true) {
      try {
        if (await Directory(current).exists()) {
          var real = await Directory(current).resolveSymbolicLinks();
          for (final part in missing.reversed) {
            real = p.join(real, part);
          }
          return real;
        }
      } catch (_) {}
      final parent = p.dirname(current);
      if (parent == current) break;
      missing.add(p.basename(current));
      current = parent;
    }
    return p.normalize(p.absolute(root));
  }

  static bool _inside(String rootAbs, String candidate) {
    final rootNorm = p.normalize(rootAbs);
    final candNorm = p.normalize(candidate);
    if (candNorm == rootNorm) return true;
    final prefix = rootNorm.endsWith(p.separator)
        ? rootNorm
        : '$rootNorm${p.separator}';
    if (Platform.isWindows) {
      return candNorm.toLowerCase().startsWith(prefix.toLowerCase());
    }
    return candNorm.startsWith(prefix);
  }
}
