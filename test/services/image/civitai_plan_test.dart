// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What a download may be, decided from what CivitAI lists for the version
// and never from what the caller says. The fixtures in test/fixtures/civitai
// are real /api/v1/model-versions responses with the bulky image and
// description fields dropped; the `files` arrays are verbatim.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/image.dart';

import 'civitai_route_support.dart';

Map<String, dynamic> _raw(int id) {
  final text = File(
    'test/fixtures/civitai/version_$id.json',
  ).readAsStringSync();
  return jsonDecode(text) as Map<String, dynamic>;
}

CivitaiVersion _version(int id, {void Function(Map<String, dynamic>)? edit}) {
  final raw = _raw(id);
  edit?.call(raw);
  return parseCivitaiVersion(jsonEncode(raw))!;
}

void main() {
  const root = '/models';
  late CivitaiRelay relay;

  setUp(() {
    relay = CivitaiRelay(memoryCivitaiStore({'civitai_credential_local': 'k'}));
  });

  Future<CivitaiDownloadPlan> plan(
    CivitaiVersion version,
    String filename, {
    bool lora = false,
    String backend = 'comfyui',
    bool adult = false,
    CivitaiRelay? via,
  }) {
    return (via ?? relay).planDownload(
      accountId: 'local',
      version: version,
      filename: filename,
      adult: adult,
      savedRoot: root,
      fromLoraSheet: lora,
      backend: backend,
    );
  }

  group('reading a version', () {
    test('a LoRA lists its real size, checksum and own download address', () {
      final v = _version(133005);
      expect(v.id, 133005);
      expect(v.modelType, 'LORA');
      expect(v.adult, isFalse);
      final file = v.files.single;
      expect(file.name, 'MaouBigV1.2.safetensors');
      expect(file.sizeBytes, (147572.7763671875 * 1024).round());
      expect(
        file.sha256,
        'eb748ea422fea806c85e142a06055a3f54ac91e3333153a766af57c2fcc91817',
      );
      expect(file.primary, isTrue);
      expect(file.format, 'SafeTensor');
      expect(
        file.downloadUri.toString(),
        'https://civitai.com/api/download/models/133005?fileId=96913',
      );
      expect(file.isSafeWeight, isTrue);
    });

    test('a body that is not a version is not one', () {
      expect(parseCivitaiVersion('not json'), isNull);
      expect(parseCivitaiVersion('[]'), isNull);
      expect(parseCivitaiVersion('{"id":1}'), isNull);
      expect(parseCivitaiVersion('{"id":1,"model":{},"files":"x"}'), isNull);
    });

    test('the version URL is built for the right host and id', () {
      expect(
        civitaiVersionUri(7, adult: false).toString(),
        'https://civitai.com/api/v1/model-versions/7',
      );
      expect(
        civitaiVersionUri(7, adult: true).toString(),
        'https://civitai.red/api/v1/model-versions/7',
      );
    });
  });

  group('the caller cannot name a file CivitAI did not list', () {
    test(
      'a traversal name, an unlisted name and a near miss are all refused',
      () async {
        final v = _version(133005);
        for (final name in [
          '../../x.safetensors',
          'x.safetensors',
          'maoubigv1.2.safetensors',
          'MaouBigV1.2.safetensors ',
          '',
        ]) {
          final made = await plan(v, name, lora: true);
          expect(made.refused, isTrue, reason: 'name "$name"');
          expect(made.path, isNull);
          expect(made.uri, isNull);
          expect(made.authorization, isNull);
          expect(made.failure, CivitaiFailure.unsafe);
        }
      },
    );

    test('the listed name becomes the path under the models folder', () async {
      final made = await plan(
        _version(133005),
        'MaouBigV1.2.safetensors',
        lora: true,
      );
      expect(made.refused, isFalse);
      expect(made.path, p.join(root, 'loras', 'MaouBigV1.2.safetensors'));
      expect(made.uri.toString(), contains('fileId=96913'));
      expect(made.authorization, 'Bearer k');
      expect(made.root, root);
      expect(made.expectedBytes, (147572.7763671875 * 1024).round());
      expect(made.sha256, startsWith('eb748ea4'));
      expect(made.log.contains('Bearer'), isFalse);
      expect(made.log.contains(' k'), isFalse);
    });
  });

  group('the type comes from CivitAI, not from the caller', () {
    test('a LoRA version cannot be filed as a model', () async {
      final made = await plan(_version(133005), 'MaouBigV1.2.safetensors');
      expect(made.refused, isTrue);
      expect(made.path, isNull);
    });

    test('a checkpoint version cannot be filed as a LoRA', () async {
      final made = await plan(
        _version(128713),
        'dreamshaper_8.safetensors',
        lora: true,
      );
      expect(made.refused, isTrue);
    });

    test('a checkpoint lands in checkpoints', () async {
      final made = await plan(_version(128713), 'dreamshaper_8.safetensors');
      expect(
        made.path,
        p.join(root, 'checkpoints', 'dreamshaper_8.safetensors'),
      );
      expect(made.allInOnePath, isNull);
    });

    test(
      'an embedding is accepted from the LoRA sheet only, and only as safetensors',
      () async {
        void asEmbedding(Map<String, dynamic> raw) {
          (raw['model'] as Map)['type'] = 'TextualInversion';
        }

        final v = _version(133005, edit: asEmbedding);
        final ok = await plan(v, 'MaouBigV1.2.safetensors', lora: true);
        expect(ok.path, p.join(root, 'embeddings', 'MaouBigV1.2.safetensors'));
        expect((await plan(v, 'MaouBigV1.2.safetensors')).refused, isTrue);
        expect(
          (await plan(
            v,
            'MaouBigV1.2.safetensors',
            lora: true,
            backend: 'drawthings',
          )).refused,
          isTrue,
        );
        expect(
          civitaiSlotFolder(
            fromLoraSheet: true,
            civitaiType: 'TextualInversion',
            filename: 'e.safetensors',
            backend: 'a1111',
          ),
          'embeddings',
        );
        expect(
          civitaiDownloadPath(root: root, folder: 'embeddings', name: 'e.pt'),
          isNull,
        );
      },
    );
  });

  group('only safetensors and gguf are saved', () {
    test(
      'a pickle checkpoint is refused, its safetensors sibling is not',
      () async {
        final v = _version(130072);
        final names = {for (final f in v.files) f.name: f};
        final pickles = names.keys.where((n) => n.endsWith('.ckpt')).toList();
        final safe = names.keys
            .where((n) => n.endsWith('.safetensors'))
            .toList();
        expect(pickles, isNotEmpty);
        expect(safe, isNotEmpty);
        for (final name in pickles) {
          expect((await plan(v, name)).refused, isTrue, reason: name);
        }
        for (final name in safe) {
          expect((await plan(v, name)).refused, isFalse, reason: name);
        }
      },
    );

    test(
      'a file CivitAI marks pickle is refused whatever its extension says',
      () async {
        final v = _version(
          133005,
          edit: (raw) {
            final file = (raw['files'] as List).first as Map;
            (file['metadata'] as Map)['format'] = 'PickleTensor';
          },
        );
        expect(
          (await plan(v, 'MaouBigV1.2.safetensors', lora: true)).refused,
          isTrue,
        );
      },
    );

    test('a file CivitAI flags dangerous is refused', () async {
      for (final field in ['pickleScanResult', 'virusScanResult']) {
        final v = _version(
          133005,
          edit: (raw) {
            ((raw['files'] as List).first as Map)[field] = 'Danger';
          },
        );
        expect(
          (await plan(v, 'MaouBigV1.2.safetensors', lora: true)).refused,
          isTrue,
          reason: field,
        );
      }
    });

    test('a VAE with an .sft name is not a model this app saves', () async {
      final v = _version(1957126);
      expect((await plan(v, 'ae.sft')).refused, isTrue);
    });

    test('a primary pickle never beats a safetensors file when picking', () {
      final raw = _raw(130072);
      final files = (raw['files'] as List).cast<Map>();
      for (final f in files) {
        f['primary'] = (f['name'] as String).endsWith('.ckpt');
      }
      final picked = civitaiPickFilename(files);
      expect(picked, isNotNull);
      expect(picked, endsWith('.safetensors'));
    });

    test('a version with no safe file offers none', () {
      expect(
        civitaiPickFilename([
          {'name': 'a.ckpt', 'primary': true, 'type': 'Model'},
          {'name': 'b.pt', 'type': 'Model'},
        ]),
        isNull,
      );
    });

    test('picking still prefers the primary model among safe files', () {
      final picked = civitaiPickFilename((_raw(1957126)['files'] as List));
      expect(picked, 'chromaGGUFOldVersions_20250629CFGDistillQ8.gguf');
    });
  });

  group('GGUF', () {
    test(
      'goes to diffusion_models on Comfy and is refused elsewhere',
      () async {
        final v = _version(1236037);
        const name = 'ggufFluxmaniaIII_iiiQ80.gguf';
        final comfy = await plan(v, name);
        expect(comfy.path, p.join(root, 'diffusion_models', name));
        expect(comfy.allInOnePath, isNull);
        expect((await plan(v, name, backend: 'a1111')).refused, isTrue);
        expect((await plan(v, name, backend: 'drawthings')).refused, isTrue);
      },
    );
  });

  group('a checkpoint that may carry its own encoders', () {
    test(
      'a diffusion-folder safetensors checkpoint names its all-in-one home',
      () {
        expect(
          civitaiAllInOnePath(
            root: root,
            backend: 'comfyui',
            folder: 'diffusion_models',
            modelType: 'Checkpoint',
            name: 'flux1-dev-fp8.safetensors',
          ),
          p.join(root, 'checkpoints', 'flux1-dev-fp8.safetensors'),
        );
      },
    );

    test('nothing else can be one', () {
      String? aio({
        String backend = 'comfyui',
        String folder = 'diffusion_models',
        String type = 'Checkpoint',
        String name = 'a.safetensors',
      }) => civitaiAllInOnePath(
        root: root,
        backend: backend,
        folder: folder,
        modelType: type,
        name: name,
      );
      expect(aio(backend: 'a1111'), isNull);
      expect(aio(folder: 'checkpoints'), isNull);
      expect(aio(type: 'LORA'), isNull);
      expect(aio(name: 'a.gguf'), isNull);
    });
  });

  group('the address', () {
    CivitaiVersionFile file({String? url, bool primary = false}) =>
        CivitaiVersionFile(
          name: 'a.safetensors',
          type: 'Model',
          primary: primary,
          downloadUri: url == null ? null : Uri.parse(url),
        );
    Uri? addr(CivitaiVersionFile f, {bool adult = false}) =>
        civitaiFileDownloadUri(f, versionId: 5, adult: adult);

    test("the file's own address is used when it stays on the host", () {
      final own = 'https://civitai.com/api/download/models/5?fileId=9';
      expect(addr(file(url: own)).toString(), own);
    });

    test(
      'an address on another host, over http, with a port or login, or for another version is not trusted',
      () {
        for (final url in [
          'https://evil.example/api/download/models/5?fileId=9',
          'http://civitai.com/api/download/models/5?fileId=9',
          'https://civitai.com:8443/api/download/models/5?fileId=9',
          'https://user:pw@civitai.com/api/download/models/5?fileId=9',
          'https://civitai.com/api/download/models/6?fileId=9',
          'https://civitai.com/other/path',
          'https://civitai.red/api/download/models/5?fileId=9',
        ]) {
          expect(addr(file(url: url)), isNull, reason: url);
        }
      },
    );

    test(
      'a primary file falls back to the version default, a secondary one does not',
      () {
        expect(
          addr(file(url: 'https://evil.example/x', primary: true)).toString(),
          'https://civitai.com/api/download/models/5',
        );
        expect(addr(file(url: 'https://evil.example/x')), isNull);
        expect(addr(file(primary: true), adult: true)!.host, 'civitai.red');
      },
    );

    test('an adult request never uses a civitai.com address', () async {
      final made = await plan(
        _version(133005),
        'MaouBigV1.2.safetensors',
        lora: true,
        adult: true,
      );
      expect(made.uri!.host, 'civitai.red');
      expect(made.uri!.path, '/api/download/models/133005');
    });
  });

  group('without a key', () {
    test('nothing is planned and no path is reported', () async {
      final made = await plan(
        _version(133005),
        'MaouBigV1.2.safetensors',
        lora: true,
        via: CivitaiRelay(memoryCivitaiStore({})),
      );
      expect(made.refused, isTrue);
      expect(made.failure, CivitaiFailure.keyMissing);
      expect(made.path, isNull);
      expect(made.uri, isNull);
    });
  });

  test('a models folder that is not absolute is refused', () async {
    final made = await relay.planDownload(
      accountId: 'local',
      version: _version(133005),
      filename: 'MaouBigV1.2.safetensors',
      adult: false,
      savedRoot: 'models',
      fromLoraSheet: true,
      backend: 'comfyui',
    );
    expect(made.refused, isTrue);
  });
}
