// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The one-time clean-up of old wrong links from a model to a preset
// (kobold_preset_link_repair_test) runs when the app starts: by the time the
// settings are loaded, a link whose preset loads a different model on this
// computer is gone, a right one is kept, and that it ran is recorded.
//
// The real storage service starts on a temporary library, with a real
// preferences store and real files.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage/settings/preset_settings.dart';
import 'package:front_porch_ai/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fpai preset links at start');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? dir.path
              : null,
        );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('the app removes a wrong link when it starts, and keeps a right '
      'one', () async {
    String model(String name) => (File(
      p.join(dir.path, name),
    )..writeAsBytesSync('GGUF'.codeUnits + List.filled(32, 0))).path;
    final a = model('A.gguf');
    final b = model('B.gguf');
    final loadsB = (File(
      p.join(dir.path, 'Loads B.kcpps'),
    )..writeAsStringSync(jsonEncode({'model_param': b}))).path;
    SharedPreferences.setMockInitialValues({
      // Wrong under A, right under B.
      PresetSettings().k('model_preset_map'): jsonEncode({
        a: loadsB,
        b: loadsB,
      }),
    });

    final storage = StorageService();
    await storage.initialized;

    expect(storage.presetSettings.modelPresetMap, {b: loadsB});
    final s = storage.presetSettings;
    expect(s.prefs!.getBool(s.k('kobold_preset_links_repaired')), isTrue);
  });
}
