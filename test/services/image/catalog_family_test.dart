// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

Future<T> _withRealHttp<T>(Future<T> Function() body) =>
    HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fallback = [
    ImageModelInfo(id: 'bundled-qwen', name: 'Bundled Qwen', isPaid: false),
  ];

  test(
    'fixture body contributes a model that is not in the fallback',
    () async {
      final models = await loadNanoImageCatalog(
        fetchBody: () async => jsonEncode({
          'data': [
            {'id': 'only-in-fixture', 'name': 'Fixture Only', 'isPaid': false},
          ],
        }),
        fallback: fallback,
      );
      expect(models.map((m) => m.id), contains('only-in-fixture'));
      expect(models.single.isPaid, isFalse);
      expect(models.map((m) => m.id), isNot(contains('bundled-qwen')));
    },
  );

  test(
    'a failed fetch returns the fallback and does not fetch again',
    () async {
      var calls = 0;
      final models = await loadNanoImageCatalog(
        fetchBody: () async {
          calls++;
          throw const SocketException('offline');
        },
        fallback: fallback,
      );
      expect(calls, 1);
      expect(models, isNotEmpty);
      expect(models.single.id, 'bundled-qwen');
    },
  );

  test('fetchImageModels reads a loopback fixture and falls back on 500', () {
    return _withRealHttp(() async {
      final server = await _CatalogServer.start();
      final storage = _Store('/does/not/matter');
      await storage.backendSettings.setRemoteApiUrl(server.baseUrl);
      await storage.backendSettings.setRemoteApiKey('key-123');
      final service = ImageGenService(storage);

      server.body = jsonEncode({
        'data': [
          {'id': 'only-in-fixture', 'name': 'Fixture Only', 'isPaid': true},
        ],
      });
      server.status = 200;
      final live = await service.fetchImageModels();
      expect(live.map((m) => m.id), contains('only-in-fixture'));
      expect(server.hits, 1);

      server.status = 500;
      final offline = await service.fetchImageModels();
      expect(offline, isNotEmpty);
      expect(offline.map((m) => m.id), contains('qwen-image'));
      expect(offline.map((m) => m.id), isNot(contains('only-in-fixture')));
      expect(server.hits, 2);
      await server.close();
    });
  });

  group('family detection', () {
    test('qwen, z-image, and kontext are known; a stranger stays unknown', () {
      expect(
        ImageModelFamily.detectFromName('qwen_image_edit.safetensors'),
        ModelFamily.qwen,
      );
      expect(
        ImageModelFamily.detectFromName('z-image-turbo.safetensors'),
        ModelFamily.zImage,
      );
      expect(
        ImageModelFamily.detectFromName('z_image_base.ckpt'),
        ModelFamily.zImage,
      );
      expect(
        ImageModelFamily.detectFromName('flux-kontext-dev.safetensors'),
        ModelFamily.kontext,
      );
      expect(
        ImageModelFamily.detectFromMetadata({
          'modelspec.architecture': 'qwen-image',
        }),
        ModelFamily.qwen,
      );
      expect(
        ImageModelFamily.detectFromMetadata({
          'ss_base_model_version': 'z-image-turbo',
        }),
        ModelFamily.zImage,
      );
      expect(
        ImageModelFamily.detectFromMetadata({
          'modelspec.architecture': 'flux-kontext',
        }),
        ModelFamily.kontext,
      );

      const stranger = 'grandmas_recipe_lora_f16.ckpt';
      expect(ImageModelFamily.detectFromName(stranger), ModelFamily.unknown);
      final option = ImageModelFamily.classifyLora(stranger);
      final compat = ImageModelFamily.compatibility(
        option.family,
        ModelFamily.sdxl,
        metadataBacked: option.familyFromMetadata,
      );
      expect(compat, LoraCompat.unknown);
      expect(ImageModelFamily.shownInPicker(compat), isTrue);
    });
  });
}

class _CatalogServer {
  _CatalogServer._(this._server);
  final HttpServer _server;
  int hits = 0;
  int status = 200;
  String body = '{}';

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  static Future<_CatalogServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _CatalogServer._(server);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    hits++;
    req.response.statusCode = status;
    if (status == 200) {
      req.response.headers.contentType = ContentType.json;
      req.response.write(body);
    }
    await req.response.close();
  }
}

class _Store extends ChangeNotifier implements StorageService {
  _Store(String rootPathValue)
    : rootPath = rootPathValue,
      charactersDir = Directory(p.join(rootPathValue, 'Characters'));

  @override
  final String? rootPath;

  @override
  final Directory charactersDir;

  @override
  final ImageGenSettings imageGenSettings = ImageGenSettings();

  @override
  final BackendSettings backendSettings = BackendSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
