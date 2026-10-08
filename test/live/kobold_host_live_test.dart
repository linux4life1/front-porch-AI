// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The app's KoboldCpp answers this computer only, on a REAL engine. The
// app's launch gives KoboldCpp nothing on its command line about where to
// listen, so the address can only come from the config the app stages: the
// engine answers on 127.0.0.1 and not on any other address this computer
// has, and it stays that way through a live reload, even of a config that
// names no host. Skipped unless KOBOLD_LIVE_BIN and KOBOLD_LIVE_MODEL are
// set; see kobold_engine_live_test.dart. Run:
//   KOBOLD_LIVE_BIN=… KOBOLD_LIVE_MODEL=… flutter test --tags kobold_live \
//     test/live/kobold_host_live_test.dart

@Tags(['kobold_live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'live_engine.dart';

const _slow = Timeout(Duration(minutes: 10));

class _Engine extends BackendManager {
  _Engine(super.storage, this.exe);
  final String exe;

  @override
  String? get backendPath => exe;
}

/// What KoboldCpp answers at [host]:[port], or null when nothing does.
Future<Object?> _answerAt(String host, int port) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.getUrl(
      Uri.parse('http://$host:$port/api/extra/version'),
    );
    final response = await request.close().timeout(const Duration(seconds: 5));
    return jsonDecode(await utf8.decodeStream(response));
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// This computer's own IPv4 addresses on its networks, loopback left out.
Future<List<String>> _networkAddresses() async => [
  for (final face in await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  ))
    for (final address in face.addresses) address.address,
];

void main() {
  late Directory root;
  late StorageService storage;
  late KoboldService kobold;
  late LLMProvider provider;
  late HardwareService hardware;
  late String exe;
  late int port;

  setUpAll(() => HttpOverrides.global = null);

  setUp(() async {
    final temp = await Directory.systemTemp.createTemp('fpai host live');
    root = Directory(temp.resolveSymbolicLinksSync());
    TestWidgetsFlutterBinding.ensureInitialized();
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
    final b = storage.backendSettings;
    await b.setBackendType('kobold');
    await b.setContextSize(4096);
    await b.setLastUsedModelPath(liveEngineModel);

    hardware = HardwareService();
    await hardware.detectHardware();
    kobold = KoboldService(storage)
      ..hardwareInfo = (() => hardware.hardwareInfo)
      ..readFreeMemory = (() => hardware.readFreeMemory());
    exe = await copyEngineInto(storage.binDir);
    port = await freePort();
    kobold.setBaseUrl('http://127.0.0.1:$port');
    provider = LLMProvider(
      kobold,
      OpenRouterService(apiUrl: '', apiKey: '', modelName: ''),
      storage,
      _Engine(storage, exe),
    );
  });

  tearDown(() async {
    await kobold.stopKobold();
    provider.dispose();
    hardware.dispose();
    await stopLiveEnginesUnder(root);
    await root.delete(recursive: true);
  });

  Future<void> start() async {
    expect((await kobold.launch(exe, port: port)).started, isTrue);
    await waitForLiveModel(port);
    for (var i = 0; i < 120 && !kobold.modelReady; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(kobold.modelReady, isTrue);
  }

  /// The engine answers on 127.0.0.1 and on none of this computer's other
  /// addresses (checked only where it has any).
  Future<void> expectThisComputerOnly() async {
    expect(
      await _answerAt('127.0.0.1', port),
      isA<Map>(),
      reason: 'the app reaches it on 127.0.0.1',
    );
    final others = await _networkAddresses();
    if (others.isEmpty) {
      markTestSkipped(
        'this computer has no network address besides loopback: only the '
        '127.0.0.1 half was checked',
      );
    }
    for (final address in others) {
      expect(
        await _answerAt(address, port),
        isNull,
        reason:
            'KoboldCpp answers on $address, which is not this computer '
            'alone',
      );
    }
  }

  test(
    'the engine the app launches answers on 127.0.0.1 and on no other '
    'address this computer has',
    () async {
      await start();

      await expectThisComputerOnly();
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );

  test(
    'a live reload, even of a config that names no host, leaves it '
    'answering this computer only',
    () async {
      await start();

      // A config with no host in it, as the preset editor's speed test
      // loads one. KoboldCpp must keep the address it was launched with.
      final ran = await provider.loadKoboldTrial('fpai-trial.kcpps', {
        'model_param': liveEngineModel,
        'contextsize': 8192,
      });
      expect(ran, isTrue);
      expect(await liveContextSize(port), 8192, reason: 'it was reloaded');
      await expectThisComputerOnly();

      // And back to chat's own config, which names the host.
      await provider.reloadChatKobold();
      expect(await liveContextSize(port), 4096, reason: 'it was reloaded');
      await expectThisComputerOnly();
    },
    timeout: _slow,
    skip: liveEngineSkip,
  );
}
