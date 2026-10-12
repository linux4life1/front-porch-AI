// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/image.dart';

const _info = <String, dynamic>{
  'UNETLoader': {},
  'CLIPLoader': {},
  'VAELoader': {},
  'CLIPTextEncode': {},
  'EmptySD3LatentImage': {},
  'KSampler': {},
  'VAEDecode': {},
  'SaveImage': {},
};

const _graph = {
  'unet': {
    'class_type': 'UNETLoader',
    'inputs': {'unet_name': 'z_image_turbo_bf16.safetensors'},
  },
  'clip': {
    'class_type': 'CLIPLoader',
    'inputs': {'clip_name': 'qwen_3_4b.safetensors'},
  },
  'vae': {
    'class_type': 'VAELoader',
    'inputs': {'vae_name': 'ae.safetensors'},
  },
  'pos': {
    'class_type': 'CLIPTextEncode',
    'inputs': {
      'text': 'a porch',
      'clip': ['clip', 0],
    },
  },
  'latent': {
    'class_type': 'EmptySD3LatentImage',
    'inputs': {'width': 1024, 'height': 1024, 'batch_size': 1},
  },
  'ks': {
    'class_type': 'KSampler',
    'inputs': {
      'model': ['unet', 0],
      'positive': ['pos', 0],
      'negative': ['pos', 0],
      'latent_image': ['latent', 0],
      'seed': 1,
      'steps': 8,
      'cfg': 1,
      'sampler_name': 'euler',
      'scheduler': 'simple',
      'denoise': 1,
    },
  },
  'decode': {
    'class_type': 'VAEDecode',
    'inputs': {
      'samples': ['ks', 0],
      'vae': ['vae', 0],
    },
  },
  'save': {
    'class_type': 'SaveImage',
    'inputs': {
      'images': ['decode', 0],
      'filename_prefix': 'fpai',
    },
  },
};

String line(StudioReadiness ready, {String primary = ''}) => studioNotReadyLine(
  readiness: ready,
  backendName: 'ComfyUI',
  primaryFile: primary,
);

void main() {
  group('the line beside Generate', () {
    test('names the empty slots of a template graph', () {
      const id = 'comfy:default:zimage';
      final ready = deskReadiness(
        backend: 'comfyui',
        primaryFile: 'z_image_turbo_bf16.safetensors',
        objectInfo: _info,
        workflowId: id,
        liveTemplate: _graph,
        modelChoices: const {
          '$id/%MODEL_DIFFUSION%': 'z_image_turbo_bf16.safetensors',
        },
      );
      expect(ready.kind, StudioReady.missingFile);
      expect(
        line(ready, primary: 'z_image_turbo_bf16.safetensors'),
        'Not ready — choose a file for Text encoder and VAE.',
      );
    });

    test('a graph with nothing chosen names every file', () {
      const id = 'comfy:default:zimage';
      final ready = deskReadiness(
        backend: 'comfyui',
        primaryFile: '',
        objectInfo: _info,
        workflowId: id,
        liveTemplate: _graph,
      );
      expect(
        line(ready),
        'Not ready — choose a file for Diffusion model, Text encoder and VAE.',
      );
    });

    test('a graph that cannot be read says so', () {
      final ready = deskReadiness(
        backend: 'comfyui',
        primaryFile: '',
        objectInfo: _info,
        workflowId: kComfyUploadedWorkflowId,
        uploadedWorkflowJson: '{ cut off',
      );
      expect(
        line(ready),
        'Not ready — this graph could not be read. Choose it again, or '
        'choose another graph.',
      );
    });

    test('says how to fix each other verdict', () {
      expect(
        line(const StudioReadiness(StudioReady.unreachable)),
        'Not ready — ComfyUI can’t be reached. Start it, or check its '
        'address.',
      );
      expect(
        line(const StudioReadiness(StudioReady.missingNodeClass, 'KSampler')),
        'Not ready — ComfyUI is missing the KSampler node. Install the '
        'custom node that provides it, then restart ComfyUI.',
      );
      expect(
        line(const StudioReadiness(StudioReady.needsUnetGraph)),
        'Not ready — this model needs a graph that loads a diffusion '
        'model. Choose one of those graphs.',
      );
      expect(
        line(const StudioReadiness(StudioReady.ready)),
        'Ready to generate.',
      );
    });

    test('a backend with no model chosen says what to set up', () {
      final ready = deskReadiness(
        backend: 'remote',
        primaryFile: '',
        objectInfo: const {},
      );
      expect(
        studioNotReadyLine(readiness: ready, backendName: 'Remote'),
        'Not ready — no image model is chosen. Add your image API’s address '
        'and key, then choose one of its models.',
      );
    });
  });

  group('a dropped-in Create graph', () {
    test('runs with the files it names', () {
      final ready = deskReadiness(
        backend: 'comfyui',
        primaryFile: '',
        objectInfo: _info,
        workflowId: kComfyUploadedWorkflowId,
        uploadedWorkflowJson: _json,
      );
      expect(ready.kind, StudioReady.ready);
      final req = resolveComfyCreateRequest(
        workflowId: kComfyUploadedWorkflowId,
        uploadedWorkflowJson: _json,
        modelChoices: const {},
        prompt: 'p',
        negative: '',
        seed: 1,
        steps: 8,
        cfg: 1,
        denoise: 1,
        shift: null,
        width: 1024,
        height: 1024,
      )!;
      final graph = substituteComfyWorkflow(req.template, req.values);
      expect(unresolvedComfyTokens(graph), isEmpty);
      expect(
        (graph['unet'] as Map)['inputs']['unet_name'],
        'z_image_turbo_bf16.safetensors',
      );
      expect((graph['vae'] as Map)['inputs']['vae_name'], 'ae.safetensors');
    });

    test('a file picked for a slot still wins', () {
      final req = resolveComfyCreateRequest(
        workflowId: kComfyUploadedWorkflowId,
        uploadedWorkflowJson: _json,
        modelChoices: const {
          '$kComfyUploadedWorkflowId/%MODEL_VAE%': 'other_vae.safetensors',
        },
        prompt: 'p',
        negative: '',
        seed: 1,
        steps: 8,
        cfg: 1,
        denoise: 1,
        shift: null,
        width: 1024,
        height: 1024,
      )!;
      final graph = substituteComfyWorkflow(req.template, req.values);
      expect(
        (graph['vae'] as Map)['inputs']['vae_name'],
        'other_vae.safetensors',
      );
    });

    test('its own checkpoint wins over the global image model', () {
      final json = jsonEncode({
        'ckpt': {
          'class_type': 'CheckpointLoaderSimple',
          'inputs': {'ckpt_name': 'graph_own.safetensors'},
        },
        'pos': {
          'class_type': 'CLIPTextEncode',
          'inputs': {
            'text': 'a porch',
            'clip': ['ckpt', 1],
          },
        },
        'latent': {
          'class_type': 'EmptyLatentImage',
          'inputs': {'width': 512, 'height': 512, 'batch_size': 1},
        },
        'ks': {
          'class_type': 'KSampler',
          'inputs': {
            'model': ['ckpt', 0],
            'positive': ['pos', 0],
            'negative': ['pos', 0],
            'latent_image': ['latent', 0],
            'seed': 1,
            'steps': 8,
            'cfg': 1,
            'sampler_name': 'euler',
            'scheduler': 'simple',
            'denoise': 1,
          },
        },
        'decode': {
          'class_type': 'VAEDecode',
          'inputs': {
            'samples': ['ks', 0],
            'vae': ['ckpt', 2],
          },
        },
        'save': {
          'class_type': 'SaveImage',
          'inputs': {
            'images': ['decode', 0],
            'filename_prefix': 'fpai',
          },
        },
      });
      final req = resolveComfyCreateRequest(
        workflowId: kComfyUploadedWorkflowId,
        uploadedWorkflowJson: json,
        modelChoices: const {},
        checkpointFallback: 'other.safetensors',
        prompt: 'p',
        negative: '',
        seed: 1,
        steps: 8,
        cfg: 1,
        denoise: 1,
        shift: null,
        width: 512,
        height: 512,
      )!;
      final graph = substituteComfyWorkflow(req.template, req.values);
      expect(
        (graph['ckpt'] as Map)['inputs']['ckpt_name'],
        'graph_own.safetensors',
      );
    });
  });
}

final String _json = jsonEncode(_graph);
