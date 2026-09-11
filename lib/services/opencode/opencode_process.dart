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

import 'dart:io';

/// What [OpenCodeManager] asked the OS to spawn. Tests assert this instead
/// of talking to Homebrew.
class OpenCodeSpawnRequest {
  const OpenCodeSpawnRequest({
    required this.executable,
    required this.arguments,
    required this.environment,
    this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final String? workingDirectory;
}

typedef OpenCodeSpawn =
    Future<OpenCodeProcessHandle> Function(OpenCodeSpawnRequest request);

/// Own PID only. Never `pkill -f opencode` — that would kill a brew copy.
class OpenCodeProcessHandle {
  OpenCodeProcessHandle({
    required this.pid,
    required void Function(ProcessSignal signal) kill,
    Future<int>? exitCode,
  }) : _kill = kill,
       exitCode = exitCode ?? Future<int>.value(0);

  factory OpenCodeProcessHandle.fake({
    required int pid,
    void Function()? onKill,
  }) {
    return OpenCodeProcessHandle(pid: pid, kill: (_) => onKill?.call());
  }

  final int pid;
  final void Function(ProcessSignal signal) _kill;
  final Future<int> exitCode;

  void kill([ProcessSignal signal = ProcessSignal.sigterm]) => _kill(signal);
}

OpenCodeProcessHandle openCodeHandleForProcess(Process process) {
  return OpenCodeProcessHandle(
    pid: process.pid,
    kill: process.kill,
    exitCode: process.exitCode,
  );
}

Future<OpenCodeProcessHandle> openCodeSpawnProcess(
  OpenCodeSpawnRequest request,
) async {
  final process = await Process.start(
    request.executable,
    request.arguments,
    environment: request.environment,
    workingDirectory: request.workingDirectory,
    includeParentEnvironment: true,
  );
  return openCodeHandleForProcess(process);
}
