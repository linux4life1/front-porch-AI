// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The sweep for a KoboldCpp left behind by a previous run says it killed
// something only when it did. It used to log "Killed orphaned KoboldCPP
// processes." whatever `pkill` answered, so a KoboldCpp that was NOT the
// app's own (and was rightly left running) was reported as gone. What the
// sweep matches is pinned against real processes in
// `kobold_owned_kill_test.dart`; this is the other half of its answer.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold_process_control.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  final started = <Process>[];

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('fpai sweep log');
    // Resolved, so the path is the one a process really shows (the macOS
    // temp folder sits behind a /var -> /private/var link).
    root = Directory(temp.resolveSymbolicLinksSync());
  });

  tearDown(() async {
    for (final proc in started) {
      proc.kill(ProcessSignal.sigkill);
    }
    started.clear();
    await root.delete(recursive: true);
  });

  test('nothing of the app\'s was running: the log says nothing was stopped, '
      'and another KoboldCpp is left alone', () async {
    final owned = Directory(p.join(root.path, 'koboldcpp_bin'))..createSync();
    final theirs = Directory(p.join(root.path, 'my tools'))..createSync();
    // Someone's own engine, run from somewhere else: a link to a system
    // tool, because a script's command line begins with its interpreter.
    final exe = Link(p.join(theirs.path, 'koboldcpp'))
      ..createSync('/bin/sleep');
    final other = await Process.start(exe.path, const ['30']);
    started.add(other);
    final log = <String>[];

    await killOrphanedKoboldProcesses(log.add, binDir: owned.path);

    expect(log, hasLength(1));
    expect(log.single, isNot(contains('Killed')));
    expect(log.single, contains('nothing was stopped'));
    final alive = await Process.run('kill', ['-0', '${other.pid}']);
    expect(alive.exitCode, 0, reason: 'the other KoboldCpp is still running');
  }, skip: Platform.isWindows ? 'pkill is not used on Windows' : false);
}
