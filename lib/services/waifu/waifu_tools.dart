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

import 'package:front_porch_ai/services/waifu/waifu_jail.dart';

/// Runaway fuse, not a chat-length cap. The model stops when it stops.
const kWaifuMaxSteps = 80;
const kWaifuReadClipChars = 100000;

/// Default and hard max for `read`. Whole-file dumps choke coding models.
const kWaifuReadDefaultLines = 200;
const kWaifuGrepMaxHits = 50;
const kWaifuBashClipChars = 32000;

const kWaifuToolRead = 'read';
const kWaifuToolEdit = 'edit';
const kWaifuToolApplyPatch = 'apply_patch';
const kWaifuToolWrite = 'write';
const kWaifuToolGlob = 'glob';
const kWaifuToolGrep = 'grep';
const kWaifuToolBash = 'bash';
const kWaifuToolTodoRead = 'todoread';
const kWaifuToolTodoWrite = 'todowrite';
const kWaifuToolQuestion = 'question';
const kWaifuToolSkill = 'skill';
const kWaifuToolSkillInstall = 'skill_install';
const kWaifuToolWebFetch = 'webfetch';
const kWaifuToolWebSearch = 'web_search';
const kWaifuToolTask = 'task';
const kWaifuToolWorkflow = 'workflow';

const kWaifuFsToolNames = {
  kWaifuToolRead,
  kWaifuToolEdit,
  kWaifuToolApplyPatch,
  kWaifuToolWrite,
  kWaifuToolGlob,
  kWaifuToolGrep,
};

/// File tools plus bash. Their path wording follows the sit-down scope.
List<Map<String, dynamic>> waifuFileToolsFor(WaifuPathMode pathMode) {
  final open = pathMode == WaifuPathMode.wholeDisk;
  final pathHelp = open
      ? 'Relative paths start at the sit-down folder; absolute, ~, and .. '
            'paths may walk the disk'
      : 'Paths stay inside the sit-down folder; outside absolute, ~, .., and '
            'symlink targets are denied by the folder jail';
  return [
    _fn(
      kWaifuToolRead,
      'Read a file in a line window. Default and max '
      '$kWaifuReadDefaultLines lines from offset (1-based). '
      'If the result says more lines remain, call again with that '
      'offset. $pathHelp.',
      {
        'path': {'type': 'string', 'description': pathHelp},
        'offset': {
          'type': 'integer',
          'description':
              '1-based start line. Default 1. Use the next offset '
              'from a previous read to continue.',
        },
        'limit': {
          'type': 'integer',
          'description':
              'Lines to return. Default and max $kWaifuReadDefaultLines.',
        },
      },
      const ['path'],
    ),
    _fn(
      kWaifuToolEdit,
      'Replace exactly one occurrence of old_string with new_string. $pathHelp.',
      {
        'path': {'type': 'string'},
        'old_string': {'type': 'string'},
        'new_string': {'type': 'string'},
      },
      const ['path', 'old_string', 'new_string'],
    ),
    _fn(
      kWaifuToolApplyPatch,
      'Apply one or more exact unified-diff hunks to one text file. $pathHelp.',
      {
        'path': {'type': 'string', 'description': pathHelp},
        'patch': {
          'type': 'string',
          'description':
              'Unified diff hunks, optionally wrapped in *** Begin Patch',
        },
      },
      const ['path', 'patch'],
    ),
    _fn(
      kWaifuToolWrite,
      'Create or overwrite a file. $pathHelp.',
      {
        'path': {'type': 'string'},
        'contents': {'type': 'string'},
      },
      const ['path', 'contents'],
    ),
    _fn(
      kWaifuToolGlob,
      'List files matching a glob. Default is the sit-down folder. $pathHelp.',
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
      kWaifuToolGrep,
      'Search file contents. $pathHelp.',
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
      kWaifuToolBash,
      open
          ? 'Run a shell command. Cwd starts at the sit-down folder; cd elsewhere '
                'is allowed. Secret and wipe/destroy-class commands are denied.'
          : 'Run a shell command inside the folder jail. Cwd starts at the '
                'sit-down folder; paths and cd cannot leave it. Secret and '
                'wipe/destroy-class commands are denied.',
      {
        'command': {'type': 'string', 'description': 'Command to run'},
      },
      const ['command'],
    ),
    _fn(kWaifuToolTodoRead, 'Read the current todo list.', const {}, const []),
    _fn(
      kWaifuToolTodoWrite,
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
      kWaifuToolQuestion,
      'Ask the user a question with optional choices. They can pick a '
      'choice or type a custom answer. Pauses until they answer. Use only '
      'for a real fork, not a keep-going prompt.',
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
      kWaifuToolSkill,
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
      kWaifuToolSkillInstall,
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
}

final List<Map<String, dynamic>> kWaifuFileTools = waifuFileToolsFor(
  WaifuPathMode.folderJail,
);
final List<Map<String, dynamic>> kWaifuWholeDiskFileTools = waifuFileToolsFor(
  WaifuPathMode.wholeDisk,
);

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

String waifuBareToolName(String name) {
  var n = name.trim();
  final i = n.lastIndexOf('__');
  if (i >= 0 && i < n.length - 2) n = n.substring(i + 2);
  return n;
}

/// Local models sometimes emit OpenCode / Desktop Commander aliases.
String canonicalWaifuToolName(String name) {
  switch (waifuBareToolName(name)) {
    case 'read_file':
    case 'readFile':
      return kWaifuToolRead;
    case 'write_file':
    case 'writeFile':
      return kWaifuToolWrite;
    case 'search_replace':
    case 'edit_block':
      return kWaifuToolEdit;
    case 'patch':
    case 'applyPatch':
      return kWaifuToolApplyPatch;
    case 'run_command':
    case 'shell':
    case 'start_process':
      return kWaifuToolBash;
    case 'list_directory':
    case 'directory_tree':
      return kWaifuToolGlob;
    case 'search_files':
      return kWaifuToolGrep;
    case 'todo_read':
    case 'todoRead':
      return kWaifuToolTodoRead;
    case 'todo_write':
    case 'todoWrite':
      return kWaifuToolTodoWrite;
    case 'explore':
    case 'general':
    case 'task':
      return kWaifuToolTask;
    case 'workflow':
      return kWaifuToolWorkflow;
    default:
      return name;
  }
}

Map<String, dynamic> waifuNormalizeToolArgs(
  String original,
  Map<String, dynamic> args,
) {
  final canon = canonicalWaifuToolName(original);
  if (canon == kWaifuToolGlob) {
    final pattern = (args['pattern'] ?? args['glob'] ?? '').toString();
    if (pattern.trim().isEmpty) {
      return {...args, 'pattern': '*'};
    }
  }
  if (canon == kWaifuToolGrep) {
    final pattern = (args['pattern'] ?? '').toString();
    final query = args['query']?.toString();
    if (pattern.trim().isEmpty && query != null && query.trim().isNotEmpty) {
      return {...args, 'pattern': query};
    }
  }
  if (canon == kWaifuToolBash) {
    final cmd = (args['command'] ?? args['cmd'] ?? '').toString();
    if (cmd.trim().isEmpty && args['args'] is List) {
      return {...args, 'command': (args['args'] as List).join(' ')};
    }
  }
  return args;
}

String? waifuToolPathArg(Map<String, dynamic> args) {
  final v =
      args['path'] ?? args['file_path'] ?? args['filename'] ?? args['file'];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// 1-based start line for `read`. Missing or invalid → 1.
int waifuReadOffsetArg(Map<String, dynamic>? args) {
  final n = _toolInt(args, 'offset');
  if (n == null || n < 1) return 1;
  return n;
}

/// Line window for `read`. Missing, invalid, or over the max → default.
int waifuReadLimitArg(Map<String, dynamic>? args) {
  final n = _toolInt(args, 'limit');
  if (n == null || n < 1) return kWaifuReadDefaultLines;
  if (n > kWaifuReadDefaultLines) return kWaifuReadDefaultLines;
  return n;
}

/// Same path + same window. Used to stub duplicate reads without
/// blocking a later offset of that file.
String waifuReadWindowKey(Map<String, dynamic>? args) =>
    '${waifuReadOffsetArg(args)}:${waifuReadLimitArg(args)}';

int? _toolInt(Map<String, dynamic>? args, String key) {
  if (args == null) return null;
  final v = args[key];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// Caption for a tool chip. Never repeats the tool name as the detail
/// (that rendered as "bash bash" in the transcript).
String waifuChipDetail(String name, Map<String, dynamic> args) {
  switch (canonicalWaifuToolName(name)) {
    case kWaifuToolBash:
      return _clipChip(
        (args['command'] ?? args['cmd'] ?? args['script'] ?? '').toString(),
      );
    case kWaifuToolGlob:
      return _clipChip((args['pattern'] ?? args['glob'] ?? '').toString());
    case kWaifuToolGrep:
      return _clipChip((args['pattern'] ?? args['query'] ?? '').toString());
    case kWaifuToolWebFetch:
      return _clipChip((args['url'] ?? '').toString());
    case kWaifuToolWebSearch:
      return _clipChip((args['query'] ?? '').toString());
    case kWaifuToolSkill:
    case kWaifuToolSkillInstall:
      return _clipChip((args['name'] ?? '').toString());
    case kWaifuToolTask:
      return _clipChip((args['subagent'] ?? args['prompt'] ?? '').toString());
    case kWaifuToolWorkflow:
      final n = (args['name'] ?? '').toString().trim();
      if (n.isNotEmpty) return _clipChip(n);
      if (args['script'] != null) return 'inline';
      return 'list';
    default:
      return _clipChip(waifuToolPathArg(args) ?? '');
  }
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
