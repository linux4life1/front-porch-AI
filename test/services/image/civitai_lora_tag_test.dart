// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A LoRA saved for Draw Things is tagged from the base model CivitAI lists for
// it, never guessed from its file name. A name that says "Klein" does not say
// which Klein, and a wrong tag hides the LoRA on the checkpoint it fits. With
// no base model, or one that cannot be placed, no version is written and the
// LoRA shows everywhere.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/grpc/dt_native/dt_local_loras.dart';
import 'package:front_porch_ai/services/image/draw_things_lora_filter.dart';
import 'package:front_porch_ai/services/image/image.dart';

import 'civitai_route_support.dart';
import 'civitai_test_server.dart';

const _file = 'PixelArt_Klein.safetensors';

void main() {
  late Directory models;

  setUp(() {
    models = Directory.systemTemp.createTempSync('civitai-lora-tag');
    addTearDown(() => models.deleteSync(recursive: true));
  });

  Map<String, dynamic> catalogRow() {
    final rows =
        jsonDecode(
              File(p.join(models.path, 'custom_lora.json')).readAsStringSync(),
            )
            as List;
    return rows.single as Map<String, dynamic>;
  }

  /// The LoRAs Draw Things shows on a checkpoint of [modelVersion].
  Future<List<String>> shownOn(String modelVersion) async {
    final entries = await drawThingsLoraFilesIn(models);
    return drawThingsVisibleLoras(
      files: [for (final e in entries) e.file],
      loraVersions: {for (final e in entries) e.file: e.version},
      modelVersion: modelVersion,
    );
  }

  Future<void> saveWithBase(String baseModel) async {
    File(p.join(models.path, _file)).writeAsBytesSync(const [1]);
    await rememberDrawThingsLora(models, _file, baseModel: baseModel);
  }

  test(
    'a Klein 4B LoRA is tagged 4B, not 9B, and shows on a 4B checkpoint',
    () async {
      await saveWithBase('Flux.2 Klein 4B');

      expect(catalogRow()['version'], 'flux2_4b');
      expect(await shownOn('flux2_4b'), [_file]);
      expect(
        await shownOn('flux2_9b'),
        isEmpty,
        reason: 'it is the other size',
      );
    },
  );

  test('a file name that says Klein does not pick the version', () async {
    await saveWithBase('');

    expect(catalogRow().containsKey('version'), isFalse);
    expect(await shownOn('flux2_4b'), [_file]);
    expect(await shownOn('flux2_9b'), [_file]);
  });

  test(
    'a base model this cannot place writes no version, so the LoRA shows',
    () async {
      await saveWithBase('Hunyuan Video');

      expect(catalogRow().containsKey('version'), isFalse);
      expect(await shownOn('flux2_4b'), [_file]);
    },
  );

  test('CivitAI base models map to Draw Things versions', () {
    const expected = {
      'Flux.2 Klein 4B': 'flux2_4b',
      'Flux.2 Klein 4B-base': 'flux2_4b',
      'Flux.2 Klein 9B': 'flux2_9b',
      'Flux.2 Klein 9B-base': 'flux2_9b',
      'Flux.2 D': 'flux2',
      'Flux.1 D': 'flux1',
      'Flux.1 S': 'flux1',
      'ZImageTurbo': 'z_image',
      'ZImageBase': 'z_image',
      'Qwen': 'qwen_image',
      'Qwen 2.1': 'qwen_image_2.1',
      'SD 3.5 Large': 'sd3',
      'SDXL 1.0': 'sdxl_base_v0.9',
      'Pony': 'sdxl_base_v0.9',
      'Illustrious': 'sdxl_base_v0.9',
      'SD 1.5': 'v1',
      // Not placed: no version rather than a guess.
      'Qwen 3': '',
      'Pony V7': '',
      'Flux.1 Kontext': '',
      'Something New': '',
      '': '',
    };
    expected.forEach((base, version) {
      expect(drawThingsVersionForBase(base), version, reason: base);
    });
  });

  test(
    'the base model CivitAI lists travels from the version to the saved file',
    () async {
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/civitai/version_133005.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      raw['baseModel'] = 'Flux.2 Klein 4B';
      (raw['files'] as List).single['name'] = _file;
      final version = parseCivitaiVersion(jsonEncode(raw))!;
      expect(version.baseModel, 'Flux.2 Klein 4B');

      final planned =
          await CivitaiRelay(
            memoryCivitaiStore({'civitai_credential_local': 'k'}),
          ).planDownload(
            accountId: 'local',
            version: version,
            filename: _file,
            adult: false,
            adultAllowed: true,
            savedRoot: models.path,
            fromLoraSheet: true,
            backend: 'drawthings',
          );
      expect(planned.refused, isFalse);
      expect(planned.baseModel, 'Flux.2 Klein 4B');

      // The same plan, fetched from a real loopback server.
      final host = await CivitaiFileHost.start();
      host.serve('/lora', const [1, 2, 3, 4]);
      final landed = await downloadCivitaiPlan(
        CivitaiDownloadPlan(
          uri: host.uri('/lora'),
          path: planned.path,
          authorization: 'Bearer test-token',
          log: planned.log,
          refused: false,
          root: models.path,
          expectedBytes: 4,
          baseModel: planned.baseModel,
        ),
      );

      expect(landed, p.join(models.path, 'lora', _file));
      expect(catalogRow()['version'], 'flux2_4b');
    },
  );
}
