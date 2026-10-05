// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// "Free the graphics memory when KoboldCpp sits idle": after the idle time
// chosen in Settings, the KoboldCpp this app started unloads its model with
// the admin reload to `unload_model` (the engine stays up), and the next
// request of any kind loads the remembered config back by name before it is
// sent. Off by default.
//
// The engine here is a real HTTP server on loopback with KoboldCpp 1.122.1's
// reload semantics: a reload is answered at once and acted on half a second
// later by a new model process; with nothing loaded the model is `inactive`
// and a completion comes back empty. The idle time is shortened through the
// service's test hook; Settings still turns the feature on and off.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/system_role_probe.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:front_porch_ai/services/web/facade/backend_facade.dart';
import 'package:front_porch_ai/ui/character_creator/character_creator.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/settings/tabs/backend/kobold_status_card.dart';
import 'package:front_porch_ai/ui/waifu/waifu_session_scope.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';

import '../../golden/support/fakes_services.dart';

class _Engine {
  _Engine._(this._server, this.adminDir, this.model);

  static Future<_Engine> start(String adminDir, String model) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _Engine._(server, adminDir, model).._serve();
  }

  final HttpServer _server;
  final String adminDir;

  /// What reached the engine, in order: `reload:<file>`, `generate` (a
  /// streamed reply), `tools` (a tool call) and `probe` (anything else).
  final events = <String>[];
  final reloads = <String>[];
  final reloadedAt = <DateTime>[];
  String model;
  DateTime _started = DateTime.now();

  /// When set, a reloaded config does not load and the engine goes back to
  /// this model, as KoboldCpp's fault recovery does.
  String? fallBack;

  /// When set, a reload is acted on only once this completes: a load that
  /// is still under way.
  Completer<void>? hold;

  /// Streamed replies asked for so far; with [replyHold] set, each waits
  /// for it before it is answered.
  int repliesAsked = 0;
  Completer<void>? replyHold;

  String get baseUrl => 'http://127.0.0.1:${_server.port}';
  bool get _loaded => model != 'inactive';

  Future<void> close() => _server.close(force: true);

  void _serve() => _server.listen((r) async {
    final raw = await utf8.decodeStream(r);
    final body = raw.isEmpty ? const {} : jsonDecode(raw) as Map;
    r.response.headers.contentType = ContentType.json;
    switch (r.uri.path) {
      case '/api/admin/reload_config':
        _reload(body['filename'] as String);
        r.response.write(jsonEncode({'success': true}));
      case '/api/extra/perf':
        final up = DateTime.now().difference(_started).inMilliseconds / 1000;
        r.response.write(jsonEncode({'uptime': up, 'idle': 1, 'queue': 0}));
      case '/api/v1/model':
        r.response.write(jsonEncode({'result': model}));
      case '/api/extra/version':
        r.response.write(jsonEncode({'result': 'KoboldCpp'}));
      case '/api/extra/tokencount':
        // With no model loaded there is no tokenizer to count with.
        events.add('tokencount');
        final words = '${body['prompt']}'.split(RegExp(r'\s+')).length;
        r.response.write(jsonEncode({'value': _loaded ? words : 0}));
      case '/v1/chat/completions':
        if (body['tools'] == null && body['stream'] == true) {
          repliesAsked++;
          await replyHold?.future;
        }
        _complete(r.response, body);
      default:
        r.response
          ..statusCode = 404
          ..write(jsonEncode({'error': 'not found'}));
    }
    await r.response.close();
  });

  void _reload(String name) {
    events.add('reload:$name');
    reloads.add(name);
    reloadedAt.add(DateTime.now());
    Timer(const Duration(milliseconds: 500), () async {
      await hold?.future;
      _started = DateTime.now();
      if (name == 'unload_model') {
        model = 'inactive';
        return;
      }
      final config =
          jsonDecode(File(p.join(adminDir, name)).readAsStringSync()) as Map;
      model =
          fallBack ??
          'koboldcpp/${p.basenameWithoutExtension('${config['model_param']}')}';
    });
  }

  /// With a model loaded it answers "Hello."; with none, an empty reply with
  /// `finish_reason: error`, as KoboldCpp does.
  void _complete(HttpResponse out, Map body) {
    final messages = (body['messages'] as List?) ?? const [];
    final chars = messages.fold<int>(
      0,
      (n, m) => n + '${(m as Map)['content']}'.length,
    );
    final text = _loaded ? 'Hello.' : '';
    final finish = _loaded ? 'stop' : 'error';
    if (body['tools'] == null && body['stream'] == true) {
      events.add('generate');
      out.headers.contentType = ContentType('text', 'event-stream');
      out.write(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': text},
              'finish_reason': finish,
            },
          ],
        })}\n\n'
        'data: [DONE]\n\n',
      );
      return;
    }
    events.add(body['tools'] == null ? 'probe' : 'tools');
    out.write(
      jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': text},
            'finish_reason': finish,
          },
        ],
        'usage': {
          'prompt_tokens': chars ~/ 4,
          'completion_tokens': _loaded ? 2 : 0,
        },
      }),
    );
  }
}

/// The service without its start-up probe of port 5001. Its stop is left
/// out: the process it holds is [_Launched], not a real one.
class _Kobold extends KoboldService {
  _Kobold(super.storage)
    : super(systemRoleProbe: SystemRoleProbe(retryBackoff: Duration.zero));

  @override
  Future<void> reconnectIfAlive() async {}

  @override
  Future<void> stopKobold() async {}

  /// Stands for the engine's process having ended (or still running).
  bool? running;

  @override
  bool get isRunning => running ?? super.isRunning;
}

/// Stands for the KoboldCpp process this app launched. The service keeps it
/// as the sign that the engine is the app's own; nothing here is ever run
/// or killed.
class _Launched implements Process {
  @override
  int get pid => -1;

  @override
  Future<int> get exitCode => Completer<int>().future;

  @override
  IOSink get stdin => throw UnsupportedError('not a real process');

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => false;
}

/// Model files are read for real.
class _Models extends FakeModelManager {
  @override
  Future<GGUFModelInfo?> getModelArchitectureInfo(String filePath) =>
      GGUFParser.getModelArchitectureInfo(filePath);
}

/// The machine, with the free memory read before the engine started.
class _Hardware extends FakeHardwareService {
  FreeMemoryMb? _free = (graphics: 10240, system: 24576);

  @override
  FreeMemoryMb? get freeBeforeEngine => _free;

  @override
  set freeBeforeEngine(FreeMemoryMb? value) => _free = value;
}

const _unloadedWords =
    'The model was unloaded after 30 idle minutes to free graphics memory. '
    'It loads again with your next message.';

void main() {
  late Directory root;
  late StorageService storage;
  late _Engine engine;
  late _Kobold kobold;
  late String chatModel;
  late String stagedChat;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
    root = await Directory.systemTemp.createTemp('fpai idle unload');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null;
        });
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.initialized;
    await storage.backendSettings.setBackendType('kobold');

    chatModel = p.join(root.path, 'chat-model.gguf');
    File(chatModel).writeAsBytesSync('GGUF'.codeUnits + List.filled(32, 0));
    // What a launch stages and loads: chat's config in the admin folder.
    final adminDir = koboldAdminDirFor(storage);
    stagedChat = jsonEncode({'model_param': chatModel, 'contextsize': 8192});
    await stageKoboldConfig(adminDir, kStagedChatConfig, stagedChat);
    await stageKoboldConfig(
      adminDir,
      'fpai-worker.kcpps',
      jsonEncode({'model_param': p.join(root.path, 'helper.gguf')}),
    );

    engine = await _Engine.start(adminDir, 'koboldcpp/chat-model');
    kobold = _Kobold(storage)..setBaseUrl(engine.baseUrl);
  });

  tearDown(() async {
    kobold.dispose();
    await engine.close();
    await root.delete(recursive: true);
  });

  /// The engine up with chat's model loaded and ready, as after a launch.
  /// [startedByApp] false: an engine the app found running, not its own.
  Future<void> ready({
    required Duration idleAfter,
    bool startedByApp = true,
  }) async {
    kobold.debugIdleUnloadAfter = idleAfter;
    if (startedByApp) {
      kobold.debugStartIdleClock(startedByApp: _Launched());
    } else {
      kobold
        ..debugMarkProcessRunning()
        ..debugStartIdleClock();
    }
    kobold.noteAdminLoadedPair(modelPath: chatModel, kcppsPath: '');
    kobold.noteResident(stagedChat);
    await kobold.debugMarkModelReady();
    engine.events.clear();
  }

  /// Waits for [done]; the ceiling only matters on a loaded machine (the
  /// Linux CI image runs emulated), since it returns as soon as [done] holds.
  Future<void> until(
    bool Function() done, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final end = DateTime.now().add(timeout);
    while (!done()) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<String> reply() =>
      kobold.generateStream(GenerationParams(prompt: 'Are you there?')).join();

  /// The idle unload has happened and the engine has acted on it.
  Future<void> unloaded() async {
    await until(
      () => kobold.phase == KoboldPhase.unloaded && engine.model == 'inactive',
    );
  }

  test('off by default: an idle engine is never unloaded', () async {
    expect(storage.backendSettings.idleUnloadMinutes, 0);
    await ready(idleAfter: const Duration(milliseconds: 300));

    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(engine.reloads, isEmpty);
    expect(kobold.modelReady, isTrue);
    expect(kobold.phase, KoboldPhase.ready);
  });

  test('after the idle time the model is unloaded once, the engine stays '
      'up, and the status line says so in plain words', () async {
    await storage.backendSettings.setIdleUnloadMinutes(30);
    await ready(idleAfter: const Duration(milliseconds: 400));

    await unloaded();
    // A few more turns of the clock: nothing more is sent.
    await Future<void>.delayed(const Duration(milliseconds: 1000));

    expect(engine.reloads, ['unload_model']);
    expect(kobold.modelReady, isFalse);
    expect(kobold.isResident(stagedChat), isFalse);
    expect(kobold.modelLoadingStatus, _unloadedWords);
    expect(kobold.isProcessRunning, isTrue);
    expect(
      kobold.isReady,
      isTrue,
      reason: 'it serves the next request, loading the model first',
    );
  });

  test('the next reply loads the remembered config back by its name first, '
      'then is answered', () async {
    await storage.backendSettings.setIdleUnloadMinutes(30);
    await ready(idleAfter: const Duration(milliseconds: 400));
    await unloaded();
    engine.events.clear();

    expect(await reply(), 'Hello.');

    expect(engine.reloads, ['unload_model', kStagedChatConfig]);
    final load = engine.events.indexOf('reload:$kStagedChatConfig');
    expect(load, isNonNegative);
    expect(load, lessThan(engine.events.indexOf('generate')));
    expect(kobold.modelReady, isTrue);
    expect(kobold.phase, KoboldPhase.ready);
    expect(kobold.isResident(stagedChat), isTrue);
    expect(kobold.loadedModelPath, chatModel);
    expect(kobold.modelLoadingStatus, isEmpty);
  });

  test('a config that does not load back: nothing is ready, the record '
      'stays, and requests in the pause after are refused at once', () async {
    await storage.backendSettings.setIdleUnloadMinutes(30);
    await ready(idleAfter: const Duration(milliseconds: 400));
    await unloaded();
    engine.fallBack = 'koboldcpp/startup-model';
    final heard = <KoboldPhase>[];
    kobold.addListener(() => heard.add(kobold.phase));

    await expectLater(reply(), throwsA(isA<LlmToolTransportException>()));
    expect(
      heard.last,
      KoboldPhase.unloaded,
      reason: 'the status settles on unloaded, not on loading',
    );
    expect(kobold.modelReady, isFalse);
    expect(kobold.phase, KoboldPhase.unloaded, reason: 'the record stays');
    final sent = engine.reloads.length;
    await expectLater(reply(), throwsA(isA<LlmToolTransportException>()));
    expect(engine.reloads.length, sent, reason: 'nothing is sent in the pause');
  });

  test(
    'a model already back on the engine is checked, not loaded again',
    () async {
      await storage.backendSettings.setIdleUnloadMinutes(30);
      await ready(idleAfter: const Duration(milliseconds: 400));
      await unloaded();
      // Once the unload is done with the engine, something else loads the
      // model back (a long load that finished, say).
      await until(() => !kobold.adminSwapLock.busy);
      engine.model = 'koboldcpp/${p.basenameWithoutExtension(chatModel)}';

      expect(await reply(), 'Hello.');
      expect(engine.reloads, ['unload_model']);
      expect(kobold.phase, KoboldPhase.ready);
      expect(kobold.modelReady, isTrue);
    },
  );

  test('a tool call after the unload loads the model back first too', () async {
    await storage.backendSettings.setIdleUnloadMinutes(30);
    await ready(idleAfter: const Duration(milliseconds: 400));
    await unloaded();
    engine.events.clear();

    final answer = await kobold.generateWithTools(
      GenerationParams(prompt: 'Rate this.'),
      [
        {
          'type': 'function',
          'function': {
            'name': 'rate',
            'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
          },
        },
      ],
    );

    expect(answer?.text, 'Hello.');
    final load = engine.events.indexOf('reload:$kStagedChatConfig');
    expect(load, isNonNegative);
    expect(load, lessThan(engine.events.indexOf('tools')));
  });

  test('a Waifu Coder turn, where OpenCode asks KoboldCpp itself, loads the '
      'model back first', () async {
    await storage.backendSettings.setIdleUnloadMinutes(30);
    await ready(idleAfter: const Duration(milliseconds: 400));
    await unloaded();
    final backend = BackendManager(storage);
    final provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      backend,
    );
    addTearDown(() {
      provider.dispose();
      backend.dispose();
    });
    final harness = waifuBindSessionHarness(
      session: WaifuSession(
        folderRoot: root.path,
        coworker: CharacterCard(name: 'Mira'),
      ),
      provider: provider,
    )!;

    await harness.send('Tidy the readme.');

    expect(engine.reloads, ['unload_model', kStagedChatConfig]);
    expect(kobold.modelReady, isTrue);
  });

  test('the helper model resident at the unload is the one loaded back, by '
      'its own name', () async {
    await storage.backendSettings.setIdleUnloadMinutes(10);
    await ready(idleAfter: const Duration(milliseconds: 400));
    // A swap put the helper model in, as a Realism check does.
    final helper = File(
      p.join(koboldAdminDirFor(storage), 'fpai-worker.kcpps'),
    ).readAsStringSync();
    final helperModel = p.join(root.path, 'helper.gguf');
    kobold.noteAdminLoadedPair(modelPath: helperModel, kcppsPath: '');
    kobold.noteResident(helper);
    await unloaded();

    expect(await reply(), 'Hello.');

    expect(engine.reloads, ['unload_model', 'fpai-worker.kcpps']);
    expect(kobold.isResident(helper), isTrue);
    expect(kobold.loadedModelPath, helperModel);
  });

  test('requests before the deadline keep the model loaded; the unload comes '
      'the idle time after the last one', () async {
    const idle = Duration(milliseconds: 1500);
    await storage.backendSettings.setIdleUnloadMinutes(10);
    await ready(idleAfter: idle);

    late DateTime last;
    final busyUntil = DateTime.now().add(const Duration(milliseconds: 3200));
    while (DateTime.now().isBefore(busyUntil)) {
      expect(await reply(), 'Hello.');
      last = DateTime.now();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(engine.reloads, isEmpty, reason: 'it was never idle that long');

    await unloaded();
    expect(engine.reloads, ['unload_model']);
    // Counted from the last request, not from the load (a little slack for
    // the moment between the request ending and its reply being read).
    expect(
      engine.reloadedAt.single.difference(last),
      greaterThanOrEqualTo(idle - const Duration(milliseconds: 100)),
    );
  });

  test('a KoboldCpp the app did not start is never unloaded', () async {
    await storage.backendSettings.setIdleUnloadMinutes(10);
    await ready(
      idleAfter: const Duration(milliseconds: 300),
      startedByApp: false,
    );

    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(engine.reloads, isEmpty);
    expect(kobold.modelReady, isTrue);
  });

  test('a token count after the unload loads the model back first and is '
      'counted by its tokenizer', () async {
    await storage.backendSettings.setIdleUnloadMinutes(30);
    await ready(idleAfter: const Duration(milliseconds: 400));
    await unloaded();
    engine.events.clear();

    expect(await kobold.countTokens('one two three four'), 4);

    final load = engine.events.indexOf('reload:$kStagedChatConfig');
    expect(load, isNonNegative);
    expect(load, lessThan(engine.events.indexOf('tokencount')));
    expect(kobold.phase, KoboldPhase.ready);
  });

  test('a KoboldCpp that stops while its model is unloaded says Stopped, '
      'not Unloaded', () async {
    await storage.backendSettings.setIdleUnloadMinutes(30);
    await ready(idleAfter: const Duration(milliseconds: 400));
    await unloaded();

    kobold.running = false;

    expect(kobold.phase, KoboldPhase.stopped);
  });

  test('the clock stops with the service', () async {
    await storage.backendSettings.setIdleUnloadMinutes(10);
    await ready(idleAfter: const Duration(milliseconds: 300));

    kobold.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(engine.reloads, isEmpty);
    kobold = _Kobold(storage); // for tearDown to dispose
  });

  test('only the offered choices are kept', () async {
    final b = storage.backendSettings;
    await b.setIdleUnloadMinutes(30);
    await b.setIdleUnloadMinutes(45);
    expect(b.idleUnloadMinutes, 30);
    expect(kKoboldIdleUnloadChoices, [0, 10, 30, 60]);
  });

  /// Every place that shows the local engine's state, at once, on the real
  /// service; and the web server's answer for the phone.
  Future<({LLMProvider provider, BackendFacade facade})> showStatus(
    WidgetTester tester,
  ) async {
    late LLMProvider provider;
    late BackendFacade facade;
    final creator = CreatorState();
    await tester.runAsync(() async {
      final backend = BackendManager(storage);
      provider = LLMProvider(
        kobold,
        OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
        storage,
        backend,
      );
      addTearDown(() {
        provider.dispose();
        backend.dispose();
        creator.dispose();
      });
      facade = BackendFacade(provider, storage, _Models(), _Hardware());
    });
    await tester.binding.setSurfaceSize(const Size(1000, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StorageService>.value(value: storage),
          ChangeNotifierProvider<KoboldService>.value(value: kobold),
          ChangeNotifierProvider<LLMProvider>.value(value: provider),
          ChangeNotifierProvider<OpenRouterService>.value(
            value: provider.openRouterService,
          ),
          ChangeNotifierProvider<HardwareService>.value(value: _Hardware()),
          ChangeNotifierProvider<ModelManager>.value(value: _Models()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                KoboldStatusCard(unified: false, reloadChat: () async {}),
                const SizedBox(height: 640, child: KoboldLogDialog()),
                SetupStep(state: creator),
              ],
            ),
          ),
        ),
      ),
    );
    return (provider: provider, facade: facade);
  }

  Finder on<T>(String text) =>
      find.descendant(of: find.byType(T), matching: find.text(text));

  Future<Object?> phone(WidgetTester tester, BackendFacade facade) async {
    final card = (await tester.runAsync(facade.localModel))!;
    return card['phase'];
  }

  void expectLoading() {
    expect(on<KoboldStatusCard>('Loading…'), findsOneWidget);
    expect(on<KoboldLogDialog>('Loading…'), findsOneWidget);
    expect(on<SetupStep>('Loading model...'), findsOneWidget);
    expect(find.text('Ready'), findsNothing);
    expect(find.textContaining('Unloaded'), findsNothing);
  }

  void expectReady() {
    for (final surface in [KoboldStatusCard, KoboldLogDialog, SetupStep]) {
      expect(
        find.descendant(of: find.byType(surface), matching: find.text('Ready')),
        findsOneWidget,
        reason: '$surface',
      );
    }
  }

  testWidgets('every status, and the phone, says Unloaded while the model is '
      'unloaded and Loading while it loads back; Ready as soon as it is', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await storage.backendSettings.setIdleUnloadMinutes(30);
      await ready(idleAfter: const Duration(milliseconds: 400));
      await unloaded();
    });
    final s = await showStatus(tester);
    // At each change, whether listeners were told a model is loaded.
    final heard = <KoboldPhase>[];
    void hear() => heard.add(kobold.phase);
    kobold.addListener(hear);
    addTearDown(() => kobold.removeListener(hear));

    expect(on<KoboldStatusCard>('Unloaded'), findsOneWidget);
    expect(on<KoboldLogDialog>('Unloaded while idle'), findsOneWidget);
    expect(on<SetupStep>('Unloaded while idle'), findsOneWidget);
    expect(find.text('Ready'), findsNothing);
    expect(await phone(tester, s.facade), 'unloaded');

    // The next reply loads it back; the engine is still loading it.
    late Future<String> answer;
    await tester.runAsync(() async {
      engine
        ..hold = Completer<void>()
        ..replyHold = Completer<void>();
      answer = reply();
      await until(() => engine.reloads.length == 2);
    });
    await tester.pump();
    expect(kobold.isReady, isTrue, reason: 'requests are still let through');
    expectLoading();
    expect(await phone(tester, s.facade), 'loading');

    // Loaded back; the reply is on its way to the engine.
    await tester.runAsync(() async {
      engine.hold!.complete();
      await until(() => engine.repliesAsked == 1);
    });
    expect(
      heard.last,
      KoboldPhase.ready,
      reason: 'listeners are told it is back',
    );
    await tester.pump();
    expectReady();
    expect(await phone(tester, s.facade), 'ready');

    await tester.runAsync(() async {
      engine.replyHold!.complete();
      expect(await answer, 'Hello.');
    });
  });

  testWidgets('a swap while the model is unloaded for being idle shows '
      'Loading for the whole load, not Unloaded; then Ready', (tester) async {
    await tester.runAsync(() async {
      await storage.backendSettings.setLastUsedModelPath(chatModel);
      await storage.backendSettings.setIdleUnloadMinutes(30);
      await ready(idleAfter: const Duration(milliseconds: 400));
      await unloaded();
    });
    final s = await showStatus(tester);
    expect(on<KoboldStatusCard>('Unloaded'), findsOneWidget);

    // A new chat preset or model reloads chat's config in place.
    late Future<void> swap;
    await tester.runAsync(() async {
      engine.hold = Completer<void>();
      swap = s.provider.reloadChatKobold();
      // Accepted: what the engine was told to load is noted.
      await until(() => kobold.loadedModelPath == chatModel);
    });
    await tester.pump();
    expectLoading();
    expect(await phone(tester, s.facade), 'loading');

    await tester.runAsync(() async {
      engine.hold!.complete();
      await swap;
    });
    await tester.pump();
    expectReady();
    expect(engine.reloads, ['unload_model', kStagedChatConfig]);
    expect(await phone(tester, s.facade), 'ready');
  });
}
