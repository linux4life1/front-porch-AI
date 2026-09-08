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
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/mcp/mcp_models.dart';
import 'package:front_porch_ai/services/mcp/mcp_stdio.dart';

/// Desktop spawn for stdio MCP. Kept off the HTTP client files.
Future<McpStdioSession> mcpSpawnStdio(McpServerConfig config) async {
  final command = config.command.trim();
  if (command.isEmpty) {
    throw StateError('stdio MCP needs a command');
  }
  debugPrint(
    '[MCP] stdio spawn command="$command" args=${config.args} '
    'name="${config.displayName}"',
  );
  final proc = await Process.start(
    command,
    config.args,
    environment: config.env.isEmpty ? null : config.env,
    includeParentEnvironment: true,
  );
  return McpStdioSession(
    stdout: proc.stdout,
    write: proc.stdin.add,
    flush: proc.stdin.flush,
    kill: () {
      unawaited(proc.stdin.close());
      proc.kill();
    },
    stderr: proc.stderr,
  );
}
