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
const kDeskToolTodoRead = 'todoread';
const kDeskToolTodoWrite = 'todowrite';
const kDeskToolQuestion = 'question';
const kDeskToolSkill = 'skill';
const kDeskToolSkillInstall = 'skill_install';
const kDeskToolWebFetch = 'webfetch';
const kDeskToolWebSearch = 'web_search';
const kDeskToolTask = 'task';
const kDeskToolWorkflow = 'workflow';

/// File tools plus bash. Plan/Build/Yolo gating is DeskPermissions.
final List<Map<String, dynamic>> kDeskFileTools = [
  _fn(
    kDeskToolRead,
    'Read a file. Relative to the sit-down folder, or absolute / ~ / ..',
    {
      'path': {
        'type': 'string',
        'description':
            'Relative to the project folder, or an absolute/~ /.. path',
      },
      'offset': {'type': 'integer', 'description': '1-based start line'},
      'limit': {'type': 'integer', 'description': 'Max lines to return'},
    },
    const ['path'],
  ),
  _fn(
    kDeskToolEdit,
    'Replace exactly one occurrence of old_string with new_string. '
    'Path may be relative, absolute, ~, or ..',
    {
      'path': {'type': 'string'},
      'old_string': {'type': 'string'},
      'new_string': {'type': 'string'},
    },
    const ['path', 'old_string', 'new_string'],
  ),
  _fn(
    kDeskToolWrite,
    'Create or overwrite a file. Path may be relative, absolute, ~, or ..',
    {
      'path': {'type': 'string'},
      'contents': {'type': 'string'},
    },
    const ['path', 'contents'],
  ),
  _fn(
    kDeskToolGlob,
    'List files matching a glob. Default folder is the sit-down project. '
    'Pass path to search elsewhere (absolute / ~ / .. allowed).',
    {
      'pattern': {'type': 'string'},
      'path': {
        'type': 'string',
        'description': 'Folder to search. Default: project folder.',
      },
    },
    const ['pattern'],
  ),
  _fn(
    kDeskToolGrep,
    'Search file contents. path may be relative, absolute, ~, or ..',
    {
      'pattern': {'type': 'string'},
      'path': {
        'type': 'string',
        'description': 'File or directory. Default: project folder.',
      },
      'glob': {'type': 'string', 'description': 'Optional filename glob'},
    },
    const ['pattern'],
  ),
  _fn(
    kDeskToolBash,
    'Run a shell command. Default cwd is the sit-down folder; cd elsewhere '
    'is allowed. Destructive git and rm -rf / are denied.',
    {
      'command': {'type': 'string', 'description': 'Command to run'},
    },
    const ['command'],
  ),
  _fn(kDeskToolTodoRead, 'Read the current todo list.', const {}, const []),
  _fn(
    kDeskToolTodoWrite,
    'Replace the todo list. Each item: id, content, status.',
    {
      'todos': {
        'type': 'array',
        'items': {'type': 'object'},
      },
    },
    const ['todos'],
  ),
  _fn(
    kDeskToolQuestion,
    'Ask the user a question with optional choices. Pauses until they answer.',
    {
      'prompt': {'type': 'string'},
      'choices': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    const ['prompt'],
  ),
  _fn(
    kDeskToolSkill,
    'Load the full SKILL.md for an installed skill. Prefer this after '
    'reading the installed-skills list. Also loads SKILL.md from '
    '~/.waifu/skills, this project\'s .waifu/skills, and other harness '
    'folders (~/.claude, ~/.grok, ~/.hermes) by name.',
    {
      'name': {'type': 'string'},
    },
    const ['name'],
  ),
  _fn(
    kDeskToolSkillInstall,
    'Install a skill from the allowlisted HTTPS catalogs (Anthropic, '
    'Vercel, Superpowers) into ~/.waifu/skills (Waifu Coder), then load '
    'it with skill.',
    {
      'name': {
        'type': 'string',
        'description': 'Skill folder name, e.g. pdf or frontend-design',
      },
    },
    const ['name'],
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

String deskBareToolName(String name) {
  var n = name.trim();
  final i = n.lastIndexOf('__');
  if (i >= 0 && i < n.length - 2) n = n.substring(i + 2);
  return n;
}

/// Local models sometimes emit OpenCode / Desktop Commander aliases.
String canonicalDeskToolName(String name) {
  switch (deskBareToolName(name)) {
    case 'read_file':
    case 'readFile':
      return kDeskToolRead;
    case 'write_file':
    case 'writeFile':
      return kDeskToolWrite;
    case 'search_replace':
    case 'edit_block':
      return kDeskToolEdit;
    case 'run_command':
    case 'shell':
    case 'start_process':
      return kDeskToolBash;
    case 'list_directory':
    case 'directory_tree':
      return kDeskToolGlob;
    case 'search_files':
      return kDeskToolGrep;
    case 'todo_read':
    case 'todoRead':
      return kDeskToolTodoRead;
    case 'todo_write':
    case 'todoWrite':
      return kDeskToolTodoWrite;
    case 'explore':
    case 'general':
    case 'task':
      return kDeskToolTask;
    case 'workflow':
      return kDeskToolWorkflow;
    default:
      return name;
  }
}

Map<String, dynamic> deskNormalizeToolArgs(
  String original,
  Map<String, dynamic> args,
) {
  final canon = canonicalDeskToolName(original);
  if (canon == kDeskToolGlob) {
    final pattern = (args['pattern'] ?? args['glob'] ?? '').toString();
    if (pattern.trim().isEmpty) {
      return {...args, 'pattern': '*'};
    }
  }
  if (canon == kDeskToolGrep) {
    final pattern = (args['pattern'] ?? '').toString();
    final query = args['query']?.toString();
    if (pattern.trim().isEmpty && query != null && query.trim().isNotEmpty) {
      return {...args, 'pattern': query};
    }
  }
  if (canon == kDeskToolBash) {
    final cmd = (args['command'] ?? args['cmd'] ?? '').toString();
    if (cmd.trim().isEmpty && args['args'] is List) {
      return {...args, 'command': (args['args'] as List).join(' ')};
    }
  }
  return args;
}

String? deskToolPathArg(Map<String, dynamic> args) {
  final v =
      args['path'] ?? args['file_path'] ?? args['filename'] ?? args['file'];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// Caption for a tool chip. Never repeats the tool name as the detail
/// (that rendered as "bash bash" in the transcript).
String deskChipDetail(String name, Map<String, dynamic> args) {
  switch (canonicalDeskToolName(name)) {
    case kDeskToolBash:
      return _clipChip(
        (args['command'] ?? args['cmd'] ?? args['script'] ?? '').toString(),
      );
    case kDeskToolGlob:
      return _clipChip((args['pattern'] ?? args['glob'] ?? '').toString());
    case kDeskToolGrep:
      return _clipChip((args['pattern'] ?? args['query'] ?? '').toString());
    case kDeskToolWebFetch:
      return _clipChip((args['url'] ?? '').toString());
    case kDeskToolWebSearch:
      return _clipChip((args['query'] ?? '').toString());
    case kDeskToolSkill:
    case kDeskToolSkillInstall:
      return _clipChip((args['name'] ?? '').toString());
    case kDeskToolTask:
      return _clipChip((args['subagent'] ?? args['prompt'] ?? '').toString());
    case kDeskToolWorkflow:
      final n = (args['name'] ?? '').toString().trim();
      if (n.isNotEmpty) return _clipChip(n);
      if (args['script'] != null) return 'inline';
      return 'list';
    default:
      return _clipChip(deskToolPathArg(args) ?? '');
  }
}

String deskChipCaption(String name, String detail) {
  final d = detail.trim();
  if (d.isEmpty || d == name) return name;
  return '$name $d';
}

String _clipChip(String raw, [int max = 42]) {
  final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.length <= max) return t;
  return '${t.substring(0, max).trimRight()}…';
}
