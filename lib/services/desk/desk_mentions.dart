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

import 'package:front_porch_ai/services/desk/desk_jail.dart';
import 'package:front_porch_ai/services/desk/desk_permissions.dart';
import 'package:path/path.dart' as p;

final _mention = RegExp(r'@([\w./-]+)');

/// Expand `@file` tokens into attached file contents for the next generate.
Future<String> deskExpandMentions(String text, String root) async {
  final names = [for (final m in _mention.allMatches(text)) m.group(1)!];
  if (names.isEmpty) return '';
  final files = await _listFiles(root);
  final buf = StringBuffer();
  for (final name in names) {
    final hit = _best(files, name);
    if (hit == null) continue;
    if (deskIsEnvPath(hit)) continue;
    final live = await DeskJail.resolveLive(root, hit);
    if (!live.ok) continue;
    final file = File(live.path!);
    if (!await file.exists()) continue;
    final body = await file.readAsString();
    buf
      ..writeln('Attached @$name → $hit:')
      ..writeln(body)
      ..writeln();
  }
  return buf.toString();
}

Future<List<String>> _listFiles(String root) async {
  final out = <String>[];
  await for (final entity in Directory(
    root,
  ).list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    out.add(
      p.posix.normalize(
        p.relative(entity.path, from: root).replaceAll('\\', '/'),
      ),
    );
  }
  return out;
}

String? _best(List<String> files, String token) {
  final lower = token.toLowerCase();
  for (final f in files) {
    if (f.toLowerCase() == lower) return f;
  }
  for (final f in files) {
    if (p.basename(f).toLowerCase() == lower) return f;
  }
  for (final f in files) {
    if (p.basename(f).toLowerCase().startsWith(lower)) return f;
  }
  return null;
}
