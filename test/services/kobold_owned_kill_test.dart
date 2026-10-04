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
  test('an executable\'s pattern is its full path, escaped for pkill and '
      'anchored so it must be the whole first word', () {
    final patterns = koboldOwnedPatterns(
      '/Users/me/Documents/FrontPorchAI/koboldcpp_bin/koboldcpp-mac-arm64',
      isFolder: false,
    );
    expect(patterns.single, contains('koboldcpp_bin/koboldcpp-mac-arm64'));
    // Never the bare name.
    expect(patterns.single, isNot('koboldcpp'));
    // A dot is a wildcard to pkill unless escaped.
    expect(koboldOwnedPatterns('/a/b.c', isFolder: false), [r'^/a/b\.c( |$)']);
    final exe = RegExp(patterns.single);
    const path =
        '/Users/me/Documents/FrontPorchAI/koboldcpp_bin/koboldcpp-mac-arm64';
    expect(exe.hasMatch('$path --port 5001'), isTrue);
    expect(exe.hasMatch(path), isTrue);
    expect(exe.hasMatch('$path-old --port 5001'), isFalse);
  }, skip: Platform.isWindows ? 'pkill is not used on Windows' : false);

  test('a folder\'s pattern matches an engine started from it, and nothing '
      'that only sits beside it, uses a file in it, or is another program '
      'kept in it', () {
    final patterns = koboldOwnedPatterns('/data/koboldcpp_bin', isFolder: true);
    expect(patterns, [r'^/data/koboldcpp_bin/koboldcpp']);
    final pattern = RegExp(patterns.single);
    expect(
      pattern.hasMatch('/data/koboldcpp_bin/koboldcpp-linux-x64 --port 5001'),
      isTrue,
    );
    // A sibling folder with a longer name.
    expect(
      pattern.hasMatch('/data/koboldcpp_bin_old/koboldcpp --port 5001'),
      isFalse,
    );
    // Naming a file in the folder is not being started from it.
    expect(
      pattern.hasMatch('/usr/bin/koboldcpp --model /data/koboldcpp_bin/m.gguf'),
      isFalse,
    );
    // Something else the user keeps in that folder.
    expect(
      pattern.hasMatch('/data/koboldcpp_bin/llama-server --port 8080'),
      isFalse,
    );
    // A trailing separator on the folder changes nothing.
    expect(
      koboldOwnedPatterns('/data/koboldcpp_bin/', isFolder: true),
      patterns,
    );
  }, skip: Platform.isWindows ? 'pkill is not used on Windows' : false);

  test('a blank, relative, root or top-level path gives no pattern at all, '
      'so nothing can be matched by accident', () {
    for (final path in ['', '/', 'koboldcpp_bin', '.', '/tmp', '/usr/']) {
      expect(koboldOwnedPatterns(path, isFolder: true), isEmpty, reason: path);
      expect(koboldOwnedPatterns(path, isFolder: false), isEmpty, reason: path);
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

      final patterns = koboldOwnedPatterns(link.path, isFolder: true);
      expect(patterns, hasLength(2));
      // The spelling the app has does not appear in the process at all.
      expect(await matching(patterns.first), isEmpty);
      expect(await matching(patterns.last), contains(mine.pid));
    });

    test('stopping an engine whose executable is a link leaves other copies '
        'of the program it points at running', () async {
      // The stand-in engine IS a link to a shared system tool.
      final mine = await fakeEngine(owned);
      final exe = p.join(owned.path, 'koboldcpp');
      final unrelated = await Process.start('/bin/sleep', const ['30']);
      started.add(unrelated);

      final patterns = koboldOwnedPatterns(exe, isFolder: false);
      expect(patterns, everyElement(endsWith(r'/koboldcpp( |$)')));

      await terminateKoboldTree(mine, executablePath: exe, log: (_) {});

      expect(await matching(r'^/bin/sleep 30$'), contains(unrelated.pid));
      expect(await matching(patterns.first), isEmpty);
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
