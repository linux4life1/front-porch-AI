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

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Killing KoboldCpp, cross-platform — the escalation ladder and the
/// process-name fallbacks, lifted out of `kobold_service.dart` so that file is
/// about the SERVICE (state machine, transport, readiness) and this one is
/// about the OS. Nothing here touches service state: the caller owns
/// `_process`/`_isRunning` and clears them once these return.
///
/// Both functions are best-effort by contract. A backend that is already dead,
/// a `pkill` that does not exist, a PID that has been recycled — none of that
/// is an error worth surfacing, and every path here is expected to be reached
/// during app shutdown, where throwing would strand the rest of the teardown.

/// Kill KoboldCpp processes left behind by a PREVIOUS app instance — e.g.
/// after an update where `exit(0)` bypassed cleanup, which leaves a server
/// holding port 5001 that this run has no `Process` handle for and therefore
/// cannot stop any other way.
///
/// Not by PID for exactly that reason. On Windows all three shipped
/// executable names are swept, including the non-AVX2 `oldpc` build, which is
/// a distinct image and was the one that used to survive. `taskkill` cannot
/// filter by folder, so on Windows a KoboldCpp the user started themselves
/// under one of those names is still caught.
///
/// Elsewhere only processes launched from [binDir], the app's own engine
/// folder, are killed. The old `pkill -f koboldcpp` took down any KoboldCpp
/// on the machine, including one the user was running for something else.
Future<void> killOrphanedKoboldProcesses(
  void Function(String) log, {
  required String binDir,
}) async {
  try {
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/F', '/IM', 'koboldcpp.exe']);
      await Process.run('taskkill', ['/F', '/IM', 'koboldcpp_nocuda.exe']);
      await Process.run('taskkill', ['/F', '/IM', 'koboldcpp-oldpc.exe']);
    } else {
      if (binDir.isEmpty) {
        log('Engine folder unknown; left any other KoboldCPP alone.');
        return;
      }
      await Process.run('pkill', koboldOwnedKillArgs(binDir));
    }
    log('Killed orphaned KoboldCPP processes.');
  } catch (e) {
    debugPrint('[KoboldService] killOrphanedBackend failed (OK): $e');
  }
}

/// Terminate [process] and everything it spawned.
///
/// The children are the whole reason this is not one `process.kill()`.
/// Dart's `Process.start` does NOT put the child in a new process group, so
/// it inherits ours and `kill(-pid)` would take the app down with it. The
/// ladder instead is: children by parent PID, then the parent, then — only if
/// it is still alive after 3 seconds — SIGKILL for both, and finally a sweep
/// by executable name for anything that reparented to init when its parent
/// died. That last step is what catches KoboldCpp's own worker processes,
/// which outlive their parent and keep the GPU and the port.
///
/// Windows has no process groups to fight, so `taskkill /T` does the whole
/// tree in one call, with a plain kill as the fallback if taskkill is missing.
Future<void> terminateKoboldTree(
  Process process, {
  required String? executablePath,
  required void Function(String) log,
}) async {
  final pid = process.pid;
  if (Platform.isWindows) {
    try {
      await Process.run('taskkill', ['/F', '/T', '/PID', pid.toString()]);
      log('Force killed process tree.');
    } catch (e) {
      log('Taskkill failed, trying standard kill: $e');
      process.kill();
    }
  } else {
    try {
      log('Killing child processes of PID $pid...');
      await Process.run('pkill', ['-TERM', '-P', pid.toString()]);

      process.kill(ProcessSignal.sigterm);
      log('Sent SIGTERM to parent and children.');

      // Up to 3 seconds for a graceful exit, polled with `kill -0` (which
      // only tests for existence) rather than awaiting exitCode, because the
      // caller may not own the only listener on it.
      bool exited = false;
      for (int i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        try {
          final check = await Process.run('kill', ['-0', pid.toString()]);
          if (check.exitCode != 0) {
            exited = true;
            break;
          }
        } catch (_) {
          exited = true;
          break;
        }
      }

      if (!exited) {
        log('Process did not exit gracefully, sending SIGKILL...');
        await Process.run('pkill', ['-KILL', '-P', pid.toString()]);
        process.kill(ProcessSignal.sigkill);
      }

      await _sweepByName(executablePath, log);
    } catch (e) {
      log('Process cleanup failed, using fallback: $e');
      process.kill(ProcessSignal.sigkill);
      await _sweepByName(executablePath, log);
    }
  }

  // Brief wait so the caller clears its state only after the process is
  // genuinely gone. A timeout here is fine — the kill signals are already out.
  try {
    await process.exitCode.timeout(const Duration(seconds: 2));
  } catch (_) {}
}

/// Final safety net: kill anything still matching the executable's own name.
/// Catches deeply nested children and processes that reparented to init (PID
/// 1) after their parent was killed. Reached from both the normal path and
/// the failure path, which is why it is a function rather than two copies.
///
/// Matched on the executable's FULL path, not its bare name: the name alone
/// also matches a KoboldCpp the user started from somewhere else.
Future<void> _sweepByName(
  String? executablePath,
  void Function(String) log,
) async {
  if (executablePath == null) return;
  final exeName = path.basename(executablePath);
  try {
    log('Cleaning up any remaining $exeName processes...');
    await Process.run('pkill', koboldOwnedKillArgs(executablePath));
  } catch (_) {}
}

/// `pkill` arguments that hit only processes whose command line contains
/// [ownedPath] literally (the app's engine folder, or its executable).
/// `pkill -f` takes a regular expression, so the path is escaped.
@visibleForTesting
List<String> koboldOwnedKillArgs(String ownedPath) => [
  '-KILL',
  '-f',
  RegExp.escape(ownedPath),
];
