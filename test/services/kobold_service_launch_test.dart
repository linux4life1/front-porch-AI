// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Starting the engine records the model that actually loads.
//
// `lastUsedModelPath` is the app's one record of "which model": the status
// card, the vision lookup, the thinking settings, an automatic restart and
// the web "loaded" marker all read it. When a preset owned the model that
// record used to be left alone, so the engine ran model B while everything
// else pointed at model A.
//
// This replaces `test/ui/pages/settings_launch_records_model_test.dart`,
// which read the source of one launch site and checked the order of two
// lines in it. Those lines are gone: every launch site now calls the one
// entry tested here, with a real process and the real config it is given.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late StorageService storage;
  late KoboldService kobold;
  late String exe;

  /// A file with the GGUF magic, enough for the app's model check.
  String model(String name) => (File(
    p.join(root.path, name),
  )..writeAsBytesSync('GGUF'.codeUnits + List.filled(64, 0))).path;

  String preset(String name, Map<String, Object?> settings) => (File(
    p.join(root.path, name),
  )..writeAsStringSync(jsonEncode(settings))).path;

  /// The config the engine was started from.
  Map<String, dynamic> staged() =>
      (jsonDecode(
                File(
                  p.join(koboldAdminDirFor(storage), kStagedChatConfig),
                ).readAsStringSync(),
              )
              as Map)
          .cast<String, dynamic>();

  setUp(() async {
    root = Directory(
      Directory.systemTemp
          .createTempSync('fpai launch entry')
          .resolveSymbolicLinksSync(),
    );
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
    kobold = KoboldService(storage);

    // A stand-in engine: a real process that takes any arguments and stays
    // up. What it is given is what is checked.
    await storage.binDir.create(recursive: true);
    final script = File(p.join(storage.binDir.path, 'koboldcpp'))
      ..writeAsStringSync('#!/bin/sh\nsleep 30\n');
    await Process.run('chmod', ['+x', script.path]);
    exe = script.path;
  });

  tearDown(() async {
    await kobold.stopKobold();
    kobold.dispose();
    await root.delete(recursive: true);
  });

  test('a preset that owns its model: that model is started and recorded, '
      'not the one last used', () async {
    final a = model('a.gguf');
    final b = model('b.gguf');
    final b0 = storage.backendSettings;
    await b0.setLastUsedModelPath(a);
    await b0.setActiveKcppsPath(preset('b.kcpps', {'model_param': b}));

    final result = await kobold.launch(exe);
    expect(result.started, isTrue);
    expect(result.message, isNull);

    expect(kobold.isProcessRunning, isTrue);
    expect(staged()['model_param'], b);
    expect(b0.lastUsedModelPath, b);
  });

  test('no preset: the picked model is started and recorded', () async {
    final a = model('a.gguf');
    final c = model('c.gguf');
    await storage.backendSettings.setLastUsedModelPath(a);

    expect((await kobold.launch(exe, pickedModel: c)).started, isTrue);

    expect(staged()['model_param'], c);
    expect(storage.backendSettings.lastUsedModelPath, c);
  });

  test('a preset whose model is not on this computer runs the picked model '
      'with the preset\'s settings, and says so', () async {
    final a = model('a.gguf');
    await storage.backendSettings.setActiveKcppsPath(
      preset('theirs.kcpps', {
        'model_param': '/another/computer/big.gguf',
        'contextsize': 2048,
        'noswa': true,
      }),
    );

    final result = await kobold.launch(exe, pickedModel: a);

    expect(result.started, isTrue);
    expect(result.message, contains('big.gguf'));
    expect(kobold.logs.join('\n'), contains('big.gguf'));
    expect(staged()['model_param'], a);
    expect(staged()['contextsize'], 2048);
    expect(storage.backendSettings.lastUsedModelPath, a);
  });

  test('a preset whose file is gone is cleared, and the launch goes ahead '
      'on the app\'s own settings', () async {
    final a = model('a.gguf');
    final gone = preset('gone.kcpps', {'contextsize': 2048});
    final b0 = storage.backendSettings;
    await b0.setLastUsedModelPath(a);
    await b0.setActiveKcppsPath(gone);
    // Choosing a preset copies its context size into Settings, so the
    // app's own value is set after it.
    await b0.setContextSize(4096);
    File(gone).deleteSync();

    final result = await kobold.launch(exe);

    expect(result.started, isTrue);
    expect(result.message, contains('gone.kcpps'));
    expect(b0.activeKcppsPath, isNull);
    expect(kobold.isProcessRunning, isTrue);
    expect(staged()['model_param'], a);
    expect(staged()['contextsize'], 4096);
  });

  test('nothing chosen: nothing is started, and the reason is plain', () async {
    final result = await kobold.launch(exe);
    expect(result.started, isFalse);
    expect(result.message, contains('No model is chosen yet'));
    expect(kobold.isProcessRunning, isFalse);
  });

  test('a preset that cannot be read: nothing is started, and the reason '
      'is returned and logged', () async {
    final a = model('a.gguf');
    final broken = (File(
      p.join(root.path, 'broken.kcpps'),
    )..writeAsStringSync('{this is not a config')).path;
    await storage.backendSettings.setLastUsedModelPath(a);
    await storage.backendSettings.setActiveKcppsPath(broken);

    final result = await kobold.launch(exe);

    expect(result.started, isFalse);
    expect(result.message, contains('broken.kcpps'));
    expect(result.message, contains('can\'t be read'));
    expect(kobold.logs.join('\n'), contains('broken.kcpps'));
    expect(kobold.isProcessRunning, isFalse);
  });

  test('a model file that is not a model: nothing is started', () async {
    final bad = (File(
      p.join(root.path, 'bad.gguf'),
    )..writeAsStringSync('not a model')).path;

    final result = await kobold.launch(exe, pickedModel: bad);

    expect(result.started, isFalse);
    expect(result.message, contains('Not a valid GGUF'));
    expect(kobold.isProcessRunning, isFalse);
  });

  test('a launch asked for while one is already starting says so instead '
      'of claiming it started', () async {
    final a = model('a.gguf');
    await storage.backendSettings.setLastUsedModelPath(a);

    final first = kobold.launch(exe);
    final second = await kobold.launch(exe);

    expect(second.started, isFalse);
    expect(second.message, contains('already starting'));
    expect((await first).started, isTrue);
  });

  test(
    'a refused launch leaves the record of the model in use alone',
    () async {
      final a = model('a.gguf');
      final bad = (File(
        p.join(root.path, 'bad.gguf'),
      )..writeAsStringSync('not a model')).path;
      await storage.backendSettings.setLastUsedModelPath(a);

      final result = await kobold.launch(exe, pickedModel: bad);

      expect(result.started, isFalse);
      expect(storage.backendSettings.lastUsedModelPath, a);
    },
  );
}
