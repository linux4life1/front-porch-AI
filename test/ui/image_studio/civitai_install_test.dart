// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What one Download press does on the desktop, against a real file host on
// loopback. Version data is the real fixture 133005 with its size and
// checksum swapped for a tiny payload; only the host name is redirected.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image/studio_model_roots.dart';
import 'package:front_porch_ai/ui/image_studio/studio_civitai_install.dart';

import '../../services/image/civitai_test_server.dart';

void main() {
  const file = 'MaouBigV1.2.safetensors';
  final payload = List<int>.generate(48, (i) => i + 1);
  final row = CivitaiModelRow(
    id: 102565,
    name: 'Maou (Both Forms)',
    type: 'LORA',
    adult: false,
    versionId: 133005,
    filename: file,
  );

  late Directory root;
  late CivitaiFileHost host;
  var lookup = CivitaiLookupKind.ok;
  var lookups = 0;
  var fixtureId = 133005;
  bool? adultSeen;
  Uri? uriSeen;

  CivitaiVersion version() {
    final raw =
        jsonDecode(
              File(
                'test/fixtures/civitai/version_$fixtureId.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final f = (raw['files'] as List).first as Map<String, dynamic>;
    f['sizeKB'] = payload.length / 1024;
    (f['hashes'] as Map)['SHA256'] = sha256.convert(payload).toString();
    return parseCivitaiVersion(jsonEncode(raw))!;
  }

  Future<CivitaiVersionLookup> fetch({
    required int versionId,
    required bool adult,
    String? authorization,
  }) async {
    lookups++;
    adultSeen = adult;
    if (lookup != CivitaiLookupKind.ok) return CivitaiVersionLookup(lookup);
    return CivitaiVersionLookup(CivitaiLookupKind.ok, version());
  }

  Future<String> save(
    CivitaiDownloadPlan plan, {
    void Function(int received, int? total)? onProgress,
    CivitaiCancel? cancel,
  }) {
    uriSeen = plan.uri;
    return downloadCivitaiPlan(
      CivitaiDownloadPlan(
        uri: host.uri('/file'),
        path: plan.path,
        authorization: plan.authorization,
        log: plan.log,
        refused: plan.refused,
        reason: plan.reason,
        failure: plan.failure,
        root: plan.root,
        expectedBytes: plan.expectedBytes,
        sha256: plan.sha256,
      ),
      idle: const Duration(milliseconds: 300),
      onProgress: onProgress,
      cancel: cancel,
    );
  }

  Future<CivitaiInstallResult> press({
    CivitaiModelRow? of,
    bool adult = false,
    bool adultAllowed = true,
    CivitaiCancel? cancel,
  }) {
    return installCivitaiRow(
      row: of ?? row,
      backend: 'comfyui',
      lora: true,
      adult: adult,
      adultAllowed: adultAllowed,
      versionFetch: fetch,
      saveCall: save,
      cancel: cancel ?? CivitaiCancel(),
      onProgress: (_, _) {},
    );
  }

  String failure(CivitaiInstallResult r) {
    expect(r, isA<CivitaiInstallFailed>());
    return (r as CivitaiInstallFailed).message;
  }

  File loraFile() => File(p.join(root.path, 'loras', file));

  setUp(() async {
    root = Directory.systemTemp.createTempSync('civitai-install');
    addTearDown(() => root.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({
      kStudioModelRootsKey: encodeModelRoots({'comfyui': root.path}),
    });
    FlutterSecureStorage.setMockInitialValues({
      'civitai_credential_local': 'k',
    });
    host = await CivitaiFileHost.start();
    host.serve('/file', payload);
    lookup = CivitaiLookupKind.ok;
    lookups = 0;
    fixtureId = 133005;
    adultSeen = null;
    uriSeen = null;
  });

  test('a good press installs the file CivitAI lists', () async {
    final result = await press();
    expect(result, isA<CivitaiInstalled>());
    expect((result as CivitaiInstalled).name, file);
    expect(loraFile().readAsBytesSync(), payload);
  });

  test('the file name comes from CivitAI when the row has none', () async {
    final bare = CivitaiModelRow(
      id: 1,
      name: 'x',
      type: 'LORA',
      adult: false,
      versionId: 133005,
    );
    expect(await press(of: bare), isA<CivitaiInstalled>());
    expect(loraFile().existsSync(), isTrue);
  });

  test(
    'a stale row naming a file CivitAI does not list saves nothing',
    () async {
      final stale = CivitaiModelRow(
        id: 1,
        name: 'x',
        type: 'LORA',
        adult: false,
        versionId: 133005,
        filename: 'renamed.safetensors',
      );
      expect(failure(await press(of: stale)), contains('does not list'));
      expect(host.requests, isEmpty);
      expect(root.listSync(), isEmpty);
    },
  );

  test('a row with no version is refused without asking CivitAI', () async {
    final none = CivitaiModelRow(id: 1, name: 'x', type: 'LORA', adult: false);
    expect(failure(await press(of: none)), contains('no file to download'));
    expect(lookups, 0);
  });

  group('two files with the same name', () {
    test('a different file is kept, and not called installed', () async {
      loraFile()
        ..createSync(recursive: true)
        ..writeAsBytesSync(const [9, 9, 9]);
      final message = failure(await press());
      expect(message, contains('different file'));
      expect(loraFile().readAsBytesSync(), const [9, 9, 9]);
      expect(host.requests, isEmpty);
    });

    test(
      'the same size as CivitAI lists is installed without downloading',
      () async {
        loraFile()
          ..createSync(recursive: true)
          ..writeAsBytesSync(List<int>.filled(payload.length, 4));
        final result = await press();
        expect(result, isA<CivitaiInstalled>());
        expect(host.requests, isEmpty);
        expect(
          loraFile().readAsBytesSync(),
          List<int>.filled(payload.length, 4),
        );
      },
    );
  });

  group('each failure has its own words', () {
    Future<String> failing(void Function() arrange) async {
      arrange();
      return failure(await press());
    }

    test(
      'the messages are different, and none blames the wrong thing',
      () async {
        final messages = <String, String>{
          'locked': await failing(() => host.status('/file', 403)),
          'missing': await failing(() => host.status('/file', 404)),
          'key': await failing(() => host.status('/file', 401)),
          'server': await failing(() => host.status('/file', 500)),
          'short': await failing(
            () => host.serveChunked('/file', payload.sublist(0, 3)),
          ),
          'checksum': await failing(
            () => host.serve('/file', List<int>.filled(payload.length, 0)),
          ),
          'stall': await failing(() => host.serveThenHold('/file', const [1])),
        };
        expect(messages['locked'], contains('will not send'));
        expect(messages['missing'], contains('no longer has'));
        expect(messages['key'], contains('refused the API key'));
        expect(messages['server'], contains('HTTP 500'));
        expect(messages['short'], contains('before the whole file'));
        expect(messages['checksum'], contains('checksum'));
        expect(messages['stall'], contains('stalled'));
        expect(messages.values.toSet().length, messages.length);
        expect(loraFile().existsSync(), isFalse);
      },
    );

    test('a lookup that fails says which way', () async {
      lookup = CivitaiLookupKind.needsCredential;
      expect(failure(await press()), contains('refused the API key'));
      lookup = CivitaiLookupKind.locked;
      expect(failure(await press()), contains('will not send'));
      lookup = CivitaiLookupKind.notFound;
      expect(failure(await press()), contains('no longer has'));
      lookup = CivitaiLookupKind.failed;
      expect(failure(await press()), contains('Could not reach'));
    });

    test('no saved key asks for one before any network', () async {
      FlutterSecureStorage.setMockInitialValues({});
      expect(failure(await press()), contains('Paste an API key'));
      expect(lookups, 0);
    });
  });

  group('stopping', () {
    test(
      'a cancel during the download stops it and leaves nothing behind',
      () async {
        final release = Completer<void>();
        host.serveThenHold(
          '/file',
          payload.sublist(0, 8),
          hold: release.future,
          rest: payload.sublist(8),
        );
        final cancel = CivitaiCancel();
        final got = Completer<void>();
        final run = installCivitaiRow(
          row: row,
          backend: 'comfyui',
          lora: true,
          adult: false,
          adultAllowed: true,
          versionFetch: fetch,
          saveCall: save,
          cancel: cancel,
          onProgress: (n, _) {
            if (n > 0 && !got.isCompleted) got.complete();
          },
        );
        await got.future.timeout(const Duration(seconds: 10));
        cancel.cancel();
        expect(await run, isA<CivitaiInstallStopped>());
        release.complete();
        expect(loraFile().existsSync(), isFalse);
        expect(File(civitaiPartPath(loraFile().path)).existsSync(), isFalse);
      },
    );

    test(
      'a cancel before the file is asked for never reaches the host',
      () async {
        final cancel = CivitaiCancel()..cancel();
        expect(await press(cancel: cancel), isA<CivitaiInstallStopped>());
        expect(host.requests, isEmpty);
      },
    );
  });

  group('a model rated adult follows the app setting', () {
    final adultRow = CivitaiModelRow(
      id: 28907,
      name: 'Anime Lineart',
      type: 'LORA',
      adult: false,
      versionId: 28907,
      filename: 'animeoutlineV4_16.safetensors',
    );

    test(
      'with adult off, a nsfw=false nsfwLevel=23 model is refused and never fetched',
      () async {
        fixtureId = 28907;
        final message = failure(await press(of: adultRow, adultAllowed: false));
        expect(message, contains('rated adult'));
        expect(host.requests, isEmpty);
        expect(root.listSync(), isEmpty);
      },
    );

    test('with adult on it installs', () async {
      fixtureId = 28907;
      final result = await press(of: adultRow);
      expect(result, isA<CivitaiInstalled>());
      expect(
        File(
          p.join(root.path, 'loras', 'animeoutlineV4_16.safetensors'),
        ).existsSync(),
        isTrue,
      );
    });
  });

  group('adult', () {
    test('an adult press asks civitai.red', () async {
      await press(adult: true);
      expect(adultSeen, isTrue);
      expect(uriSeen!.host, 'civitai.red');
    });

    test('a plain press asks civitai.com', () async {
      await press();
      expect(adultSeen, isFalse);
      expect(uriSeen!.host, 'civitai.com');
    });
  });

  test('a ComfyUI on another computer is not written to', () async {
    SharedPreferences.setMockInitialValues({
      'comfy_ui_url': 'http://192.0.2.44:8188',
    });
    expect(failure(await press()), contains('another computer'));
    expect(lookups, 0);
  });
}
