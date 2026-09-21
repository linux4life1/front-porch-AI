// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Replaceable stock Comfy API-format graphs (Save → API Format).
// Live Comfy `/templates/{name}.json` wins when reachable. To refresh a
// starter after Comfy ships a new Qwen/Flux/ZIT, drop the new API JSON
// here — do not rewrite a Dart node builder. See docs/design/comfy-templates.md.

/// Official Z-Image Turbo inner graph (image_z_image_turbo subgraph).
const Map<String, dynamic> kComfyStarterZit = {
  '28': {
    'class_type': 'UNETLoader',
    'inputs': {'unet_name': 'z_image_turbo_bf16.safetensors', 'weight_dtype': 'default'},
  },
  '30': {
    'class_type': 'CLIPLoader',
    'inputs': {'clip_name': 'qwen_3_4b.safetensors', 'type': 'lumina2', 'device': 'default'},
  },
  '29': {
    'class_type': 'VAELoader',
    'inputs': {'vae_name': 'ae.safetensors'},
  },
  '27': {
    'class_type': 'CLIPTextEncode',
    'inputs': {'text': 'placeholder', 'clip': ['30', 0]},
  },
  '33': {
    'class_type': 'ConditioningZeroOut',
    'inputs': {'conditioning': ['27', 0]},
  },
  '13': {
    'class_type': 'EmptySD3LatentImage',
    'inputs': {'width': 1024, 'height': 1024, 'batch_size': 1},
  },
  '11': {
    'class_type': 'ModelSamplingAuraFlow',
    'inputs': {'model': ['28', 0], 'shift': 3},
  },
  '3': {
    'class_type': 'KSampler',
    'inputs': {
      'seed': 0,
      'steps': 8,
      'cfg': 1,
      'sampler_name': 'res_multistep',
      'scheduler': 'simple',
      'denoise': 1,
      'model': ['11', 0],
      'positive': ['27', 0],
      'negative': ['33', 0],
      'latent_image': ['13', 0],
    },
  },
  '8': {
    'class_type': 'VAEDecode',
    'inputs': {'samples': ['3', 0], 'vae': ['29', 0]},
  },
  '9': {
    'class_type': 'SaveImage',
    'inputs': {'filename_prefix': 'FrontPorchAI', 'images': ['8', 0]},
  },
};

/// Official-shaped Flux / Schnell / Krea stove (flux_schnell).
const Map<String, dynamic> kComfyStarterFlux = {
  'unet': {
    'class_type': 'UNETLoader',
    'inputs': {'unet_name': 'flux1-schnell.safetensors', 'weight_dtype': 'default'},
  },
  'clip': {
    'class_type': 'DualCLIPLoader',
    'inputs': {
      'clip_name1': 'clip_l.safetensors',
      'clip_name2': 't5xxl_fp16.safetensors',
      'type': 'flux',
      'device': 'default',
    },
  },
  'vae': {
    'class_type': 'VAELoader',
    'inputs': {'vae_name': 'ae.safetensors'},
  },
  'pos': {
    'class_type': 'CLIPTextEncode',
    'inputs': {'text': 'placeholder', 'clip': ['clip', 0]},
  },
  'guidance': {
    'class_type': 'FluxGuidance',
    'inputs': {'conditioning': ['pos', 0], 'guidance': 3.5},
  },
  'neg': {
    'class_type': 'ConditioningZeroOut',
    'inputs': {'conditioning': ['pos', 0]},
  },
  'latent': {
    'class_type': 'EmptyLatentImage',
    'inputs': {'width': 1024, 'height': 1024, 'batch_size': 1},
  },
  'sampler': {
    'class_type': 'KSampler',
    'inputs': {
      'seed': 0,
      'steps': 4,
      'cfg': 1.0,
      'sampler_name': 'euler',
      'scheduler': 'simple',
      'denoise': 1,
      'model': ['unet', 0],
      'positive': ['guidance', 0],
      'negative': ['neg', 0],
      'latent_image': ['latent', 0],
    },
  },
  'decode': {
    'class_type': 'VAEDecode',
    'inputs': {'samples': ['sampler', 0], 'vae': ['vae', 0]},
  },
  'save': {
    'class_type': 'SaveImage',
    'inputs': {'filename_prefix': 'FrontPorchAI', 'images': ['decode', 0]},
  },
};

/// Official-shaped Qwen-Image create (image_qwen_image).
const Map<String, dynamic> kComfyStarterQwen = {
  'unet': {
    'class_type': 'UNETLoader',
    'inputs': {'unet_name': 'qwen_image_fp8_e4m3fn.safetensors', 'weight_dtype': 'default'},
  },
  'clip': {
    'class_type': 'CLIPLoader',
    'inputs': {'clip_name': 'qwen_2.5_vl_7b.safetensors', 'type': 'qwen_image', 'device': 'default'},
  },
  'vae': {
    'class_type': 'VAELoader',
    'inputs': {'vae_name': 'qwen_image_vae.safetensors'},
  },
  'pos': {
    'class_type': 'CLIPTextEncode',
    'inputs': {'text': 'placeholder', 'clip': ['clip', 0]},
  },
  'neg': {
    'class_type': 'CLIPTextEncode',
    'inputs': {'text': '', 'clip': ['clip', 0]},
  },
  'modelsampling': {
    'class_type': 'ModelSamplingAuraFlow',
    'inputs': {'model': ['unet', 0], 'shift': 3.1},
  },
  'cfgnorm': {
    'class_type': 'CFGNorm',
    'inputs': {'model': ['modelsampling', 0], 'strength': 1.0},
  },
  'latent': {
    'class_type': 'EmptySD3LatentImage',
    'inputs': {'width': 1328, 'height': 1328, 'batch_size': 1},
  },
  'sampler': {
    'class_type': 'KSampler',
    'inputs': {
      'seed': 0,
      'steps': 20,
      'cfg': 4.0,
      'sampler_name': 'euler',
      'scheduler': 'simple',
      'denoise': 1,
      'model': ['cfgnorm', 0],
      'positive': ['pos', 0],
      'negative': ['neg', 0],
      'latent_image': ['latent', 0],
    },
  },
  'decode': {
    'class_type': 'VAEDecode',
    'inputs': {'samples': ['sampler', 0], 'vae': ['vae', 0]},
  },
  'save': {
    'class_type': 'SaveImage',
    'inputs': {'filename_prefix': 'FrontPorchAI', 'images': ['decode', 0]},
  },
};

Map<String, dynamic>? comfyStarterGraph(String workflowId) {
  switch (workflowId) {
    case 'z_image_turbo':
    case 'comfy:image_z_image_turbo':
      return Map<String, dynamic>.from(kComfyStarterZit);
    case 'flux':
    case 'comfy:flux_schnell':
      return Map<String, dynamic>.from(kComfyStarterFlux);
    case 'qwen_image':
    case 'comfy:image_qwen_image':
      return Map<String, dynamic>.from(kComfyStarterQwen);
    default:
      return null;
  }
}
