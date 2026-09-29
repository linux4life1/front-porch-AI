// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A folder of thousands of LoRAs used to freeze the app: every file scanned the
// whole catalog (about 4 s at 5,000 files and 15 s at 10,000 on the review
// machine). The answer must not change, the work must be linear, and big
// lists must leave the UI isolate.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/grpc/dt_native/dt_local_loras.dart';
import 'package:front_porch_ai/services/image/draw_things_lora_filter.dart';
import 'package:front_porch_ai/services/image/model_family.dart';

/// The lookup as it was before the speed fix, kept here as the reference the
/// new one must agree with. A file's own version, else the first catalog row
/// with the same base name. The visibility rule is restated independently:
/// hidden only by a different, known tag; `flux2` and its two sizes fit.
String _referenceVersion(String file, Map<String, String> versions) {
  final base = drawThingsLoraBasename(file);
  final direct = versions[file] ?? versions[base];
  if (direct != null && direct.trim().isNotEmpty) return direct.trim();
  for (final entry in versions.entries) {
    if (drawThingsLoraBasename(entry.key) != base) continue;
    final value = entry.value.trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

List<String> _referenceVisible(
  List<String> files,
  Map<String, String> versions,
  String modelVersion,
) {
  final wanted = modelVersion.trim();
  if (wanted.isEmpty) return List<String>.from(files);
  const sizes = {'flux2_4b', 'flux2_9b'};
  bool fits(String tag) =>
      tag.isEmpty ||
      tag == wanted ||
      (tag == 'flux2' && sizes.contains(wanted)) ||
      (wanted == 'flux2' && sizes.contains(tag));
  return [
    for (final file in files)
      if (fits(_referenceVersion(file, versions))) file,
  ];
}

/// [count] LoRAs, and a catalog whose keys carry a folder, so no file is a
/// direct hit and each one used to trigger a scan of every catalog row.
({List<String> files, Map<String, String> catalog}) _bigFolder(int count) {
  final files = [for (var i = 0; i < count; i++) 'lora_$i.safetensors'];
  final catalog = {
    for (var i = 0; i < count; i++)
      'lora/lora_$i.safetensors': i.isEven ? 'flux2_9b' : 'ltx2.3',
  };
  return (files: files, catalog: catalog);
}

void main() {
  group('the same answer as before', () {
    test('on random catalogs with folders, blanks and repeats', () {
      final random = Random(20260929);
      const versions = [
        '',
        ' ',
        'flux2',
        'flux2_4b',
        'flux2_9b',
        'ltx2.3',
        'flux1',
        ' flux2_9b ',
      ];
      for (var round = 0; round < 60; round++) {
        final names = [
          for (var i = 0; i < 40; i++) 'n${random.nextInt(25)}.ckpt',
        ];
        final files = [
          for (final n in names) random.nextBool() ? n : p.join('lora', n),
        ];
        final catalog = <String, String>{
          for (var i = 0; i < 30; i++)
            (random.nextBool()
                    ? names[random.nextInt(names.length)]
                    : p.join('lora', names[random.nextInt(names.length)])):
                versions[random.nextInt(versions.length)],
        };
        for (final model in [
          'flux2_9b',
          'flux2',
          'flux2_4b',
          'ltx2.3',
          '',
          'sd3',
        ]) {
          expect(
            drawThingsVisibleLoras(
              files: files,
              loraVersions: catalog,
              modelVersion: model,
            ),
            _referenceVisible(files, catalog, model),
            reason: 'round $round model "$model"',
          );
        }
      }
    });

    test('the first non-empty version for a base name wins', () {
      final visible = drawThingsVisibleLoras(
        files: const ['a.ckpt'],
        loraVersions: const {
          'x/a.ckpt': '',
          'y/a.ckpt': 'flux2_9b',
          'z/a.ckpt': 'ltx2.3',
        },
        modelVersion: 'flux2_9b',
      );
      expect(visible, ['a.ckpt']);
    });
  });

  group('a big folder', () {
    test(
      '10,000 LoRAs against a 10,000-row catalog take well under two seconds',
      () {
        final big = _bigFolder(10000);
        final watch = Stopwatch()..start();
        final visible = drawThingsVisibleLoras(
          files: big.files,
          loraVersions: big.catalog,
          modelVersion: 'flux2_9b',
        );
        watch.stop();
        expect(visible, hasLength(5000));
        expect(visible.first, 'lora_0.safetensors');
        expect(
          watch.elapsedMilliseconds,
          lessThan(2000),
          reason:
              'was ${watch.elapsedMilliseconds} ms; the old scan took ~15 s',
        );
      },
    );
  });

  group('leaving the UI isolate', () {
    test(
      'a big list is handed to the runner, and the answer is the same',
      () async {
        final big = _bigFolder(3000);
        var handedOff = 0;
        final visible = await drawThingsVisibleLorasOffThread(
          files: big.files,
          loraVersions: big.catalog,
          modelVersion: 'flux2_9b',
          run: <R>(work) async {
            handedOff++;
            return work();
          },
        );
        expect(handedOff, 1);
        expect(
          visible,
          drawThingsVisibleLoras(
            files: big.files,
            loraVersions: big.catalog,
            modelVersion: 'flux2_9b',
          ),
        );
      },
    );

    test('a small list is answered in place', () async {
      var handedOff = 0;
      final visible = await drawThingsVisibleLorasOffThread(
        files: const ['a.ckpt'],
        loraVersions: const {'a.ckpt': 'flux2_9b'},
        modelVersion: 'flux2_9b',
        run: <R>(work) async {
          handedOff++;
          return work();
        },
      );
      expect(handedOff, 0);
      expect(visible, ['a.ckpt']);
    });

    test('the threshold is what decides', () async {
      var handedOff = 0;
      Future<R> count<R>(R Function() work) async {
        handedOff++;
        return work();
      }

      await drawThingsVisibleLorasOffThread(
        files: List.filled(5, 'a.ckpt'),
        loraVersions: const {},
        modelVersion: 'x',
        inlineMax: 5,
        run: count,
      );
      expect(handedOff, 0);
      await drawThingsVisibleLorasOffThread(
        files: List.filled(6, 'a.ckpt'),
        loraVersions: const {},
        modelVersion: 'x',
        inlineMax: 5,
        run: count,
      );
      expect(handedOff, 1);
      expect(kDrawThingsFilterInlineMax, 2000);
    });

    test('on a real isolate the answer still comes back the same', () async {
      final big = _bigFolder(4000);
      final visible = await drawThingsVisibleLorasOffThread(
        files: big.files,
        loraVersions: big.catalog,
        modelVersion: 'ltx2.3',
      );
      expect(visible, hasLength(2000));
      expect(visible.first, 'lora_1.safetensors');
    });

    test('Comfy is never filtered, and needs no isolate', () async {
      var handedOff = 0;
      final files = List.generate(3000, (i) => 'f$i.safetensors');
      final visible = await deskLoraFilesOffThread(
        backend: 'comfyui',
        files: files,
        loraVersions: const {},
        modelVersions: const {},
        modelFile: 'x.safetensors',
        run: <R>(work) async {
          handedOff++;
          return work();
        },
      );
      expect(visible, files);
      expect(handedOff, 0);
    });

    test(
      'Draw Things takes the checkpoint\'s catalog version and hands a big list off',
      () async {
        final big = _bigFolder(3000);
        var handedOff = 0;
        final visible = await deskLoraFilesOffThread(
          backend: 'drawthings',
          files: big.files,
          loraVersions: big.catalog,
          modelVersions: const {'flux_2_klein_9b_q8p.ckpt': 'flux2_9b'},
          modelFile: 'flux_2_klein_9b_q8p.ckpt',
          run: <R>(work) async {
            handedOff++;
            return work();
          },
        );
        expect(handedOff, 1);
        expect(visible, hasLength(1500));
      },
    );

    test('LoRA options are handed off the same way', () async {
      final options = [
        for (var i = 0; i < 3000; i++)
          LoraOption(
            'l$i.ckpt',
            ModelFamily.unknown,
            dtVersion: i.isEven ? 'flux2_9b' : 'ltx2.3',
          ),
      ];
      var handedOff = 0;
      final kept = await drawThingsLorasForModelOffThread(
        options,
        modelVersion: 'flux2_9b',
        run: <R>(work) async {
          handedOff++;
          return work();
        },
      );
      expect(handedOff, 1);
      expect(kept, hasLength(1500));
      expect(kept.every((row) => row.dtVersion == 'flux2_9b'), isTrue);
      final small = await drawThingsLorasForModelOffThread(
        options.take(10).toList(),
        modelVersion: 'flux2_9b',
        run: <R>(work) async {
          handedOff++;
          return work();
        },
      );
      expect(handedOff, 1);
      expect(small, hasLength(5));
    });
  });
}
