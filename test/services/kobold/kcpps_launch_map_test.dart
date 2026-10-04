// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// What a launch runs for a user's preset: the file as it was written.
//
// The launch used to rebuild a preset from the handful of settings the app
// can show. Whatever those could not hold was dropped or replaced without a
// word: a second graphics card, the CUDA options, a MoE layer count, a
// cache size past the app's own range, and every setting the file had left
// to KoboldCpp (the app wrote its own default in). The rule pinned here: a
// preset is the user's, and the app lays over it only what it has to own.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

const _fixture = 'test/fixtures/kcpps/koboldcpp_1_117_1_export.kcpps';

/// The only settings the app may differ in.
const _overlay = {'model_param', 'jinja', 'mmproj', 'noswa'};

Map<String, dynamic> _launch(
  Map<String, dynamic> preset, {
  String modelPath = '',
  String mmprojPath = '',
  void Function(String)? onNote,
}) => kcppsPresetLaunchMap(
  preset,
  modelPath: modelPath,
  mmprojPath: mmprojPath,
  onNote: onNote,
);

void main() {
  group('a config saved by KoboldCpp 1.117.1 itself', () {
    late Map<String, dynamic> original;

    setUp(() {
      original = (readKcpps(File(_fixture).readAsStringSync()) as KcppsOk).raw;
    });

    test('the reader hands back the file exactly as it was written', () {
      expect(
        original,
        (jsonDecode(File(_fixture).readAsStringSync()) as Map).cast(),
      );
      expect(original.length, greaterThan(100));
    });

    test('every setting reaches the launch as written, apart from the few '
        'the app owns', () {
      final ready = _launch(
        original,
        modelPath: '/models/picked.gguf',
        mmprojPath: '/models/proj.gguf',
      );
      expect(ready.keys.toSet(), original.keys.toSet());
      for (final key in original.keys.toSet().difference(_overlay)) {
        expect(ready[key], original[key], reason: key);
      }
      expect(ready['model_param'], '/models/picked.gguf');
      expect(ready['jinja'], isTrue);
      expect(ready['mmproj'], '/models/proj.gguf');
      // The file has sliding window on (noswa: false) with fast forward on.
      expect(ready['noswa'], isTrue);
    });

    test('with no model or vision file from the app, the file keeps its '
        'own', () {
      final ready = _launch(original);
      expect(ready['model_param'], original['model_param']);
      expect(ready['mmproj'], original['mmproj']);
    });
  });

  test('settings the app has no control for are not dropped, clamped or '
      'replaced, and nothing the file left out is filled in', () {
    for (final preset in <Map<String, dynamic>>[
      // CUDA with its options; two cards.
      {
        'noswa': true,
        'usecuda': ['normal', '1', 'nommq', 'rowsplit'],
      },
      {
        'noswa': true,
        'usecuda': ['lowvram', '0', 'mmq'],
      },
      {
        'noswa': true,
        'usevulkan': [0, 1],
        'tensor_split': [1, 1],
      },
      // A layer count with MoE experts of 12 layers on the CPU.
      {'noswa': true, 'gpulayers': 48, 'moecpu': 12},
      // Sliding window with fast forward off, and sizes past the range the
      // app's own settings offer.
      {
        'noswa': false,
        'nofastforward': true,
        'swapadding': 512,
        'smartcache': 40,
      },
      // No context size: KoboldCpp's own default must stay KoboldCpp's.
      {'noswa': true, 'gpulayers': -1},
    ]) {
      final ready = _launch(Map.of(preset));
      expect(
        {...ready}..remove('jinja'),
        preset,
        reason: 'only the chat template is added to $preset',
      );
      expect(ready['jinja'], isTrue);
    }
  });

  group('sliding window', () {
    test('on in the file, together with fast forward, is switched off and '
        'the log is told', () {
      for (final unsafe in <Map<String, dynamic>>[
        {'noswa': false},
        {'noswa': false, 'nofastforward': false},
        // The name KoboldCpp's launcher used before `noswa` existed. A
        // current engine reads it as "on" when the file has no `noswa`.
        {'useswa': true},
      ]) {
        final notes = <String>[];
        final ready = _launch(Map.of(unsafe), onNote: notes.add);
        expect(ready['noswa'], isTrue, reason: '$unsafe');
        // Fast forward and context shift are the user's, and stay.
        expect(ready['nofastforward'], unsafe['nofastforward']);
        expect(ready.containsKey('noshift'), isFalse);
        expect(ready['useswa'], unsafe['useswa'], reason: 'left as written');
        expect(notes.single, contains('sliding window is switched off'));
      }
    });

    test('is otherwise left exactly as the file has it', () {
      for (final asWritten in <Map<String, dynamic>>[
        // The safe pairing.
        {'noswa': false, 'nofastforward': true},
        {'noswa': true},
        {'noswa': true, 'nofastforward': true},
        // Not mentioned: nothing is added for it.
        {'contextsize': 4096},
        {'nofastforward': true},
        // The older name: on with fast forward off, off, or overruled by
        // the newer name the engine reads first.
        {'useswa': true, 'nofastforward': true},
        {'useswa': false},
        {'noswa': true, 'useswa': true},
      ]) {
        final notes = <String>[];
        final ready = _launch(Map.of(asWritten), onNote: notes.add);
        expect({...ready}..remove('jinja'), asWritten);
        expect(notes, isEmpty, reason: '$asWritten');
      }
    });
  });

  test('a forced automatic fit that overrides the file\'s own layer count is '
      'pointed out', () {
    final notes = <String>[];
    _launch({
      'noswa': true,
      'autofit': true,
      'gpulayers': 30,
    }, onNote: notes.add);
    expect(notes.single, contains('forces automatic fit'));
  });

  test('the preset handed in is not altered', () {
    final preset = <String, dynamic>{'model': '/m/a.gguf', 'jinja': false};
    final ready = _launch(
      preset,
      modelPath: '/m/b.gguf',
      mmprojPath: '/m/proj.gguf',
    );
    expect(preset, {'model': '/m/a.gguf', 'jinja': false});
    // The older name for the model is the file's and stays; KoboldCpp
    // reads `model_param` first.
    expect(ready['model'], '/m/a.gguf');
    expect(ready['model_param'], '/m/b.gguf');
  });
}
