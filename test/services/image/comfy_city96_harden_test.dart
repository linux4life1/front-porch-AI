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
        if (Platform.isWindows) return;
        // A second name for the same file sees an in-place write, and does not
        // see a rename.
        final twin = p.join(dir.path, 'twin.py');
        await Process.run('ln', [loader.path, twin]);
        await writeCity96Loader(loader, _patched, probe: const FakeProbe());
        expect(File(twin).readAsStringSync(), kStockCity96Loader);
        expect(loader.readAsStringSync(), _patched);
      },
    );

    test('keeps the file mode', () async {
      if (Platform.isWindows) return;
      await Process.run('chmod', ['640', loader.path]);
      await writeCity96Loader(loader, _patched, probe: const FakeProbe());
      expect((await loader.stat()).mode & 0xFFF, 416); // 0640
    });

    test('never replaces a backup that is already there', () async {
      bak().writeAsStringSync('the first original');
      await writeCity96Loader(loader, _patched, probe: const FakeProbe());
      expect(bak().readAsStringSync(), 'the first original');
      expect(loader.readAsStringSync(), _patched);
    });

    test('refuses a symlinked loader and leaves the target alone', () async {
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
    });

    test('refuses a symlinked backup and does not write through it', () async {
      final victim = File(p.join(dir.path, 'victim.txt'))
        ..writeAsStringSync('keep me');
      Link(bak().path).createSync(victim.path);
      await expectLater(
        writeCity96Loader(loader, _patched, probe: const FakeProbe()),
        throwsA(isA<City96WriteRefused>()),
      );
      expect(victim.readAsStringSync(), 'keep me');
      expect(loader.readAsStringSync(), kStockCity96Loader);
    });

    test('a planted temp name is never written through', () async {
      final victim = File(p.join(dir.path, 'victim.txt'))
        ..writeAsStringSync('keep me');
      Link('${loader.path}.fpai-tmp').createSync(victim.path);
      await writeCity96Loader(loader, _patched, probe: const FakeProbe());
      expect(victim.readAsStringSync(), 'keep me');
      expect(loader.readAsStringSync(), _patched);
    });

    test(
      'a name swapped for a link after it is created is not written through',
      () async {
        if (Platform.isWindows) return;
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
    );

    group('a check that cannot be answered refuses, and writes nothing', () {
      Future<void> refused(FakeProbe probe, String because) async {
        await expectLater(
          writeCity96Loader(loader, _patched, probe: probe),
          throwsA(
            isA<City96WriteRefused>().having(
              (e) => e.message,
              'message',
              contains(because),
            ),
          ),
        );
        expect(loader.readAsStringSync(), kStockCity96Loader);
        expect(bak().existsSync(), isFalse);
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

      test('the permissions of the folder are not known', () {
        return refused(const FakeProbe(permissionsUnknown: true), 'who owns');
      });

      test('the owner of loader.py is not known', () {
        return refused(
          const FakeProbe(unknownOwners: {'loader.py'}),
          'who owns',
        );
      });

      test('the folder belongs to another user', () {
        return refused(
          FakeProbe(owners: {p.basename(dir.path): 0}),
          'another user',
        );
      });

      for (final mode in [0x1FF, 0x1FD, 0x1F5, 0x1ED | 0x10, 0x1ED | 0x2]) {
        test(
          'the folder is writable by others (mode ${mode.toRadixString(8)})',
          () {
            return refused(
              FakeProbe(permissions: {p.basename(dir.path): mode}),
              'other users',
            );
          },
        );
      }

      test('a folder only its owner can write is fine', () async {
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
        expect(found.refused, contains('lsof'));
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
  }, skip: Platform.isWindows);

  group('the real OS probe', () {
    test('sees a socket this process listens on', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final pids = await const ComfyProcessProbe().listeningPids(server.port);
      // lsof or ss may be missing on a machine; then nothing can be checked.
      if (pids == null) return;
      expect(pids, contains(pid));
      expect(
        await const ComfyProcessProbe().listeningPids(1),
        isNot(contains(pid)),
      );
    }, skip: Platform.isWindows);

    test('reads the permission bits of a folder', () async {
      await Process.run('chmod', ['750', dir.path]);
      expect(
        await const ComfyProcessProbe().filePermissions(dir.path),
        488, // 0750
      );
    }, skip: Platform.isWindows);

    test('says when a process started', () async {
      final proc = await Process.start('sleep', ['30']);
      addTearDown(proc.kill);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final started = await const ComfyProcessProbe().processStart(proc.pid);
      expect(started, isNotNull);
      final age = DateTime.now().difference(started!);
      expect(age.inSeconds, inInclusiveRange(0, 10));
      expect(await const ComfyProcessProbe().processStart(2147483000), isNull);
    }, skip: Platform.isWindows);

    test('knows who owns a file it just made', () async {
      final me = await const ComfyProcessProbe().currentUid();
      final owner = await const ComfyProcessProbe().fileOwner(loader.path);
      expect(me, isNotNull);
      expect(owner, me);
    }, skip: Platform.isWindows);
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
