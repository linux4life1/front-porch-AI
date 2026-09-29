// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

/// Facts about this machine that decide whether a ComfyUI process and its
/// files may be trusted with a write. Each answer is null when the OS cannot
/// say (Windows has no user ids here; a tool may be missing), and callers
/// treat null as "not checked", never as a match.
class ComfyProcessProbe {
  const ComfyProcessProbe();

  /// The process ids listening on TCP [port]. An empty set means nothing
  /// listens there.
  Future<Set<int>?> listeningPids(int port) async {
    if (Platform.isWindows) {
      final out = await _run('powershell', [
        '-NoProfile',
        '-Command',
        '(Get-NetTCPConnection -LocalPort $port -State Listen '
            '-ErrorAction SilentlyContinue).OwningProcess',
      ]);
      return out == null ? null : _numbers(out);
    }
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

  /// The user id this app runs as.
  Future<int?> currentUid() async {
    if (Platform.isWindows) return null;
    final out = await _run('id', ['-u']);
    return int.tryParse(out?.trim() ?? '');
  }

  /// The user id that owns [path].
  Future<int?> fileOwner(String path) async {
    if (Platform.isWindows) return null;
    final args = Platform.isMacOS ? ['-f', '%u', path] : ['-c', '%u', path];
    final out = await _run('stat', args);
    return int.tryParse(out?.trim() ?? '');
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
