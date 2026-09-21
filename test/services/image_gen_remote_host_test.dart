// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chip selection must send fetch/generate at the Studio-scoped host + vault
// key, not chat's mouth URL.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/storage_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

Future<T> _withRealHttp<T>(Future<T> Function() body) =>
    HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fetchImageModels uses the Studio host/key, not chat\'s mouth',
    () => _withRealHttp(() async {
      final fake = await _OrCatalogServer.start();
      final storage = _Store('/does/not/matter');
      await storage.backendSettings.setRemoteApiUrl(kNanoGptApiV1);
      await storage.backendSettings.setRemoteApiKey('sk-nano-chat');
      await storage.backendSettings.setRemoteApiKeyFor(
        fake.openRouterUrl,
        'sk-or-studio',
      );
      await storage.imageGenSettings.setImageRemoteApiUrl(fake.openRouterUrl);

      final models = await ImageGenService(storage).fetchImageModels();
      expect(fake.authHeaders, ['Bearer sk-or-studio']);
      expect(models.single.id, 'or-img');
      expect(storage.backendSettings.remoteApiUrl, kNanoGptApiV1);

      await fake.close();
    }),
  );

  test(
    'Nano Studio chip lists the curated catalog and does not call chat\'s OpenRouter',
    () => _withRealHttp(() async {
      final fake = await _OrCatalogServer.start();
      final storage = _Store('/does/not/matter');
      await storage.backendSettings.setRemoteApiUrl(fake.openRouterUrl);
      await storage.backendSettings.setRemoteApiKey('sk-or-chat');
      await storage.backendSettings.setRemoteApiKeyFor(
        kNanoGptApiV1,
        'sk-nano',
      );
      await applyImageRemoteHost(
        image: storage.imageGenSettings,
        url: kNanoGptApiV1,
        chatRemoteApiUrl: storage.backendSettings.remoteApiUrl,
        editScoped: false,
      );

      final models = await ImageGenService(storage).fetchImageModels();
      expect(models, hasLength(237));
      expect(models.any((m) => !m.isPaid), isTrue);
      expect(fake.authHeaders, isEmpty);
      expect(storage.backendSettings.remoteApiUrl, fake.openRouterUrl);

      await fake.close();
    }),
  );

  test(
    'generate refuses when the Studio host has no key even if chat does',
    () async {
      final storage = _Store('/does/not/matter');
      await storage.backendSettings.setRemoteApiUrl(kNanoGptApiV1);
      await storage.backendSettings.setRemoteApiKey('sk-nano-chat');
      await storage.imageGenSettings.setImageRemoteApiUrl(kOpenRouterApiV1);
      await storage.imageGenSettings.setImageGenModel('flux');

      final svc = ImageGenService(storage);
      expect(svc.isConfigured, isFalse);
      final bytes = await svc.generateImage(prompt: 'a porch');
      expect(bytes, isNull);
      expect(svc.statusMessage, 'No API key configured.');
      expect(storage.backendSettings.remoteApiUrl, kNanoGptApiV1);
    },
  );
}

class _Store extends ChangeNotifier implements StorageService {
  _Store(String rootPathValue)
    : rootPath = rootPathValue,
      charactersDir = Directory(
        p.join(rootPathValue, 'KoboldManager', 'Characters'),
      );

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

/// Loopback OpenRouter-shaped `/models` so fetch can prove which URL/key fired.
class _OrCatalogServer {
  _OrCatalogServer._(this._server);

  final HttpServer _server;
  final List<String> authHeaders = [];

  String get openRouterUrl => 'http://127.0.0.1:${_server.port}/openrouter.ai';

  static Future<_OrCatalogServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _OrCatalogServer._(server);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    authHeaders.add(req.headers.value(HttpHeaders.authorizationHeader) ?? '');
    req.response.statusCode = 200;
    req.response.headers.contentType = ContentType.json;
    req.response.write(
      jsonEncode({
        'data': [
          {'id': 'or-img', 'name': 'OR Img', 'pricing': null},
        ],
      }),
    );
    await req.response.close();
  }
}
