// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The settings the preset editor manages, read and written back: experts
// kept in system memory for the first N layers, the forced fit, MMQ, the
// draft model, context shift, and CUDA options beside the card.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

KoboldLaunchConfig _read(Map<String, Object?> map) =>
    (readKcpps(jsonEncode(map)) as KcppsOk).config;

void main() {
  test('experts for the first N layers are kept as N', () {
    final c = _read({'gpulayers': 41, 'moecpu': 34, 'noswa': true});
    expect(c.moeExpertsOnCpu, isTrue);
    expect(c.moeCpuLayers, 34);
    expect(kcppsMap(c)['moecpu'], 34);
    // All of them, as the app's own settings ask.
    final all = c.copyWith(moeCpuLayers: 999);
    expect(kcppsMap(all)['moecpu'], 999);
  });

  test('the forced fit is written as the file had it, or not at all', () {
    expect(kcppsMap(_read({'autofit': true}))['autofit'], isTrue);
    expect(kcppsMap(_read({'autofit': false}))['autofit'], isFalse);
    expect(kcppsMap(_read({'noswa': true})).containsKey('autofit'), isFalse);
    // Not listed as a setting the app does not manage.
    final read = readKcpps(jsonEncode({'autofit': true})) as KcppsOk;
    expect(read.unmanagedKeys, isNot(contains('autofit')));
  });

  test('MMQ: the key, or "nommq" in the card list, read; written as the '
      'key', () {
    expect(_read({'nommq': true}).mmq, isFalse);
    expect(_read({'nommq': false}).mmq, isTrue);
    expect(
      _read({
        'usecuda': ['normal', '0', 'nommq'],
      }).mmq,
      isFalse,
    );
    expect(_read({'noswa': true}).mmq, isNull);
    expect(kcppsMap(_read({'nommq': true}))['nommq'], isTrue);
    expect(kcppsMap(_read({'noswa': true})).containsKey('nommq'), isFalse);
  });

  test('CUDA options beside the card survive a round trip', () {
    final c = _read({
      'usecuda': ['normal', '1', 'nommq', 'rowsplit'],
    });
    expect(c.gpuId, 1);
    expect(c.cudaOptions, ['rowsplit']);
    expect(kcppsMap(c)['usecuda'], ['normal', '1', 'rowsplit']);
  });

  test('the draft model is the editor\'s; its other draft settings ride '
      'along', () {
    final read =
        readKcpps(jsonEncode({'draftmodel': '/m/small.gguf', 'draftamount': 6}))
            as KcppsOk;
    expect(read.config.draftModelPath, '/m/small.gguf');
    expect(read.unmanagedKeys, ['draftamount']);
    final back = kcppsMap(read.config);
    expect(back['draftmodel'], '/m/small.gguf');
    expect(back['draftamount'], 6);
  });

  test('context shift off is kept with fast forward', () {
    final c = _read({'noswa': true, 'nofastforward': false, 'noshift': true});
    expect(c.contextShift, isFalse);
    expect(kcppsMap(c)['noshift'], isTrue);
    expect(kcppsMap(_read({'noswa': true}))['noshift'], isFalse);
  });

  group('the preset the editor writes', () {
    KoboldLaunchConfig preset({int? layers, int moeCpu = 0}) =>
        koboldGeneratedPreset(
          modelPath: '/m/a.gguf',
          contextSize: 16384,
          batchSize: 512,
          threads: 4,
          greedyAllocation: true,
          kvQuant: KvQuant.f16,
          backend: KoboldGpuBackend.cuda,
          gpuId: 0,
          contextMode: ContextManagementMode.fastForwardSmartCache,
          smartCacheSlots: 0,
          manualLayers: layers,
          moeCpuLayers: moeCpu,
        );

    test('placed by hand: the layer count and experts as set, no forced '
        'fit, no spare-memory setting', () {
      final map = kcppsMap(preset(layers: 41, moeCpu: 34));
      expect(map['gpulayers'], 41);
      expect(map['moecpu'], 34);
      expect(map['autofit'], isFalse);
      expect(map.containsKey('autofitpadding'), isFalse);
    });

    test('placed by KoboldCpp: forced fit with its spare memory', () {
      final map = kcppsMap(preset());
      expect(map['gpulayers'], -1);
      expect(map['autofit'], isTrue);
      expect(map['autofitpadding'], 32);
      expect(map.containsKey('moecpu'), isFalse);
    });
  });
}
