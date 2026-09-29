// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/grpc/dt_native/dt_local_loras.dart';
import 'package:front_porch_ai/services/image/civitai_download.dart';
import 'package:front_porch_ai/services/image/draw_things_lora_filter.dart';
import 'package:front_porch_ai/services/image/model_family.dart';

void main() {
  test('a Klein 9B model keeps its LoRAs and drops other versions', () {
    final visible = drawThingsVisibleLoras(
      files: const [
        'klein_unchained_v2_lora_f16.ckpt',
        'ltx_fingering_lora_f16.ckpt',
        'Flux2-Klein-Image-RestoreV1.safetensors',
        'unlabeled_lora.ckpt',
      ],
      loraVersions: const {
        'klein_unchained_v2_lora_f16.ckpt': 'flux2_9b',
        'ltx_fingering_lora_f16.ckpt': 'ltx2.3',
        'Flux2-Klein-Image-RestoreV1.safetensors': 'flux1',
      },
      modelVersion: 'flux2_9b',
    );
    expect(visible, ['klein_unchained_v2_lora_f16.ckpt']);
  });

  test('an unknown model or an untagged catalog shows every LoRA', () {
    const files = [
      'klein_unchained_v2_lora_f16.ckpt',
      'ltx_fingering_lora_f16.ckpt',
    ];
    expect(
      drawThingsVisibleLoras(
        files: files,
        loraVersions: const {
          'klein_unchained_v2_lora_f16.ckpt': 'flux2_9b',
          'ltx_fingering_lora_f16.ckpt': 'ltx2.3',
        },
        modelVersion: '',
      ),
      files,
    );
    expect(
      drawThingsVisibleLoras(
        files: files,
        loraVersions: const {
          'klein_unchained_v2_lora_f16.ckpt': '',
          'ltx_fingering_lora_f16.ckpt': '',
        },
        modelVersion: 'flux2_9b',
      ),
      files,
    );
  });

  test('Comfy keeps the full LoRA list', () {
    const files = [
      'ltx_fingering_lora_f16.ckpt',
      'klein_unchained_v2_lora_f16.ckpt',
    ];
    expect(
      deskLoraFiles(
        backend: 'comfyui',
        files: files,
        loraVersions: const {'ltx_fingering_lora_f16.ckpt': 'ltx2.3'},
        modelVersions: const {'flux_2_klein_9b_q8p.ckpt': 'flux2_9b'},
        modelFile: 'flux_2_klein_9b_q8p.ckpt',
      ),
      files,
    );
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
    expect(
      drawThingsCatalogVersion('klein_unchained_v2_lora_f16.ckpt'),
      'flux2_9b',
    );
    expect(
      drawThingsCatalogVersion('juggernautXL_v9.safetensors'),
      'sdxl_base_v0.9',
    );
  });

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

  test('custom.json maps a checkpoint file to its version', () async {
    final dir = await Directory.systemTemp.createTemp('dt_versions_');
    try {
      await File(p.join(dir.path, 'custom.json')).writeAsString(
        jsonEncode([
          {'file': 'flux_2_klein_9b_q8p.ckpt', 'version': 'flux2_9b'},
          {'file': 'skipped.ckpt', 'version': ''},
        ]),
      );
      expect(await drawThingsModelVersionsIn(dir), {
        'flux_2_klein_9b_q8p.ckpt': 'flux2_9b',
      });
    } finally {
      await dir.delete(recursive: true);
    }
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
}
