// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:path/path.dart' as p;

import 'comfy_process_probe_windows.dart';

/// What is known about one path, for deciding whether a write may go there.
/// The same shape on every OS: [owner] and [ownerIsAdmin] are a user id or a
/// SID, [othersCanWrite] means someone other than this user (and, on Windows,
/// the system and administrators) may change it.
class PathFacts {
  const PathFacts({
    this.owner,
    this.ownerIsAdmin = false,
    this.isLink = false,
    this.othersCanWrite,
    this.problem,
  });

  /// The owner, or null when the OS could not say.
  final String? owner;

  /// The owner is `root`, Administrators or SYSTEM: not this user, but not a
  /// stranger either. The person updates that file by hand.
  final bool ownerIsAdmin;

  /// This path, or a folder above it, is a symbolic link, a junction or a
  /// reparse point.
  final bool isLink;

  /// Null when the OS could not say.
  final bool? othersCanWrite;

  /// A reason to refuse the OS layer found by itself (a NULL DACL, say).
  final String? problem;
}

/// Facts about this machine that decide whether a ComfyUI process and its
/// files may be trusted with a write. Each answer is null when the OS cannot
/// say (a tool is missing, a call failed), and callers treat null as "not
/// checked, so refuse", never as a match.
class ComfyProcessProbe {
  /// [tools] false makes the probe answer without `lsof` or `ss` (a machine
  /// that has neither): for tests.
  const ComfyProcessProbe({@visibleForTesting this.tools = true});

  final bool tools;

  /// The process ids listening on TCP [port]. An empty set means nothing
  /// listens there. On Windows only processes of this user are returned.
  Future<Set<int>?> listeningPids(int port) async {
    if (Platform.isWindows) return windowsListeningPids(port);
    if (Platform.isLinux) {
      final viaProc = linuxListeningPids(port);
      if (viaProc != null) return viaProc;
    }
    if (!tools) return null;
    final lsof = await _run('lsof', [
      '-nP',
      '-iTCP:$port',
      '-sTCP:LISTEN',
      '-t',
    ], emptyOk: true);
    if (lsof != null) return _numbers(lsof);
    final ss = await _run('ss', ['-H', '-ltnp', 'sport = :$port']);
    if (ss == null) return null;
    return {
      for (final m in RegExp(r'pid=(\d+)').allMatches(ss))
        int.parse(m.group(1)!),
    };
  }

  /// Who this app runs as: a user id, or a SID on Windows.
  Future<String?> currentPrincipal() async {
    if (Platform.isWindows) return windowsCurrentSid();
    final uid = await currentUid();
    return uid?.toString();
  }

  /// The user id this app runs as (POSIX).
  Future<int?> currentUid() async {
    if (Platform.isWindows) return null;
    final out = await _run('id', ['-u']);
    return int.tryParse(out?.trim() ?? '');
  }

  /// True when process [pid] belongs to this user, false when it does not,
  /// null when that cannot be told.
  Future<bool?> processIsMine(int pid) async {
    final me = await currentPrincipal();
    if (me == null) return null;
    if (Platform.isWindows) return windowsProcessIsMine(pid);
    final uid = Platform.isLinux
        ? linuxProcessUid(pid)
        : int.tryParse(
            (await _run('ps', ['-o', 'uid=', '-p', '$pid']))?.trim() ?? '',
          );
    return uid == null ? null : '$uid' == me;
  }

  /// Facts about [path], a folder or a file. Null when they cannot be read.
  Future<PathFacts?> pathFacts(String path, {required bool folder}) async {
    if (Platform.isWindows) return windowsPathFacts(path, folder: folder);
    final stat = await _stat(path);
    if (stat == null) return null;
    return PathFacts(
      owner: '${stat.$1}',
      ownerIsAdmin: stat.$1 == 0,
      isLink: linkedPath(path, folder: folder),
      othersCanWrite: stat.$2 & 0x12 != 0,
    );
  }

  /// True when [path], or a folder above it, is a link. A folder is compared
  /// with what it resolves to, so a link anywhere in its path shows.
  static bool linkedPath(String path, {required bool folder}) {
    if (Platform.isWindows) return windowsLinked(path, folder: folder);
    if (FileSystemEntity.isLinkSync(path)) return true;
    if (!folder) return false;
    try {
      final real = Directory(path).resolveSymbolicLinksSync();
      return p.normalize(real) != p.normalize(path);
    } on FileSystemException {
      return true;
    }
  }

  /// The user id that owns [path] (POSIX).
  Future<int?> fileOwner(String path) async => (await _stat(path))?.$1;

  /// The permission bits of [path] (`0755` is 493) (POSIX).
  Future<int?> filePermissions(String path) async => (await _stat(path))?.$2;

  /// When process [pid] started.
  Future<DateTime?> processStart(int pid) async {
    if (Platform.isWindows) return windowsProcessStart(pid);
    final out = await _run('ps', ['-o', 'etime=', '-p', '$pid']);
    final elapsed = _elapsed(out?.trim() ?? '');
    return elapsed == null ? null : DateTime.now().subtract(elapsed);
  }

  /// `(owner uid, permission bits)`, from one `stat`.
  static Future<(int, int)?> _stat(String path) async {
    if (Platform.isWindows) return null;
    final args = Platform.isMacOS
        ? ['-f', '%u %Lp', path]
        : ['-c', '%u %a', path];
    final out = await _run('stat', args);
    final parts = out?.trim().split(' ');
    if (parts == null || parts.length != 2) return null;
    final uid = int.tryParse(parts[0]);
    final mode = int.tryParse(parts[1], radix: 8);
    return uid == null || mode == null ? null : (uid, mode);
  }

  /// `ps` elapsed time: `[[dd-]hh:]mm:ss`.
  static Duration? _elapsed(String text) {
    final m = RegExp(r'^(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)$').firstMatch(text);
    if (m == null) return null;
    int n(int i) => int.parse(m.group(i) ?? '0');
    return Duration(days: n(1), hours: n(2), minutes: n(3), seconds: n(4));
  }

  static Set<int> _numbers(String text) => {
    for (final line in text.split(RegExp(r'\s+')))
      if (int.tryParse(line) != null) int.parse(line),
  };

  /// Null when the tool is missing or failed. [emptyOk] lets an exit code of
  /// 1 with no output (lsof: nothing listening) count as an empty answer.
  static Future<String?> _run(
    String exe,
    List<String> args, {
    bool emptyOk = false,
  }) async {
    try {
      final r = await Process.run(exe, args);
      if (r.exitCode == 0) return '${r.stdout}';
      if (emptyOk && r.exitCode == 1 && '${r.stdout}'.trim().isEmpty) {
        return '';
      }
      return null;
    } on ProcessException {
      return null;
    }
  }
}

/// The socket inodes that listen on [port], from the text of `/proc/net/tcp`
/// or `/proc/net/tcp6`.
Set<int> parseProcNetTcp(String text, int port) {
  final inodes = <int>{};
  for (final line in text.split('\n').skip(1)) {
    final f = line.trim().split(RegExp(r'\s+'));
    if (f.length < 10 || f[3] != '0A') continue;
    final local = f[1];
    final colon = local.lastIndexOf(':');
    if (colon < 0 ||
        int.tryParse(local.substring(colon + 1), radix: 16) != port) {
      continue;
    }
    final inode = int.tryParse(f[9]);
    if (inode != null && inode != 0) inodes.add(inode);
  }
  return inodes;
}

/// The processes listening on [port], read from `/proc` (no tool needed):
/// the listening sockets in `net/tcp` and `net/tcp6`, then the process whose
/// open files include each. Null when `net/tcp` cannot be read.
Set<int>? linuxListeningPids(int port, {String proc = '/proc'}) {
  final inodes = <int>{};
  try {
    inodes.addAll(
      parseProcNetTcp(File('$proc/net/tcp').readAsStringSync(), port),
    );
  } on FileSystemException {
    return null;
  }
  try {
    inodes.addAll(
      parseProcNetTcp(File('$proc/net/tcp6').readAsStringSync(), port),
    );
  } on FileSystemException {
    // No IPv6 here: nothing listens on it.
  }
  if (inodes.isEmpty) return {};
  final pids = <int>{};
  try {
    for (final entry in Directory(proc).listSync(followLinks: false)) {
      final pid = int.tryParse(p.basename(entry.path));
      if (pid == null) continue;
      try {
        for (final fd in Directory(
          '${entry.path}/fd',
        ).listSync(followLinks: false)) {
          final target = Link(fd.path).targetSync();
          final m = RegExp(r'^socket:\[(\d+)\]$').firstMatch(target);
          if (m != null && inodes.contains(int.parse(m.group(1)!))) {
            pids.add(pid);
            break;
          }
        }
      } on FileSystemException {
        // Another user's process: its files cannot be read, and it is not ours.
      }
    }
  } on FileSystemException {
    return null;
  }
  return pids;
}

/// The user id that owns process [pid], from `/proc/<pid>/status`.
int? linuxProcessUid(int pid, {String proc = '/proc'}) {
  try {
    final text = File('$proc/$pid/status').readAsStringSync();
    final m = RegExp(r'^Uid:\s+(\d+)', multiLine: true).firstMatch(text);
    return m == null ? null : int.parse(m.group(1)!);
  } on FileSystemException {
    return null;
  }
}
