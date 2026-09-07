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

import 'package:front_porch_ai/services/waifu/waifu_fs.dart';
import 'package:front_porch_ai/services/waifu/waifu_permissions.dart';
import 'package:front_porch_ai/services/waifu/waifu_tools.dart';

const kWaifuBashTimeout = Duration(seconds: 60);

/// Runs a command. Default cwd is the sit-down folder. `cd` elsewhere is
/// allowed. Destructive git / `rm -rf /` stay denied.
class WaifuBash {
  WaifuBash(this.root, {this.timeout = kWaifuBashTimeout});

  final String root;
  final Duration timeout;

  Future<WaifuToolResult> run(Map<String, dynamic> args) async {
    final command =
        args['command']?.toString() ?? args['cmd']?.toString() ?? '';
    if (command.trim().isEmpty) {
      return WaifuToolResult.error('bash: command is empty');
    }
    final blocked = waifuBashBlocked(command);
    if (blocked != null) return WaifuToolResult.error(blocked);

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
      return WaifuToolResult.error('bash: failed to start ($e)');
    }

    final outFuture = proc.stdout.transform(utf8.decoder).join();
    final errFuture = proc.stderr.transform(utf8.decoder).join();

    try {
      final code = await proc.exitCode.timeout(timeout);
      final stdout = await outFuture;
      final stderr = await errFuture;
      final body = _clip(
        'exit $code\n$stdout${stderr.isEmpty ? '' : '\n$stderr'}',
      );
      return WaifuToolResult(ok: code == 0, output: body);
    } on TimeoutException {
      proc.kill();
      return WaifuToolResult.error(
        'bash: timeout (${timeout.inMilliseconds}ms)',
      );
    }
  }
}

String? waifuBashBlocked(String command) => waifuDeniedCommand(command);

String _clip(String s) {
  if (s.length <= kWaifuBashClipChars) return s;
  return '${s.substring(0, kWaifuBashClipChars)}\n…(clipped)';
}
