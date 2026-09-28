import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/comfy_catalog.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/services/image/studio_desk_logic.dart';
import 'package:front_porch_ai/services/image/studio_readiness.dart';

void main() {
  test('GGUF unet names stay out of the older diffusion list', () {
    final catalog = assembleComfyCatalog(
      checkpoints: const ['sdxl.safetensors'],
      unetNames: const ['z_image_turbo_bf16.safetensors'],
      ggufNames: const ['model.gguf'],
      ggufAdvancedNames: const ['model.gguf', 'other.gguf'],
      textEncoders: const ['qwen_3_4b.safetensors'],
      vaes: const ['ae.safetensors'],
      loras: const [],
    );
    expect(catalog.diffusionModels, ['z_image_turbo_bf16.safetensors']);
    expect(catalog.ggufUnets, ['model.gguf', 'other.gguf']);
    expect(catalog.createDiscovery, [
      'sdxl.safetensors',
      'z_image_turbo_bf16.safetensors',
    ]);
    expect(catalog.deskDiscovery, [
      'sdxl.safetensors',
      'z_image_turbo_bf16.safetensors',
      'model.gguf',
      'other.gguf',
    ]);
    final source = File(
      'lib/services/comfy_ui_service.catalog.dart',
    ).readAsStringSync();
    expect(source.contains('assembleComfyCatalog'), isTrue);
    expect(source.contains('unetNames:'), isTrue);
    expect(source.contains('diffusionModels: diffusion'), isFalse);
  });

  test('a title that is both tasks is on neither graph list', () {
    const both = DeskGraphRow('both', 'Text to Image Image Edit');
    expect(
      deskGraphChoices(edit: false, live: const [both]),
      isNot(contains('both')),
    );
    expect(
      deskGraphChoices(edit: true, live: const [both]),
      isNot(contains('both')),
    );
    expect(
      deskGraphChoices(
        edit: false,
        live: const [DeskGraphRow('zit', 'Z Image Text to Image')],
      ),
      contains('zit'),
    );
    expect(
      deskGraphChoices(edit: true, live: const []),
      containsAll(['qwen_image_edit', 'flux_kontext']),
    );
  });

  const zitClasses = [
    'UNETLoader',
    'CLIPLoader',
    'VAELoader',
    'CLIPTextEncode',
    'ConditioningZeroOut',
    'EmptySD3LatentImage',
    'ModelSamplingAuraFlow',
    'KSampler',
    'VAEDecode',
    'SaveImage',
  ];

  Map<String, dynamic> zitInfo() => {
    for (final name in zitClasses) name: <String, dynamic>{},
  };

  test('a Z-Image run does not become ready from a leftover checkpoint', () {
    final ready = deskReadiness(
      backend: 'comfyui',
      primaryFile: 'qwen_image.safetensors',
      objectInfo: zitInfo(),
      workflowId: 'z_image_turbo',
    );
    expect(ready.kind, StudioReady.missingFile);
    expect(generateEnabled(ready), isFalse);
  });

  test('a filled Z-Image workflow is ready when its classes are installed', () {
    final ready = deskReadiness(
      backend: 'comfyui',
      primaryFile: 'z_image_turbo_bf16.safetensors',
      objectInfo: zitInfo(),
      workflowId: 'z_image_turbo',
      modelChoices: const {
        'z_image_turbo/%MODEL_DIFFUSION%': 'z_image_turbo_bf16.safetensors',
        'z_image_turbo/%MODEL_CLIP%': 'qwen_3_4b.safetensors',
        'z_image_turbo/%MODEL_VAE%': 'ae.safetensors',
      },
    );
    expect(ready.kind, StudioReady.ready);
  });

  test('an unread catalog is unreachable, not a missing class', () {
    final ready = deskReadiness(
      backend: 'comfyui',
      primaryFile: 'z_image_turbo_bf16.safetensors',
      objectInfo: null,
      workflowId: 'z_image_turbo',
    );
    expect(ready.kind, StudioReady.unreachable);
  });

  test('a GGUF file on a template asks for the GGUF loader', () {
    final ready = deskReadiness(
      backend: 'comfyui',
      primaryFile: 'model.gguf',
      objectInfo: const {
        'UNETLoader': <String, dynamic>{},
        'CLIPTextEncode': <String, dynamic>{},
      },
      workflowId: 'comfy:default:custom',
      liveTemplate: const {
        'unet': {
          'class_type': 'UNETLoader',
          'inputs': {'unet_name': '%MODEL_DIFFUSION%'},
        },
        'txt': {
          'class_type': 'CLIPTextEncode',
          'inputs': {'text': '%PROMPT%'},
        },
      },
    );
    expect(ready.kind, StudioReady.missingNodeClass);
    expect(ready.missingClass, 'UnetLoaderGGUF');
  });

  test('an uploaded graph is not retargeted onto a GGUF loader', () {
    const graph = {
      'unet': {
        'class_type': 'UNETLoader',
        'inputs': {'unet_name': '%MODEL_DIFFUSION%'},
      },
      'txt': {
        'class_type': 'CLIPTextEncode',
        'inputs': {'text': '%PROMPT%'},
      },
    };
    final ready = deskReadiness(
      backend: 'comfyui',
      primaryFile: 'model.gguf',
      objectInfo: const {
        'UNETLoader': <String, dynamic>{},
        'CLIPTextEncode': <String, dynamic>{},
      },
      workflowId: '__uploaded__',
      uploadedWorkflowJson: jsonEncode(graph),
      modelChoices: const {'__uploaded__/%MODEL_DIFFUSION%': 'model.gguf'},
    );
    expect(ready.kind, StudioReady.ready);
  });

  test('a GGUF text encoder is not ready on a plain CLIP loader', () {
    final ready = deskReadiness(
      backend: 'comfyui',
      primaryFile: 'model.safetensors',
      objectInfo: const {
        'UNETLoader': <String, dynamic>{},
        'CLIPLoader': <String, dynamic>{},
        'CLIPTextEncode': <String, dynamic>{},
      },
      workflowId: 'comfy:default:custom',
      modelChoices: const {
        'comfy:default:custom/%MODEL_DIFFUSION%': 'model.safetensors',
        'comfy:default:custom/%MODEL_CLIP%': 'encoder.gguf',
      },
      liveTemplate: const {
        'unet': {
          'class_type': 'UNETLoader',
          'inputs': {'unet_name': '%MODEL_DIFFUSION%'},
        },
        'clip': {
          'class_type': 'CLIPLoader',
          'inputs': {'clip_name': '%MODEL_CLIP%'},
        },
        'txt': {
          'class_type': 'CLIPTextEncode',
          'inputs': {
            'text': '%PROMPT%',
            'clip': ['clip', 0],
          },
        },
      },
    );
    expect(ready.kind, StudioReady.missingNodeClass);
    expect(ready.missingClass, 'CLIPLoaderGGUF');
    expect(generateEnabled(ready), isFalse);
  });

  test('a GGUF file on the SD checkpoint graph is not ready', () {
    final ready = deskReadiness(
      backend: 'comfyui',
      primaryFile: 'model.gguf',
      objectInfo: const {
        'CheckpointLoaderSimple': <String, dynamic>{},
        'UnetLoaderGGUF': <String, dynamic>{},
        'CLIPTextEncode': <String, dynamic>{},
        'EmptyLatentImage': <String, dynamic>{},
        'KSampler': <String, dynamic>{},
        'VAEDecode': <String, dynamic>{},
        'SaveImage': <String, dynamic>{},
      },
      workflowId: 'sd',
      modelChoices: const {'sd/%MODEL_DIFFUSION%': 'model.gguf'},
    );
    expect(ready.kind, StudioReady.needsUnetGraph);
    expect(generateEnabled(ready), isFalse);
  });

  test('a checkpoint is not selected on a diffusion workflow', () {
    expect(
      deskAcceptsInstalledFile(
        backend: 'comfyui',
        workflowId: 'z_image_turbo',
        file: 'sdxl.safetensors',
        lora: false,
        checkpoints: const ['sdxl.safetensors'],
        diffusionModels: const ['z_image_turbo_bf16.safetensors'],
        ggufUnets: const [],
        loras: const [],
      ),
      isFalse,
    );
    expect(
      deskAcceptsInstalledFile(
        backend: 'comfyui',
        workflowId: 'z_image_turbo',
        file: 'z_image_turbo_bf16.safetensors',
        lora: false,
        checkpoints: const ['sdxl.safetensors'],
        diffusionModels: const ['z_image_turbo_bf16.safetensors'],
        ggufUnets: const [],
        loras: const [],
      ),
      isTrue,
    );
  });

  test('a metadata-certain LoRA mismatch keeps Generate off', () {
    final blocked = deskReadiness(
      backend: 'a1111',
      primaryFile: 'z_image_turbo_bf16.safetensors',
      objectInfo: null,
      loras: const [
        DeskLoraCheck(
          'qwen_lora.safetensors',
          ModelFamily.qwen,
          metadataBacked: true,
        ),
      ],
    );
    expect(blocked.kind, StudioReady.loraMismatch);
    expect(generateEnabled(blocked), isFalse);

    final namedOnly = deskReadiness(
      backend: 'a1111',
      primaryFile: 'z_image_turbo_bf16.safetensors',
      objectInfo: null,
      loras: const [DeskLoraCheck('qwen_lora.safetensors', ModelFamily.qwen)],
    );
    expect(namedOnly.kind, StudioReady.ready);
  });
}
