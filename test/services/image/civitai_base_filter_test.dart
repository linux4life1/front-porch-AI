// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/civitai_bases.dart';
import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/image/civitai_fetch.dart';
import 'package:front_porch_ai/services/image/civitai_files.dart';
import 'package:front_porch_ai/services/image/civitai_installed.dart';
import 'package:path/path.dart' as p;

void main() {
  test('a typed base filter keeps the matching family', () {
    final klein = filterCivitaiBaseGroups(kCivitaiBaseGroups, query: 'klein');
    final apis = [
      for (final group in klein)
        for (final choice in group.choices) choice.api,
    ];
    expect(apis, contains('Flux.2 Klein 9B'));
    expect(apis, contains('Flux.2 Klein 4B-base'));
    expect(apis, isNot(contains('Flux.1 D')));
    expect(apis, isNot(contains('Qwen')));
  });

  test('typing a family name keeps that whole group', () {
    final flux = filterCivitaiBaseGroups(kCivitaiBaseGroups, query: 'Flux');
    final apis = [
      for (final group in flux)
        for (final choice in group.choices) choice.api,
    ];
    expect(apis, contains('Flux.1 D'));
    expect(apis, contains('Flux.2 D'));
    expect(apis, isNot(contains('Qwen 2.1')));
  });

  test('installed models limit the base list to those files', () {
    final only = civitaiBasesForFiles(const [
      'qwen-image-2.1-Q2_K.gguf',
      'z_image_turbo_bf16.safetensors',
      'flux1-dev-Q5.gguf',
    ]);
    final groups = filterCivitaiBaseGroups(kCivitaiBaseGroups, onlyApis: only);
    final apis = [
      for (final group in groups)
        for (final choice in group.choices) choice.api,
    ];
    expect(apis, contains('Qwen 2.1'));
    expect(apis, contains('ZImageTurbo'));
    expect(apis, contains('Flux.1 D'));
    expect(apis, isNot(contains('Qwen')));
    expect(apis, isNot(contains('SDXL 1.0')));
    expect(apis, isNot(contains('ZImageBase')));
  });

  test('file names map to the CivitAI base they can run', () {
    expect(civitaiBasesForFilename('qwen-image-2.1-Q2_K.gguf'), ['Qwen 2.1']);
    expect(civitaiBasesForFilename('qwen-image-2512.safetensors'), ['Qwen']);
    expect(civitaiBasesForFilename('z_image_turbo_bf16.safetensors'), [
      'ZImageTurbo',
    ]);
    expect(
      civitaiBasesForFilename('z-image-Q5.gguf'),
      containsAll(['ZImageTurbo', 'ZImageBase']),
    );
    expect(civitaiBasesForFilename('flux1-schnell-Q4.gguf'), ['Flux.1 S']);
    expect(civitaiBasesForFilename('flux1-dev-Q5.gguf'), ['Flux.1 D']);
    expect(civitaiBasesForFilename('juggernautXL_v9.safetensors'), [
      'SDXL 1.0',
    ]);
    expect(civitaiBasesForFilename('ponyDiffusion.safetensors'), ['Pony']);
    expect(civitaiBasesForFilename('sd3.5_large_turbo.safetensors'), [
      'SD 3.5 Large Turbo',
    ]);
    expect(civitaiBasesForFilename('hidream.safetensors'), ['HiDream']);
    expect(civitaiBasesForFilename('qwen_3_4b.safetensors'), isEmpty);
    expect(civitaiBasesForFilename('mmproj-Qwen3-VL-8B.gguf'), isEmpty);
  });

  test('the weight file is chosen ahead of a preview', () {
    final name = civitaiPickFilename(const [
      {'name': 'cover.jpeg', 'type': 'Image'},
      {
        'name': 'night.safetensors',
        'type': 'Model',
        'primary': true,
        'sizeKB': 140000,
      },
    ]);
    expect(name, 'night.safetensors');
  });

  test('model scan folders skip text encoders and LoRA drawers', () {
    expect(
      civitaiScanFolders(backend: 'comfyui', lora: false),
      isNot(contains('text_encoders')),
    );
    expect(
      civitaiScanFolders(backend: 'comfyui', lora: false),
      contains('diffusion_models'),
    );
    expect(civitaiScanFolders(backend: 'comfyui', lora: true), ['loras']);
    expect(civitaiScanFolders(backend: 'a1111', lora: true), ['models/Lora']);
    expect(civitaiScanFolders(backend: 'drawthings', lora: true), ['lora']);
  });

  test('a LoRA already in the folder counts as installed', () async {
    final root = Directory.systemTemp.createTempSync('civitai-installed');
    addTearDown(() => root.deleteSync(recursive: true));
    final loras = Directory(p.join(root.path, 'loras'))..createSync();
    File(p.join(loras.path, 'night.safetensors')).writeAsStringSync('x');
    File(p.join(loras.path, 'partial.safetensors.part')).writeAsStringSync('x');
    final names = await civitaiSlotNames(
      root: root.path,
      backend: 'comfyui',
      lora: true,
    );
    expect(civitaiFileInstalled('night.safetensors', names), isTrue);
    expect(civitaiFileInstalled('Night.safetensors', names), isTrue);
    expect(civitaiFileInstalled('partial.safetensors.part', names), isFalse);
    final listed = await mergeCivitaiDisk(
      root: root.path,
      backend: 'comfyui',
      file: 'night.safetensors',
      lora: true,
      workflowId: 'qwen_image_21',
      checkpoints: const [],
      diffusion: const [],
      gguf: const [],
      loras: const [],
    );
    expect(listed.loras, ['night.safetensors']);
    final missing = await mergeCivitaiDisk(
      root: root.path,
      backend: 'comfyui',
      file: 'other.safetensors',
      lora: true,
      workflowId: 'qwen_image_21',
      checkpoints: const [],
      diffusion: const [],
      gguf: const [],
      loras: const [],
    );
    expect(missing.loras, isEmpty);
  });

  test('a download reports how many bytes have arrived', () async {
    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = saved);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.contentLength = 4;
      request.response.add(const [1, 2, 3, 4]);
      await request.response.close();
    });
    final dir = Directory.systemTemp.createTempSync('civitai-progress');
    addTearDown(() => dir.deleteSync(recursive: true));
    final seen = <int>[];
    await downloadCivitaiPlan(
      CivitaiDownloadPlan(
        uri: Uri.parse('http://${server.address.host}:${server.port}/file'),
        path: p.join(dir.path, 'night.safetensors'),
        authorization: 'Bearer test-token',
        log: 'civitai download account=local adult=false',
        refused: false,
      ),
      onProgress: (got, total) {
        expect(total, 4);
        seen.add(got);
      },
    );
    expect(seen, isNotEmpty);
    expect(seen.last, 4);
  });
}
