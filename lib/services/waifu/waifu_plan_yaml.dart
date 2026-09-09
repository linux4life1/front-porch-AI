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

/// Read-only YAML front matter for plans written before JSON encode.
Map<String, dynamic> waifuPlanParseYamlMap(String raw) =>
    _YamlMini(raw).parseMap(0);

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
