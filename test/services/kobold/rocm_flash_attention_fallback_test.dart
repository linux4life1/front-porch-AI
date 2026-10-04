// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The ROCm flash attention fallback (maintainer ruling, 2026-10-04): ROCm
// follows the Flash Attention setting like other cards; when the ROCm build
// dies mid-answer with it on, the machine is marked and later launches
// leave it off, including a user's preset, which is otherwise run as
// written. Switching Flash Attention back on in Settings clears the mark.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_launch_args.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:path/path.dart' as p;

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  test('KoboldCpp runs flash attention unless a config turns it off', () {
    expect(kcppsRunsFlashAttention({}), isTrue);
    expect(kcppsRunsFlashAttention({'noflashattention': false}), isTrue);
    expect(kcppsRunsFlashAttention({'flashattention': true}), isTrue);
    expect(kcppsRunsFlashAttention({'noflashattention': true}), isFalse);
    expect(kcppsRunsFlashAttention({'flashattention': false}), isFalse);
  });

  test('on a marked machine, a preset runs without flash attention and a '
      'full-size cache, and the log says why', () {
    final notes = <String>[];
    final map = kcppsPresetLaunchMap(
      {'contextsize': 8192, 'quantkv': 'q8_0'},
      modelPath: '/m/a.gguf',
      mmprojPath: '',
      onNote: notes.add,
      flashAttentionOff: true,
    );
    expect(map['noflashattention'], isTrue);
    expect(map['quantkv'], 'f16');
    expect(map['contextsize'], 8192, reason: 'the rest is as written');
    expect(notes, contains(contains('stopped on this machine')));
  });

  test('elsewhere the preset is left as written', () {
    final map = kcppsPresetLaunchMap(
      {'contextsize': 8192, 'quantkv': 'q8_0'},
      modelPath: '/m/a.gguf',
      mmprojPath: '',
    );
    expect(map.containsKey('noflashattention'), isFalse);
    expect(map['quantkv'], 'q8_0');
  });

  group('with stored settings', () {
    late StorageService storage;
    late Directory dir;

    setUp(() async {
      storage = await createStorageService();
      dir = Directory.systemTemp.createTempSync('fpai_rocm_fa_');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('a launch of a preset with the ROCm build on a marked machine '
        'turns flash attention off; without the mark it stays', () async {
      final preset = File(p.join(dir.path, 'mine.kcpps'))
        ..writeAsStringSync(jsonEncode({'contextsize': 8192}));
      Future<Map<String, dynamic>> launchMap() => koboldLaunchMap(
        storage: storage,
        modelPath: '',
        kcppsPath: preset.path,
        mmprojPath: null,
        gpuLayers: 0,
        contextSize: 8192,
        useVulkan: false,
        useCublas: false,
        useMetal: false,
        useRocm: true,
      );

      expect((await launchMap()).containsKey('noflashattention'), isFalse);
      await storage.backendSettings.setRocmFlashAttentionFailed(true);
      expect((await launchMap())['noflashattention'], isTrue);
    });

    test(
      'switching Flash Attention back on in Settings clears the mark',
      () async {
        final b = storage.backendSettings;
        await b.setRocmFlashAttentionFailed(true);
        await b.setFlashAttentionEnabled(false);
        expect(b.rocmFlashAttentionFailed, isTrue);
        await b.setFlashAttentionEnabled(true);
        expect(b.rocmFlashAttentionFailed, isFalse);
      },
    );
  });
}
