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
///
/// The log says a process was killed only when one was: `pkill` and
/// `taskkill` answer 0 when they stopped something, and anything else when
/// they found nothing to stop.
Future<void> killOrphanedKoboldProcesses(
  void Function(String) log, {
  required String binDir,
}) async {
  try {
    var killed = false;
    Future<void> run(String command, List<String> args) async {
      final result = await Process.run(command, args);
      killed = killed || result.exitCode == 0;
    }

    if (Platform.isWindows) {
      await run('taskkill', ['/F', '/IM', 'koboldcpp.exe']);
      await run('taskkill', ['/F', '/IM', 'koboldcpp_nocuda.exe']);
      await run('taskkill', ['/F', '/IM', 'koboldcpp-oldpc.exe']);
    } else {
      final patterns = koboldOwnedPatterns(binDir, isFolder: true);
      if (patterns.isEmpty) {
        log('Engine folder unknown; left any other KoboldCPP alone.');
        return;
      }
      for (final pattern in patterns) {
        await run('pkill', ['-KILL', '-f', pattern]);
      }
    }
    log(
      killed
          ? 'Killed orphaned KoboldCPP processes.'
          : 'No orphaned KoboldCPP process was running; nothing was stopped.',
    );
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
/// of anything started from the same executable that reparented to init when
/// its parent died. That last step is what catches KoboldCpp's own worker processes,
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

/// Final safety net: kill anything still started from the executable.
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
    for (final pattern in koboldOwnedPatterns(
      executablePath,
      isFolder: false,
    )) {
      await Process.run('pkill', ['-KILL', '-f', pattern]);
    }
  } catch (_) {}
}

/// What every engine build the app installs is named with.
const String _engineNamePrefix = 'koboldcpp';

/// `pkill -f` patterns that match only an engine STARTED FROM [ownedPath]:
/// the app's engine folder ([isFolder]), or its one executable.
///
/// `pkill -f` matches a regular expression against the whole command line,
/// so each pattern is the escaped path anchored to the start. Unanchored,
/// it also matched a program that merely used a file kept in the folder
/// (a KoboldCpp started elsewhere with a model stored there). A folder
/// pattern goes on to the engine's name, so nothing else kept or linked in
/// that folder is touched, and `koboldcpp_bin_old/` beside it is not
/// matched; an executable must be the whole first word.
///
/// Two spellings are given when the FOLDER is reached through a symbolic
/// link: as written, and resolved (on macOS a temp or home path runs under
/// its `/private/...` name). The executable itself is never resolved: a
/// linked one could point at a shared program, and every copy of that
/// would be stopped.
///
/// Empty for a path that is blank, relative, the root, or one level below
/// the root.
@visibleForTesting
List<String> koboldOwnedPatterns(String ownedPath, {required bool isFolder}) {
  if (!path.isAbsolute(ownedPath) || path.split(ownedPath).length <= 2) {
    return const [];
  }
  final folder = isFolder ? ownedPath : path.dirname(ownedPath);
  final folders = <String>{folder};
  try {
    folders.add(Directory(folder).resolveSymbolicLinksSync());
  } on FileSystemException {
    // Not on disk (already removed): the given spelling is all there is.
  }
  return {
    for (final f in folders)
      isFolder
          ? '^${RegExp.escape(path.join(f, _engineNamePrefix))}'
          : '^${RegExp.escape(path.join(f, path.basename(ownedPath)))}( |\$)',
  }.toList();
}
