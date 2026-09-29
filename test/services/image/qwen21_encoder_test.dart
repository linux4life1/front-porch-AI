// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/comfy_catalog.dart';
import 'package:front_porch_ai/services/image/comfy_create_presets.dart';
import 'package:front_porch_ai/services/image/comfy_edit_workflow.dart';
import 'package:front_porch_ai/services/image/comfy_gguf_loaders.dart';
import 'package:front_porch_ai/services/image/image_submit_error.dart';
import 'package:front_porch_ai/services/image/studio_support_fit.dart';
import 'package:front_porch_ai/ui/image_studio/studio_desk_copy.dart';

void main() {
  const primary = 'qwen-image-2.1-Q2_K.gguf';
  const vl = 'Qwen3-VL-8B-Instruct-Q2_K.gguf';
  const installed = [
    'Meta-Llama-3.1-8B-Instruct-Q2_K.gguf',
    'Qwen3-4B-Q2_K.gguf',
    vl,
    'clip_g.safetensors',
    'clip_l.safetensors',
    'mmproj-Qwen3-VL-8B-Instruct-F16.gguf',
    'qwen_3_4b.safetensors',
    't5-v1_1-xxl-encoder-Q3_K_S.gguf',
    'qwen_2.5_vl_7b.safetensors',
    'qwen3.5_9b_qwen_image_2.1_pe_t2i.int8_convrot.safetensors',
  ];

  test('Qwen-Image 2.1 takes the Qwen3-VL 8B encoder, not the 4B file', () {
    expect(
      pickSupportFile(
        primary: primary,
        token: '%MODEL_CLIP%',
        files: installed,
      ),
      vl,
    );
    final fills = supportAutofill(
      workflowId: 'qwen_image_21',
      primary: primary,
      choices: const {'qwen_image_21/%MODEL_CLIP%': 'qwen_3_4b.safetensors'},
      clips: installed,
      vaes: const ['qwen_image_2.1_vae_bf16.safetensors'],
      tokens: const ['%MODEL_CLIP%'],
    );
    expect(fills['%MODEL_CLIP%'], vl);
  });

  test('without that encoder the 2.1 slot is cleared', () {
    const blocked = [
      'qwen_3_4b.safetensors',
      'Qwen3-4B-Q2_K.gguf',
      'qwen_2.5_vl_7b.safetensors',
      'mmproj-Qwen3-VL-8B-Instruct-F16.gguf',
      'qwen3.5_9b_qwen_image_2.1_pe_t2i.int8_convrot.safetensors',
    ];
    expect(
      pickSupportFile(primary: primary, token: '%MODEL_CLIP%', files: blocked),
      '',
    );
    expect(
      supportAutofill(
        workflowId: 'qwen_image_21',
        primary: primary,
        choices: const {'qwen_image_21/%MODEL_CLIP%': 'qwen_3_4b.safetensors'},
        clips: blocked,
        vaes: const ['qwen_image_2.1_vae_bf16.safetensors'],
        tokens: const ['%MODEL_CLIP%'],
      )['%MODEL_CLIP%'],
      '',
    );
  });

  test('a safetensors Qwen3-VL 8B name still wins', () {
    expect(
      pickSupportFile(
        primary: 'Qwen-Image-2_1-Q6_K.gguf',
        token: '%MODEL_CLIP%',
        files: const [
          'qwen_3_4b.safetensors',
          'qwen3vl_8b_int8_convrot.safetensors',
        ],
      ),
      'qwen3vl_8b_int8_convrot.safetensors',
    );
  });

  test('Z-Image still uses qwen_3_4b and Qwen-Image 1.0 still uses 2.5 VL', () {
    expect(
      pickSupportFile(
        primary: 'z_image_turbo_bf16.safetensors',
        token: '%MODEL_CLIP%',
        files: installed,
      ),
      'qwen_3_4b.safetensors',
    );
    expect(
      pickSupportFile(
        primary: 'qwen_image_bf16.safetensors',
        token: '%MODEL_CLIP%',
        files: installed,
      ),
      'qwen_2.5_vl_7b.safetensors',
    );
  });

  test('the text-encoder catalog includes GGUF CLIP files', () {
    final source = File(
      'lib/services/comfy_ui_service.catalog.dart',
    ).readAsStringSync();
    expect(source, contains('CLIPLoaderGGUF'));
    final merged = mergeComfyCreateModels(
      const ['clip_l.safetensors', 'qwen_3_4b.safetensors'],
      const [
        vl,
        'qwen_3_4b.safetensors',
        'mmproj-Qwen3-VL-8B-Instruct-F16.gguf',
      ],
    );
    expect(
      pickSupportFile(primary: primary, token: '%MODEL_CLIP%', files: merged),
      vl,
    );
  });

  test('Qwen-Image 2.1 is not ready on the Z-Image encoder', () {
    const vae = 'qwen_image_2.1_vae_bf16.safetensors';
    expect(
      comfyCreateReady(
        workflowId: 'qwen_image_21',
        uploadedWorkflowJson: '',
        modelChoices: const {
          'qwen_image_21/%MODEL_DIFFUSION%': primary,
          'qwen_image_21/%MODEL_CLIP%': 'qwen_3_4b.safetensors',
          'qwen_image_21/%MODEL_VAE%': vae,
        },
      ),
      isFalse,
    );
    expect(
      comfyCreateReady(
        workflowId: 'qwen_image_21',
        uploadedWorkflowJson: '',
        modelChoices: const {
          'qwen_image_21/%MODEL_DIFFUSION%': primary,
          'qwen_image_21/%MODEL_CLIP%': vl,
          'qwen_image_21/%MODEL_VAE%': vae,
        },
      ),
      isTrue,
    );
  });

  test('the posted 2.1 graph loads both GGUF files', () {
    final req = resolveComfyCreateRequest(
      workflowId: 'qwen_image_21',
      uploadedWorkflowJson: '',
      modelChoices: const {
        'qwen_image_21/%MODEL_DIFFUSION%': primary,
        'qwen_image_21/%MODEL_CLIP%': vl,
        'qwen_image_21/%MODEL_VAE%': 'qwen_image_2.1_vae_bf16.safetensors',
      },
      prompt: 'a plate of tacos',
      negative: '',
      seed: 1,
      steps: 19,
      cfg: 5,
      denoise: 1,
      shift: 1,
      width: 1024,
      height: 1536,
    );
    expect(req, isNotNull);
    final filled = substituteComfyWorkflow(req!.template, req.values);
    final posted = graphToPost(
      graph: filled,
      primaryFile: primary,
      uploaded: false,
      objectInfo: const {
        'UnetLoaderGGUF': <String, dynamic>{},
        'CLIPLoaderGGUF': <String, dynamic>{},
        'VAELoader': <String, dynamic>{},
      },
    );
    expect(graphUsesLoader(posted, 'UnetLoaderGGUF'), isTrue);
    expect(graphUsesLoader(posted, 'CLIPLoaderGGUF'), isTrue);
    final clip = posted.values.whereType<Map>().firstWhere(
      (node) => node['class_type'] == 'CLIPLoaderGGUF',
    );
    final inputs = clip['inputs'] as Map;
    expect(inputs['clip_name'], vl);
    expect(inputs['type'], 'qwen_image');
  });

  test('an empty 2.1 encoder names the missing file', () {
    expect(
      studioMissingEncoderLine(
        primary: primary,
        rows: const [StudioSupportRow('Text encoder', '%MODEL_CLIP%', '')],
      ),
      kStudioQwen21Encoder,
    );
    expect(
      studioMissingEncoderLine(
        primary: 'z_image_turbo_bf16.safetensors',
        rows: const [StudioSupportRow('Text encoder', '%MODEL_CLIP%', '')],
      ),
      '',
    );
  });

  test('a Comfy history error keeps the exception text', () {
    const detail =
        'Given normalized_shape=[4096], expected input with shape '
        '[*4096], but got input of size[1, 65, 2560]';
    final msg = comfyHistoryFailureMessage('http://127.0.0.1:8189', {
      'status_str': 'error',
      'messages': [
        [
          'execution_error',
          {
            'node_id': '12',
            'node_type': 'TextEncodeQwenImage21',
            'exception_message': detail,
          },
        ],
      ],
    });
    expect(msg, startsWith('ComfyUI'));
    expect(msg, contains('node 12 (TextEncodeQwenImage21)'));
    expect(msg, contains(detail));
    expect(msg, isNot(contains('server console')));
    final source = File(
      'lib/services/comfy_ui_service.dart',
    ).readAsStringSync();
    expect(source, contains('comfyHistoryFailureMessage'));
  });
}
