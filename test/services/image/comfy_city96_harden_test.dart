// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The loader update is written carefully and only after a real answer. Every
// loader is a temp file; the OS facts (who owns a file, who listens on a
// port) come from a probe a test can set, and one test asks the real OS.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/city96_exclusive_write.dart';
import 'package:front_porch_ai/services/image/comfy_gguf_city96_gate.dart';
import 'package:front_porch_ai/services/image/comfy_gguf_city96_write.dart';
import 'package:front_porch_ai/services/image/comfy_model_paths.dart';
import 'package:front_porch_ai/services/image/local_model_roots.dart';
import 'package:front_porch_ai/services/image/comfy_process_probe.dart';

import 'city96_test_loader.dart';
import 'city96_test_probe.dart';

const _url = 'http://127.0.0.1:8188';

final _graph = {
  '1': {
    'class_type': 'UnetLoaderGGUF',
    'inputs': {'unet_name': 'qwen-image-2.1-Q2_K.gguf'},
  },
};

const _patched = '# patched\n';

const _posixOnly = 'needs POSIX file modes and hard links';
final Object _links = city96LinkSkip();

void main() {
  late Directory dir;
  late File loader;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('city96-harden');
    addTearDown(() => dir.deleteSync(recursive: true));
    loader = File(p.join(dir.path, 'loader.py'))
      ..writeAsStringSync(kStockCity96Loader);
  });

  File bak() => File('${loader.path}.bak');
  List<String> leftovers() => [
    for (final e in dir.listSync())
      if (p.basename(e.path).contains('fpai-tmp')) e.path,
  ];

  group('the writer', () {
    test('replaces the file and keeps the original as loader.py.bak', () async {
      await writeCity96Loader(loader, _patched, probe: const FakeProbe());
      expect(loader.readAsStringSync(), _patched);
      expect(bak().readAsStringSync(), kStockCity96Loader);
      expect(leftovers(), isEmpty);
    });

    test(
      'goes through a new file and a rename, never a write in place',
      () async {
        // A second name for the same file sees an in-place write, and does not
        // see a rename.
        final twin = p.join(dir.path, 'twin.py');
        await Process.run('ln', [loader.path, twin]);
        await writeCity96Loader(loader, _patched, probe: const FakeProbe());
        expect(File(twin).readAsStringSync(), kStockCity96Loader);
        expect(loader.readAsStringSync(), _patched);
      },
      skip: Platform.isWindows ? _posixOnly : false,
    );

    test('keeps the file mode', () async {
      await Process.run('chmod', ['640', loader.path]);
      await writeCity96Loader(loader, _patched, probe: const FakeProbe());
      expect((await loader.stat()).mode & 0xFFF, 416); // 0640
    }, skip: Platform.isWindows ? _posixOnly : false);

    test('never replaces a backup that is already there', () async {
      bak().writeAsStringSync('the first original');
      await writeCity96Loader(loader, _patched, probe: const FakeProbe());
      expect(bak().readAsStringSync(), 'the first original');
      expect(loader.readAsStringSync(), _patched);
    });

    test(
      'refuses a symlinked loader and leaves the target alone',
      skip: _links,
      () async {
        final target = File(p.join(dir.path, 'elsewhere.py'))
          ..writeAsStringSync('not yours');
        loader.deleteSync();
        Link(loader.path).createSync(target.path);
        await expectLater(
          writeCity96Loader(loader, _patched, probe: const FakeProbe()),
          throwsA(isA<City96WriteRefused>()),
        );
        expect(target.readAsStringSync(), 'not yours');
        expect(bak().existsSync(), isFalse);
      },
    );

    test(
      'refuses a symlinked backup and does not write through it',
      skip: _links,
      () async {
        final victim = File(p.join(dir.path, 'victim.txt'))
          ..writeAsStringSync('keep me');
        Link(bak().path).createSync(victim.path);
        await expectLater(
          writeCity96Loader(loader, _patched, probe: const FakeProbe()),
          throwsA(isA<City96WriteRefused>()),
        );
        expect(victim.readAsStringSync(), 'keep me');
        expect(loader.readAsStringSync(), kStockCity96Loader);
      },
    );

    test(
      'a loader swapped for a link after it was judged is not copied',
      () async {
        final private = File(p.join(dir.path, 'private.txt'))
          ..writeAsStringSync('someone else\'s secret');
        // Between the checks and the copy, another user puts a link in
        // loader.py's place.
        void swap(String path) {
          File(path).deleteSync();
          Link(path).createSync(private.path);
        }

        await expectLater(
          writeCity96Loader(
            loader,
            _patched,
            probe: const FakeProbe(),
            beforeRead: swap,
          ),
          throwsA(isA<City96WriteRefused>()),
        );

        expect(bak().existsSync(), isFalse, reason: 'nothing was copied');
        expect(private.readAsStringSync(), 'someone else\'s secret');
        expect(leftovers(), isEmpty);
      },
      skip: Platform.isWindows
          ? 'needs POSIX symbolic links and descriptors'
          : false,
    );

    test(
      'the copy is read through the descriptor it opened, not the name',
      () async {
        final other = File(p.join(dir.path, 'other.txt'))
          ..writeAsStringSync('not the loader');
        // Once it is open, the name is pointed elsewhere: what is read is
        // still what was opened.
        final got = readFileNoFollow(
          loader.path,
          afterOpen: (path) {
            File(path).deleteSync();
            Link(path).createSync(other.path);
          },
        );
        expect(String.fromCharCodes(got), kStockCity96Loader);
      },
      skip: Platform.isWindows
          ? 'needs POSIX symbolic links and descriptors'
          : false,
    );

    test(
      'the mode is the opened file\'s, not whatever the name holds later',
      () async {
        Process.runSync('chmod', ['640', loader.path]);
        int? seen;
        readFileNoFollow(
          loader.path,
          onMode: (m) => seen = m,
          afterOpen: (path) {
            // The name now holds a different file with a different mode.
            final swapped = File('$path.swap')..writeAsStringSync('other');
            Process.runSync('chmod', ['600', swapped.path]);
            swapped.renameSync(path);
          },
        );
        expect(seen, 416); // 0640
      },
      skip: Platform.isWindows
          ? 'needs POSIX symbolic links and descriptors'
          : false,
    );

    test('a link is refused, never read', () {
      final target = File(p.join(dir.path, 'target.txt'))
        ..writeAsStringSync('nope');
      final link = Link(p.join(dir.path, 'link.txt'))..createSync(target.path);
      expect(
        () => readFileNoFollow(link.path),
        throwsA(isA<City96WriteRefused>()),
      );
    }, skip: Platform.isWindows ? 'needs POSIX symbolic links' : false);

    test(
      'a planted temp name is never written through',
      skip: _links,
      () async {
        final victim = File(p.join(dir.path, 'victim.txt'))
          ..writeAsStringSync('keep me');
        Link('${loader.path}.fpai-tmp').createSync(victim.path);
        await writeCity96Loader(loader, _patched, probe: const FakeProbe());
        expect(victim.readAsStringSync(), 'keep me');
        expect(loader.readAsStringSync(), _patched);
      },
    );

    test(
      'a name swapped for a link after it is created is not written through',
      () async {
        final victim = File(p.join(dir.path, 'victim.txt'))
          ..writeAsStringSync('keep me');
        // Between creating a new file and writing it, put a link in its place.
        void swap(String path) {
          File(path).deleteSync();
          Link(path).createSync(victim.path);
        }

        await expectLater(
          writeCity96Loader(
            loader,
            _patched,
            probe: const FakeProbe(),
            afterCreate: swap,
          ),
          throwsA(isA<City96WriteRefused>()),
        );

        expect(victim.readAsStringSync(), 'keep me');
        expect(loader.readAsStringSync(), kStockCity96Loader);
        expect(FileSystemEntity.isLinkSync(loader.path), isFalse);
        expect(leftovers(), isEmpty);
      },
      skip: Platform.isWindows
          ? 'needs POSIX symbolic links and descriptors'
          : false,
    );

    group('a check that cannot be answered refuses, and writes nothing', () {
      Future<void> refused(FakeProbe probe, String because, {File? at}) async {
        final target = at ?? loader;
        await expectLater(
          writeCity96Loader(target, _patched, probe: probe),
          throwsA(
            isA<City96WriteRefused>().having(
              (e) => e.message,
              'message',
              contains(because),
            ),
          ),
        );
        expect(target.readAsStringSync(), kStockCity96Loader);
        expect(File('${target.path}.bak').existsSync(), isFalse);
        expect(leftovers(), isEmpty);
      }

      test(
        'the user this app runs as is not known (id failed, or Windows)',
        () => refused(const FakeProbe(me: null), 'which user'),
      );

      test('the owner of the folder is not known (stat failed)', () {
        return refused(
          FakeProbe(unknownOwners: {p.basename(dir.path)}),
          'who owns',
        );
      });

      test('who else can write to the folder is not known', () {
        return refused(
          const FakeProbe(permissionsUnknown: true),
          'who else can write',
        );
      });

      test('the owner of loader.py is not known', () {
        return refused(
          const FakeProbe(unknownOwners: {'loader.py'}),
          'who owns',
        );
      });

      test('the OS layer found a reason of its own (a NULL DACL, say)', () {
        return refused(
          FakeProbe(problems: {p.basename(dir.path): 'no access list at all'}),
          'no access list at all',
        );
      });

      test('a link or junction anywhere on the way', () {
        return refused(const FakeProbe(linkedAnywhere: true), 'link');
      });
    });

    group('an owner that is not this user refuses', () {
      Future<void> refused(FakeProbe probe, String because, File target) async {
        await expectLater(
          writeCity96Loader(target, _patched, probe: probe),
          throwsA(
            isA<City96WriteRefused>().having(
              (e) => e.message,
              'message',
              contains(because),
            ),
          ),
        );
        expect(target.readAsStringSync(), kStockCity96Loader);
      }

      File nested() {
        final gguf = Directory(
          p.join(dir.path, 'ComfyUI', 'custom_nodes', 'ComfyUI-GGUF'),
        )..createSync(recursive: true);
        return File(p.join(gguf.path, 'loader.py'))
          ..writeAsStringSync(kStockCity96Loader);
      }

      test('an administrator (root) is told to update by hand', () {
        return refused(
          FakeProbe(owners: {p.basename(dir.path): 0}),
          'by hand',
          loader,
        );
      });

      test('another user is told so', () {
        return refused(
          FakeProbe(owners: {p.basename(dir.path): 5}),
          'another user',
          loader,
        );
      });

      test('the custom_nodes folder counts too', () {
        return refused(
          const FakeProbe(owners: {'custom_nodes': 5}),
          'custom_nodes folder belongs to another user',
          nested(),
        );
      });

      test('and so does an administrator owning custom_nodes', () {
        return refused(
          const FakeProbe(owners: {'custom_nodes': 0}),
          'custom_nodes folder is owned by an administrator',
          nested(),
        );
      });
    });

    group('others who can write allow the update, with a warning', () {
      for (final mode in [0x1FF, 0x1FD, 0x1F5, 0x1ED | 0x10, 0x1ED | 0x2]) {
        test(
          'the folder is writable by others (mode ${mode.toRadixString(8)})',
          () async {
            final probe = FakeProbe(permissions: {p.basename(dir.path): mode});
            final judged = await city96Judge(loader, probe: probe);
            expect(judged.refusal, isNull);
            expect(judged.othersCanWrite, isTrue);

            await writeCity96Loader(loader, _patched, probe: probe);
            expect(loader.readAsStringSync(), _patched);
          },
        );
      }

      test('so is the custom_nodes folder above it', () async {
        final gguf = Directory(
          p.join(dir.path, 'ComfyUI', 'custom_nodes', 'ComfyUI-GGUF'),
        )..createSync(recursive: true);
        final nested = File(p.join(gguf.path, 'loader.py'))
          ..writeAsStringSync(kStockCity96Loader);

        final judged = await city96Judge(
          nested,
          probe: const FakeProbe(permissions: {'custom_nodes': 0x1FF}),
        );

        expect(judged.refusal, isNull);
        expect(judged.othersCanWrite, isTrue);
      });

      test('a folder only its owner can write says nothing', () async {
        final judged = await city96Judge(
          loader,
          probe: FakeProbe(permissions: {p.basename(dir.path): 0x1C0}),
        );
        expect(judged.refusal, isNull);
        expect(judged.othersCanWrite, isFalse);

        await writeCity96Loader(
          loader,
          _patched,
          probe: FakeProbe(permissions: {p.basename(dir.path): 0x1C0}),
        );
        expect(loader.readAsStringSync(), _patched);
      });
    });

    test('refuses a loader or backup that another user owns', () async {
      final probe = FakeProbe(me: 1000, owners: {'loader.py': 0});
      await expectLater(
        writeCity96Loader(loader, _patched, probe: probe),
        throwsA(isA<City96WriteRefused>()),
      );
      expect(loader.readAsStringSync(), kStockCity96Loader);

      bak().writeAsStringSync('planted');
      final other = FakeProbe(me: 1000, owners: {'.bak': 0});
      await expectLater(
        writeCity96Loader(loader, _patched, probe: other),
        throwsA(isA<City96WriteRefused>()),
      );
    });

    test(
      'a failed write removes its temp file and the backup it made',
      () async {
        Future<void> fail() => writeCity96Loader(
          loader,
          _patched,
          probe: const FakeProbe(),
          beforeRename: (_) => throw const FileSystemException('disk full'),
        );
        await expectLater(fail(), throwsA(isA<FileSystemException>()));
        expect(loader.readAsStringSync(), kStockCity96Loader);
        expect(bak().existsSync(), isFalse);
        expect(leftovers(), isEmpty);
      },
    );

    test('a failed write keeps a backup that was already there', () async {
      bak().writeAsStringSync('the first original');
      await expectLater(
        writeCity96Loader(
          loader,
          _patched,
          probe: const FakeProbe(),
          beforeRename: (_) => throw const FileSystemException('disk full'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(bak().readAsStringSync(), 'the first original');
      expect(leftovers(), isEmpty);
    });
  });

  group('which process it trusts', () {
    ComfyProcessSnapshot proc({int? pid = 7, int? uid = 1000}) {
      return ComfyProcessSnapshot(
        command: 'python ${p.join(dir.path, 'main.py')} --port 8188',
        cwd: dir.path,
        pid: pid,
        uid: uid,
      );
    }

    setUp(() {
      Directory(
        p.join(dir.path, 'custom_nodes', 'ComfyUI-GGUF'),
      ).createSync(recursive: true);
      File(
        p.join(dir.path, 'custom_nodes', 'ComfyUI-GGUF', 'loader.py'),
      ).writeAsStringSync(kStockCity96Loader);
    });

    test('one that listens on the port and belongs to this user', () async {
      final found = await city96TargetForUrl(
        _url,
        processes: [proc()],
        probe: const FakeProbe(byPort: {8188: 7}, me: 1000),
      );
      expect(found.pid, 7);
      expect(found.loader, isNotNull);
    });

    test('not a look-alike that is not listening', () async {
      for (final probe in [
        const FakeProbe(byPort: {8188: 99}),
        const FakeProbe(),
      ]) {
        final found = await city96TargetForUrl(
          _url,
          processes: [proc()],
          probe: probe,
        );
        expect(found.loader, isNull);
        expect(found.refused, isNull);
      }
    });

    test('not another user\'s process', () async {
      final found = await city96TargetForUrl(
        _url,
        processes: [proc(uid: 0)],
        probe: const FakeProbe(byPort: {8188: 7}),
      );
      expect(found.loader, isNull);
    });

    group('a check that cannot be answered refuses', () {
      test('no lsof or ss: who listens is not known', () async {
        final found = await city96TargetForUrl(
          _url,
          processes: [proc()],
          probe: const FakeProbe(byPort: {8188: 7}, portsUnknown: true),
        );
        expect(found.loader, isNull);
        expect(found.refused, contains('listening'));
      });

      test(
        'no user ids (Windows): the process cannot be tied to this user',
        () async {
          final found = await city96TargetForUrl(
            _url,
            processes: [proc()],
            probe: const FakeProbe(byPort: {8188: 7}, me: null),
          );
          expect(found.loader, isNull);
          expect(found.refused, contains('which user'));
        },
      );

      test('a process with no owner in the list is asked about', () async {
        for (final (owners, found) in [
          ({7: 1000}, true),
          ({7: 0}, false),
        ]) {
          final result = await city96TargetForUrl(
            _url,
            processes: [proc(uid: null)],
            probe: FakeProbe(byPort: const {8188: 7}, processOwners: owners),
          );
          expect(result.loader != null, found, reason: '$owners');
        }
      });

      test('a process whose owner is unknown is not a candidate', () async {
        final found = await city96TargetForUrl(
          _url,
          processes: [proc(uid: null)],
          probe: const FakeProbe(byPort: {8188: 7}),
        );
        expect(found.loader, isNull);
        expect(found.refused, contains('who owns'));
      });

      test('a process on another port is none of its business', () async {
        final found = await city96TargetForUrl(
          'http://127.0.0.1:9999',
          processes: [proc()],
          probe: const FakeProbe(portsUnknown: true, me: null),
        );
        expect(found.refused, isNull);
      });
    });
  });

  test('a scan reports the process id and owner of a real process', () async {
    // A process whose command line looks like a ComfyUI server.
    final proc = await Process.start('sh', [
      '-c',
      'sleep 30',
      'main.py',
      '--port',
      '8199',
    ]);
    addTearDown(proc.kill);
    final found = (await scanComfyProcesses()).where((s) => s.pid == proc.pid);
    expect(found, hasLength(1));
    expect(found.single.command, contains('--port 8199'));
    expect(found.single.uid, await const ComfyProcessProbe().currentUid());
  }, skip: Platform.isWindows ? 'needs ps and POSIX processes' : false);

  group('listeners and process owners from /proc', () {
    // Real lines, as Linux writes them: a listener on 8188 (0x1FFC), a
    // listener on another port, and an established connection on 8188.
    const tcp =
        '  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n'
        '   0: 0100007F:1FFC 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 5001 1 0 100 0\n'
        '   1: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 5002 1 0 100 0\n'
        '   2: 0100007F:1FFC 0100007F:C350 01 00000000:00000000 00:00000000 00000000  1000        0 5003 1 0 100 0\n';
    const tcp6 =
        '  sl  local_address                         remote_address                        st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n'
        '   0: 00000000000000000000000001000000:1FFC 00000000000000000000000000000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 6001 1 0 100 0\n';

    test('the listening sockets on a port, IPv4 and IPv6', () {
      expect(parseProcNetTcp(tcp, 8188), {5001});
      expect(parseProcNetTcp(tcp6, 8188), {6001});
      expect(parseProcNetTcp(tcp, 9999), isEmpty);
    });

    /// A /proc tree with process [pid] holding socket [inode].
    Directory fakeProc({
      String v4 = tcp,
      String? v6 = tcp6,
      Map<int, int> holds = const {},
      int uid = 1000,
    }) {
      final root = Directory(p.join(dir.path, 'proc'))..createSync();
      Directory(p.join(root.path, 'net')).createSync();
      if (v4.isNotEmpty) {
        File(p.join(root.path, 'net', 'tcp')).writeAsStringSync(v4);
      }
      if (v6 != null) {
        File(p.join(root.path, 'net', 'tcp6')).writeAsStringSync(v6);
      }
      holds.forEach((pid, inode) {
        final fd = Directory(p.join(root.path, '$pid', 'fd'))
          ..createSync(recursive: true);
        Link(p.join(fd.path, '3')).createSync('socket:[$inode]');
        File(
          p.join(root.path, '$pid', 'status'),
        ).writeAsStringSync('Name:\tpython\nUid:\t$uid\t$uid\t$uid\t$uid\n');
      });
      return root;
    }

    test('the process that holds a listening socket is found', () {
      final root = fakeProc(holds: {77: 5001, 88: 5002});
      expect(linuxListeningPids(8188, proc: root.path), {77});
      expect(linuxListeningPids(8080, proc: root.path), {88});
      expect(linuxListeningPids(9999, proc: root.path), isEmpty);
    }, skip: Platform.isWindows ? _posixOnly : false);

    test('a listener on IPv6 only is found', () {
      final root = fakeProc(v4: tcp.split('\n').first, holds: {99: 6001});
      expect(linuxListeningPids(8188, proc: root.path), {99});
    }, skip: Platform.isWindows ? _posixOnly : false);

    test('no IPv6 on the machine is no listener there, not a failure', () {
      final root = fakeProc(v6: null, holds: {77: 5001});
      expect(linuxListeningPids(8188, proc: root.path), {77});
    }, skip: Platform.isWindows ? _posixOnly : false);

    test('when /proc/net/tcp cannot be read nothing can be said', () {
      final root = fakeProc(v4: '', v6: null);
      expect(linuxListeningPids(8188, proc: root.path), isNull);
    });

    test('the owner is the first Uid in /proc/<pid>/status', () {
      final root = fakeProc(holds: {77: 5001}, uid: 1234);
      expect(linuxProcessUid(77, proc: root.path), 1234);
      expect(linuxProcessUid(1, proc: root.path), isNull);
    }, skip: Platform.isWindows ? _posixOnly : false);

    test('the real /proc names this very process for its own socket', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      expect(linuxListeningPids(server.port), contains(pid));
      expect(
        linuxProcessUid(pid),
        await const ComfyProcessProbe().currentUid(),
      );
    }, skip: Platform.isLinux ? false : 'needs Linux /proc');
  });

  group('the real OS probe', () {
    test('sees a socket this process listens on', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final pids = await const ComfyProcessProbe().listeningPids(server.port);
      // Linux reads /proc, so this always answers there; macOS has lsof.
      expect(pids, isNotNull, reason: 'the OS must be able to say');
      expect(pids, contains(pid));
      expect(
        await const ComfyProcessProbe().listeningPids(1),
        isNot(contains(pid)),
      );
    }, skip: Platform.isWindows ? _posixOnly : false);

    test('says who owns a path, and whether others can write it', () async {
      const probe = ComfyProcessProbe();
      await Process.run('chmod', ['700', dir.path]);
      var facts = await probe.pathFacts(dir.path, folder: true);
      expect(facts, isNotNull);
      expect(facts!.owner, await probe.currentPrincipal());
      expect(facts.othersCanWrite, isFalse);
      expect(facts.isLink, isFalse);

      await Process.run('chmod', ['777', dir.path]);
      facts = await probe.pathFacts(dir.path, folder: true);
      expect(facts!.othersCanWrite, isTrue);
      await Process.run('chmod', ['700', dir.path]);
    }, skip: Platform.isWindows ? _posixOnly : false);

    test('a folder reached through a link is a link', () async {
      final real = Directory(p.join(dir.path, 'real'))..createSync();
      final via = Link(p.join(dir.path, 'via'))..createSync(real.path);

      final probe = const ComfyProcessProbe();
      expect((await probe.pathFacts(real.path, folder: true))!.isLink, isFalse);
      expect((await probe.pathFacts(via.path, folder: true))!.isLink, isTrue);
      // A link further up the path shows too.
      final inner = Directory(p.join(real.path, 'inner'))..createSync();
      expect(
        (await probe.pathFacts(
          p.join(via.path, 'inner'),
          folder: true,
        ))!.isLink,
        isTrue,
        reason: inner.path,
      );
    }, skip: Platform.isWindows ? _posixOnly : false);

    test('a loader reached through a linked folder is refused', () async {
      final real = Directory(p.join(dir.path, 'real'));
      final gguf = Directory(p.join(real.path, 'custom_nodes', 'ComfyUI-GGUF'))
        ..createSync(recursive: true);
      File(
        p.join(gguf.path, 'loader.py'),
      ).writeAsStringSync(kStockCity96Loader);
      final via = Link(p.join(dir.path, 'via'))..createSync(real.path);
      final target = File(
        p.join(via.path, 'custom_nodes', 'ComfyUI-GGUF', 'loader.py'),
      );

      await expectLater(
        writeCity96Loader(target, _patched, probe: const FakeProbe()),
        throwsA(isA<City96WriteRefused>()),
      );

      expect(
        File(p.join(gguf.path, 'loader.py')).readAsStringSync(),
        kStockCity96Loader,
      );
    }, skip: Platform.isWindows ? _posixOnly : false);

    test('without lsof or ss the answer still comes, from /proc', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final pids = await const ComfyProcessProbe(
        tools: false,
      ).listeningPids(server.port);
      expect(pids, contains(pid));
    }, skip: Platform.isLinux ? false : 'needs Linux /proc');

    test('knows a process of this user from one that is not', () async {
      const probe = ComfyProcessProbe();
      expect(await probe.processIsMine(pid), isTrue);
      expect(await probe.processIsMine(2147483000), isNull);
    }, skip: Platform.isWindows ? _posixOnly : false);

    test('reads the permission bits of a folder', () async {
      await Process.run('chmod', ['750', dir.path]);
      expect(
        await const ComfyProcessProbe().filePermissions(dir.path),
        488, // 0750
      );
    }, skip: Platform.isWindows ? _posixOnly : false);

    test('says when a process started', () async {
      final proc = await Process.start('sleep', ['30']);
      addTearDown(proc.kill);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final started = await const ComfyProcessProbe().processStart(proc.pid);
      expect(started, isNotNull);
      final age = DateTime.now().difference(started!);
      expect(age.inSeconds, inInclusiveRange(0, 10));
      expect(await const ComfyProcessProbe().processStart(2147483000), isNull);
    }, skip: Platform.isWindows ? _posixOnly : false);

    test('knows who owns a file it just made', () async {
      final me = await const ComfyProcessProbe().currentUid();
      final owner = await const ComfyProcessProbe().fileOwner(loader.path);
      expect(me, isNotNull);
      expect(owner, me);
    }, skip: Platform.isWindows ? _posixOnly : false);
  });

  group('asking', () {
    City96Gate gate({
      City96Asker? ask,
      Future<void> Function(File, String)? write,
    }) {
      return City96Gate(
        locate: (_) async => loader,
        ask: ask,
        probe: const FakeProbe(),
        pidFor: (_) async => 100,
        write: write,
      );
    }

    test('a window that is gone is not a "no", and is asked again', () async {
      var answers = <bool?>[null, true];
      var asked = 0;
      final g = gate(
        ask: (_) async {
          asked++;
          return answers.removeAt(0);
        },
      );
      final first = await g.ensure(comfyUrl: _url, graph: _graph);
      expect(first.state, City96State.needsUpdate);
      expect(first.message, contains('Open Front Porch'));
      expect(loader.readAsStringSync(), kStockCity96Loader);

      final second = await g.ensure(comfyUrl: _url, graph: _graph);
      expect(asked, 2);
      expect(second.state, City96State.restartNeeded);
    });

    test('pressing "Update loader…" asks again after a "no"', () async {
      var asked = 0;
      var yes = false;
      final g = gate(
        ask: (_) async {
          asked++;
          return yes;
        },
      );
      await g.ensure(comfyUrl: _url, graph: _graph);
      await g.ensure(comfyUrl: _url, graph: _graph);
      expect(asked, 1, reason: 'posting again does not ask again');

      yes = true;
      final result = await g.ensure(
        comfyUrl: _url,
        graph: _graph,
        askAgain: true,
      );
      expect(asked, 2);
      expect(result.state, City96State.restartNeeded);
    });

    test(
      'a phone or web caller gets the answer at once and nobody is asked',
      () async {
        var asked = 0;
        final g = gate(
          ask: (_) => Completer<bool>().future.whenComplete(() => asked++),
        );
        final result = await runZoned(
          () => g.ensure(comfyUrl: _url, graph: _graph),
          zoneValues: {kCity96NoAsk: true},
        ).timeout(const Duration(seconds: 5));
        expect(result.state, City96State.needsUpdate);
        expect(result.message, startsWith(kCity96NeedsUpdate));
        expect(result.message, contains(kCity96ConfirmOnDesktop));
        expect(asked, 0);
        expect(loader.readAsStringSync(), kStockCity96Loader);
      },
    );
  });
}
