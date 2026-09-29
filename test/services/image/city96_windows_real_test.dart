// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The real Win32 calls behind the loader update, on a Windows machine: the
// writer against a real folder, junctions, real ACLs, and the listener table.
// Everything here is skipped, with its reason, on any other OS; the same logic
// runs against an in-memory Windows in city96_windows_test.dart. Every folder
// is a temp folder; nothing here touches a real ComfyUI install.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/city96_exclusive_write_windows.dart';
import 'package:front_porch_ai/services/image/city96_write_common.dart';
import 'package:front_porch_ai/services/image/comfy_process_probe_windows.dart';

import 'city96_test_loader.dart';

final Object _skip = Platform.isWindows
    ? false
    : 'Windows only: this calls the real Win32 API';

/// Whether this runner may create symbolic links (it needs developer mode or
/// elevation); the reason to skip when it may not.
Object _symlinkSkip() {
  if (!Platform.isWindows) return _skip;
  final probe = Directory.systemTemp.createTempSync('fpai-symlink-probe');
  try {
    Link(p.join(probe.path, 'l')).createSync(probe.path);
    return false;
  } on FileSystemException {
    return 'this runner cannot create symbolic links (needs developer mode)';
  } finally {
    probe.deleteSync(recursive: true);
  }
}

void main() {
  late Directory root;
  late Directory gguf;
  late File loader;

  setUp(() {
    if (!Platform.isWindows) return;
    root = Directory.systemTemp.createTempSync('fpai-win-real');
    gguf = Directory(
      p.join(root.path, 'ComfyUI', 'custom_nodes', 'ComfyUI-GGUF'),
    )..createSync(recursive: true);
    loader = File(p.join(gguf.path, 'loader.py'))
      ..writeAsStringSync(kStockCity96Loader);
    addTearDown(() => root.deleteSync(recursive: true));
  });

  List<String> leftovers() => [
    for (final e in gguf.listSync())
      if (p.basename(e.path).contains('fpai-tmp')) e.path,
  ];

  test('this user has a SID', () async {
    final sid = await windowsCurrentSid();
    expect(sid, isNotNull);
    expect(sid, startsWith('S-1-5-'));
  }, skip: _skip);

  group('the writer', () {
    test(
      'replaces loader.py and keeps the original as loader.py.bak',
      () async {
        await writeCity96LoaderWindows(loader, '# patched\n');

        expect(loader.readAsStringSync(), '# patched\n');
        expect(
          File('${loader.path}.bak').readAsStringSync(),
          kStockCity96Loader,
        );
        expect(leftovers(), isEmpty);
        // Nothing is left open: the folder can be deleted.
        loader.deleteSync();
        File('${loader.path}.bak').deleteSync();
      },
      skip: _skip,
    );

    test('an existing backup is kept', () async {
      File('${loader.path}.bak').writeAsStringSync('the first original');

      await writeCity96LoaderWindows(loader, '# patched\n');

      expect(
        File('${loader.path}.bak').readAsStringSync(),
        'the first original',
      );
      expect(loader.readAsStringSync(), '# patched\n');
    }, skip: _skip);

    test(
      'the new file cannot be deleted or renamed while it is being written',
      () async {
        var deleteFailed = false;
        var renameFailed = false;

        await writeCity96LoaderWindows(
          loader,
          '# patched\n',
          beforeRename: (temp) async {
            try {
              File(temp).deleteSync();
            } on FileSystemException {
              deleteFailed = true;
            }
            try {
              File(temp).renameSync('$temp-moved');
            } on FileSystemException {
              renameFailed = true;
            }
          },
        );

        expect(deleteFailed, isTrue);
        expect(renameFailed, isTrue);
        expect(loader.readAsStringSync(), '# patched\n');
      },
      skip: _skip,
    );

    test(
      'a fault before the rename leaves the original and no temp file',
      () async {
        await expectLater(
          writeCity96LoaderWindows(
            loader,
            '# patched\n',
            beforeRename: (_) async =>
                throw const FileSystemException('disk full'),
          ),
          throwsA(isA<FileSystemException>()),
        );

        expect(loader.readAsStringSync(), kStockCity96Loader);
        expect(File('${loader.path}.bak').existsSync(), isFalse);
        expect(leftovers(), isEmpty);
      },
      skip: _skip,
    );

    test('a junction as the folder is refused', () async {
      final real = Directory(p.join(root.path, 'real'))..createSync();
      final junction = p.join(root.path, 'junction');
      final made = await Process.run('cmd', [
        '/c',
        'mklink',
        '/J',
        junction,
        real.path,
      ]);
      expect(made.exitCode, 0, reason: '${made.stderr}');
      final through = File(p.join(junction, 'loader.py'))
        ..writeAsStringSync(kStockCity96Loader);

      await expectLater(
        writeCity96LoaderWindows(through, '# patched\n'),
        throwsA(isA<City96WriteRefused>()),
      );

      expect(through.readAsStringSync(), kStockCity96Loader);
    }, skip: _skip);

    test('a symbolic link as loader.py is refused', () async {
      final target = File(p.join(root.path, 'elsewhere.py'))
        ..writeAsStringSync('not yours');
      loader.deleteSync();
      Link(loader.path).createSync(target.path);

      await expectLater(
        writeCity96LoaderWindows(loader, '# patched\n'),
        throwsA(isA<City96WriteRefused>()),
      );

      expect(target.readAsStringSync(), 'not yours');
    }, skip: _symlinkSkip());
  });

  group('what a path says', () {
    test('a folder made here is not a link and has an owner', () async {
      final facts = await windowsPathFacts(gguf.path, folder: true);

      expect(facts, isNotNull);
      expect(facts!.isLink, isFalse);
      expect(facts.owner, isNotNull);
      expect(facts.problem, isNull);
    }, skip: _skip);

    test('a junction is a link', () async {
      final junction = p.join(root.path, 'junction');
      final made = await Process.run('cmd', [
        '/c',
        'mklink',
        '/J',
        junction,
        gguf.path,
      ]);
      expect(made.exitCode, 0, reason: '${made.stderr}');

      final facts = await windowsPathFacts(junction, folder: true);

      expect(facts!.isLink, isTrue);
    }, skip: _skip);

    test(
      'Everyone with write on the folder is others being able to write',
      () async {
        final granted = await Process.run('icacls', [
          gguf.path,
          '/grant',
          '*S-1-1-0:(OI)(CI)M',
        ]);
        expect(granted.exitCode, 0, reason: '${granted.stderr}');

        final facts = await windowsPathFacts(gguf.path, folder: true);

        expect(facts!.othersCanWrite, isTrue);
      },
      skip: _skip,
    );

    test('a path that does not exist cannot be answered', () async {
      expect(
        await windowsPathFacts(p.join(root.path, 'missing'), folder: true),
        isNull,
      );
    }, skip: _skip);
  });

  group('processes and listeners', () {
    test(
      'a socket this process listens on is found, IPv4 and IPv6 only',
      () async {
        final v4 = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final v6 = await ServerSocket.bind(
          InternetAddress.loopbackIPv6,
          0,
          v6Only: true,
        );
        addTearDown(v4.close);
        addTearDown(v6.close);

        expect(await windowsListeningPids(v4.port), contains(pid));
        expect(await windowsListeningPids(v6.port), contains(pid));
      },
      skip: _skip,
    );

    test('a port nothing listens on has no listener', () async {
      final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = free.port;
      await free.close();

      expect(await windowsListeningPids(port), isEmpty);
    }, skip: _skip);

    test('this process is this user\'s, and started a moment ago', () async {
      expect(await windowsProcessIsMine(pid), isTrue);
      final started = await windowsProcessStart(pid);
      expect(started, isNotNull);
      expect(DateTime.now().toUtc().difference(started!).inHours, lessThan(24));
    }, skip: _skip);
  });
}
