// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's download route, end to end: a real relay, real CivitAI version
// data (fixture 133005 with its size and checksum swapped for a tiny payload),
// and a real HTTP file host on loopback. The one thing swapped is the host
// name the finished plan points at.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/web/routes/civitai_routes.dart';

import 'civitai_route_support.dart';
import 'civitai_test_server.dart';

void main() {
  const file = 'MaouBigV1.2.safetensors';
  final payload = List<int>.generate(48, (i) => i + 1);

  late Directory root;
  late CivitaiFileHost host;
  late CivitaiRoutes routes;
  late Map<String, String> box;
  var adult = false;
  var lookupKind = CivitaiLookupKind.ok;
  var lookups = 0;
  var planned = <CivitaiDownloadPlan>[];

  String versionJson() {
    final raw =
        jsonDecode(
              File(
                'test/fixtures/civitai/version_133005.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final f = (raw['files'] as List).first as Map<String, dynamic>;
    f['sizeKB'] = payload.length / 1024;
    (f['hashes'] as Map)['SHA256'] = sha256
        .convert(payload)
        .toString()
        .toUpperCase();
    return jsonEncode(raw);
  }

  Future<CivitaiVersionLookup> fetchVersion({
    required int versionId,
    required bool adult,
    String? authorization,
  }) async {
    lookups++;
    if (lookupKind != CivitaiLookupKind.ok) {
      return CivitaiVersionLookup(lookupKind);
    }
    expect(authorization, 'Bearer the-key');
    return CivitaiVersionLookup(
      CivitaiLookupKind.ok,
      parseCivitaiVersion(versionJson()),
    );
  }

  Future<CivitaiRoutes> build({String? Function(String)? rootFor}) async {
    final harness = await CivitaiAuthHarness.create();
    return CivitaiRoutes(
      Router(),
      auth: harness.auth,
      adultAllowed: () => adult,
      relay: CivitaiRelay(memoryCivitaiStore(box)),
      rootFor: rootFor ?? (_) => root.path,
      versionFetch: fetchVersion,
      downloads: CivitaiDownloads(
        run: (plan, {onProgress, cancel, onStarted}) {
          planned.add(plan);
          return downloadCivitaiPlan(
            CivitaiDownloadPlan(
              uri: host.uri('/file'),
              path: plan.path,
              authorization: plan.authorization,
              log: plan.log,
              refused: false,
              root: plan.root,
              expectedBytes: plan.expectedBytes,
              sha256: plan.sha256,
              allInOnePath: plan.allInOnePath,
            ),
            idle: const Duration(milliseconds: 400),
            onProgress: onProgress,
            cancel: cancel,
            onStarted: onStarted,
          );
        },
      ),
    );
  }

  Map<String, Object?> body({Map<String, Object?> extra = const {}}) => {
    'versionId': 133005,
    'filename': file,
    'lora': true,
    'backend': 'comfyui',
    ...extra,
  };

  Future<Response> post(Map<String, Object?> b, {String? account = 'local'}) =>
      routes.download(
        civitaiRequest(
          'POST',
          '/api/image/civitai/download',
          body: b,
          account: account,
        ),
      );

  Future<Map<String, dynamic>> status(
    String id, {
    String account = 'local',
  }) async {
    final res = await routes.downloadStatus(
      civitaiRequest(
        'GET',
        '/api/image/civitai/download/status?job=$id',
        account: account,
      ),
    );
    return {'status': res.statusCode, ...await civitaiJson(res)};
  }

  Future<Map<String, dynamic>> settle(String id) async {
    for (var i = 0; i < 100; i++) {
      final now = await status(id);
      if (now['state'] != 'running') return now;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('the download never finished');
  }

  Future<String> started(Map<String, Object?> b) async {
    final res = await post(b);
    expect(res.statusCode, 202);
    return (await civitaiJson(res))['jobId'] as String;
  }

  String dest() => p.join(root.path, 'loras', file);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('civitai-routes');
    addTearDown(() => root.deleteSync(recursive: true));
    host = await CivitaiFileHost.start();
    host.serve('/file', payload);
    box = {'civitai_credential_local': 'the-key'};
    adult = false;
    lookupKind = CivitaiLookupKind.ok;
    lookups = 0;
    planned = [];
    routes = await build();
  });

  group('starting a download', () {
    test(
      'answers at once with a job, and never says where the file is',
      () async {
        final res = await post(body());
        expect(res.statusCode, 202);
        final text = await res.readAsString();
        final json = jsonDecode(text) as Map<String, dynamic>;
        expect(json['jobId'], isA<String>());
        expect(json['name'], file);
        expect(json['state'], 'running');
        expect(json.containsKey('path'), isFalse);
        expect(text.contains(root.path), isFalse);
        expect(text.contains('the-key'), isFalse);
      },
    );

    test('finishes with the listed file in the saved folder', () async {
      final id = await started(body());
      final done = await settle(id);
      expect(done['state'], 'done');
      expect(done['percent'], 100);
      expect(done['received'], payload.length);
      expect(File(dest()).readAsBytesSync(), payload);
      expect(File(civitaiPartPath(dest())).existsSync(), isFalse);
      expect(done.containsKey('path'), isFalse);
    });

    test(
      'a request that names no file gets the version\'s own primary file',
      () async {
        final id = await started(body(extra: {'filename': ''}));
        expect((await settle(id))['state'], 'done');
        expect(File(dest()).existsSync(), isTrue);
      },
    );

    test('the phone cannot pick the type, the folder or the file', () async {
      final res = await post(
        body(
          extra: {
            'filename': '../../etc/evil.safetensors',
            'type': 'Checkpoint',
            'root': '/tmp/evil',
            'accountId': 'other',
          },
        ),
      );
      expect(res.statusCode, 400);
      expect((await civitaiJson(res))['code'], 'unsafe');
      expect(planned, isEmpty);
      expect(root.listSync(), isEmpty);
    });

    test('a file CivitAI does not list for that version is refused', () async {
      final res = await post(body(extra: {'filename': 'other.safetensors'}));
      expect(res.statusCode, 400);
      expect(planned, isEmpty);
    });

    test(
      'a LoRA cannot be sent to the model folders by naming another sheet',
      () async {
        final res = await post(body(extra: {'lora': false}));
        expect(res.statusCode, 400);
        expect(planned, isEmpty);
      },
    );

    test(
      'the plan handed to the downloader uses the server-side folder',
      () async {
        final id = await started(body(extra: {'root': '/tmp/evil'}));
        await settle(id);
        expect(planned.single.path, dest());
        expect(planned.single.root, root.path);
        expect(planned.single.expectedBytes, payload.length);
      },
    );
  });

  group('refusals say why, with their own status and code', () {
    Future<void> expectRefused(Response res, int status, String code) async {
      expect(res.statusCode, status);
      final json = await civitaiJson(res);
      expect(json['code'], code);
      expect(json['error'], isA<String>());
      expect(json['error'], isNotEmpty);
    }

    test('no saved key', () async {
      box.clear();
      await expectRefused(await post(body()), 400, 'key_missing');
      expect(lookups, 0);
    });

    test('CivitAI refusing the key while looking the version up', () async {
      lookupKind = CivitaiLookupKind.needsCredential;
      await expectRefused(await post(body()), 403, 'key_refused');
    });

    test('a locked version', () async {
      lookupKind = CivitaiLookupKind.locked;
      await expectRefused(await post(body()), 403, 'locked');
    });

    test('a version that is gone', () async {
      lookupKind = CivitaiLookupKind.notFound;
      await expectRefused(await post(body()), 404, 'not_found');
    });

    test('CivitAI being unreachable', () async {
      lookupKind = CivitaiLookupKind.failed;
      await expectRefused(await post(body()), 502, 'network');
    });

    test('no versionId', () async {
      await expectRefused(
        await post({'backend': 'comfyui'}),
        400,
        'bad_request',
      );
    });

    test('not signed in', () async {
      final res = await post(body(), account: null);
      expect(res.statusCode, 401);
    });

    test('an adult download while adult themes are off', () async {
      await expectRefused(
        await post(body(extra: {'adult': true})),
        403,
        'adult_disabled',
      );
      expect(lookups, 0);
    });

    test('a backend with no models folder', () async {
      routes = await build(rootFor: (_) => null);
      await expectRefused(
        await post(body(extra: {'backend': 'a1111'})),
        400,
        'no_folder',
      );
    });

    test('a ComfyUI on another computer', () async {
      SharedPreferences.setMockInitialValues({
        'comfy_ui_url': 'http://192.0.2.9:8188',
      });
      routes = await build(rootFor: (_) => null);
      await expectRefused(await post(body()), 400, 'remote_comfy');
    });
  });

  group('the same file twice', () {
    test('while it is downloading is a 409 "busy"', () async {
      final release = Completer<void>();
      host.serveThenHold(
        '/file',
        payload.sublist(0, 8),
        hold: release.future,
        rest: payload.sublist(8),
      );
      await started(body());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final second = await post(body());
      expect(second.statusCode, 409);
      final json = await civitaiJson(second);
      expect(json['code'], 'busy');
      expect(json['installed'], isFalse);
      release.complete();
    });

    test(
      'when a different file has that name is a 409 "name_taken" and it is kept',
      () async {
        File(dest())
          ..createSync(recursive: true)
          ..writeAsBytesSync(const [9, 9]);
        final res = await post(body());
        expect(res.statusCode, 409);
        expect((await civitaiJson(res))['code'], 'name_taken');
        expect(File(dest()).readAsBytesSync(), const [9, 9]);
      },
    );

    test('when it is already installed is a 409 that says so', () async {
      File(dest())
        ..createSync(recursive: true)
        ..writeAsBytesSync(List<int>.filled(payload.length, 5));
      final res = await post(body());
      expect(res.statusCode, 409);
      final json = await civitaiJson(res);
      expect(json['code'], 'exists');
      expect(json['installed'], isTrue);
    });
  });

  test('a third download at once is a 429 with a wait', () async {
    final release = Completer<void>();
    host.serveThenHold(
      '/file',
      payload.sublist(0, 8),
      hold: release.future,
      rest: payload.sublist(8),
    );
    File(p.join(root.path, 'seed')).createSync();
    Future<Response> other(String name) => routes.download(
      civitaiRequest(
        'POST',
        '/api/image/civitai/download',
        body: body(),
        account: 'local',
      ),
    );
    // Two different files: hold two real downloads open by hand.
    final slot1 = downloadCivitaiPlan(
      civitaiTestPlan(
        host.uri('/file'),
        p.join(root.path, 'loras', 'one.safetensors'),
        root: root.path,
      ),
      idle: const Duration(seconds: 5),
    ).then<Object?>((v) => v, onError: (_) => null);
    final slot2 = downloadCivitaiPlan(
      civitaiTestPlan(
        host.uri('/file'),
        p.join(root.path, 'loras', 'two.safetensors'),
        root: root.path,
      ),
      idle: const Duration(seconds: 5),
    ).then<Object?>((v) => v, onError: (_) => null);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final res = await other('c');
    expect(res.statusCode, 429);
    expect((await civitaiJson(res))['code'], 'too_many');
    expect(res.headers['retry-after'], '30');
    release.complete();
    await Future.wait([slot1, slot2]);
  });

  group('a download that fails reports its own reason', () {
    Future<Map<String, dynamic>> failing(void Function() arrange) async {
      arrange();
      final id = await started(body());
      final done = await settle(id);
      expect(done['state'], 'failed');
      expect(File(dest()).existsSync(), isFalse);
      expect(File(civitaiPartPath(dest())).existsSync(), isFalse);
      return done;
    }

    test('CivitAI refusing the file', () async {
      final done = await failing(() => host.status('/file', 403));
      expect(done['code'], 'locked');
      expect(done['error'], contains('will not send'));
    });

    test('a missing file', () async {
      final done = await failing(() => host.status('/file', 404));
      expect(done['code'], 'not_found');
    });

    test('a rejected key', () async {
      final done = await failing(() => host.status('/file', 401));
      expect(done['code'], 'key_refused');
    });

    test('a body that ends early', () async {
      final done = await failing(
        () => host.serveChunked('/file', payload.sublist(0, 5)),
      );
      expect(done['code'], 'short');
    });

    test('a file that is not what CivitAI listed', () async {
      final done = await failing(
        () => host.serve('/file', List<int>.filled(payload.length, 0)),
      );
      expect(done['code'], 'hash_mismatch');
    });

    test('a stall', () async {
      final done = await failing(
        () => host.serveThenHold('/file', const [1, 2]),
      );
      expect(done['code'], 'stalled');
    });
  });

  group('stopping a download', () {
    Future<String> holdOpen(Completer<void> release) async {
      host.serveThenHold(
        '/file',
        payload.sublist(0, 8),
        hold: release.future,
        rest: payload.sublist(8),
      );
      final id = await started(body());
      for (
        var i = 0;
        i < 100 && File(civitaiPartPath(dest())).existsSync() == false;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      expect((await status(id))['state'], 'running');
      return id;
    }

    test('DELETE cancels it, removes the part and frees the name', () async {
      final release = Completer<void>();
      final id = await holdOpen(release);
      final res = await routes.cancelDownload(
        civitaiRequest('DELETE', '/api/image/civitai/download?job=$id'),
      );
      expect(res.statusCode, 200);
      final done = await settle(id);
      expect(done['state'], 'cancelled');
      expect(done['code'], 'cancelled');
      expect(File(dest()).existsSync(), isFalse);
      expect(File(civitaiPartPath(dest())).existsSync(), isFalse);
      release.complete();
      host.serve('/file', payload);
      expect((await settle(await started(body())))['state'], 'done');
    });

    test('the POST form works for a phone that cannot send DELETE', () async {
      final release = Completer<void>();
      final id = await holdOpen(release);
      final res = await routes.cancelDownload(
        civitaiRequest(
          'POST',
          '/api/image/civitai/download/cancel',
          body: {'job': id},
        ),
      );
      expect(res.statusCode, 200);
      expect((await settle(id))['state'], 'cancelled');
      release.complete();
    });

    test('another account can neither see nor stop it', () async {
      final release = Completer<void>();
      final id = await holdOpen(release);
      expect((await status(id, account: 'other'))['status'], 404);
      final res = await routes.cancelDownload(
        civitaiRequest(
          'DELETE',
          '/api/image/civitai/download?job=$id',
          account: 'other',
        ),
      );
      expect(res.statusCode, 404);
      expect((await status(id))['state'], 'running');
      release.complete();
    });

    test('an unknown job is a 404', () async {
      expect((await status('nope'))['status'], 404);
      final res = await routes.cancelDownload(
        civitaiRequest('DELETE', '/api/image/civitai/download?job=nope'),
      );
      expect(res.statusCode, 404);
    });
  });

  test(
    'starting a download clears our stale partial files in that folder',
    () async {
      final stale = File(
        civitaiPartPath(p.join(root.path, 'loras', 'old.safetensors')),
      )..createSync(recursive: true);
      final id = await started(body());
      await settle(id);
      expect(stale.existsSync(), isFalse);
    },
  );

  test('progress carries a percent the phone can draw', () async {
    final release = Completer<void>();
    host.serveThenHold(
      '/file',
      payload.sublist(0, 24),
      hold: release.future,
      rest: payload.sublist(24),
    );
    final id = await started(body());
    Map<String, dynamic> now = {};
    for (var i = 0; i < 100; i++) {
      now = await status(id);
      if ((now['received'] as int) > 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    expect(now['total'], payload.length);
    expect(now['percent'], 50);
    release.complete();
    expect((await settle(id))['percent'], 100);
  });
}
