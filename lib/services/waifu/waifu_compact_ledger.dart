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

import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_tools.dart';
import 'package:front_porch_ai/services/waifu/waifu_verify.dart';

const kWaifuMachineLedgerTitle = 'MACHINE LEDGER';

/// Non-LLM receipt block for a fold. Paths and commands are copied as-run
/// from tool messages — the recap must not invent either.
String waifuMachineLedger({
  required List<WaifuMessage> folded,
  String? planPin,
  String todos = '',
}) {
  final paths = <String>{};
  final cmds = <String>[];
  for (final m in folded) {
    if (m.kind != WaifuMsgKind.tool) continue;
    final path = (m.toolPath ?? m.toolArgs?['path']?.toString() ?? '').trim();
    if (path.isNotEmpty) paths.add(path.replaceAll('\\', '/'));
    if ((m.toolName ?? '') == kWaifuToolBash) {
      final cmd = (m.toolArgs?['command'] ?? m.toolArgs?['cmd'] ?? '')
          .toString()
          .trim();
      // As-run string only — never a guessed host stack. Theater (ls/echo)
      // is not a verify even if bash ran it.
      if (cmd.isNotEmpty && waifuLooksVerifyCommand(cmd)) cmds.add(cmd);
    }
  }
  final buf = StringBuffer(kWaifuMachineLedgerTitle)..writeln();
  buf.writeln('paths:');
  if (paths.isEmpty) {
    buf.writeln('  (none)');
  } else {
    for (final path in paths) {
      buf.writeln('  $path');
    }
  }
  buf.writeln('verify as-run:');
  if (cmds.isEmpty) {
    buf.writeln('  (none)');
  } else {
    for (final cmd in cmds) {
      buf.writeln('  $cmd');
    }
  }
  final pin = planPin?.trim() ?? '';
  buf.writeln('plan: ${pin.isEmpty ? '(none)' : pin}');
  buf.writeln('todos:');
  final todo = todos.trim();
  if (todo.isEmpty || todo == '(no todos)') {
    buf.writeln('  (none)');
  } else {
    for (final line in todo.split('\n')) {
      if (line.trim().isEmpty) continue;
      buf.writeln('  $line');
    }
  }
  return buf.toString().trimRight();
}

/// Put the ledger under the compact prefix so a fold always keeps facts
/// even when the LLM recap is empty or invents names.
String waifuInjectMachineLedger(String recap, String ledger) {
  final facts = ledger.trim();
  if (facts.isEmpty) return recap;
  // Same facts already in the recap. A title-only invented block is not
  // a receipt — still inject the as-run ledger.
  // Same facts already in the recap. A title-only invented block is not
  // a receipt — still inject the as-run ledger.
  if (recap.contains(facts)) return recap;
  const prefix = '[Session compact]';
  if (recap.startsWith(prefix)) {
    final rest = recap.substring(prefix.length).trimLeft();
    return rest.isEmpty ? '$prefix\n$facts' : '$prefix\n$facts\n$rest';
  }
  return recap.trim().isEmpty ? facts : '${recap.trimRight()}\n$facts';
}
