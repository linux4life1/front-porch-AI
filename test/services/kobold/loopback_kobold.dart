// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A KoboldCpp on loopback: a real HTTP server that answers the way the
// engine does for the calls the app's swaps make, so the app's own swap code
// runs against it end to end.
//
// What it copies from KoboldCpp 1.122.1: `reload_config` is answered at once
// and acted on half a second later by a NEW model process (its uptime starts
// again); a staged config it cannot load sends it back to the config it was
// started with, and says nothing; `unload_model` leaves it with no model
// ("inactive") and a completion then fails.
//
// [KoboldRig] wires the app's own pieces to it the way the app does: real
// storage, the real KoboldCpp service (its process left out) and the real
// LLMProvider with its swap hosts.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';

class LoopbackKobold {
  LoopbackKobold._(this._server, this.adminDir);

  static Future<LoopbackKobold> start(String adminDir) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return LoopbackKobold._(server, adminDir).._serve();
  }

  final HttpServer _server;

  /// Where the app stages configs: what a reload by name reads.
  final String adminDir;

  /// Staged configs it cannot load.
  final failing = <String>{};

  /// What it was asked to reload, in order.
  final reloads = <String>[];

  /// What it reports having loaded: `koboldcpp/<model>`, or `inactive`.
  String model = 'koboldcpp/startup-model';

  /// The model of the config it was started with.
  String startupModel = 'koboldcpp/startup-model';
  int context = 16384;

  /// What it runs for a config with no contextsize.
  int defaultContext = 16384;
  DateTime _started = DateTime.now();

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  Future<void> close() => _server.close(force: true);

  void _serve() => _server.listen((r) async {
    final inactive = model == 'inactive';
    final body = switch (r.uri.path) {
      '/api/admin/reload_config' => await _reload(r),
      '/api/extra/perf' => {
        'uptime': DateTime.now().difference(_started).inMilliseconds / 1000,
        'idle': 1,
        'queue': 0,
      },
      '/api/v1/model' => {'result': model},
      '/api/extra/true_max_context_length' => {'value': context},
      '/api/extra/version' => {'result': 'KoboldCpp', 'version': '1.122.1'},
      '/v1/chat/completions' =>
        inactive
            ? null
            : {
                'choices': [
                  {
                    'message': {'role': 'assistant', 'content': 'Ready.'},
                    'finish_reason': 'length',
                  },
                ],
                'usage': {'completion_tokens': 2},
              },
      _ => null,
    };
    r.response
      ..statusCode = body == null ? 404 : 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body ?? {'error': 'not found'}));
    await r.response.close();
  });

  Future<Map<String, dynamic>> _reload(HttpRequest r) async {
    final name =
        (jsonDecode(await utf8.decodeStream(r)) as Map)['filename'] as String;
    reloads.add(name);
    Timer(const Duration(milliseconds: 500), () => _act(name));
    return {'success': true};
  }

  void _act(String name) {
    _started = DateTime.now();
    if (name == 'unload_model') {
      model = 'inactive';
    } else if (name == 'initial_model' || failing.contains(name)) {
      model = startupModel;
      context = defaultContext;
    } else {
      final config =
          jsonDecode(File(p.join(adminDir, name)).readAsStringSync()) as Map;
      final file = config['model_param']?.toString() ?? '';
      model = 'koboldcpp/${p.basenameWithoutExtension(file)}';
      context = (config['contextsize'] as num?)?.toInt() ?? defaultContext;
    }
  }
}

class _EngineFile extends BackendManager {
  _EngineFile(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

/// The app's KoboldCpp service with the process left out: it runs from the
/// first, and a fresh start (what chat falls back to when a reload fails)
/// is counted, not run.
class ProcesslessKobold extends KoboldService {
  ProcesslessKobold(super.storage);

  bool running = true;
  int launches = 0;

  @override
  Future<void> reconnectIfAlive() async {}

  @override
  bool get isRunning => running;

  @override
  bool get isProcessRunning => running;

  @override
  Future<void> stopKobold() async => running = false;

  @override
  Future<KoboldLaunchResult> launch(
    String executablePath, {
    String? pickedModel,
    int port = 5001,
  }) async {
    launches++;
    running = true;
    return const KoboldLaunchResult.started();
  }
}

/// The app's pieces on a [LoopbackKobold], with files under [root].
class KoboldRig {
  KoboldRig._(this.root, this.storage, this.engine, this.kobold, this.provider);

  static Future<KoboldRig> start(Directory root) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null;
        });
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await storage.initialized;
    await storage.backendSettings.setBackendType('kobold');
    await storage.binDir.create(recursive: true);
    final adminDir = koboldAdminDirFor(storage);
    await Directory(adminDir).create(recursive: true);
    final engine = await LoopbackKobold.start(adminDir);
    final kobold = ProcesslessKobold(storage)..setBaseUrl(engine.baseUrl);
    final provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _EngineFile(storage, p.join(storage.binDir.path, 'koboldcpp')),
    );
    return KoboldRig._(root, storage, engine, kobold, provider);
  }

  final Directory root;
  final StorageService storage;
  final LoopbackKobold engine;
  final ProcesslessKobold kobold;
  final LLMProvider provider;

  /// A file with the GGUF magic, enough for the app's model check.
  String gguf(String name) => (File(
    p.join(root.path, name),
  )..writeAsBytesSync('GGUF'.codeUnits + List.filled(32, 0))).path;

  /// A preset in the engine folder, as the user would have saved it.
  File preset(String name, Map<String, dynamic> config) =>
      File(p.join(storage.binDir.path, name))
        ..writeAsStringSync(jsonEncode(config));

  Future<void> close() async {
    provider.dispose();
    await engine.close();
  }
}
