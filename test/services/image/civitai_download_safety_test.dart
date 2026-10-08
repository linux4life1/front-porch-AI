// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What the downloader must refuse to do: overwrite a file, leave the models
// folder, send the key to another host, or run too many at once.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/image.dart';

import 'civitai_test_server.dart';

void main() {
  late Directory dir;
  late CivitaiFileHost host;
  final bytes = List<int>.generate(64, (i) => i);

  String at(String folder, String name) => p.join(dir.path, folder, name);

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('civitai-safety');
    addTearDown(() => dir.deleteSync(recursive: true));
    host = await CivitaiFileHost.start();
  });

  CivitaiDownloadPlan plan(String path, String route, {int? expected}) {
    return civitaiTestPlan(
      host.uri(route),
      path,
      root: dir.path,
      expectedBytes: expected,
    );
  }

  group('a download never replaces a file', () {
    test('a different file of the same name is left alone', () async {
      host.serve('/ok', bytes);
      final dest = at('loras', 'style.safetensors');
      File(dest).createSync(recursive: true);
      File(dest).writeAsBytesSync(const [9, 9, 9, 9]);
      final kind = await civitaiFailureOf(
        downloadCivitaiPlan(plan(dest, '/ok', expected: bytes.length)),
      );
      expect(kind, CivitaiFailure.nameTaken);
      expect(File(dest).readAsBytesSync(), const [9, 9, 9, 9]);
      expect(host.requests, isEmpty);
    });

    test('the same size as listed counts as already installed', () async {
      host.serve('/ok', bytes);
      final dest = at('loras', 'style.safetensors');
      File(dest).createSync(recursive: true);
      File(dest).writeAsBytesSync(List<int>.filled(bytes.length, 7));
      final kind = await civitaiFailureOf(
        downloadCivitaiPlan(plan(dest, '/ok', expected: bytes.length)),
      );
      expect(kind, CivitaiFailure.exists);
      expect(File(dest).readAsBytesSync(), List<int>.filled(bytes.length, 7));
      expect(host.requests, isEmpty);
    });

    test('a link in the way is never written through', () async {
      host.serve('/ok', bytes);
      final real = File(p.join(dir.path, 'elsewhere.safetensors'))
        ..writeAsBytesSync(const [1]);
      final dest = at('loras', 'style.safetensors');
      Directory(p.dirname(dest)).createSync(recursive: true);
      Link(dest).createSync(real.path);
      final kind = await civitaiFailureOf(
        downloadCivitaiPlan(plan(dest, '/ok', expected: bytes.length)),
      );
      expect(kind, CivitaiFailure.nameTaken);
      expect(real.readAsBytesSync(), const [1]);
    }, skip: Platform.isWindows);

    test('a file that appears while downloading is not replaced', () async {
      final release = Completer<void>();
      host.serveThenHold(
        '/race',
        bytes.sublist(0, 32),
        hold: release.future,
        rest: bytes.sublist(32),
      );
      final dest = at('loras', 'style.safetensors');
      final started = Completer<void>();
      final run = civitaiFailureOf(
        downloadCivitaiPlan(
          plan(dest, '/race', expected: bytes.length),
          onProgress: (got, _) {
            if (got > 0 && !started.isCompleted) started.complete();
          },
        ),
      );
      await started.future.timeout(const Duration(seconds: 10));
      File(dest).writeAsBytesSync(const [4, 4]);
      release.complete();
      expect(await run, CivitaiFailure.nameTaken);
      expect(File(dest).readAsBytesSync(), const [4, 4]);
      expect(File(civitaiPartPath(dest)).existsSync(), isFalse);
    });
  });

  group('how many downloads run at once', () {
    test('the same file twice is "busy", whatever the letter case', () async {
      final release = Completer<void>();
      host.serveThenHold('/hold', bytes, hold: release.future);
      final first = downloadCivitaiPlan(
        plan(at('loras', 'Style.safetensors'), '/hold'),
      );
      final firstDone = first.then<Object?>((v) => v, onError: (_) => null);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final kind = await civitaiFailureOf(
        downloadCivitaiPlan(plan(at('loras', 'STYLE.safetensors'), '/hold')),
      );
      expect(kind, CivitaiFailure.busy);
      release.complete();
      await firstDone;
    });

    test('a third download waits for one of two to finish', () async {
      final release = Completer<void>();
      host.serveThenHold('/hold', bytes, hold: release.future);
      host.serve('/ok', bytes);
      final running = [
        for (final name in ['a', 'b'])
          downloadCivitaiPlan(
            plan(at('loras', '$name.safetensors'), '/hold'),
          ).then<Object?>((v) => v, onError: (_) => null),
      ];
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(kCivitaiMaxActive, 2);
      final kind = await civitaiFailureOf(
        downloadCivitaiPlan(plan(at('loras', 'c.safetensors'), '/ok')),
      );
      expect(kind, CivitaiFailure.tooMany);
      release.complete();
      await Future.wait(running);
      await downloadCivitaiPlan(plan(at('loras', 'c.safetensors'), '/ok'));
      expect(File(at('loras', 'c.safetensors')).existsSync(), isTrue);
    });
  });

  group('redirects', () {
    test(
      'only https may follow, so an http hop is refused unrequested',
      () async {
        host.routes['/r'] = (request) async {
          request.response.statusCode = 302;
          request.response.headers.set('location', 'http://example.invalid/x');
          await request.response.close();
        };
        final kind = await civitaiFailureOf(
          downloadCivitaiPlan(plan(at('loras', 'x.safetensors'), '/r')),
        );
        expect(kind, CivitaiFailure.redirect);
        expect(host.hits('/r'), 1);
      },
    );

    test('a redirect with no address is refused', () async {
      host.status('/r', 302);
      final kind = await civitaiFailureOf(
        downloadCivitaiPlan(plan(at('loras', 'x.safetensors'), '/r')),
      );
      expect(kind, CivitaiFailure.redirect);
    });

    test('a redirect loop ends', () async {
      host.routes['/loop'] = (request) async {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/loop');
        await request.response.close();
      };
      final kind = await civitaiFailureOf(
        downloadCivitaiPlan(plan(at('loras', 'x.safetensors'), '/loop')),
      );
      expect(kind, CivitaiFailure.redirect);
      expect(host.hits('/loop'), 5);
    });

    test(
      'the key does not follow to another host, or come back on its next hop',
      () async {
        void redirect(String from, Uri to) {
          host.routes[from] = (request) async {
            request.response.statusCode = 302;
            request.response.headers.set('location', to.toString());
            await request.response.close();
          };
        }

        redirect('/a', host.uri('/b', host: 'localhost'));
        redirect('/b', host.uri('/c', host: 'localhost'));
        host.serve('/c', bytes);
        await downloadCivitaiPlan(plan(at('loras', 'x.safetensors'), '/a'));
        expect(host.authorizationAt('/a'), 'Bearer test-token');
        expect(host.authorizationAt('/b'), isNull);
        expect(host.authorizationAt('/c'), isNull);
        expect(File(at('loras', 'x.safetensors')).readAsBytesSync(), bytes);
      },
    );

    test(
      'the key is sent again only when a hop returns to the original origin',
      () async {
        host.routes['/a'] = (request) async {
          request.response.statusCode = 302;
          request.response.headers.set(
            'location',
            host.uri('/b', host: 'localhost').toString(),
          );
          await request.response.close();
        };
        host.routes['/b'] = (request) async {
          request.response.statusCode = 302;
          request.response.headers.set('location', host.uri('/c').toString());
          await request.response.close();
        };
        host.serve('/c', bytes);
        await downloadCivitaiPlan(plan(at('loras', 'y.safetensors'), '/a'));
        expect(host.authorizationAt('/b'), isNull);
        expect(host.authorizationAt('/c'), 'Bearer test-token');
      },
    );

    test('the header rule itself never keeps the key off-origin', () {
      const token = 'Bearer k';
      final origin = Uri.parse('https://civitai.com/api/download/models/1');
      Map<String, String> hop(String to) => civitaiFollowHeaders(
        from: origin,
        to: Uri.parse(to),
        authorization: token,
      );
      expect(hop('https://civitai.com/other'), {'Authorization': token});
      expect(hop('http://civitai.com/other'), isEmpty);
      expect(hop('https://cdn.example/f'), isEmpty);
      expect(hop('https://civitai.com:8443/f'), isEmpty);
      expect(hop('https://civitai.red/f'), isEmpty);
      expect(civitaiHopAllowed(Uri.parse('http://cdn.example/f')), isFalse);
      expect(civitaiHopAllowed(Uri.parse('https://cdn.example/f')), isTrue);
    });
  });

  group('the shipped app allows only https', () {
    setUp(() => civitaiAllowLoopbackForTests = false);

    test('plain http to this computer is not allowed as a start or a hop', () {
      for (final url in [
        'http://127.0.0.1:8080/f',
        'http://localhost/f',
        'http://[::1]/f',
        'http://cdn.example/f',
      ]) {
        expect(civitaiHopAllowed(Uri.parse(url)), isFalse, reason: url);
      }
      expect(civitaiHopAllowed(Uri.parse('https://civitai.com/f')), isTrue);
    });

    test('and the key is not sent over it', () {
      final origin = Uri.parse('http://127.0.0.1:8080/api/download/models/1');
      expect(
        civitaiFollowHeaders(
          from: origin,
          to: origin,
          authorization: 'Bearer k',
        ),
        isEmpty,
      );
    });

    test(
      'a download plan that points at http is refused before any request',
      () async {
        host.serve('/ok', bytes);
        civitaiAllowLoopbackForTests = false;
        final kind = await civitaiFailureOf(
          downloadCivitaiPlan(plan(at('loras', 'x.safetensors'), '/ok')),
        );
        expect(kind, CivitaiFailure.redirect);
        expect(host.requests, isEmpty);
      },
    );
  });

  group('where a download may be written', () {
    Directory otherPlace() {
      final d = Directory.systemTemp.createTempSync('civitai-elsewhere');
      addTearDown(() => d.deleteSync(recursive: true));
      return d;
    }

    Future<CivitaiFailure> refusedInto(String link, String target) async {
      Link(link).createSync(target);
      host.serve('/ok', bytes);
      final kind = await civitaiFailureOf(
        downloadCivitaiPlan(plan(at('loras', 'x.safetensors'), '/ok')),
      );
      expect(host.requests, isEmpty);
      return kind;
    }

    test('a subfolder that is a link to another drive is followed', () async {
      final elsewhere = otherPlace();
      Link(p.join(dir.path, 'loras')).createSync(elsewhere.path);
      host.serve('/ok', bytes);
      await downloadCivitaiPlan(plan(at('loras', 'x.safetensors'), '/ok'));
      expect(
        File(p.join(elsewhere.path, 'x.safetensors')).readAsBytesSync(),
        bytes,
      );
    }, skip: Platform.isWindows);

    test('a models folder that is itself a link is followed', () async {
      final elsewhere = otherPlace();
      final shortcut = p.join(dir.path, 'models_link');
      Link(shortcut).createSync(elsewhere.path);
      host.serve('/ok', bytes);
      await downloadCivitaiPlan(
        civitaiTestPlan(
          host.uri('/ok'),
          p.join(shortcut, 'loras', 'x.safetensors'),
          root: shortcut,
        ),
      );
      expect(
        File(p.join(elsewhere.path, 'loras', 'x.safetensors')).existsSync(),
        isTrue,
      );
    }, skip: Platform.isWindows);

    test('a link to the drive root is refused', () async {
      expect(
        await refusedInto(p.join(dir.path, 'loras'), '/'),
        CivitaiFailure.unsafe,
      );
    }, skip: Platform.isWindows);

    test('a link to the home folder is refused', () async {
      final home = Platform.environment['HOME'] ?? '';
      if (home.isEmpty || !Directory(home).existsSync()) return;
      expect(
        await refusedInto(p.join(dir.path, 'loras'), home),
        CivitaiFailure.unsafe,
      );
    }, skip: Platform.isWindows);

    test('a link to a system folder is refused', () async {
      expect(
        await refusedInto(p.join(dir.path, 'loras'), '/etc'),
        CivitaiFailure.unsafe,
      );
    }, skip: Platform.isWindows || !Directory('/etc').existsSync());

    test(
      'a models folder that is a link to the drive root is refused',
      () async {
        final shortcut = p.join(dir.path, 'everything');
        Link(shortcut).createSync('/');
        final kind = await civitaiFailureOf(
          downloadCivitaiPlan(
            civitaiTestPlan(
              host.uri('/ok'),
              p.join(shortcut, 'x.safetensors'),
              root: shortcut,
            ),
          ),
        );
        expect(kind, CivitaiFailure.unsafe);
        expect(host.requests, isEmpty);
      },
      skip: Platform.isWindows,
    );

    test('the rule itself, with folders it is told about', () async {
      final sys = otherPlace();
      final home = otherPlace();
      final inHome = Directory(p.join(home.path, 'models'))..createSync();
      Future<bool> safe(String folder) => civitaiFolderIsSafe(
        folder,
        home: home.path,
        systemFolders: [sys.path],
      );
      expect(await safe(sys.path), isFalse);
      expect(await safe(p.join(sys.path, 'deep', 'not', 'yet')), isFalse);
      expect(await safe(home.path), isFalse);
      expect(await safe(inHome.path), isTrue);
      expect(await safe(p.join(inHome.path, 'loras')), isTrue);
      expect(await safe(dir.path), isTrue);
      expect(await safe(p.rootPrefix(dir.path)), isFalse);
    });

    test('pathStaysUnderRoot rejects escapes, siblings and relative roots', () {
      expect(pathStaysUnderRoot('/models', '/models'), isTrue);
      expect(pathStaysUnderRoot('/models', '/models/loras/a'), isTrue);
      expect(pathStaysUnderRoot('/models', '/models/../etc/passwd'), isFalse);
      expect(pathStaysUnderRoot('/models', '/models/loras/../../etc'), isFalse);
      expect(pathStaysUnderRoot('/models', '/models2/loras/a'), isFalse);
      expect(pathStaysUnderRoot('/models', '/model'), isFalse);
      expect(pathStaysUnderRoot('/models', '/'), isFalse);
      expect(pathStaysUnderRoot('models', 'models/a'), isFalse);
      expect(pathStaysUnderRoot('', '/a'), isFalse);
    });
  });

  group('a checkpoint that carries its own encoders and VAE', () {
    CivitaiDownloadPlan modelPlan(String route, List<int> body) {
      return civitaiTestPlan(
        host.uri(route),
        at('diffusion_models', 'flux.safetensors'),
        root: dir.path,
        expectedBytes: body.length,
        allInOnePath: at('checkpoints', 'flux.safetensors'),
      );
    }

    test('goes to checkpoints, because the header says so', () async {
      final body = civitaiSafetensors([
        'model.diffusion_model.double_blocks.0.w',
        'text_encoders.clip_l.transformer.w',
        'text_encoders.t5xxl.transformer.w',
        'vae.decoder.conv_in.w',
      ]);
      host.serve('/aio', body);
      final landed = await downloadCivitaiPlan(modelPlan('/aio', body));
      expect(landed, at('checkpoints', 'flux.safetensors'));
      expect(File(landed).lengthSync(), body.length);
      expect(
        File(at('diffusion_models', 'flux.safetensors')).existsSync(),
        isFalse,
      );
      expect(
        File(
          civitaiPartPath(at('diffusion_models', 'flux.safetensors')),
        ).existsSync(),
        isFalse,
      );
    });

    test('a bare diffusion model stays in diffusion_models', () async {
      final body = civitaiSafetensors([
        'double_blocks.0.img_attn.qkv.weight',
        'single_blocks.0.linear1.weight',
      ]);
      host.serve('/unet', body);
      final landed = await downloadCivitaiPlan(modelPlan('/unet', body));
      expect(landed, at('diffusion_models', 'flux.safetensors'));
      expect(File(at('checkpoints', 'flux.safetensors')).existsSync(), isFalse);
    });

    test(
      'a file that is not safetensors at all stays where the name put it',
      () async {
        final body = List<int>.generate(40, (i) => 200 - i);
        host.serve('/junk', body);
        final landed = await downloadCivitaiPlan(modelPlan('/junk', body));
        expect(landed, at('diffusion_models', 'flux.safetensors'));
      },
    );

    test('an all-in-one never replaces a checkpoint of that name', () async {
      final body = civitaiSafetensors([
        'text_encoders.clip_l.w',
        'vae.decoder.w',
        'model.diffusion_model.w',
      ]);
      host.serve('/aio', body);
      final existing = File(at('checkpoints', 'flux.safetensors'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(const [3, 3]);
      final kind = await civitaiFailureOf(
        downloadCivitaiPlan(modelPlan('/aio', body)),
      );
      expect(kind, CivitaiFailure.nameTaken);
      expect(existing.readAsBytesSync(), const [3, 3]);
      expect(
        File(
          civitaiPartPath(at('diffusion_models', 'flux.safetensors')),
        ).existsSync(),
        isFalse,
      );
    });

    test('the header reader names tensors and ignores metadata', () async {
      final file = File(p.join(dir.path, 't.safetensors'))
        ..writeAsBytesSync(civitaiSafetensors(['a.b', 'c.d']));
      expect(await safetensorsTensorNames(file), ['a.b', 'c.d']);
      final junk = File(p.join(dir.path, 'junk.bin'))
        ..writeAsBytesSync(const [1, 2, 3]);
      expect(await safetensorsTensorNames(junk), isNull);
      final huge = File(p.join(dir.path, 'huge.safetensors'))
        ..writeAsBytesSync(const [255, 255, 255, 255, 255, 255, 255, 127, 1]);
      expect(await safetensorsTensorNames(huge), isNull);
    });
  });

  group('partial downloads left behind', () {
    test('a sweep removes only our stale parts and never a live one', () async {
      final longAgo = DateTime.now().subtract(const Duration(hours: 3));
      final stale1 = File(civitaiPartPath(at('loras', 'a.safetensors')))
        ..createSync(recursive: true)
        ..setLastModifiedSync(longAgo);
      final stale2 = File(civitaiPartPath(at('checkpoints', 'b.safetensors')))
        ..createSync(recursive: true)
        ..setLastModifiedSync(longAgo);
      final otherTool = File(at('loras', 'browser.safetensors.part'))
        ..createSync(recursive: true)
        ..setLastModifiedSync(longAgo);
      final model = File(at('loras', 'keep.safetensors'))
        ..writeAsBytesSync(const [1]);
      final release = Completer<void>();
      host.serveThenHold('/live', bytes.sublist(0, 8), hold: release.future);
      final live = at('loras', 'live.safetensors');
      final started = Completer<void>();
      final run = downloadCivitaiPlan(
        plan(live, '/live'),
        onProgress: (got, _) {
          if (got > 0 && !started.isCompleted) started.complete();
        },
      ).then<Object?>((v) => v, onError: (_) => null);
      await started.future.timeout(const Duration(seconds: 10));

      expect(await sweepCivitaiParts(dir.path), 2);

      expect(stale1.existsSync(), isFalse);
      expect(stale2.existsSync(), isFalse);
      expect(otherTool.existsSync(), isTrue);
      expect(model.existsSync(), isTrue);
      expect(File(civitaiPartPath(live)).existsSync(), isTrue);
      release.complete();
      await run;
    });
  });
}
