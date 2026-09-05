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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:front_porch_ai/services/desk/desk_fs.dart';
import 'package:front_porch_ai/services/desk/desk_permissions.dart';
import 'package:front_porch_ai/services/desk/desk_tools.dart';

const kDeskBashTimeout = Duration(seconds: 60);

/// Runs a command with cwd = project root. Hard-deny + no `cd` out.
class DeskBash {
  DeskBash(this.root, {this.timeout = kDeskBashTimeout});

  final String root;
  final Duration timeout;

  Future<DeskToolResult> run(Map<String, dynamic> args) async {
    final command =
        args['command']?.toString() ?? args['cmd']?.toString() ?? '';
    if (command.trim().isEmpty) {
      return DeskToolResult.error('bash: command is empty');
    }
    final blocked = deskBashBlocked(command);
    if (blocked != null) return DeskToolResult.error(blocked);

    late final Process proc;
    try {
      proc = await Process.start(
        'bash',
        ['-c', command],
        workingDirectory: root,
        includeParentEnvironment: true,
        runInShell: false,
      );
    } catch (e) {
      return DeskToolResult.error('bash: failed to start ($e)');
    }

    final out = StringBuffer();
    final err = StringBuffer();
    proc.stdout.transform(utf8.decoder).listen(out.write);
    proc.stderr.transform(utf8.decoder).listen(err.write);

    try {
      final code = await proc.exitCode.timeout(timeout);
      final body = _clip('exit $code\n$out${err.isEmpty ? '' : '\n$err'}');
      return DeskToolResult(ok: code == 0, output: body);
    } on TimeoutException {
      proc.kill();
      return DeskToolResult.error(
        'bash: timeout (${timeout.inMilliseconds}ms)',
      );
    }
  }
}

String? deskBashBlocked(String command) {
  final denied = deskDeniedCommand(command);
  if (denied != null) return denied;
  if (_cdsOut(command)) {
    return 'denied: bash cannot cd out of the project folder';
  }
  return null;
}

bool _cdsOut(String command) {
  final parts = command.split(RegExp(r'[;&|\n]'));
  for (final raw in parts) {
    var s = raw.trim();
    if (s.isEmpty) continue;
    if (!RegExp(r'^cd\b').hasMatch(s)) continue;
    final rest = s.replaceFirst(RegExp(r'^cd\s*'), '').trim();
    if (rest.isEmpty) continue;
    final dest = rest
        .split(RegExp(r'\s+'))
        .first
        .replaceAll('"', '')
        .replaceAll("'", '');
    if (dest.startsWith('..') || dest.startsWith('/') || dest.startsWith('~')) {
      return true;
    }
  }
  return false;
}

String _clip(String s) {
  if (s.length <= kDeskBashClipChars) return s;
  return '${s.substring(0, kDeskBashClipChars)}\n…(clipped)';
}
