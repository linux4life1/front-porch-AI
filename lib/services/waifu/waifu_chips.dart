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

/// Caption for a tool chip. Never repeats the tool name as the detail.
String waifuChipDetail(String name, Map<String, dynamic> args) {
  final n = name.trim().toLowerCase();
  String raw;
  switch (n) {
    case 'bash':
      raw = (args['command'] ?? args['cmd'] ?? args['script'] ?? '').toString();
    case 'glob':
      raw = (args['pattern'] ?? args['glob'] ?? '').toString();
    case 'grep':
      raw = (args['pattern'] ?? args['query'] ?? '').toString();
    case 'webfetch':
      raw = (args['url'] ?? '').toString();
    case 'web_search':
      raw = (args['query'] ?? '').toString();
    case 'skill':
    case 'skill_install':
      raw = (args['name'] ?? '').toString();
    case 'task':
      raw = (args['subagent'] ?? args['prompt'] ?? '').toString();
    case 'workflow':
      final named = (args['name'] ?? '').toString().trim();
      if (named.isNotEmpty) {
        raw = named;
      } else if (args['script'] != null) {
        raw = 'inline';
      } else {
        raw = 'list';
      }
    default:
      raw = (args['path'] ?? args['file'] ?? '').toString();
  }
  return _clipChip(raw);
}

String waifuChipCaption(String name, String detail) {
  final d = detail.trim();
  if (d.isEmpty || d == name) return name;
  return '$name $d';
}

String _clipChip(String raw, [int max = 42]) {
  final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.length <= max) return t;
  return '${t.substring(0, max).trimRight()}…';
}
