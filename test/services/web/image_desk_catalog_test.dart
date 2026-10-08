// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What the phone desk is told: the Change graph lists (both modes, from one
// read of the Comfy install), the files a slot can take with the ones that
// look wrong last, what the Ready line judged (Create and Edit are different
// graphs), and the config fields the desk shows. Real routes against a real
// loopback ComfyUI.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'image_desk_harness.dart';

const _createFile =
    'test/fixtures/comfy_templates/image_qwen_image_2_1_t2i.json';
const _editFile =
    'test/fixtures/comfy_templates/image_qwen_image_edit_2509_relight.json';

List<String> _ids(dynamic rows) => [
  for (final row in rows as List) (row as Map)['id'] as String,
];

Map<String, dynamic> _row(dynamic rows, String id) => (rows as List)
    .cast<Map<String, dynamic>>()
    .firstWhere((row) => row['id'] == id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the catalog', () {
    late DeskComfy comfy;
    late DeskHarness h;

    setUp(() async {
      comfy = await DeskComfy.start(
        unet: const ['z_image_turbo_bf16.safetensors'],
        clip: const [
          'qwen_2.5_vl_7b_fp8.safetensors',
          'Qwen3-VL-8B-Instruct-Q4_K_M.gguf',
          'clip_l.safetensors',
        ],
        vae: const ['ae.safetensors', 'qwen_image_2.1_vae_bf16.safetensors'],
        loras: const ['qwen_image_lora.safetensors', 'flux_style.safetensors'],
        saved: {
          'porch_create.json': File(_createFile).readAsStringSync(),
          'porch_edit.json': File(_editFile).readAsStringSync(),
        },
      );
      h = await DeskHarness.boot(comfy: comfy);
    });

    test('reads the saved workflows once, for both lists', () async {
      final (status, _) = await h.call('GET', '/api/image/comfy-catalog');

      expect(status, 200);
      final listings = comfy.requests
          .where((r) => r.startsWith('/userdata?'))
          .toList();
      expect(listings, hasLength(1));
      for (final name in ['porch_create.json', 'porch_edit.json']) {
        expect(
          comfy.requests.where((r) => r == '/userdata/workflows/$name'),
          hasLength(1),
          reason: name,
        );
      }
    });

    test('files a saved graph under the mode it is for', () async {
      final (_, body) = await h.call('GET', '/api/image/comfy-catalog');

      final create = _ids(body['graphs']);
      final edit = _ids(body['editGraphs']);
      expect(create, contains('comfy:userdata:porch_create'));
      expect(create, isNot(contains('comfy:userdata:porch_edit')));
      expect(edit, contains('comfy:userdata:porch_edit'));
      expect(edit, isNot(contains('comfy:userdata:porch_create')));
      expect(
        _row(body['graphs'], 'comfy:userdata:porch_create')['group'],
        'Saved on this Comfy',
      );
      // The built-in graphs come first.
      expect(create.first, isNot(startsWith('comfy:')));
    });

    test(
      'leaves off built-in graphs the model on the desk cannot load',
      () async {
        await h.settings.setComfyCreateWorkflowId('z_image_turbo');
        await h.settings.setComfyCreateModelChoice(
          'z_image_turbo',
          '%MODEL_DIFFUSION%',
          'z_image_turbo_bf16.safetensors',
        );

        final (_, body) = await h.call('GET', '/api/image/comfy-catalog');

        expect(_ids(body['graphs']), contains('z_image_turbo'));
        expect(_ids(body['graphs']), isNot(contains('flux')));
      },
    );

    test(
      'lists the files a slot can take, the odd ones last and named',
      () async {
        await h.settings.setComfyCreateWorkflowId('qwen_image_21');
        await h.settings.setComfyCreateModelChoice(
          'qwen_image_21',
          '%MODEL_DIFFUSION%',
          'qwen-image-2.1-Q2_K.gguf',
        );

        final (_, body) = await h.call(
          'GET',
          '/api/image/comfy-catalog?token=%25MODEL_CLIP%25',
        );

        final slot = body['slotFiles'] as Map<String, dynamic>;
        expect(slot['files'], [
          'Qwen3-VL-8B-Instruct-Q4_K_M.gguf',
          'qwen_2.5_vl_7b_fp8.safetensors',
          'clip_l.safetensors',
        ]);
        expect(slot['unfit'], [
          'qwen_2.5_vl_7b_fp8.safetensors',
          'clip_l.safetensors',
        ]);
      },
    );

    test(
      'filters each list by the model of the mode it is asked for',
      () async {
        await h.settings.setComfyCreateWorkflowId('z_image_turbo');
        await h.settings.setComfyCreateModelChoice(
          'z_image_turbo',
          '%MODEL_DIFFUSION%',
          'z_image_turbo_bf16.safetensors',
        );
        await h.settings.setComfyEditWorkflowId('flux_kontext');
        await h.settings.setComfyEditModelChoice(
          'flux_kontext',
          '%MODEL_DIFFUSION%',
          'flux1-kontext-dev.safetensors',
        );

        final (_, forEdit) = await h.call(
          'GET',
          '/api/image/comfy-catalog?mode=edit',
        );
        final (_, forCreate) = await h.call('GET', '/api/image/comfy-catalog');

        expect(_ids(forEdit['editGraphs']), contains('flux_kontext'));
        expect(_ids(forEdit['graphs']), isNot(contains('z_image_turbo')));
        expect(_ids(forCreate['editGraphs']), isNot(contains('flux_kontext')));
        expect(_ids(forCreate['graphs']), contains('z_image_turbo'));
      },
    );

    test('lists no slot files unless a slot is asked about', () async {
      final (_, body) = await h.call('GET', '/api/image/comfy-catalog');
      expect(body.containsKey('slotFiles'), isFalse);
    });

    test('names each LoRA\'s base only when asked', () async {
      final (_, plain) = await h.call('GET', '/api/image/comfy-catalog');
      expect(plain.containsKey('loraFacts'), isFalse);

      final (_, asked) = await h.call('GET', '/api/image/comfy-catalog?lora=1');
      final facts = {
        for (final f in asked['loraFacts'] as List)
          (f as Map)['file']: f['family'],
      };
      expect(facts['qwen_image_lora.safetensors'], 'qwen');
      expect(facts['flux_style.safetensors'], 'flux');
    });

    test('still lists what the older forms read', () async {
      final (_, body) = await h.call('GET', '/api/image/comfy-catalog');

      expect(body['diffusionModels'], ['z_image_turbo_bf16.safetensors']);
      expect(body['textEncoders'], hasLength(3));
      expect(body['vaes'], hasLength(2));
      expect(body['loras'], hasLength(2));
      expect(body['deskDiscovery'], contains('z_image_turbo_bf16.safetensors'));
      expect(
        (body['templates'] as List).map((t) => (t as Map)['id']),
        contains('comfy:userdata:porch_create'),
      );
      expect(
        (body['editTemplates'] as List).map((t) => (t as Map)['id']),
        contains('comfy:userdata:porch_edit'),
      );
    });
  });

  group('what Ready judged', () {
    late DeskHarness h;

    setUp(() async {
      final comfy = await DeskComfy.start(
        unet: const ['z_image_turbo_bf16.safetensors'],
        clip: const ['qwen_3_4b.safetensors'],
        vae: const ['ae.safetensors'],
      );
      h = await DeskHarness.boot(comfy: comfy);
      final s = h.settings;
      await s.setComfyCreateWorkflowId('z_image_turbo');
      await s.setComfyCreateModelChoice(
        'z_image_turbo',
        '%MODEL_DIFFUSION%',
        'z_image_turbo_bf16.safetensors',
      );
      await s.setComfyCreateModelChoice(
        'z_image_turbo',
        '%MODEL_CLIP%',
        'qwen_3_4b.safetensors',
      );
      await s.setComfyEditWorkflowId('qwen_image_edit');
      await s.setComfyEditModelChoice(
        'qwen_image_edit',
        '%MODEL_DIFFUSION%',
        'qwen_image_edit_2509_fp8.safetensors',
      );
    });

    test('Create and Edit are judged separately', () async {
      final (_, create) = await h.call(
        'GET',
        '/api/image/studio/ready?mode=create',
      );
      final (_, edit) = await h.call(
        'GET',
        '/api/image/studio/ready?mode=edit',
      );

      expect(create['mode'], 'create');
      expect(create['workflowId'], 'z_image_turbo');
      expect(create['primary'], 'z_image_turbo_bf16.safetensors');
      expect(edit['mode'], 'edit');
      expect(edit['workflowId'], 'qwen_image_edit');
      expect(edit['primary'], 'qwen_image_edit_2509_fp8.safetensors');
    });

    test('lists the slots the graph has, with the file in each', () async {
      final (_, create) = await h.call(
        'GET',
        '/api/image/studio/ready?mode=create',
      );

      final slots = {
        for (final slot in create['slots'] as List)
          (slot as Map)['token']: slot['file'],
      };
      expect(slots['%MODEL_DIFFUSION%'], 'z_image_turbo_bf16.safetensors');
      expect(slots['%MODEL_CLIP%'], 'qwen_3_4b.safetensors');
      expect(slots.containsKey('%MODEL_VAE%'), isTrue);
      expect(slots['%MODEL_VAE%'], '');
    });

    test('names an uploaded graph and counts its nodes', () async {
      await h.settings.setComfyCreateWorkflowId('__uploaded__');
      await h.settings.setComfyCreateUploadedWorkflow(
        jsonEncode({
          'a': {'class_type': 'KSampler', 'inputs': <String, dynamic>{}},
          'b': {'class_type': 'VAEDecode', 'inputs': <String, dynamic>{}},
        }),
        title: 'porch.json',
      );

      final (_, create) = await h.call(
        'GET',
        '/api/image/studio/ready?mode=create',
      );

      expect(create['uploadedTitle'], 'porch.json');
      expect(create['uploadedNodes'], 2);
    });
  });

  group('the config', () {
    late DeskHarness h;

    setUp(() async {
      h = await DeskHarness.boot(comfy: await DeskComfy.start());
    });

    test('carries what the desk shows', () async {
      final (_, config) = await h.call('GET', '/api/image/config');

      expect(config.containsKey('editModel'), isTrue);
      expect(config['drawThingsSampler'], 16);
      expect(config.containsKey('comfyCreateUploadedTitle'), isTrue);
      expect(config.containsKey('comfyEditUploadedTitle'), isTrue);
      expect(config.containsKey('genProgress'), isTrue);
      expect(config['genProgress'], isNull);
      expect(config['drawThingsPort'], isA<int>());
    });

    test('says whether adult CivitAI results are allowed', () async {
      final (_, off) = await h.call('GET', '/api/image/config');
      await h.storage.realismSettings.setAdultThemesEnabled(true);
      final (_, on) = await h.call('GET', '/api/image/config');

      expect(off['adultAllowed'], isFalse);
      expect(on['adultAllowed'], isTrue);
    });

    test(
      'lists the Draw Things samplers by the desktop\'s wire values',
      () async {
        final (_, config) = await h.call('GET', '/api/image/config');

        final samplers = (config['drawThingsSamplers'] as List)
            .cast<Map<String, dynamic>>();
        expect(samplers.first, {'label': 'DDIM Trailing', 'value': 16});
        expect(samplers.map((s) => s['value']).toSet(), hasLength(19));
      },
    );

    test('snaps a size to multiples of 64 within 256 to 2048', () async {
      final (_, snapped) = await h.call('POST', '/api/image/config', {
        'size': '300x1000',
      });
      final (_, clamped) = await h.call('POST', '/api/image/config', {
        'size': '9000x100',
      });
      final (_, odd) = await h.call('POST', '/api/image/config', {
        'size': 'wide',
      });

      expect(snapped['size'], '320x1024');
      expect(clamped['size'], '2048x256');
      expect(odd['size'], 'wide');
    });

    test('takes the Edit model and the Draw Things sampler', () async {
      final (status, config) = await h.call('POST', '/api/image/config', {
        'editModel': 'qwen_image_edit_2509_fp8.safetensors',
        'drawThingsSampler': 10,
      });

      expect(status, 200);
      expect(config['editModel'], 'qwen_image_edit_2509_fp8.safetensors');
      expect(config['drawThingsSampler'], 10);
      expect(h.settings.drawThingsSampler, 10);
    });

    test(
      'moving the Draw Things port needs the password, like the host',
      () async {
        // The port decides where a host is dialled, so it is as sensitive as
        // the host itself (this used to be writable without the password).
        final (port, _) = await h.call('POST', '/api/image/config', {
          'drawThingsPort': 7860,
        });
        final (host, _) = await h.call('POST', '/api/image/config', {
          'drawThingsHost': 'elsewhere.example',
        });
        final (steppedUp, _) = await h.call('POST', '/api/image/config', {
          'drawThingsPort': 7860,
          'currentPassword': kDeskPassword,
        });

        expect(port, 401);
        expect(host, 401);
        expect(steppedUp, 200);
        expect(h.settings.drawThingsGrpcPort, 7860);
      },
    );
  });

  group('"Use anyway"', () {
    late DeskHarness h;
    const key = 'image_studio_lora_override_family';

    setUp(() async {
      final comfy = await DeskComfy.start(
        unet: const ['z_image_turbo_bf16.safetensors'],
      );
      h = await DeskHarness.boot(comfy: comfy, realPrefs: true);
      await h.settings.setComfyCreateWorkflowId('z_image_turbo');
      await h.settings.setComfyCreateModelChoice(
        'z_image_turbo',
        '%MODEL_DIFFUSION%',
        'z_image_turbo_bf16.safetensors',
      );
    });

    String? stored() => h.settings.prefs?.getString(h.settings.k(key));

    test('is stored for the family it was pressed for', () async {
      final (status, _) = await h.call('POST', '/api/image/config', {
        'loraOverrideFamily': 'zImage',
      });

      expect(status, 200);
      expect(stored(), 'zImage');
    });

    test('is kept when the model changes within that family', () async {
      await h.call('POST', '/api/image/config', {
        'loraOverrideFamily': 'zImage',
      });

      await h.call('POST', '/api/image/studio/pick', {
        'kind': 'model',
        'mode': 'create',
        'file': 'z_image_turbo_fp8.safetensors',
      });

      expect(stored(), 'zImage');
    });

    test(
      'pressed for the other mode\'s family is kept by a pick that changes nothing',
      () async {
        // Pressed on the Edit desk, for a Qwen model; Create picks another
        // Z-Image file and stays a Z-Image model.
        await h.call('POST', '/api/image/config', {
          'loraOverrideFamily': 'qwen',
        });

        await h.call('POST', '/api/image/studio/pick', {
          'kind': 'model',
          'mode': 'create',
          'file': 'z_image_turbo_fp8.safetensors',
        });

        expect(stored(), 'qwen');
      },
    );

    test('is dropped when the model changes to another family', () async {
      await h.call('POST', '/api/image/config', {
        'loraOverrideFamily': 'zImage',
      });

      await h.call('POST', '/api/image/studio/pick', {
        'kind': 'model',
        'mode': 'create',
        'file': 'flux1-dev-fp8.safetensors',
      });

      expect(stored(), isNull);
    });
  });
}
