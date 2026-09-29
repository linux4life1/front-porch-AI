// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// How the Draw Things LoRA list gets its versions: Echo names carry none, so
// the local catalog's versions are overlaid. Cases that do not depend on which
// LoRAs the filter hides come from image-studio-rewrite's filter tests; the
// combine step and the "every LoRA shows" cases are new.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/grpc/dt_native/dt_local_loras.dart';
import 'package:front_porch_ai/services/image/civitai_download.dart';
import 'package:front_porch_ai/services/image/draw_things_lora_filter.dart';
import 'package:front_porch_ai/services/image/model_family.dart';

void main() {
  test('echo names take the catalog version and keep catalog-only files', () {
    final merged = drawThingsMergeLoraVersions(
      listed: const [
        DrawThingsLoraEntry('lora/klein_unchained_v2_lora_f16.ckpt'),
        DrawThingsLoraEntry('echo_only_lora.ckpt'),
      ],
      catalog: const [
        DrawThingsLoraEntry('klein_unchained_v2_lora_f16.ckpt', 'flux2_9b'),
        DrawThingsLoraEntry('disk_only_lora.ckpt', 'ltx2.3'),
      ],
    );
    expect(merged.map((row) => row.file), [
      'klein_unchained_v2_lora_f16.ckpt',
      'echo_only_lora.ckpt',
      'disk_only_lora.ckpt',
    ]);
    expect(merged[0].version, 'flux2_9b');
    expect(merged[1].version, '');
    expect(merged[2].version, 'ltx2.3');
  });

  group('the list offered to the picker', () {
    const echoed = [DrawThingsLoraEntry('zoo_style_lora_f16.ckpt')];
    const local = [
      DrawThingsLoraEntry('zoo_style_lora_f16.ckpt', 'flux2_9b'),
      DrawThingsLoraEntry('downloaded_lora.safetensors', 'ltx2.3'),
    ];

    test(
      'what Draw Things listed gets its catalog version, and disk-only files join',
      () {
        final list = drawThingsCombineLoras(echoed: echoed, local: local);
        expect(list.map((row) => row.file), [
          'zoo_style_lora_f16.ckpt',
          'downloaded_lora.safetensors',
        ]);
        expect(list.first.version, 'flux2_9b');
      },
    );

    test('nothing listed means the folder\'s own list', () {
      expect(drawThingsCombineLoras(echoed: const [], local: local), local);
    });

    test(
      'a catalog with nothing in it leaves the listed names as they are',
      () {
        final list = drawThingsCombineLoras(echoed: echoed, local: const []);
        expect(list.map((row) => row.file), ['zoo_style_lora_f16.ckpt']);
        expect(list.single.version, '');
      },
    );
  });

  test('custom.json maps a checkpoint file to its version', () async {
    final dir = await Directory.systemTemp.createTemp('dt_versions_');
    addTearDown(() => dir.delete(recursive: true));
    await File(p.join(dir.path, 'custom.json')).writeAsString(
      jsonEncode([
        {'file': 'flux_2_klein_9b_q8p.ckpt', 'version': 'flux2_9b'},
        {'file': 'skipped.ckpt', 'version': ''},
      ]),
    );
    expect(await drawThingsModelVersionsIn(dir), {
      'flux_2_klein_9b_q8p.ckpt': 'flux2_9b',
    });
  });

  test('the catalog version wins over a filename guess', () {
    expect(
      drawThingsVersionForModel('v2_flux_klein_4_lora_f16.ckpt', const {
        'v2_flux_klein_4_lora_f16.ckpt': 'flux2_9b',
      }),
      'flux2_9b',
    );
    expect(
      drawThingsVersionForModel('flux_2_klein_9b_q8p.ckpt', const {}),
      'flux2_9b',
    );
    expect(drawThingsVersionFromName('ltx_fingering_lora_f16.ckpt'), 'ltx2.3');
    expect(drawThingsVersionFromName('klein_4b_lora_f16.ckpt'), 'flux2_4b');
    expect(drawThingsVersionFromName('mystery.ckpt'), '');
    expect(drawThingsVersionForBase('Flux.2 Klein 9B'), 'flux2_9b');
    expect(drawThingsVersionForBase('SDXL 1.0'), 'sdxl_base_v0.9');
  });

  test(
    'a Draw Things version stays on the LoRA when the family is unknown',
    () {
      final option = ImageModelFamily.classifyLora(
        'ltx_fingering_lora_f16.ckpt',
        metadata: const {'dt_base_model': 'ltx2.3'},
      );
      expect(option.family, ModelFamily.unknown);
      expect(option.dtVersion, 'ltx2.3');
    },
  );

  test('an unknown model, or Comfy, keeps the full LoRA list', () {
    const files = [
      'klein_unchained_v2_lora_f16.ckpt',
      'ltx_fingering_lora_f16.ckpt',
    ];
    const versions = {
      'klein_unchained_v2_lora_f16.ckpt': 'flux2_9b',
      'ltx_fingering_lora_f16.ckpt': 'ltx2.3',
    };
    expect(
      drawThingsVisibleLoras(
        files: files,
        loraVersions: versions,
        modelVersion: '',
      ),
      files,
    );
    expect(
      deskLoraFiles(
        backend: 'comfyui',
        files: files,
        loraVersions: versions,
        modelVersions: const {'flux_2_klein_9b_q8p.ckpt': 'flux2_9b'},
        modelFile: 'flux_2_klein_9b_q8p.ckpt',
      ),
      files,
    );
  });
}
