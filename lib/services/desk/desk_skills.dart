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
import 'package:path/path.dart' as p;

const kDeskAgentsTemplate =
    '# AGENTS.md\n\n'
    'This is a Desk project. Prefer small diffs. Stay in character.\n'
    'Do not invent files you did not read.\n';

const kDeskAgentsPath = 'AGENTS.md';

/// Load a skill file. Tries `.desk/skills/<name>/SKILL.md`,
/// `.opencode/skills/<name>/SKILL.md`, then `SKILL.md`.
Future<String> deskLoadSkill(String root, String name) async {
  final trimmed = name.trim();
  final candidates = <String>[
    if (trimmed.isNotEmpty) p.join('.desk', 'skills', trimmed, 'SKILL.md'),
    if (trimmed.isNotEmpty) p.join('.opencode', 'skills', trimmed, 'SKILL.md'),
    if (trimmed.isNotEmpty) p.join('skills', trimmed, 'SKILL.md'),
    'SKILL.md',
  ];
  for (final rel in candidates) {
    final hit = await DeskJail.resolveLive(root, rel);
    if (!hit.ok) continue;
    final file = File(hit.path!);
    if (!await file.exists()) continue;
    return await file.readAsString();
  }
  return 'skill not found: $name';
}
