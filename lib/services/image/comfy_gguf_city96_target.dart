// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:path/path.dart' as p;

import 'comfy_model_paths.dart';
import 'comfy_process_probe.dart';
import 'local_model_roots.dart';

const String _kNoUser =
    'Front Porch cannot tell which user it runs as here, so it cannot check '
    'that the ComfyUI it found is yours and left its loader alone. Update '
    'ComfyUI-GGUF by hand.';

const String _kNoProcessOwner =
    'Front Porch could not tell who owns the ComfyUI it found, so it left '
    'its loader alone. Update ComfyUI-GGUF by hand.';

const String _kNoListeners =
    'Front Porch cannot tell which program is listening on that port, so it '
    'cannot be sure which ComfyUI this is and left its loader alone. Update '
    'ComfyUI-GGUF by hand.';

/// Who serves a ComfyUI URL on this computer: its loader and process id, or
/// why it cannot be told ([refused], shown as it is). All three are null when
/// nothing there looks like a local ComfyUI.
typedef City96Target = ({File? loader, int? pid, String? refused});

bool _desktopRelativeMain(ComfyProcessSnapshot proc, bool isWindows) =>
    isWindows &&
    proc.cwd == null &&
    splitCommandLine(proc.command)
            .where(
              (arg) =>
                  p.windows.normalize(arg).toLowerCase() == r'comfyui\main.py',
            )
            .length ==
        1;

bool _desktopEnv(String? executable) {
  if (executable == null) return false;
  final parts = p.windows.split(executable).map((part) => part.toLowerCase());
  return parts.contains('standalone-env') || parts.contains('.venv');
}

/// Desktop inference is only for its environment layout. Portable and
/// manual installs keep the main.py/working-directory lookup.
Future<List<String?>> city96LoaderDirs(
  ComfyProcessSnapshot proc, {
  bool? isWindows,
  Future<bool> Function(String)? exists,
}) async {
  final hints = comfyLaunchHints(
    proc.command,
    cwd: proc.cwd,
    executable: proc.executable,
  );
  if (_desktopRelativeMain(proc, isWindows ?? Platform.isWindows) &&
      _desktopEnv(proc.executable)) {
    return [
      await _desktopMainDir(proc, exists ?? (path) => File(path).exists()),
    ];
  }
  return [hints.mainPyDir, proc.cwd];
}

/// Comfy Desktop runs `ComfyUI/main.py` from its install folder, while its
/// Python executable lives in a sibling environment folder. CIM does not
/// expose the working directory, so the executable's directory is not it.
Future<String?> _desktopMainDir(
  ComfyProcessSnapshot proc,
  Future<bool> Function(String) exists,
) async {
  final executable = proc.executable;
  if (executable == null || !p.windows.isAbsolute(executable)) return null;
  if (!{
    'python.exe',
    'pythonw.exe',
  }.contains(p.windows.basename(executable).toLowerCase())) {
    return null;
  }
  final found = <String>[];
  var dir = p.windows.dirname(executable);
  for (var depth = 0; depth < 5; depth++) {
    final main = p.windows.join(dir, 'ComfyUI', 'main.py');
    if (await exists(main)) found.add(p.windows.dirname(main));
    final parent = p.windows.dirname(dir);
    if (parent == dir) break;
    dir = parent;
  }
  return found.length == 1 ? found.single : null;
}

/// The running ComfyUI on [comfyUrl]'s port and its loader, and only that one:
/// its command line names that port, this user owns it, and it is really the
/// process listening there. Another user's process, or a look-alike that is
/// not listening, is never a candidate.
///
/// A fact that cannot be checked refuses instead of passing: no `lsof` or
/// `ss`, an OS that reports no user ids (Windows), or a process whose owner is
/// unknown.
Future<City96Target> city96TargetForUrl(
  String comfyUrl, {
  List<ComfyProcessSnapshot>? processes,
  ComfyProcessProbe probe = const ComfyProcessProbe(),
}) async {
  final port = comfyUrlPort(comfyUrl);
  final procs = processes ?? await scanComfyProcesses();
  String? me;
  var meAsked = false;
  Set<int>? listeners;
  var listenersAsked = false;
  String? unverified;
  for (final proc in procs) {
    final hints = comfyLaunchHints(
      proc.command,
      cwd: proc.cwd,
      executable: proc.executable,
    );
    if (hints.port != port) continue;
    if (!meAsked) {
      me = await probe.currentPrincipal();
      meAsked = true;
    }
    if (me == null) {
      return (loader: null, pid: null, refused: _kNoUser);
    }
    // The owner comes from the process list where it says, else from the OS.
    final pid = proc.pid;
    final mine = proc.uid != null
        ? '${proc.uid}' == me
        : pid == null
        ? null
        : await probe.processIsMine(pid);
    if (mine == null) {
      unverified = _kNoProcessOwner;
      continue;
    }
    if (!mine) continue;
    if (!listenersAsked) {
      listeners = await probe.listeningPids(port);
      listenersAsked = true;
    }
    if (listeners == null) {
      return (loader: null, pid: null, refused: _kNoListeners);
    }
    if (pid == null || !listeners.contains(pid)) continue;
    final dirs = await city96LoaderDirs(proc);
    for (final dir in dirs) {
      if (dir == null || dir.isEmpty) continue;
      final loader = File(
        p.join(dir, 'custom_nodes', 'ComfyUI-GGUF', 'loader.py'),
      );
      if (await loader.exists()) {
        return (loader: loader, pid: pid, refused: null);
      }
    }
  }
  return (loader: null, pid: null, refused: unverified);
}

Future<File?> city96LoaderForUrl(
  String comfyUrl, {
  List<ComfyProcessSnapshot>? processes,
  ComfyProcessProbe probe = const ComfyProcessProbe(),
}) async => (await city96TargetForUrl(
  comfyUrl,
  processes: processes,
  probe: probe,
)).loader;

/// The id of the process serving [comfyUrl], for noticing a restart.
Future<int?> city96PidForUrl(String comfyUrl) async =>
    (await city96TargetForUrl(comfyUrl)).pid;
