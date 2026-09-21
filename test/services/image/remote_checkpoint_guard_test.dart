// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A leftover Comfy `.ckpt` in image_gen_edit_model must never reach Nano
// /images/edits (expression pack + Edit tab share generateImage).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/storage_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

Future<T> _withRealHttp<T>(Future<T> Function() body) =>
    HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides());

/// 1×1 PNG so Edit/pack can attach a reference without a fixture file.
final Uint8List _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('remoteEditSpec does not treat a Comfy ckpt as a Nano edit id', () {
    expect(remoteEditSpec('qwen_image_edit_2511_i8x.ckpt'), isNull);
    expect(remoteEditSpec('qwen-image-max-edit'), isNotNull);
    expect(remoteEditSpec('qwen-image-2.1/edit'), isNotNull);
  });

  test('packEditMode is false for a leftover remote ckpt', () async {
    final s = ImageGenSettings();
    await s.setImageGenBackend('remote');
    await s.setImageGenEditModel('qwen_image_edit_2511_i8x.ckpt');
    expect(ImageReferenceResolver.packEditMode(s), isFalse);
  });

  test(
    'generateImage refuses a leftover ckpt before HTTP and clears the edit pref',
    () async {
      final storage = _Store();
      await storage.imageGenSettings.setImageGenBackend('remote');
      await storage.imageGenSettings.setImageRemoteApiUrl(kNanoGptApiV1);
      await storage.imageGenSettings.setImageGenEditModel(
        'qwen_image_edit_2511_i8x.ckpt',
      );
      await storage.backendSettings.setRemoteApiKeyFor(
        kNanoGptApiV1,
        'sk-nano',
      );

      final svc = ImageGenService(storage);
      final bytes = await svc.generateImage(
        prompt: 'make them smile',
        referenceImage: _pixel,
        intent: StudioIntent.edit,
      );
      expect(bytes, isNull);
      expect(svc.statusMessage, kRemoteLocalCheckpointMessage);
      expect(storage.imageGenSettings.imageGenEditModel, isEmpty);
    },
  );

  test(
    'generateImage posts a valid Nano edit id to /images/edits',
    () => _withRealHttp(() async {
      final fake = await _EditServer.start();
      final storage = _Store();
      await storage.imageGenSettings.setImageGenBackend('remote');
      await storage.imageGenSettings.setImageRemoteApiUrl(fake.url);
      await storage.imageGenSettings.setImageGenEditModel(
        'qwen-image-max-edit',
      );
      await storage.backendSettings.setRemoteApiKeyFor(fake.url, 'sk-nano');

      final svc = ImageGenService(storage);
      final bytes = await svc.generateImage(
        prompt: 'make them smile',
        referenceImage: _pixel,
        intent: StudioIntent.edit,
      );
      expect(bytes, isNotNull);
      expect(fake.postedModels, ['qwen-image-max-edit']);
      expect(fake.editPaths, isNotEmpty);
      await fake.close();
    }),
  );
}

class _Store extends ChangeNotifier implements StorageService {
  _Store()
    : rootPath = '/does/not/matter',
      charactersDir = Directory(
        p.join('/does/not/matter', 'KoboldManager', 'Characters'),
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

class _EditServer {
  _EditServer._(this._server);

  final HttpServer _server;
  final postedModels = <String>[];
  final editPaths = <String>[];

  String get url => 'http://127.0.0.1:${_server.port}';

  static Future<_EditServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _EditServer._(server);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    if (req.uri.path.endsWith('/images/edits')) {
      editPaths.add(req.uri.path);
    }
    final body = jsonDecode(await utf8.decodeStream(req)) as Map;
    postedModels.add('${body['model']}');
    req.response.statusCode = 200;
    req.response.headers.contentType = ContentType.json;
    req.response.write(
      jsonEncode({
        'data': [
          {'b64_json': base64Encode(_pixel)},
        ],
      }),
    );
    await req.response.close();
  }
}
