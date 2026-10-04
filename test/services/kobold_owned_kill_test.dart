// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Stopping the app's KoboldCpp must not take down one the user started
// themselves. The kill pattern is the app's own engine path, matched
// literally at the start of the command line; the bare name "koboldcpp"
// matched every KoboldCpp on the machine. The group runs the real `pkill`
// and its matcher (`pgrep -f`, same pattern rules) against real processes.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold_process_control.dart';
import 'package:path/path.dart' as p;

void main() {
  test('the pattern is the full owned path, escaped for pkill and anchored '
      'to the start of the command line', () {
    final args = koboldOwnedKillArgs(
      '/Users/me/Documents/FrontPorchAI/koboldcpp_bin/koboldcpp-mac-arm64',
    );
    expect(args.take(2), ['-KILL', '-f']);
    expect(args.last, contains('koboldcpp_bin/koboldcpp-mac-arm64'));
    // A dot is a wildcard to pkill unless escaped. An executable must be
    // the whole first word, so `b.c-old` beside it is not matched.
    expect(koboldOwnedKillArgs('/a/b.c').last, r'^/a/b\.c( |$)');
    // Never the bare name.
    expect(args.last, isNot('koboldcpp'));
  }, skip: Platform.isWindows ? 'pkill is not used on Windows' : false);

  test('a folder pattern ends in a separator, so a sibling folder with a '
      'longer name is not matched', () {
    final paths = koboldOwnedPaths('/data/koboldcpp_bin', isFolder: true);
    expect(paths.first, '/data/koboldcpp_bin/');
    final pattern = RegExp(koboldOwnedKillArgs(paths.first).last);
    expect(
      pattern.hasMatch('/data/koboldcpp_bin/koboldcpp --port 5001'),
      isTrue,
    );
    expect(
      pattern.hasMatch('/data/koboldcpp_bin_old/koboldcpp --port 5001'),
      isFalse,
    );
    // Naming a file in the folder is not being started from it.
    expect(
      pattern.hasMatch('/usr/bin/koboldcpp --model /data/koboldcpp_bin/m.gguf'),
      isFalse,
    );
    // An executable is matched as it stands.
    expect(koboldOwnedPaths('/data/bin/koboldcpp', isFolder: false), [
      '/data/bin/koboldcpp',
    ]);
  }, skip: Platform.isWindows ? 'pkill is not used on Windows' : false);

  test('a blank, relative, root or top-level path gives no pattern at all, '
      'so nothing can be matched by accident', () {
    for (final path in ['', '/', 'koboldcpp_bin', '.', '/tmp', '/usr/']) {
      expect(koboldOwnedPaths(path, isFolder: true), isEmpty, reason: path);
      expect(koboldOwnedPaths(path, isFolder: false), isEmpty, reason: path);
    }
  });

  group('against real processes', () {
    late Directory root;
    late Directory owned;
    final started = <Process>[];

    /// A stand-in engine: a real process whose command line begins with the
    /// path it was started from, which is all the kill pattern looks at. A
    /// link to a system tool, because a script's command line begins with
    /// its interpreter.
    Future<Process> fakeEngine(
      Directory dir, {
      String tool = '/bin/sleep',
      List<String> args = const ['30'],
    }) async {
      dir.createSync(recursive: true);
      final exe = Link(p.join(dir.path, 'koboldcpp'))..createSync(tool);
      final proc = await Process.start(exe.path, args);
      started.add(proc);
      return proc;
    }

    Future<Set<int>> matching(String pattern) async {
      final out = await Process.run('pgrep', ['-f', pattern]);
      return (out.stdout as String)
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map(int.parse)
          .toSet();
    }

    setUp(() async {
      // Resolved, so every spelling below is the one a process really shows
      // (the macOS temp folder sits behind a /var -> /private/var link).
      final temp = await Directory.systemTemp.createTemp('fpai kill (test)');
      root = Directory(temp.resolveSymbolicLinksSync());
      owned = Directory(p.join(root.path, 'koboldcpp_bin'));
    });

    tearDown(() async {
      for (final proc in started) {
        proc.kill(ProcessSignal.sigkill);
      }
      started.clear();
      await root.delete(recursive: true);
    });

    test('an engine the app knows through a symbolic link is found under '
        'the real path it runs from', () async {
      final mine = await fakeEngine(owned);
      final link = Link(p.join(root.path, 'linked'))..createSync(owned.path);

      final patterns = koboldOwnedPaths(link.path, isFolder: true);
      expect(patterns, hasLength(2));
      // The spelling the app has does not appear in the process at all.
      expect(await matching(koboldOwnedKillArgs(patterns.first).last), isEmpty);
      expect(
        await matching(koboldOwnedKillArgs(patterns.last).last),
        contains(mine.pid),
      );
    });

    test('cleaning up orphans stops the engine in the app\'s folder and '
        'leaves one run from elsewhere, one in a sibling folder, and one '
        'that only uses a file kept in the app\'s folder', () async {
      final mine = await fakeEngine(owned);
      final theirs = await fakeEngine(Directory(p.join(root.path, 'my tools')));
      final sibling = await fakeEngine(
        Directory(p.join(root.path, 'koboldcpp_bin_old')),
      );
      // Someone's own engine, loading a model stored in the app's folder.
      final model = File(p.join(owned.path, 'model.gguf'))..createSync();
      final borrower = await fakeEngine(
        Directory(p.join(root.path, 'their engine')),
        tool: '/usr/bin/tail',
        args: ['-f', model.path],
      );
      // The old pattern, the bare name, catches every one of them.
      expect(
        await matching('koboldcpp'),
        containsAll([mine.pid, theirs.pid, sibling.pid, borrower.pid]),
      );
      final log = <String>[];

      await killOrphanedKoboldProcesses(log.add, binDir: owned.path);
      await mine.exitCode.timeout(const Duration(seconds: 5));

      final left = await matching('koboldcpp');
      expect(left, isNot(contains(mine.pid)));
      expect(left, containsAll([theirs.pid, sibling.pid, borrower.pid]));
      expect(log.single, contains('Killed orphaned KoboldCPP'));
    });

    test('with no engine folder known, nothing is stopped and the log says '
        'so', () async {
      final theirs = await fakeEngine(Directory(p.join(root.path, 'my tools')));
      final log = <String>[];

      await killOrphanedKoboldProcesses(log.add, binDir: '');

      expect(await matching('koboldcpp'), contains(theirs.pid));
      expect(log.single, contains('left any other KoboldCPP alone'));
    });
  }, skip: Platform.isWindows ? 'pkill is not used on Windows' : false);
}
