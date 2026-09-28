import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/comfy_gguf_loaders.dart';
import 'package:front_porch_ai/services/image/image_job.dart';
import 'package:front_porch_ai/services/image/model_family.dart';
import 'package:front_porch_ai/services/image/studio_dispatch.dart';
import 'package:front_porch_ai/services/image/studio_readiness.dart';
import 'package:front_porch_ai/services/image/studio_support_copy.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

void main() {
  const starter = {
    'unet': {
      'class_type': 'UNETLoader',
      'inputs': {'unet_name': '%MODEL_DIFFUSION%'},
    },
  };

  test('a gguf file is not submitted through UNETLoader', () {
    final info = {
      'UnetLoaderGGUF': {
        'input': {
          'required': {'unet_name': <Object>[]},
        },
      },
    };
    final result = retargetForFile(
      graph: starter,
      primaryFile: 'z-image-turbo-Q5_K_M.gguf',
      uploaded: false,
      objectInfo: info,
    );
    expect(result.missingClass, isNull);
    expect(result.unreachable, isFalse);
    expect(graphUsesLoader(result.graph, 'UNETLoader'), isFalse);
    expect(graphUsesLoader(result.graph, 'UnetLoaderGGUF'), isTrue);
  });

  test('a missing gguf unet class is rewritten to the installed one', () {
    final result = retargetForFile(
      graph: {
        'unet': {
          'class_type': 'UnetLoaderGGUF',
          'inputs': {'unet_name': 'model.gguf', 'weight_dtype': 'default'},
        },
      },
      primaryFile: 'model.gguf',
      uploaded: false,
      objectInfo: {
        'UnetLoaderGGUFAdvanced': {
          'input': {
            'required': {
              'unet_name': <Object>[],
              'dequant_dtype': [
                ['default', 'target', 'float32'],
              ],
              'patch_dtype': [
                ['default', 'target'],
              ],
              'patch_on_device': [
                'BOOLEAN',
                {'default': false},
              ],
            },
          },
        },
      },
    );
    final node = result.graph['unet'] as Map;
    final inputs = node['inputs'] as Map;
    expect(node['class_type'], 'UnetLoaderGGUFAdvanced');
    expect(inputs['unet_name'], 'model.gguf');
    expect(inputs['dequant_dtype'], 'default');
    expect(inputs['patch_dtype'], 'default');
    expect(inputs['patch_on_device'], isFalse);
    expect(inputs.containsKey('weight_dtype'), isFalse);
    expect(result.missingClass, isNull);
  });

  test('a gguf loader with no default for a required input is not swapped', () {
    final result = retargetForFile(
      graph: {
        'unet': {
          'class_type': 'UnetLoaderGGUF',
          'inputs': {'unet_name': 'model.gguf'},
        },
      },
      primaryFile: 'model.gguf',
      uploaded: false,
      objectInfo: {
        'OddUnetGGUF': {
          'input': {
            'required': {
              'unet_name': <Object>[],
              'device': ['STRING'],
            },
          },
        },
      },
    );
    final node = result.graph['unet'] as Map;
    expect(node['class_type'], 'UnetLoaderGGUF');
    expect(result.missingClass, 'OddUnetGGUF');
  });

  test('a gguf diffusion node without unet in its name is still rewritten', () {
    final result = retargetForFile(
      graph: {
        'unet': {
          'class_type': 'LoaderGGUF',
          'inputs': {'unet_name': 'model.gguf'},
        },
      },
      primaryFile: 'model.gguf',
      uploaded: false,
      objectInfo: {
        'UnetLoaderGGUF': {
          'input': {
            'required': {'unet_name': <Object>[]},
          },
        },
      },
    );
    expect(graphUsesLoader(result.graph, 'UnetLoaderGGUF'), isTrue);
    expect(result.missingClass, isNull);
  });

  test('a COMBO options list fills a required input', () {
    final result = retargetForFile(
      graph: {
        'unet': {
          'class_type': 'UNETLoader',
          'inputs': {'unet_name': 'model.gguf'},
        },
      },
      primaryFile: 'model.gguf',
      uploaded: false,
      objectInfo: {
        'UnetLoaderGGUFAdvanced': {
          'input': {
            'required': {
              'unet_name': <Object>[],
              'dequant_dtype': [
                'COMBO',
                {
                  'options': ['default', 'target'],
                },
              ],
            },
          },
        },
      },
    );
    final node = result.graph['unet'] as Map;
    expect(node['class_type'], 'UnetLoaderGGUFAdvanced');
    expect((node['inputs'] as Map)['dequant_dtype'], 'default');
    expect(result.missingClass, isNull);
  });

  test('each diffusion node follows its own file', () {
    final info = {
      'UnetLoaderGGUF': {
        'input': {
          'required': {'unet_name': <Object>[]},
        },
      },
      'UNETLoader': {
        'input': {
          'required': {
            'unet_name': <Object>[],
            'weight_dtype': [
              ['default', 'fp8_e4m3fn'],
            ],
          },
        },
      },
    };
    final mixed = retargetForFile(
      graph: {
        'main': {
          'class_type': 'UNETLoader',
          'inputs': {'unet_name': 'model.gguf', 'weight_dtype': 'default'},
        },
        'refiner': {
          'class_type': 'UNETLoader',
          'inputs': {
            'unet_name': 'refiner.safetensors',
            'weight_dtype': 'default',
          },
        },
      },
      primaryFile: 'model.gguf',
      uploaded: false,
      objectInfo: info,
    );
    expect((mixed.graph['main'] as Map)['class_type'], 'UnetLoaderGGUF');
    expect((mixed.graph['refiner'] as Map)['class_type'], 'UNETLoader');
    final reverse = retargetForFile(
      graph: {
        'main': {
          'class_type': 'UNETLoader',
          'inputs': {'unet_name': 'model.safetensors'},
        },
        'side': {
          'class_type': 'UnetLoaderGGUF',
          'inputs': {'unet_name': 'side.gguf'},
        },
      },
      primaryFile: 'model.safetensors',
      uploaded: false,
      objectInfo: info,
    );
    expect((reverse.graph['main'] as Map)['class_type'], 'UNETLoader');
    expect((reverse.graph['side'] as Map)['class_type'], 'UnetLoaderGGUF');
  });

  test('a safetensors file is not submitted through a GGUF loader', () {
    final result = retargetForFile(
      graph: {
        'unet': {'class_type': 'UnetLoaderGGUF', 'inputs': {}},
      },
      primaryFile: 'z_image_turbo_bf16.safetensors',
      uploaded: false,
      objectInfo: {'UNETLoader': {}},
    );
    expect(graphUsesLoader(result.graph, 'UnetLoaderGGUF'), isFalse);
    expect(graphUsesLoader(result.graph, 'UNETLoader'), isTrue);
  });

  test('an uploaded graph is not retargeted', () {
    final original = {
      'unet': {'class_type': 'UNETLoader', 'inputs': {}},
    };
    final result = retargetForFile(
      graph: original,
      primaryFile: 'model.gguf',
      uploaded: true,
      objectInfo: {'UnetLoaderGGUF': {}},
    );
    expect(result.graph['unet']['class_type'], 'UNETLoader');
  });

  test(
    'no GGUF loader is a missing class, and a null catalog is unreachable',
    () {
      final missing = retargetForFile(
        graph: starter,
        primaryFile: 'model.gguf',
        uploaded: false,
        objectInfo: {'UNETLoader': {}},
      );
      expect(missing.missingClass, 'UnetLoaderGGUF');
      final unread = retargetForFile(
        graph: starter,
        primaryFile: 'model.gguf',
        uploaded: false,
        objectInfo: null,
      );
      expect(unread.unreachable, isTrue);
      expect(unread.missingClass, isNull);
      expect(
        studioReady(
          objectInfo: null,
          requiredClasses: ['UNETLoader'],
          files: {'diffusion': 'model.safetensors'},
        ).kind,
        StudioReady.unreachable,
      );
      expect(
        generateEnabled(
          studioReady(
            objectInfo: {'UNETLoader': {}},
            requiredClasses: ['UNETLoader'],
            files: {'diffusion': ''},
          ),
        ),
        isFalse,
      );
      expect(
        studioReady(
          objectInfo: {},
          requiredClasses: ['UNETLoader'],
          files: {'diffusion': 'model.safetensors'},
        ).missingClass,
        'UNETLoader',
      );
    },
  );

  test('a mixed create and edit title is not a Create row', () {
    expect(
      isCreateTemplateTitle('Flux.2 Klein 9B: Text to Image Image Edit'),
      isFalse,
    );
    expect(isCreateTemplateTitle('Z-Image-Turbo: Text to Image'), isTrue);
  });

  test('support copy stays inside one section and keeps a changed encoder', () {
    const stored = {
      'z_image_turbo/%MODEL_CLIP%': 'qwen_3_4b.safetensors',
      'qwen_image_edit/%MODEL_CLIP%': 'other_clip.safetensors',
      'image_z_image_turbo/%MODEL_CLIP%': 'changed_clip.safetensors',
    };
    final first = copySupportForStem(
      newWorkflowId: 'image_z_image_turbo',
      previousWorkflowId: '',
      legacyWorkflowId: 'z_image_turbo',
      stored: stored,
    );
    expect(first['%MODEL_CLIP%'], 'changed_clip.safetensors');
    final fromLegacy = copySupportForStem(
      newWorkflowId: 'image_z_image_turbo',
      previousWorkflowId: '',
      legacyWorkflowId: 'z_image_turbo',
      stored: {
        'z_image_turbo/%MODEL_CLIP%': 'qwen_3_4b.safetensors',
        'qwen_image_edit/%MODEL_CLIP%': 'other_clip.safetensors',
      },
    );
    expect(fromLegacy['%MODEL_CLIP%'], 'qwen_3_4b.safetensors');
    final nextStem = copySupportForStem(
      newWorkflowId: 'image_z_image_turbo_int8',
      previousWorkflowId: 'image_z_image_turbo',
      legacyWorkflowId: 'z_image_turbo',
      stored: stored,
    );
    expect(nextStem['%MODEL_CLIP%'], 'changed_clip.safetensors');
  });

  test('the run family is the diffusion file, not the text encoder', () {
    expect(
      familyForRun(
        primaryFile: 'z_image_turbo_bf16.safetensors',
        textEncoder: 'qwen_3_4b.safetensors',
      ),
      ModelFamily.zImage,
    );
  });

  test('a png with no workflow text is refused', () {
    expect(pngWorkflowText({}), isNull);
    expect(
      pngWorkflowText({'prompt': '   ', 'workflow': '{"1":{}}'}),
      isNotNull,
    );
    expect(pngWorkflowText({'prompt': 'not json'}), isNull);
  });

  test('draw things is not sent on the automatic1111 http path', () {
    expect(studioTransport('drawthings'), 'grpc:7859');
    expect(studioTransport('drawthings'), isNot(studioTransport('a1111')));
    expect(studioTransport('comfyui'), 'http:comfy');
    expect(studioTransport('remote'), 'http:remote');
    expect(studioTransport('typo'), isNull);
  });

  test(
    'a gguf text encoder is retargeted even when the diffusion file is not',
    () {
      final result = retargetForFile(
        graph: {
          'clip': {
            'class_type': 'CLIPLoader',
            'inputs': {'clip_name': 'qwen_3_4b.gguf'},
          },
        },
        primaryFile: 'z_image_turbo_bf16.safetensors',
        uploaded: false,
        objectInfo: {
          'CLIPLoader': {},
          'CLIPLoaderGGUF': {
            'input': {
              'required': {'clip_name': <Object>[]},
            },
          },
        },
      );
      expect(graphUsesLoader(result.graph, 'CLIPLoaderGGUF'), isTrue);
    },
  );

  test(
    'one gguf clip in a dual loader switches the node and a missing class blocks',
    () {
      final mixed = retargetForFile(
        graph: {
          'clip': {
            'class_type': 'DualCLIPLoader',
            'inputs': {
              'clip_name1': 'clip_l.safetensors',
              'clip_name2': 't5.gguf',
            },
          },
        },
        primaryFile: 'flux.safetensors',
        uploaded: false,
        objectInfo: {
          'DualCLIPLoaderGGUF': {
            'input': {
              'required': {'clip_name1': <Object>[], 'clip_name2': <Object>[]},
            },
          },
        },
      );
      expect(graphUsesLoader(mixed.graph, 'DualCLIPLoaderGGUF'), isTrue);
      final mixedNode = mixed.graph['clip'] as Map;
      final mixedInputs = mixedNode['inputs'] as Map;
      expect(mixedInputs['clip_name1'], 'clip_l.safetensors');
      expect(mixedInputs['clip_name2'], 't5.gguf');
      final missing = retargetForFile(
        graph: {
          'clip': {
            'class_type': 'CLIPLoader',
            'inputs': {'clip_name': 'qwen.gguf'},
          },
        },
        primaryFile: 'model.safetensors',
        uploaded: false,
        objectInfo: {'CLIPLoader': {}},
      );
      expect(missing.missingClass, 'CLIPLoaderGGUF');
    },
  );

  test('a gguf clip swap drops inputs the new class does not take', () {
    final result = retargetForFile(
      graph: {
        'clip': {
          'class_type': 'CLIPLoader',
          'inputs': {
            'clip_name': 'qwen.gguf',
            'type': 'lumina2',
            'device': 'default',
          },
        },
      },
      primaryFile: 'model.gguf',
      uploaded: false,
      objectInfo: {
        'CLIPLoaderGGUF': {
          'input': {
            'required': {
              'clip_name': <Object>[],
              'type': [
                ['stable_diffusion', 'lumina2'],
                {'default': 'stable_diffusion'},
              ],
            },
          },
        },
      },
    );
    final node = result.graph['clip'] as Map;
    final inputs = node['inputs'] as Map;
    expect(node['class_type'], 'CLIPLoaderGGUF');
    expect(inputs['clip_name'], 'qwen.gguf');
    expect(inputs['type'], 'lumina2');
    expect(inputs.containsKey('device'), isFalse);
  });

  test('an already-gguf clip loader missing from the catalog is named', () {
    final missing = retargetForFile(
      graph: {
        'clip': {
          'class_type': 'CLIPLoaderGGUF',
          'inputs': {'clip_name': 'qwen.gguf'},
        },
      },
      primaryFile: 'model.safetensors',
      uploaded: false,
      objectInfo: {'CLIPLoader': {}},
    );
    expect(missing.missingClass, 'CLIPLoaderGGUF');
    expect(graphUsesLoader(missing.graph, 'CLIPLoaderGGUF'), isTrue);
  });

  test('two safetensors clips switch a gguf dual loader back', () {
    final result = retargetForFile(
      graph: {
        'clip': {
          'class_type': 'DualCLIPLoaderGGUF',
          'inputs': {
            'clip_name1': 'clip_l.safetensors',
            'clip_name2': 't5xxl.safetensors',
          },
        },
      },
      primaryFile: 'flux.safetensors',
      uploaded: false,
      objectInfo: {
        'DualCLIPLoader': {},
        'DualCLIPLoaderGGUF': {
          'input': {
            'required': {'clip_name1': <Object>[]},
          },
        },
      },
    );
    expect(graphUsesLoader(result.graph, 'DualCLIPLoader'), isTrue);
    expect(result.missingClass, isNull);
  });

  test('a vision loader is not treated as a text encoder', () {
    final result = retargetForFile(
      graph: {
        'vision': {
          'class_type': 'CLIPVisionLoader',
          'inputs': {'clip_name': 'siglip.gguf'},
        },
      },
      primaryFile: 'model.safetensors',
      uploaded: false,
      objectInfo: {'CLIPVisionLoader': {}},
    );
    expect(graphUsesLoader(result.graph, 'CLIPVisionLoader'), isTrue);
    expect(result.missingClass, isNull);
  });

  test('switching an advanced gguf unet back drops its extra inputs', () {
    final result = retargetForFile(
      graph: {
        'unet': {
          'class_type': 'UnetLoaderGGUFAdvanced',
          'inputs': {
            'unet_name': 'model.safetensors',
            'dequant_dtype': 'default',
            'patch_dtype': 'default',
            'patch_on_device': false,
          },
        },
      },
      primaryFile: 'model.safetensors',
      uploaded: false,
      objectInfo: {
        'UnetLoaderGGUFAdvanced': {
          'input': {
            'required': {'unet_name': <Object>[]},
          },
        },
        'UNETLoader': {
          'input': {
            'required': {
              'unet_name': <Object>[],
              'weight_dtype': [
                ['default', 'fp8_e4m3fn'],
              ],
            },
          },
        },
      },
    );
    final node = result.graph['unet'] as Map;
    final inputs = node['inputs'] as Map;
    expect(node['class_type'], 'UNETLoader');
    expect(inputs['unet_name'], 'model.safetensors');
    expect(inputs['weight_dtype'], 'default');
    expect(inputs.containsKey('dequant_dtype'), isFalse);
    expect(inputs.containsKey('patch_on_device'), isFalse);
  });

  test('switching a gguf unet back adds weight_dtype', () {
    final result = retargetForFile(
      graph: {
        'unet': {
          'class_type': 'UnetLoaderGGUF',
          'inputs': {'unet_name': 'model.safetensors'},
        },
      },
      primaryFile: 'model.safetensors',
      uploaded: false,
      objectInfo: {
        'UnetLoaderGGUF': {
          'input': {
            'required': {'unet_name': <Object>[]},
          },
        },
        'UNETLoader': {},
      },
    );
    final node = result.graph['unet'] as Map;
    expect(node['class_type'], 'UNETLoader');
    expect((node['inputs'] as Map)['weight_dtype'], 'default');
  });

  test('a second pack start does not call the driver', () async {
    final dir = Directory.systemTemp.createTempSync('fp-pack');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = StorageService.sandbox(dir.path);
    final service = ImageGenService(storage);
    var driverCalls = 0;
    final first = service.startExpressionPack(['smile'], (emotions) async {
      driverCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return ['smile.png'];
    });
    final second = await service.startExpressionPack(['anger'], (
      emotions,
    ) async {
      driverCalls++;
      return ['anger.png'];
    });
    expect(second, isNull);
    expect(service.statusMessage, kAlreadyGeneratingMessage);
    expect(await first, ['smile.png']);
    expect(driverCalls, 1);
  });
}
