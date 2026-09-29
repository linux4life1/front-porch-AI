// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone route with a ComfyUI whose config keeps checkpoints on another
// drive. Real relay, real version data (DreamShaper 128713, size and checksum
// swapped for a tiny payload), a real file host on loopback.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/web/routes/civitai_routes.dart';

import 'civitai_route_support.dart';
import 'civitai_test_server.dart';

void main() {
  const file = 'dreamshaper_8.safetensors';
  final payload = List<int>.generate(40, (i) => i + 3);

  late Directory root;
  late String bigDrive;
  late CivitaiFileHost host;
  late CivitaiRoutes routes;
  final swept = <String>[];

  CivitaiVersion version() {
    final raw =
        jsonDecode(
              File(
                'test/fixtures/civitai/version_128713.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final f = (raw['files'] as List).first as Map<String, dynamic>;
    f['sizeKB'] = payload.length / 1024;
    (f['hashes'] as Map)['SHA256'] = sha256.convert(payload).toString();
    return parseCivitaiVersion(jsonEncode(raw))!;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('civitai-kinds');
    addTearDown(() => dir.deleteSync(recursive: true));
    root = Directory(p.join(dir.path, 'data'))..createSync();
    bigDrive = p.join(dir.path, 'big', 'checkpoints');
    host = await CivitaiFileHost.start();
    host.serve('/file', payload);
    swept.clear();
    final harness = await CivitaiAuthHarness.create();
    routes = CivitaiRoutes(
      Router(),
      auth: harness.auth,
      adultAllowed: () => false,
      relay: CivitaiRelay(
        memoryCivitaiStore({'civitai_credential_local': 'k'}),
      ),
      rootFor: (_) => root.path,
      rootGone: (_) async => false,
      typeFoldersFor: (backend, _) async =>
          backend == 'comfyui' ? {'checkpoints': bigDrive} : const {},
      sweep: (folder) async {
        swept.add(folder);
        return 0;
      },
      versionFetch:
          ({required versionId, required adult, authorization}) async =>
              CivitaiVersionLookup(CivitaiLookupKind.ok, version()),
      downloads: CivitaiDownloads(
        run: (plan, {onProgress, cancel, onStarted}) => downloadCivitaiPlan(
          CivitaiDownloadPlan(
            uri: host.uri('/file'),
            path: plan.path,
            authorization: plan.authorization,
            log: plan.log,
            refused: false,
            root: plan.root,
            expectedBytes: plan.expectedBytes,
            sha256: plan.sha256,
          ),
          onProgress: onProgress,
          cancel: cancel,
          onStarted: onStarted,
        ),
      ),
    );
  });

  Future<Map<String, dynamic>> settle(String id) async {
    for (var i = 0; i < 100; i++) {
      final res = await routes.downloadStatus(
        civitaiRequest('GET', '/api/image/civitai/download/status?job=$id'),
      );
      final json = await civitaiJson(res);
      if (json['state'] != 'running') return json;
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    fail('the download never finished');
  }

  test(
    'a checkpoint lands in the config\'s checkpoints folder, not under the models folder',
    () async {
      final res = await routes.download(
        civitaiRequest(
          'POST',
          '/api/image/civitai/download',
          body: {
            'versionId': 128713,
            'filename': file,
            'lora': false,
            'backend': 'comfyui',
          },
        ),
      );
      expect(res.statusCode, 202);
      final id = (await civitaiJson(res))['jobId'] as String;
      expect((await settle(id))['state'], 'done');
      expect(File(p.join(bigDrive, file)).readAsBytesSync(), payload);
      expect(
        File(p.join(root.path, 'checkpoints', file)).existsSync(),
        isFalse,
      );
      expect(swept, containsAll([root.path, bigDrive]));
    },
  );

  test('the installed list reads the config\'s checkpoints folder', () async {
    File(p.join(bigDrive, 'far_away.safetensors'))
      ..createSync(recursive: true)
      ..writeAsStringSync('w');
    final res = await routes.installedFiles(
      civitaiRequest('GET', '/api/image/civitai/installed?backend=comfyui'),
    );
    final json = await civitaiJson(res);
    expect(json['models'], contains('far_away.safetensors'));
  });
}
