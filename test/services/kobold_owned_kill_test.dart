// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Stopping the app's KoboldCpp must not take down one the user started
// themselves. The kill pattern is the app's own engine path, matched
// literally; the bare name "koboldcpp" matched every KoboldCpp on the
// machine. The second test runs the real `pkill` matcher (`pgrep -f`, same
// pattern rules) against real processes.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold_process_control.dart';
import 'package:path/path.dart' as p;

void main() {
  test('the pattern is the full owned path, escaped for pkill', () {
    final args = koboldOwnedKillArgs(
      '/Users/me/Documents/FrontPorchAI/koboldcpp_bin/koboldcpp-mac-arm64',
    );
    expect(args.take(2), ['-KILL', '-f']);
    expect(args.last, contains('koboldcpp_bin/koboldcpp-mac-arm64'));
    // A dot is a wildcard to pkill unless escaped.
    expect(koboldOwnedKillArgs('/a/b.c').last, r'/a/b\.c');
    // Never the bare name.
    expect(args.last, isNot('koboldcpp'));
  });

  test('the pattern finds a process run from the owned folder and not one of '
      'the same name run from elsewhere', () async {
    final root = await Directory.systemTemp.createTemp('fpai kill (test)');
    addTearDown(() => root.delete(recursive: true));
    final owned = Directory(p.join(root.path, 'koboldcpp_bin'))..createSync();
    final other = Directory(p.join(root.path, 'my own tools'))..createSync();
    const script = '#!/bin/sh\nsleep 30\n';
    final mine = File(p.join(owned.path, 'koboldcpp'))
      ..writeAsStringSync(script);
    final theirs = File(p.join(other.path, 'koboldcpp'))
      ..writeAsStringSync(script);
    await Process.run('chmod', ['+x', mine.path, theirs.path]);

    final a = await Process.start(mine.path, const []);
    final b = await Process.start(theirs.path, const []);
    addTearDown(() {
      a.kill(ProcessSignal.sigkill);
      b.kill(ProcessSignal.sigkill);
    });

    final pattern = koboldOwnedKillArgs(owned.path).last;
    final found = await Process.run('pgrep', ['-f', pattern]);
    final pids = (found.stdout as String)
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map(int.parse)
        .toSet();

    expect(pids, contains(a.pid));
    expect(pids, isNot(contains(b.pid)));

    // The old pattern, the bare name, catches both.
    final old = await Process.run('pgrep', ['-f', 'koboldcpp']);
    final oldPids = (old.stdout as String)
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map(int.parse)
        .toSet();
    expect(oldPids, containsAll([a.pid, b.pid]));
  }, skip: Platform.isWindows ? 'pkill is not used on Windows' : false);
}
