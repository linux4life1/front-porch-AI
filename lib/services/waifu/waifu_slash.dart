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

import 'package:front_porch_ai/services/waifu/waifu_brand.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';

class WaifuSlashCommand {
  const WaifuSlashCommand({
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

const kWaifuSlashCommands = <WaifuSlashCommand>[
  WaifuSlashCommand(
    name: 'help',
    hint: '/help',
    blurb: 'List every slash command and what it does.',
  ),
  WaifuSlashCommand(
    name: 'skills',
    hint: '/skills [name]',
    blurb:
        'Skills marketplace. Bare /skills lists official + installed; '
        '/skills pdf installs that Claude skill.',
  ),
  WaifuSlashCommand(
    name: 'review',
    hint: '/review [focus]',
    blurb:
        'Code review this folder. Hostile: bugs, missing tests, residual risk.',
    local: false,
    runOnPick: false,
  ),
  WaifuSlashCommand(
    name: 'code-review',
    hint: '/code-review [focus]',
    blurb: 'Same as /review — code review this folder.',
    local: false,
    runOnPick: false,
  ),
  WaifuSlashCommand(
    name: 'init',
    hint: '/init',
    blurb: 'Write AGENTS.md in this folder so she has house rules.',
    local: false,
  ),
  WaifuSlashCommand(
    name: 'plan',
    hint: '/plan',
    blurb:
        'Switch to Plan — explore and write a plan under .waifu/plans/. '
        'Project source stays read-only.',
  ),
  WaifuSlashCommand(
    name: 'build',
    hint: '/build',
    blurb:
        'Switch to Build — in-folder writes just happen; mutating bash '
        'and off-porch paths still ask.',
  ),
  WaifuSlashCommand(
    name: 'yolo',
    hint: '/yolo',
    blurb:
        'Switch to Yolo — skip “are you sure?” (still not for critical repos).',
  ),
  WaifuSlashCommand(
    name: 'undo',
    hint: '/undo',
    blurb: 'Undo her last file write on disk.',
  ),
  WaifuSlashCommand(
    name: 'compact',
    hint: '/compact',
    blurb: 'Fold old turns into a recap when the context window is filling.',
  ),
  WaifuSlashCommand(
    name: 'stop',
    hint: '/stop',
    blurb: 'Stop the current run. Tools in flight are aborted.',
  ),
  WaifuSlashCommand(
    name: 'test',
    hint: '/test',
    blurb: 'She finds and runs the tests for this project.',
    local: false,
  ),
  WaifuSlashCommand(
    name: 'loop',
    hint: '/loop',
    blurb: 'She keeps going on the last task without a new prompt.',
    local: false,
  ),
  WaifuSlashCommand(
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
String? waifuSlashPrefix(String text) {
  final m = RegExp(r'^/([A-Za-z0-9_-]*)$').firstMatch(text.trim());
  return m?.group(1);
}

List<WaifuSlashCommand> waifuSlashMatches(String text) {
  final prefix = waifuSlashPrefix(text);
  if (prefix == null) return const [];
  final p = prefix.toLowerCase();
  return [
    for (final c in kWaifuSlashCommands)
      if (c.name.startsWith(p)) c,
  ];
}

WaifuSlashCommand? waifuSlashExact(String text) {
  final t = text.trim();
  if (!t.startsWith('/')) return null;
  final name = t.split(RegExp(r'\s+')).first.substring(1).toLowerCase();
  for (final c in kWaifuSlashCommands) {
    if (c.name == name) return c;
  }
  return null;
}

String waifuSlashHelpText() {
  final lines = [
    'Slash commands:',
    for (final c in kWaifuSlashCommands) '  ${c.hint} — ${c.blurb}',
  ];
  return lines.join('\n');
}

String waifuSlashAgentTask(String text) {
  final cmd = waifuSlashExact(text);
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

void waifuRewriteSlashUser(List<WaifuMessage> transcript, String text) {
  final cmd = waifuSlashExact(text);
  if (cmd == null || cmd.local) return;
  final expanded = waifuSlashAgentTask(text);
  if (expanded == text || transcript.isEmpty) return;
  transcript[transcript.length - 1] = WaifuMessage.user(expanded);
}

Map<String, dynamic>? waifuWorkflowSlashArgs(String text) {
  final cmd = waifuSlashExact(text);
  if (cmd == null || cmd.name != 'workflow') return null;
  final rest = text
      .trim()
      .replaceFirst(RegExp(r'^/workflow\s*', caseSensitive: false), '')
      .trim();
  if (rest.isEmpty) return <String, dynamic>{};
  return {'name': rest.split(RegExp(r'\s+')).first};
}

WaifuMode? waifuSlashMode(String name) {
  switch (name) {
    case 'plan':
      return WaifuMode.plan;
    case 'build':
      return WaifuMode.build;
    case 'yolo':
      return WaifuMode.yolo;
    default:
      return null;
  }
}
