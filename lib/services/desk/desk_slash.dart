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

import 'package:front_porch_ai/services/desk/desk_brand.dart';
import 'package:front_porch_ai/services/desk/desk_session.dart';
import 'package:front_porch_ai/services/desk/desk_sit_down.dart';

class DeskSlashCommand {
  const DeskSlashCommand({
    required this.name,
    required this.hint,
    required this.blurb,
    this.local = true,
    this.runOnPick = true,
  });

  final String name;
  final String hint;
  final String blurb;
  final bool local;
  final bool runOnPick;
}

const kDeskSlashCommands = <DeskSlashCommand>[
  DeskSlashCommand(
    name: 'help',
    hint: '/help',
    blurb: 'List every slash command and what it does.',
  ),
  DeskSlashCommand(
    name: 'skills',
    hint: '/skills [name]',
    blurb:
        'Skills marketplace. Bare /skills lists official + installed; '
        '/skills pdf installs that Claude skill.',
  ),
  DeskSlashCommand(
    name: 'review',
    hint: '/review [focus]',
    blurb:
        'Code review this folder. Hostile: bugs, missing tests, residual risk.',
    local: false,
    runOnPick: false,
  ),
  DeskSlashCommand(
    name: 'code-review',
    hint: '/code-review [focus]',
    blurb: 'Same as /review — code review this folder.',
    local: false,
    runOnPick: false,
  ),
  DeskSlashCommand(
    name: 'init',
    hint: '/init',
    blurb: 'Write AGENTS.md in this folder so she has house rules.',
    local: false,
  ),
  DeskSlashCommand(
    name: 'plan',
    hint: '/plan',
    blurb: 'Switch to Plan — she asks before writes and shell.',
  ),
  DeskSlashCommand(
    name: 'build',
    hint: '/build',
    blurb: 'Switch to Build — asks on the first write, then goes.',
  ),
  DeskSlashCommand(
    name: 'yolo',
    hint: '/yolo',
    blurb:
        'Switch to Yolo — skip “are you sure?” (still not for critical repos).',
  ),
  DeskSlashCommand(
    name: 'undo',
    hint: '/undo',
    blurb: 'Undo her last file write on disk.',
  ),
  DeskSlashCommand(
    name: 'compact',
    hint: '/compact',
    blurb: 'Fold old turns into a recap to free context.',
  ),
  DeskSlashCommand(
    name: 'stop',
    hint: '/stop',
    blurb: 'Stop the current run. Tools in flight are aborted.',
  ),
  DeskSlashCommand(
    name: 'test',
    hint: '/test',
    blurb: 'She finds and runs the tests for this project.',
    local: false,
  ),
  DeskSlashCommand(
    name: 'loop',
    hint: '/loop',
    blurb: 'She keeps going on the last task without a new prompt.',
    local: false,
  ),
  DeskSlashCommand(
    name: 'workflow',
    hint: '/workflow [name]',
    blurb:
        'List or run a JSON pipeline in $kWaifuDotDir/workflows. Not a Rhai script.',
    local: false,
    runOnPick: false,
  ),
];

/// Prefix after `/` while the box is only a command token (`/`, `/he`, …).
/// Hyphens are allowed so `/code-review` stays a command.
String? deskSlashPrefix(String text) {
  final m = RegExp(r'^/([A-Za-z0-9_-]*)$').firstMatch(text.trim());
  return m?.group(1);
}

List<DeskSlashCommand> deskSlashMatches(String text) {
  final prefix = deskSlashPrefix(text);
  if (prefix == null) return const [];
  final p = prefix.toLowerCase();
  return [
    for (final c in kDeskSlashCommands)
      if (c.name.startsWith(p)) c,
  ];
}

DeskSlashCommand? deskSlashExact(String text) {
  final t = text.trim();
  if (!t.startsWith('/')) return null;
  final name = t.split(RegExp(r'\s+')).first.substring(1).toLowerCase();
  for (final c in kDeskSlashCommands) {
    if (c.name == name) return c;
  }
  return null;
}

String deskSlashHelpText() {
  final lines = [
    'Slash commands:',
    for (final c in kDeskSlashCommands) '  ${c.hint} — ${c.blurb}',
  ];
  return lines.join('\n');
}

String deskSlashAgentTask(String text) {
  final cmd = deskSlashExact(text);
  if (cmd == null) return text;
  final rest = text
      .trim()
      .replaceFirst(RegExp('^/${cmd.name}\\s*', caseSensitive: false), '')
      .trim();
  switch (cmd.name) {
    case 'review':
    case 'code-review':
      return rest.isEmpty
          ? 'Review this folder. Be hostile. Name bugs, missing tests, and residual risk.'
          : 'Review this folder with focus: $rest. Be hostile.';
    case 'test':
      return 'Find and run the tests for this project. Report failures with the file and name.';
    case 'loop':
      return 'Continue the last task. Do not wait for a new brief.';
    case 'workflow':
      return rest.isEmpty
          ? 'List saved workflows under $kWaifuDotDir/workflows, then stop.'
          : 'Run the saved workflow named $rest.';
    case 'init':
      return text;
    default:
      return text;
  }
}

void deskRewriteSlashUser(List<DeskMessage> transcript, String text) {
  final cmd = deskSlashExact(text);
  if (cmd == null || cmd.local) return;
  final expanded = deskSlashAgentTask(text);
  if (expanded == text || transcript.isEmpty) return;
  transcript[transcript.length - 1] = DeskMessage(isUser: true, text: expanded);
}

Map<String, dynamic>? deskWorkflowSlashArgs(String text) {
  final cmd = deskSlashExact(text);
  if (cmd == null || cmd.name != 'workflow') return null;
  final rest = text
      .trim()
      .replaceFirst(RegExp(r'^/workflow\s*', caseSensitive: false), '')
      .trim();
  if (rest.isEmpty) return <String, dynamic>{};
  return {'name': rest.split(RegExp(r'\s+')).first};
}

DeskMode? deskSlashMode(String name) {
  switch (name) {
    case 'plan':
      return DeskMode.plan;
    case 'build':
      return DeskMode.build;
    case 'yolo':
      return DeskMode.yolo;
    default:
      return null;
  }
}
