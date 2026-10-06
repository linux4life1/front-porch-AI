// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A KoboldCpp on loopback for the speed test, and the app's own pieces wired
// to it the way the app wires them: real storage, the real KoboldCpp service
// (its process left out, see ProcesslessKobold), the real LLMProvider with
// its swap hosts, its staging and its speed test.
//
// The engine copies what the test depends on from KoboldCpp 1.122.1: a
// `reload_config` is answered at once and acted on half a second later by
// a new model process that reads the staged file by name; a timing prompt
// (`/api/v1/generate`) is read and written, and the speed line KoboldCpp
// prints after it ("Processed:N in Xs ..., Generated:N/N in Ys") is printed
// through the service's own output reader. The speeds follow the config the
// engine really loaded, from [speedsOf]: a try that loaded the wrong config
// is timed as that config.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';

import 'loopback_kobold.dart' show ProcesslessKobold;

/// Prompt read and reply written per second for a loaded config.
typedef SpeedsOf =
    ({double read, double write}) Function(Map<String, dynamic> loaded);

class SpeedEngine {
  SpeedEngine._(this._server, this.adminDir, this.speedsOf);

  static Future<SpeedEngine> start(String adminDir, SpeedsOf speedsOf) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return SpeedEngine._(server, adminDir, speedsOf).._serve();
  }

  final HttpServer _server;
  final String adminDir;
  final SpeedsOf speedsOf;
  String get baseUrl => 'http://127.0.0.1:${_server.port}';
  Future<void> close() => _server.close(force: true);

  /// What the engine prints, as KoboldCpp's console would hand it over.
  void Function(String output)? printed;

  /// Called as a timing prompt is read, before its answer: a test can hold
  /// it there.
  Future<void> Function(int timing)? beforeTiming;

  /// Staged files it was asked to reload, in order.
  final reloads = <String>[];

  /// The config it runs now, as read from the staged file.
  Map<String, dynamic> loaded = {};
  int timings = 0;
  DateTime _started = DateTime.now();

  String get _model =>
      'koboldcpp/${p.basenameWithoutExtension(loaded['model_param']?.toString() ?? 'none')}';

  void _serve() => _server.listen((r) async {
    final body = await utf8.decodeStream(r);
    final Object? answer = switch (r.uri.path) {
      '/api/admin/reload_config' => _reload(body),
      '/api/extra/perf' => {
        'uptime': DateTime.now().difference(_started).inMilliseconds / 1000,
        'idle': 1,
        'queue': 0,
      },
      '/api/v1/model' => {'result': _model},
      '/api/extra/true_max_context_length' => {
        'value': loaded['contextsize'] ?? 16384,
      },
      '/api/extra/version' => {'result': 'KoboldCpp', 'version': '1.122.1'},
      '/v1/chat/completions' => {
        'choices': [
          {
            'message': {'role': 'assistant', 'content': 'Ready.'},
            'finish_reason': 'length',
          },
        ],
        'usage': {'completion_tokens': 2},
      },
      '/api/v1/generate' => await _generate(body),
      _ => null,
    };
    r.response
      ..statusCode = answer == null ? 404 : 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(answer ?? {'error': 'not found'}));
    await r.response.close();
  });

  Map<String, dynamic> _reload(String body) {
    final name = (jsonDecode(body) as Map)['filename'] as String;
    reloads.add(name);
    Timer(const Duration(milliseconds: 500), () {
      _started = DateTime.now();
      loaded =
          (jsonDecode(File(p.join(adminDir, name)).readAsStringSync()) as Map)
              .cast<String, dynamic>();
    });
    return {'success': true};
  }

  Future<Map<String, dynamic>> _generate(String body) async {
    final json = jsonDecode(body) as Map;
    final words = json['prompt'].toString().trim().split(RegExp(r'\s+'));
    final wrote = (json['max_length'] as num).toInt();
    final n = ++timings;
    await beforeTiming?.call(n);
    final s = speedsOf(loaded);
    String secs(double v) => v.toStringAsFixed(2);
    printed?.call(
      '\n[10:49:15] CtxLimit:${words.length + wrote}/16384, Init:0.01s, '
      'Processed:${words.length} in ${secs(words.length / s.read)}s '
      '(${s.read.toStringAsFixed(2)}T/s), '
      'Generated:$wrote/$wrote in ${secs(wrote / s.write)}s '
      '(${s.write.toStringAsFixed(2)}T/s), Total:9.99s',
    );
    return {
      'results': [
        {'text': 'And then the rain came.'},
      ],
    };
  }
}

class _EngineFile extends BackendManager {
  _EngineFile(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

/// The app's pieces on a [SpeedEngine], files under [root]: an NVIDIA card,
/// KoboldCpp 1.122.1, and Qwen3 14B (a real header grown to its real size)
/// running in auto mode, chat's own config loaded.
class SpeedTestRig {
  SpeedTestRig._(this.root, this.storage, this.engine, this.kobold, this.llm);

  static const card = 'NVIDIA GeForce RTX 4090';

  static Future<SpeedTestRig> start(Directory root, SpeedsOf speedsOf) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null,
        );
    SharedPreferences.setMockInitialValues({
      'character_evolution_enabled': false,
    });
    final storage = StorageService();
    await storage.initialized;
    final b = storage.backendSettings;
    await b.setBackendType('kobold');
    await storage.binDir.create(recursive: true);
    final adminDir = koboldAdminDirFor(storage);
    await Directory(adminDir).create(recursive: true);
    final exe = File(p.join(storage.binDir.path, 'koboldcpp'))
      ..writeAsBytesSync(List.filled(64, 1));
    await KoboldBinaryVersion.write(
      storage.binDir.path,
      version: '1.122.1',
      size: 64,
    );
    await b.setLastUsedModelPath(await _model(root, 'Qwen3-14B'));
    final engine = await SpeedEngine.start(adminDir, speedsOf);
    final kobold = ProcesslessKobold(storage)
      ..setBaseUrl(engine.baseUrl)
      ..hardwareInfo = (() => HardwareInfo(
        gpuName: card,
        vramMb: 24564,
        ramMb: 65536,
        vendor: 'Nvidia',
        hasCuda: true,
      ))
      ..freeBeforeLaunch = (graphics: 23000, system: 60000);
    engine.printed = kobold.debugEngineSaid;
    final llm = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _EngineFile(storage, exe.path),
    );
    kobold.debugMarkProcessRunning();
    await kobold.debugMarkModelReady();
    // The engine runs chat's own config, as after a launch.
    await llm.reloadChatKobold();
    engine.reloads.clear();
    return SpeedTestRig._(root, storage, engine, kobold, llm);
  }

  final Directory root;
  final StorageService storage;
  final SpeedEngine engine;
  final ProcesslessKobold kobold;
  final LLMProvider llm;

  KoboldSpeedTest get test => llm.koboldSpeedTest!;
  String get model => storage.backendSettings.lastUsedModelPath!;

  /// Waits until the test is over.
  Future<void> finished() async {
    final end = DateTime.now().add(const Duration(minutes: 2));
    while (test.running) {
      if (DateTime.now().isAfter(end)) fail('the speed test never ended');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<void> close() async {
    llm.dispose();
    await engine.close();
  }

  static Future<String> _model(Directory dir, String fixture) async {
    const fx = 'test/fixtures/gguf_headers';
    final side =
        jsonDecode(File('$fx/$fixture.json').readAsStringSync()) as Map;
    final file = File(p.join(dir.path, '$fixture.gguf'));
    final raf = await file.open(mode: FileMode.write);
    await raf.writeFrom(File('$fx/$fixture.gguf').readAsBytesSync());
    await raf.setPosition((side['fixture_file_bytes'] as int) - 1);
    await raf.writeByte(0);
    await raf.close();
    return file.path;
  }
}
