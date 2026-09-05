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

const kDeskMaxSteps = 20;
const kDeskReadClipChars = 100000;
const kDeskGrepMaxHits = 50;
const kDeskBashClipChars = 32000;

const kDeskToolRead = 'read';
const kDeskToolEdit = 'edit';
const kDeskToolWrite = 'write';
const kDeskToolGlob = 'glob';
const kDeskToolGrep = 'grep';
const kDeskToolBash = 'bash';

/// File tools plus bash. Plan/Build/Yolo gating is DeskPermissions.
final List<Map<String, dynamic>> kDeskFileTools = [
  _fn(
    kDeskToolRead,
    'Read a file in the project folder. Paths are relative to the folder.',
    {
      'path': {'type': 'string', 'description': 'Path relative to the project'},
      'offset': {'type': 'integer', 'description': '1-based start line'},
      'limit': {'type': 'integer', 'description': 'Max lines to return'},
    },
    const ['path'],
  ),
  _fn(
    kDeskToolEdit,
    'Replace exactly one occurrence of old_string with new_string in a file.',
    {
      'path': {'type': 'string'},
      'old_string': {'type': 'string'},
      'new_string': {'type': 'string'},
    },
    const ['path', 'old_string', 'new_string'],
  ),
  _fn(
    kDeskToolWrite,
    'Create or overwrite a file in the project folder.',
    {
      'path': {'type': 'string'},
      'contents': {'type': 'string'},
    },
    const ['path', 'contents'],
  ),
  _fn(
    kDeskToolGlob,
    'List files under the project folder matching a glob (e.g. **/*.dart).',
    {
      'pattern': {'type': 'string'},
    },
    const ['pattern'],
  ),
  _fn(
    kDeskToolGrep,
    'Search file contents in the project folder.',
    {
      'pattern': {'type': 'string'},
      'path': {'type': 'string', 'description': 'Optional file or directory'},
      'glob': {'type': 'string', 'description': 'Optional filename glob'},
    },
    const ['pattern'],
  ),
  _fn(
    kDeskToolBash,
    'Run a shell command in the project folder. cwd is the folder. '
    'Cannot cd out. Destructive git and rm -rf / are denied.',
    {
      'command': {'type': 'string', 'description': 'Command to run'},
    },
    const ['command'],
  ),
];

Map<String, dynamic> _fn(
  String name,
  String description,
  Map<String, dynamic> properties,
  List<String> required,
) {
  return {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': properties,
        'required': required,
      },
    },
  };
}

/// Local models sometimes emit OpenCode-ish aliases.
String canonicalDeskToolName(String name) {
  switch (name) {
    case 'read_file':
    case 'readFile':
      return kDeskToolRead;
    case 'write_file':
    case 'writeFile':
      return kDeskToolWrite;
    case 'search_replace':
      return kDeskToolEdit;
    case 'run_command':
    case 'shell':
      return kDeskToolBash;
    default:
      return name;
  }
}

String? deskToolPathArg(Map<String, dynamic> args) {
  final v =
      args['path'] ?? args['file_path'] ?? args['filename'] ?? args['file'];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}
