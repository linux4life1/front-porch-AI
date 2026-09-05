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

import 'package:front_porch_ai/services/desk/desk_tools.dart';

const kDeskExploreToolNames = {kDeskToolRead, kDeskToolGlob, kDeskToolGrep};

/// Nested Explore (read-only) or General (same jail). Scout is not shipped.
final kDeskTaskToolSchema = <String, dynamic>{
  'type': 'function',
  'function': {
    'name': kDeskToolTask,
    'description':
        'Run a nested Explore (read-only) or General (same folder jail) '
        'agent and wait. The child cannot leave the project folder or spawn '
        'another nested agent.',
    'parameters': {
      'type': 'object',
      'properties': {
        'subagent': {'type': 'string', 'description': 'explore or general'},
        'prompt': {
          'type': 'string',
          'description': 'What the nested agent should do',
        },
      },
      'required': ['subagent', 'prompt'],
    },
  },
};

String? deskSubagentKind(String name, Map<String, dynamic> args) {
  switch (name.trim().toLowerCase()) {
    case 'explore':
      return 'explore';
    case 'general':
      return 'general';
  }
  final v = (args['subagent'] ?? args['type'] ?? args['agent'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  if (v == 'explore' || v == 'general') return v;
  return null;
}
