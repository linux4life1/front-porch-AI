// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Which LoRAs the Draw Things picker shows for the loaded checkpoint.
//
// Only a LoRA's catalog tag can hide it, and only when the tag is a different,
// known version. Untagged files and zoo LoRAs stay visible; the file name is
// never used to hide anything. `flux2` (no size stated) and its sizes
// `flux2_4b` / `flux2_9b` show each other; the sizes hide each other; every
// other version, including qwen_image vs qwen_image_2.1, must match exactly.
//
// This replaces image-studio-rewrite's "a Klein 9B model keeps its LoRAs and
// drops other versions" case, which asserted that an untagged file is hidden.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/draw_things_lora_filter.dart';
import 'package:front_porch_ai/services/image/model_family.dart';

const _klein9b = 'klein_unchained_v2_lora_f16.ckpt';
const _generic = 'flux_2_style_lora_f16.ckpt';
const _unlabeled = 'unlabeled_lora.ckpt';
const _klein4b = 'klein_4b_lora_f16.ckpt';
const _ltx = 'ltx_fingering_lora_f16.ckpt';
const _restore = 'Flux2-Klein-Image-RestoreV1.safetensors';

/// The catalog as Draw Things records it: `_unlabeled` has no row at all.
const _catalog = {
  _klein9b: 'flux2_9b',
  _generic: 'flux2',
  _klein4b: 'flux2_4b',
  _ltx: 'ltx2.3',
  _restore: 'flux1',
};

const _all = [_klein9b, _generic, _unlabeled, _klein4b, _ltx, _restore];

List<String> _shown(String model, [Map<String, String> catalog = _catalog]) =>
    drawThingsVisibleLoras(
      files: _all,
      loraVersions: catalog,
      modelVersion: model,
    );

void main() {
  group('a Klein 9B checkpoint (flux2_9b)', () {
    test(
      'shows exact, generic and untagged LoRAs; hides other sizes and families',
      () {
        expect(_shown('flux2_9b'), [_klein9b, _generic, _unlabeled]);
      },
    );

    test('shows a LoRA tagged with its own version', () {
      expect(_shown('flux2_9b'), contains(_klein9b));
    });

    test('shows a LoRA tagged only flux2, size not stated', () {
      expect(_shown('flux2_9b'), contains(_generic));
    });

    test('shows an untagged or zoo LoRA, which the old rule hid', () {
      expect(_shown('flux2_9b'), contains(_unlabeled));
    });

    test('hides a flux2_4b LoRA: another size, weights that do not fit', () {
      expect(_shown('flux2_9b'), isNot(contains(_klein4b)));
    });

    test('hides an ltx2.3 LoRA', () {
      expect(_shown('flux2_9b'), isNot(contains(_ltx)));
    });

    test(
      'hides a LoRA the catalog tags flux1, even though its name says Klein',
      () {
        expect(_shown('flux2_9b'), isNot(contains(_restore)));
      },
    );
  });

  group('a checkpoint tagged only flux2', () {
    test(
      'shows flux2 and both sizes and untagged files, hides flux1 and ltx2.3',
      () {
        expect(_shown('flux2'), [_klein9b, _generic, _unlabeled, _klein4b]);
      },
    );

    test('the sizes are the only ones a generic flux2 reaches', () {
      final visible = drawThingsVisibleLoras(
        files: const ['a', 'b', 'c', 'd'],
        loraVersions: const {
          'a': 'flux2_4b',
          'b': 'flux2_9b',
          'c': 'flux1',
          'd': 'flux',
        },
        modelVersion: 'flux2',
      );
      expect(visible, ['a', 'b']);
    });
  });

  group('a Klein 4B checkpoint (flux2_4b)', () {
    test(
      'mirrors the 9B: its own size, generic and untagged; not the other size',
      () {
        expect(_shown('flux2_4b'), [_generic, _unlabeled, _klein4b]);
      },
    );
  });

  group('Qwen-Image generations stay separate', () {
    const files = ['q21', 'q10', 'z', 'plain'];
    const catalog = {
      'q21': 'qwen_image_2.1',
      'q10': 'qwen_image',
      'z': 'z_image',
    };

    List<String> qwen(String model) => drawThingsVisibleLoras(
      files: files,
      loraVersions: catalog,
      modelVersion: model,
    );

    test('2.1 shows 2.1 and untagged, and hides 1.0 and other families', () {
      expect(qwen('qwen_image_2.1'), ['q21', 'plain']);
    });

    test('1.0 shows 1.0 and untagged, and hides 2.1', () {
      expect(qwen('qwen_image'), ['q10', 'plain']);
    });
  });

  group('every other version is an exact match', () {
    test(
      'an SDXL checkpoint hides SD 1.5, SD3 and Flux tags, and shows its own',
      () {
        final visible = drawThingsVisibleLoras(
          files: const ['xl', 'v1', 'sd3', 'fx', 'none'],
          loraVersions: const {
            'xl': 'sdxl_base_v0.9',
            'v1': 'v1',
            'sd3': 'sd3',
            'fx': 'flux1',
          },
          modelVersion: 'sdxl_base_v0.9',
        );
        expect(visible, ['xl', 'none']);
      },
    );

    test('flux1 and flux2 are different families', () {
      final visible = drawThingsVisibleLoras(
        files: const ['one', 'two'],
        loraVersions: const {'one': 'flux1', 'two': 'flux2'},
        modelVersion: 'flux1',
      );
      expect(visible, ['one']);
    });
  });

  group('only the catalog tag counts', () {
    test('a file whose name says ltx is shown while it has no tag', () {
      final visible = drawThingsVisibleLoras(
        files: const [_ltx],
        loraVersions: const {},
        modelVersion: 'flux2_9b',
      );
      expect(visible, [_ltx]);
    });

    test(
      'one tagged LoRA in the catalog no longer hides the untagged ones',
      () {
        final visible = drawThingsVisibleLoras(
          files: const ['tagged', 'untagged', 'blank', 'spaces'],
          loraVersions: const {
            'tagged': 'flux2_9b',
            'blank': '',
            'spaces': '  ',
          },
          modelVersion: 'flux2_9b',
        );
        expect(visible, ['tagged', 'untagged', 'blank', 'spaces']);
      },
    );

    test('a tag with stray spaces still counts as its version', () {
      final visible = drawThingsVisibleLoras(
        files: const ['a', 'b'],
        loraVersions: const {'a': ' flux2_9b ', 'b': ' ltx2.3 '},
        modelVersion: 'flux2_9b',
      );
      expect(visible, ['a']);
    });

    test(
      'catalog rows are matched by base name, so a folder in the key changes nothing',
      () {
        final visible = drawThingsVisibleLoras(
          files: const [_klein9b, _ltx, _unlabeled],
          loraVersions: const {
            'lora/$_klein9b': 'flux2_9b',
            'lora/$_ltx': 'ltx2.3',
          },
          modelVersion: 'flux2_9b',
        );
        expect(visible, [_klein9b, _unlabeled]);
      },
    );

    test('an empty model version still shows everything', () {
      expect(_shown(''), _all);
      expect(_shown('  '), _all);
    });
  });

  group('the same rule everywhere it is applied', () {
    test('Draw Things: the checkpoint\'s catalog version picks the list', () {
      final visible = deskLoraFiles(
        backend: 'drawthings',
        files: _all,
        loraVersions: _catalog,
        modelVersions: const {'flux_2_klein_9b_q8p.ckpt': 'flux2_9b'},
        modelFile: 'flux_2_klein_9b_q8p.ckpt',
      );
      expect(visible, [_klein9b, _generic, _unlabeled]);
    });

    test('Comfy is not filtered at all', () {
      final visible = deskLoraFiles(
        backend: 'comfyui',
        files: _all,
        loraVersions: _catalog,
        modelVersions: const {'flux_2_klein_9b_q8p.ckpt': 'flux2_9b'},
        modelFile: 'flux_2_klein_9b_q8p.ckpt',
      );
      expect(visible, _all);
    });

    test(
      'LoRA options follow the same rule through their Draw Things version',
      () {
        final options = [
          for (final e in {..._catalog, _unlabeled: ''}.entries)
            LoraOption(e.key, ModelFamily.unknown, dtVersion: e.value),
        ];
        final kept = drawThingsLorasForModel(options, modelVersion: 'flux2_9b');
        expect(kept.map((o) => o.name), [_klein9b, _generic, _unlabeled]);
      },
    );

    test('the off-thread versions give the same answer', () async {
      final files = await drawThingsVisibleLorasOffThread(
        files: _all,
        loraVersions: _catalog,
        modelVersion: 'flux2_9b',
        inlineMax: 1,
        run: <R>(work) async => work(),
      );
      expect(files, [_klein9b, _generic, _unlabeled]);
      final options = await drawThingsLorasForModelOffThread(
        [
          for (final e in {..._catalog, _unlabeled: ''}.entries)
            LoraOption(e.key, ModelFamily.unknown, dtVersion: e.value),
        ],
        modelVersion: 'flux2',
        inlineMax: 1,
        run: <R>(work) async => work(),
      );
      expect(options.map((o) => o.name), [
        _klein9b,
        _generic,
        _klein4b,
        _unlabeled,
      ]);
    });
  });
}
