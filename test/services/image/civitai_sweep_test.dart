// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Clearing partial downloads must never delete one that another running copy
// of the app is still writing. A file lock only conflicts between processes,
// so the locked cases use a real second Dart process.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/image.dart';

import 'civitai_test_server.dart';

/// A `dart` binary to run a second process with, or null.
String? _dart() {
  final root = Platform.environment['FLUTTER_ROOT'];
  final names = Platform.isWindows ? ['dart.exe'] : ['dart'];
  final candidates = <String>[
    if (root != null)
      for (final n in names) p.join(root, 'bin', 'cache', 'dart-sdk', 'bin', n),
  ];
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    for (final n in names) {
      candidates.add(p.join(dir.path, 'cache', 'dart-sdk', 'bin', n));
      candidates.add(p.join(dir.path, 'dart-sdk', 'bin', n));
    }
    dir = dir.parent;
  }
  for (final c in candidates) {
    if (File(c).existsSync()) return c;
  }
  return null;
}

/// Another process that holds an exclusive lock on [path] until [release].
class _OtherCopy {
  _OtherCopy(this._process);

  final Process _process;

  static Future<_OtherCopy> lock(
    String path,
    Directory scratch, {
    bool shared = false,
  }) async {
    final script = File(p.join(scratch.path, 'hold_lock.dart'))
      ..writeAsStringSync('''
import 'dart:io';
Future<void> main(List<String> args) async {
  final f = await File(args[0]).open(mode: FileMode.append);
  await f.lock(args[1] == 'shared' ? FileLock.shared : FileLock.exclusive);
  stdout.writeln('locked');
  await stdin.drain<void>();
}
''');
    final process = await Process.start(_dart()!, [
      script.path,
      path,
      shared ? 'shared' : 'exclusive',
    ]);
    final first = await process.stdout
        .transform(utf8.decoder)
        .first
        .timeout(const Duration(seconds: 60));
    expect(first.trim(), 'locked');
    return _OtherCopy(process);
  }

  Future<void> release() async {
    await _process.stdin.close();
    await _process.exitCode.timeout(const Duration(seconds: 30));
  }
}

void main() {
  late Directory dir;
  final longAgo = DateTime.now().subtract(const Duration(hours: 3));
  final hasDart = _dart() != null;

  File part(String folder, String name, {DateTime? modified}) {
    final f = File(civitaiPartPath(p.join(dir.path, folder, name)))
      ..createSync(recursive: true)
      ..writeAsBytesSync(const [1, 2, 3]);
    if (modified != null) f.setLastModifiedSync(modified);
    return f;
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('civitai-sweep');
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  test(
    'a part touched in the last hour is left for whoever is writing it',
    () async {
      final fresh = part('loras', 'fresh.safetensors');
      final minutesOld = part(
        'loras',
        'recent.safetensors',
        modified: DateTime.now().subtract(const Duration(minutes: 50)),
      );
      expect(await sweepCivitaiParts(dir.path), 0);
      expect(fresh.existsSync(), isTrue);
      expect(minutesOld.existsSync(), isTrue);
    },
  );

  test('a part untouched for hours is removed', () async {
    final old = part('loras', 'old.safetensors', modified: longAgo);
    expect(await sweepCivitaiParts(dir.path), 1);
    expect(old.existsSync(), isFalse);
  });

  test('the age is a parameter, and an hour by default', () async {
    expect(kCivitaiPartStaleAfter, const Duration(hours: 1));
    final f = part(
      'loras',
      'x.safetensors',
      modified: DateTime.now().subtract(const Duration(minutes: 10)),
    );
    expect(await sweepCivitaiParts(dir.path), 0);
    expect(
      await sweepCivitaiParts(dir.path, olderThan: const Duration(minutes: 5)),
      1,
    );
    expect(f.existsSync(), isFalse);
  });

  test('a folder that is missing or not a folder is not an error', () async {
    expect(await sweepCivitaiParts(p.join(dir.path, 'nowhere')), 0);
    File(p.join(dir.path, 'loras')).writeAsStringSync('a file, not a folder');
    expect(await sweepCivitaiParts(dir.path), 0);
  });

  group('another running copy of the app', () {
    test(
      'a part it has locked is not deleted, however old',
      () async {
        final theirs = part('loras', 'theirs.safetensors', modified: longAgo);
        final mine = part('checkpoints', 'mine.safetensors', modified: longAgo);
        final other = await _OtherCopy.lock(theirs.path, dir);
        addTearDown(other.release);
        expect(await sweepCivitaiParts(dir.path), 1);
        expect(theirs.existsSync(), isTrue);
        expect(theirs.readAsBytesSync(), const [1, 2, 3]);
        expect(mine.existsSync(), isFalse);
        await other.release();
        expect(await sweepCivitaiParts(dir.path), 1);
        expect(theirs.existsSync(), isFalse);
      },
      skip: Platform.isWindows || !hasDart
          ? 'needs a second dart process'
          : null,
    );

    test(
      'a download does not touch a part another copy is writing',
      () async {
        final host = await CivitaiFileHost.start();
        host.serve('/ok', List<int>.generate(16, (i) => i));
        final target = p.join(dir.path, 'loras', 'same.safetensors');
        final theirs = File(civitaiPartPath(target))
          ..createSync(recursive: true)
          ..writeAsBytesSync(const [7, 7, 7, 7]);
        final other = await _OtherCopy.lock(theirs.path, dir);
        addTearDown(other.release);
        final kind = await civitaiFailureOf(
          downloadCivitaiPlan(
            civitaiTestPlan(host.uri('/ok'), target, root: dir.path),
          ),
        );
        expect(kind, CivitaiFailure.busy);
        expect(theirs.readAsBytesSync(), const [7, 7, 7, 7]);
        expect(File(target).existsSync(), isFalse);
      },
      skip: Platform.isWindows || !hasDart
          ? 'needs a second dart process'
          : null,
    );
  });

  test(
    'a download needs the part to itself: even a shared lock refuses it',
    () async {
      final host = await CivitaiFileHost.start();
      host.serve('/ok', List<int>.generate(16, (i) => i));
      final target = p.join(dir.path, 'loras', 'same.safetensors');
      final theirs = File(civitaiPartPath(target))
        ..createSync(recursive: true)
        ..writeAsBytesSync(const [7, 7]);
      final other = await _OtherCopy.lock(theirs.path, dir, shared: true);
      addTearDown(other.release);
      final kind = await civitaiFailureOf(
        downloadCivitaiPlan(
          civitaiTestPlan(host.uri('/ok'), target, root: dir.path),
        ),
      );
      expect(kind, CivitaiFailure.busy);
      expect(theirs.readAsBytesSync(), const [7, 7]);
    },
    skip: Platform.isWindows || !hasDart ? 'needs a second dart process' : null,
  );

  test(
    'our own running download is never swept, even with an old part',
    () async {
      final host = await CivitaiFileHost.start();
      final release = Completer<void>();
      host.serveThenHold('/live', const [1, 2, 3, 4], hold: release.future);
      final target = p.join(dir.path, 'loras', 'live.safetensors');
      final got = Completer<void>();
      final run = downloadCivitaiPlan(
        civitaiTestPlan(host.uri('/live'), target, root: dir.path),
        onProgress: (n, _) {
          if (n > 0 && !got.isCompleted) got.complete();
        },
      ).then<Object?>((v) => v, onError: (_) => null);
      await got.future.timeout(const Duration(seconds: 10));
      File(civitaiPartPath(target)).setLastModifiedSync(longAgo);
      expect(await sweepCivitaiParts(dir.path), 0);
      expect(File(civitaiPartPath(target)).existsSync(), isTrue);
      release.complete();
      await run;
    },
  );
}
