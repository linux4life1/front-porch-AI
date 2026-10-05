// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Reading a preset never throws. Every caller treats what comes back as the
// whole answer; a read that threw instead used to end a launch half way,
// with the app left unable to start KoboldCpp again until it was restarted.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

void main() {
  test('whatever a setting holds, the file reads, and what was read can be '
      'written back out', () {
    const settings = [
      'model_param',
      'model',
      'contextsize',
      'batchsize',
      'blasbatchsize',
      'threads',
      'gpulayers',
      'autofit',
      'autofitpadding',
      'usemmap',
      'usemlock',
      'quantkv',
      'noflashattention',
      'flashattention',
      'usecuda',
      'usecublas',
      'usehipblas',
      'usevulkan',
      'noswa',
      'useswa',
      'swapadding',
      'nofastforward',
      'noshift',
      'smartcache',
      'jinja',
      'mmproj',
      'mmprojcpu',
      'moecpu',
      'something the app has never heard of',
    ];
    const odd = <Object?>[
      null,
      true,
      7,
      -1,
      2.5,
      1e300,
      'text',
      '',
      <Object?>[],
      [1, 'a', null, 2.5],
      <String, Object?>{},
      {'a': 1},
    ];
    for (final setting in settings) {
      for (final value in odd) {
        final text = jsonEncode({setting: value});
        final read = readKcpps(text);
        expect(read, isA<KcppsOk>(), reason: text);
        read as KcppsOk;
        expect(read.raw, jsonDecode(text), reason: text);
        expect(
          () => encodeKcpps(kcppsMap(read.config)),
          returnsNormally,
          reason: text,
        );
        expect(
          () => encodeKcpps(
            kcppsPresetLaunchMap(read.raw, modelPath: '', mmprojPath: ''),
          ),
          returnsNormally,
          reason: text,
        );
      }
    }
  });

  test('a number too large to hold is refused by name, wherever it sits', () {
    // It reads as infinity, which cannot be written back out.
    for (final text in [
      '{"contextsize": 1e999}',
      '{"something else": -1e999}',
      '{"tensor_split": [1, 1e999]}',
      '{"nested": {"deeper": [{"n": 1e999}]}}',
    ]) {
      expect(
        (readKcpps(text) as KcppsBroken).reason,
        contains('too large'),
        reason: text,
      );
    }
  });

  test('text that is not a config at all is reported, not thrown', () {
    expect(
      (readKcpps('{not json') as KcppsBroken).reason,
      contains('not valid'),
    );
    expect(
      (readKcpps('[1, 2]') as KcppsBroken).reason,
      contains('not a KoboldCpp config'),
    );
    expect((readKcpps('') as KcppsBroken).reason, contains('not valid'));
    // Nested far past anything a config holds.
    final deep = '{"a": ${'[' * 20000}${']' * 20000}}';
    expect(() => readKcpps(deep), returnsNormally);
  });

  test('the file as written comes back next to the summary of it', () {
    const text =
        '{"usevulkan": [0, 1], "moecpu": 12, "noswa": true, "extra": "kept"}';
    final read = readKcpps(text) as KcppsOk;
    expect(read.raw, jsonDecode(text));
    // The summary holds one card and "experts on the CPU: yes".
    expect(read.config.gpuId, 0);
    expect(read.config.moeExpertsOnCpu, isTrue);
  });
}
