// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Where a VAE, a text encoder and an Automatic1111 LoRA are saved. The review
// found these branches unpinned: changing them left every test green.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/image.dart';

import 'civitai_route_support.dart';

String? _slot(
  String type, {
  bool lora = false,
  String backend = 'comfyui',
  String file = 'x.safetensors',
}) => civitaiSlotFolder(
  fromLoraSheet: lora,
  civitaiType: type,
  filename: file,
  backend: backend,
);

/// Real version 133005 with its model type swapped.
CivitaiVersion _versionOfType(String type) {
  final raw =
      jsonDecode(
            File(
              'test/fixtures/civitai/version_133005.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  (raw['model'] as Map)['type'] = type;
  return parseCivitaiVersion(jsonEncode(raw))!;
}

void main() {
  group('VAE', () {
    test('goes to vae on ComfyUI and models/VAE on Automatic1111', () {
      expect(_slot('VAE'), 'vae');
      expect(_slot('vae'), 'vae');
      expect(_slot('VAE', backend: 'a1111'), 'models/VAE');
    });

    test('is not saved from the LoRA sheet, or on Draw Things', () {
      expect(_slot('VAE', lora: true), isNull);
      expect(_slot('VAE', lora: true, backend: 'a1111'), isNull);
      expect(_slot('VAE', backend: 'drawthings'), isNull);
    });
  });

  group('text encoder', () {
    test('goes to text_encoders on ComfyUI, in either spelling', () {
      expect(_slot('Text Encoder'), 'text_encoders');
      expect(_slot('TextEncoder'), 'text_encoders');
    });

    test(
      'Automatic1111 has no text encoder folder, and the LoRA sheet saves none',
      () {
        expect(_slot('Text Encoder', backend: 'a1111'), isNull);
        expect(_slot('TextEncoder', lora: true), isNull);
        expect(_slot('Text Encoder', backend: 'drawthings'), isNull);
      },
    );
  });

  group('Automatic1111 LoRA', () {
    test('goes to models/Lora from the LoRA sheet, LoCon and DoRA too', () {
      for (final type in ['LORA', 'LoCon', 'DoRA']) {
        expect(_slot(type, lora: true, backend: 'a1111'), 'models/Lora');
      }
    });

    test('is not saved from the model sheet', () {
      expect(_slot('LORA', backend: 'a1111'), isNull);
    });

    test('a checkpoint on Automatic1111 goes to models/Stable-diffusion', () {
      expect(_slot('Checkpoint', backend: 'a1111'), 'models/Stable-diffusion');
    });

    test('the installed scan reads the same folders it saves to', () {
      expect(civitaiScanFolders(backend: 'a1111', lora: true), ['models/Lora']);
      expect(civitaiScanFolders(backend: 'a1111', lora: false), [
        'models/Stable-diffusion',
      ]);
    });
  });

  group('through a real plan', () {
    final relay = CivitaiRelay(
      memoryCivitaiStore({'civitai_credential_local': 'k'}),
    );
    const root = '/models';

    Future<String?> planned(
      String type, {
      bool lora = false,
      String backend = 'comfyui',
    }) async {
      final made = await relay.planDownload(
        accountId: 'local',
        version: _versionOfType(type),
        filename: 'MaouBigV1.2.safetensors',
        adult: false,
        adultAllowed: true,
        savedRoot: root,
        fromLoraSheet: lora,
        backend: backend,
      );
      return made.path;
    }

    test('each lands in its folder under the models folder', () async {
      expect(
        await planned('VAE'),
        p.join(root, 'vae', 'MaouBigV1.2.safetensors'),
      );
      expect(
        await planned('VAE', backend: 'a1111'),
        p.join(root, 'models', 'VAE', 'MaouBigV1.2.safetensors'),
      );
      expect(
        await planned('Text Encoder'),
        p.join(root, 'text_encoders', 'MaouBigV1.2.safetensors'),
      );
      expect(
        await planned('LORA', lora: true, backend: 'a1111'),
        p.join(root, 'models', 'Lora', 'MaouBigV1.2.safetensors'),
      );
      expect(await planned('Text Encoder', backend: 'a1111'), isNull);
    });
  });
}
