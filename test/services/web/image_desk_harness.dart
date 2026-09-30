// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/image_facade.dart';
import 'package:front_porch_ai/services/web/routes/backend_routes.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

/// The web password the harness's account was set up with.
const String kDeskPassword = 'password123';

/// The node classes the bundled graphs use.
const List<String> kDeskComfyClasses = [
  'KSampler',
  'VAEDecode',
  'SaveImage',
  'EmptySD3LatentImage',
  'EmptyLatentImage',
  'CLIPTextEncode',
  'ModelSamplingAuraFlow',
  'ConditioningZeroOut',
  'LoadImage',
  'VAEEncode',
];

/// A real loopback ComfyUI. It lists these model files and every node class
/// in [kDeskComfyClasses], answers an upload with [stored], and keeps the
/// graph a generate posts to `/prompt` (then fails it, so nothing waits).
class DeskComfy {
  DeskComfy._(this.server);

  final HttpServer server;
  int uploads = 0;
  final List<int> uploaded = [];
  Map<String, dynamic>? posted;

  /// Every path asked of it, with its query, in order.
  final List<String> requests = [];

  static const String stored = 'stored_by_comfy_7.png';

  /// [saved] are the workflows in its Desktop `workflows` folder, by file
  /// name (`my_flow.json`) with the JSON text of each.
  static Future<DeskComfy> start({
    List<String> unet = const [],
    List<String> clip = const [],
    List<String> vae = const [],
    List<String> checkpoints = const [],
    List<String> loras = const [],
    Map<String, String> saved = const {},
  }) async {
    Map<String, dynamic> loader(String input, List<String> files) => {
      'input': {
        'required': {
          input: [files],
        },
      },
    };
    final info = <String, dynamic>{
      for (final c in kDeskComfyClasses) c: <String, dynamic>{},
      'UNETLoader': loader('unet_name', unet),
      'CLIPLoader': loader('clip_name', clip),
      'VAELoader': loader('vae_name', vae),
      'CheckpointLoaderSimple': loader('ckpt_name', checkpoints),
      'LoraLoader': loader('lora_name', loras),
    };
    HttpOverrides.global = null;
    final comfy = DeskComfy._(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    comfy.server.listen((request) async {
      final path = Uri.decodeComponent(request.uri.path);
      comfy.requests.add(
        request.uri.hasQuery ? '$path?${request.uri.query}' : path,
      );
      request.response.headers.contentType = ContentType.json;
      if (path == '/object_info') {
        request.response.write(jsonEncode(info));
      } else if (request.method == 'GET' && path == '/userdata') {
        request.response.write(
          jsonEncode([for (final name in saved.keys) 'workflows/$name']),
        );
      } else if (request.method == 'GET' &&
          path.startsWith('/userdata/workflows/') &&
          saved.containsKey(path.split('/').last)) {
        request.response.write(saved[path.split('/').last]);
      } else if (request.method == 'POST' && path == '/upload/image') {
        comfy.uploads++;
        await for (final chunk in request) {
          comfy.uploaded.addAll(chunk);
        }
        request.response.write(jsonEncode({'name': stored, 'subfolder': ''}));
      } else if (request.method == 'POST' && path == '/prompt') {
        final body = jsonDecode(await utf8.decodeStream(request)) as Map;
        comfy.posted = (body['prompt'] as Map).cast<String, dynamic>();
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('stop');
      } else {
        await request.drain<void>();
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() => comfy.server.close(force: true));
    return comfy;
  }

  String get url => 'http://127.0.0.1:${server.port}';
}

/// The phone routes over sandboxed storage and a real account, called the
/// way the web app calls them.
class DeskHarness {
  DeskHarness._();

  late final StorageService storage;
  late final AppDatabase db;
  late final AuthService auth;
  late final Router router;
  late final ImageGenService image;
  late final ImageFacade facade;

  /// With [realPrefs] the settings are kept in (mock) shared preferences, as
  /// in the app, for what is stored there and not in the sandbox.
  static Future<DeskHarness> boot({
    DeskComfy? comfy,
    bool realPrefs = false,
  }) async {
    final h = DeskHarness._();
    final dir = Directory.systemTemp.createTempSync('image-desk');
    addTearDown(() => dir.deleteSync(recursive: true));
    if (realPrefs) {
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => call.method == 'getApplicationDocumentsDirectory'
                ? dir.path
                : null,
          );
      h.storage = StorageService();
      await h.storage.initialized;
    } else {
      h.storage = StorageService.sandbox(dir.path);
    }
    h.db = AppDatabase.forTesting();
    addTearDown(h.db.close);
    h.auth = AuthService(h.db);
    expect(
      await h.auth.setupAccount(
        'admin',
        kDeskPassword,
        isDirectLoopbackClient: true,
      ),
      SetupStatus.success,
    );
    if (comfy != null) {
      await h.settings.setImageGenBackend('comfyui');
      await h.settings.setComfyUiUrl(comfy.url);
    }
    h.image = ImageGenService(h.storage);
    h.facade = ImageFacade(h.image, h.storage);
    h.router = Router();
    WebBackendRoutes(
      WebServerDeps(storage: h.storage, db: h.db, auth: h.auth),
      h.router,
      image: h.facade,
    );
    return h;
  }

  ImageGenSettings get settings => storage.imageGenSettings;

  Map<String, String> choices({bool edit = false}) => edit
      ? storage.imageGenSettings.comfyEditModelChoices
      : storage.imageGenSettings.comfyCreateModelChoices;

  Future<(int, Map<String, dynamic>)> call(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final res = await router.call(
      shelf.Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {'content-type': 'application/json'},
        body: body == null ? null : jsonEncode(body),
      ),
    );
    final text = await res.readAsString();
    return (
      res.statusCode,
      text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>,
    );
  }
}
