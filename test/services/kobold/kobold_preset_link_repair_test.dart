// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Old wrong links from a model to a preset are cleaned up once (maintainer
// ruling Q, 2026-10-05: "Clean up once"). Before Phase 9 the app kept a
// preset under whichever model a screen showed, so a preset that loads model
// B could sit under model A, and choosing A in Settings or on the phone
// started B. At app start, once, the links whose preset loads a DIFFERENT
// model that is on this computer are removed, each with a plain-words line
// in the log. Everything else is left exactly as it was: a right link, a
// preset that names no model, a preset whose file is gone, a preset naming a
// model that is not here. That it ran is recorded (beta-aware), so a link
// made afterwards is never touched.
//
// Real files on disk and a real preferences store.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/storage/settings/preset_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late List<String> logged;
  late DebugPrintCallback realPrint;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fpai preset links');
    logged = [];
    realPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message ?? '');
  });

  tearDown(() {
    debugPrint = realPrint;
    dir.deleteSync(recursive: true);
  });

  String model(String name) => (File(
    p.join(dir.path, name),
  )..writeAsBytesSync('GGUF'.codeUnits + List.filled(32, 0))).path;

  String preset(String name, Map<String, dynamic> config) => (File(
    p.join(dir.path, name),
  )..writeAsStringSync(jsonEncode(config))).path;

  /// Preset settings over a real preferences store holding [links].
  Future<PresetSettings> open(Map<String, String> links) async {
    SharedPreferences.setMockInitialValues({
      PresetSettings().k('model_preset_map'): jsonEncode(links),
    });
    return PresetSettings()
      ..initializeBase(await SharedPreferences.getInstance(), () {})
      ..load();
  }

  Map<String, dynamic> stored(PresetSettings s) =>
      jsonDecode(s.prefs!.getString(s.k('model_preset_map'))!)
          as Map<String, dynamic>;

  test('a link to a preset that loads another model on this computer is '
      'removed, with a line in the log; everything else is kept', () async {
    final a = model('A.gguf');
    final b = model('B.gguf');
    final c = model('C.gguf');
    final d = model('D.gguf');
    final e = model('E.gguf');
    final f = model('F.gguf');
    final g = model('G.gguf');
    final wrong = preset('Loads B.kcpps', {'model_param': b});
    final links = {
      a: wrong,
      // Right: it loads the model it is kept for.
      c: preset('Loads C.kcpps', {'model_param': c}),
      // Names no model: it runs the model it is chosen with.
      d: preset('No model.kcpps', {'contextsize': 8192}),
      // The file is gone: a launch drops it anyway.
      e: p.join(dir.path, 'Gone.kcpps'),
      // Names a model that is not here: it runs this one with its settings.
      f: preset('Elsewhere.kcpps', {'model_param': '/far/away/H.gguf'}),
      // "No preset for this model".
      g: '',
    };
    final presets = await open(links);

    await repairKoboldPresetLinks(presets, engineDir: dir.path);

    final kept = Map.of(links)..remove(a);
    expect(presets.modelPresetMap, kept);
    expect(stored(presets), kept, reason: 'what is kept for the next start');
    final removals = logged.where((l) => l.contains('The link was removed'));
    expect(removals, hasLength(1));
    expect(
      removals.single,
      allOf(contains('Loads B.kcpps'), contains('A.gguf'), contains('B.gguf')),
    );
    expect(File(wrong).existsSync(), isTrue, reason: 'the preset is kept');
  });

  test(
    'a model named relative to the engine folder is the model there',
    () async {
      final a = model('A.gguf');
      final b = model('B.gguf');
      final right = preset('Mine.kcpps', {'model_param': 'A.gguf'});
      final wrong = preset('Theirs.kcpps', {'model': 'B.gguf'});
      final presets = await open({a: right, b: right, '${a}x': wrong});

      await repairKoboldPresetLinks(presets, engineDir: dir.path);

      expect(presets.modelPresetMap, {a: right});
    },
  );

  test('it runs once: a link made after it ran is not touched', () async {
    final a = model('A.gguf');
    final b = model('B.gguf');
    final wrong = preset('Loads B.kcpps', {'model_param': b});
    final presets = await open({a: wrong});

    await repairKoboldPresetLinks(presets, engineDir: dir.path);
    expect(presets.modelPresetMap, isEmpty);
    expect(
      presets.prefs!.getBool(presets.k('kobold_preset_links_repaired')),
      isTrue,
      reason: 'recorded under the beta-aware key',
    );

    await presets.setModelPreset(a, wrong);
    logged.clear();
    await repairKoboldPresetLinks(presets, engineDir: dir.path);

    expect(presets.modelPresetMap, {a: wrong});
    expect(logged.where((l) => l.contains('The link was removed')), isEmpty);
  });
}
