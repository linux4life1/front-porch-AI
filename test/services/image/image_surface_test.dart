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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/image_facade.dart';
import 'package:front_porch_ai/services/web/routes/backend_routes.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

class _RealHttpOverrides extends HttpOverrides {}

Future<T> _withRealHttp<T>(Future<T> Function() body) =>
    HttpOverrides.runWithHttpOverrides(body, _RealHttpOverrides());

void _mockPathProvider() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_surface_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('edit versus img2img follows the capability result', () {
    const editOnly = ImageSurfaceCapabilities(
      edit: true,
      img2img: false,
      lora: false,
      negativePrompt: false,
      checkpointSlot: false,
      workflowSlots: false,
      scheduler: false,
      editAllowlist: true,
      editPicker: true,
    );
    const blendOnly = ImageSurfaceCapabilities(
      edit: false,
      img2img: true,
      lora: true,
      negativePrompt: true,
      checkpointSlot: true,
      workflowSlots: false,
      scheduler: true,
      editAllowlist: false,
      editPicker: false,
    );
    final editControls = imageSurfaceControls(editOnly);
    final blendControls = imageSurfaceControls(blendOnly);
    expect(editControls.showEdit, isTrue);
    expect(editControls.showImg2img, isFalse);
    expect(blendControls.showEdit, isFalse);
    expect(blendControls.showImg2img, isTrue);
    expect(editControls.showLora, isFalse);
    expect(blendControls.showLora, isTrue);
    expect(imageSurfaceControls(editOnly).toJson(), editControls.toJson());

    final fn = File('lib/services/image/image_surface.dart')
        .readAsStringSync()
        .split('ImageSurfaceControls imageSurfaceControls')
        .last
        .split('ImageSurfaceCapabilities capabilitiesFor')
        .first;
    expect(fn.contains('ImageGenBackend'), isFalse);

    final a1111 = capabilitiesFor(
      backend: ImageGenBackend.a1111,
      reference: const ImageReferenceCapability(
        supportsEdit: false,
        editMaxImages: 0,
        supportsImg2img: true,
        editKind: EditModelKind.none,
      ),
    );
    expect(imageSurfaceControls(a1111).showEdit, isFalse);
    expect(imageSurfaceControls(a1111).showImg2img, isTrue);
    expect(imageSurfaceControls(a1111).showLora, isTrue);
  });

  test('a busy generate is already-generating on the web image route', () {
    return _withRealHttp(() async {
      _mockPathProvider();
      SharedPreferences.setMockInitialValues({});
      final server = await _HoldServer.start();
      final storage = StorageService();
      await storage.imageGenSettings.setImageGenBackend('a1111');
      await storage.imageGenSettings.setLocalImageGenUrl(server.baseUrl);
      final image = ImageGenService(storage);
      final facade = ImageFacade(image, storage);
      final db = AppDatabase.forTesting();
      final router = Router();
      WebBackendRoutes(
        WebServerDeps(storage: storage, db: db, auth: AuthService(db)),
        router,
        image: facade,
      );
      server.hold = Completer<void>();
      final started = Completer<void>();
      server.onTxt2Img = () {
        if (!started.isCompleted) started.complete();
      };
      final first = image.generateImage(prompt: 'hold');
      await started.future.timeout(const Duration(seconds: 5));
      final res = await router.call(
        shelf.Request(
          'POST',
          Uri.parse('http://localhost/api/image/generate'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'prompt': 'overlap'}),
        ),
      );
      final body = jsonDecode(await res.readAsString()) as Map<String, dynamic>;
      expect(res.statusCode, 502);
      expect(body['error'], kAlreadyGeneratingMessage);
      expect(image.statusMessage, kAlreadyGeneratingMessage);
      expect(facade.config()['statusMessage'], kAlreadyGeneratingMessage);
      expect(server.txt2imgCount, 1);
      server.hold!.complete();
      expect(await first, isNotNull);
      await server.close();
      await db.close();
    });
  });
}

class _HoldServer {
  _HoldServer._(this._server);
  final HttpServer _server;
  Completer<void>? hold;
  void Function()? onTxt2Img;
  int txt2imgCount = 0;

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  static Future<_HoldServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _HoldServer._(server);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final key = '${req.method} ${req.uri.path}';
    await req.drain<void>();
    if (key == 'POST /sdapi/v1/txt2img') {
      txt2imgCount++;
      onTxt2Img?.call();
      final hold = this.hold;
      if (hold != null) await hold.future;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({
          'images': [
            base64Encode(const <int>[1, 2, 3]),
          ],
        }),
      );
    } else if (key == 'GET /sdapi/v1/progress') {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'progress': 0}));
    } else {
      req.response.statusCode = HttpStatus.notFound;
    }
    await req.response.close();
  }
}
