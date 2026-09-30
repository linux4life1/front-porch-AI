// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Small uploaded ComfyUI graphs the phone-desk and pack tests share.

/// A ComfyUI graph node.
Map<String, dynamic> deskNode(String type, Map<String, dynamic> inputs) => {
  'class_type': type,
  'inputs': inputs,
};

/// An uploaded Edit graph: a photo, an instruction, and a model file.
final Map<String, dynamic> deskEditGraph = {
  'ckpt': deskNode('CheckpointLoaderSimple', {
    'ckpt_name': 'edit-model.safetensors',
  }),
  'photo': deskNode('LoadImage', {'image': '%IMAGE%'}),
  'pos': deskNode('CLIPTextEncode', {
    'text': '%PROMPT%',
    'clip': ['ckpt', 1],
  }),
  'neg': deskNode('CLIPTextEncode', {
    'text': '%NEGATIVE%',
    'clip': ['ckpt', 1],
  }),
  'latent': deskNode('VAEEncode', {
    'pixels': ['photo', 0],
    'vae': ['ckpt', 2],
  }),
  'ks': deskNode('KSampler', {
    'model': ['ckpt', 0],
    'positive': ['pos', 0],
    'negative': ['neg', 0],
    'latent_image': ['latent', 0],
    'seed': '%SEED%',
    'steps': '%STEPS%',
    'cfg': '%CFG%',
    'sampler_name': 'euler',
    'scheduler': 'normal',
    'denoise': '%DENOISE%',
  }),
  'decode': deskNode('VAEDecode', {
    'samples': ['ks', 0],
    'vae': ['ckpt', 2],
  }),
  'save': deskNode('SaveImage', {
    'images': ['decode', 0],
    'filename_prefix': 'fpai',
  }),
};

/// An uploaded Create graph: no photo.
final Map<String, dynamic> deskCreateGraph = {
  'ckpt': deskNode('CheckpointLoaderSimple', {
    'ckpt_name': 'create-model.safetensors',
  }),
  'pos': deskNode('CLIPTextEncode', {
    'text': '%PROMPT%',
    'clip': ['ckpt', 1],
  }),
  'neg': deskNode('CLIPTextEncode', {
    'text': '%NEGATIVE%',
    'clip': ['ckpt', 1],
  }),
  'latent': deskNode('EmptyLatentImage', {
    'width': '%WIDTH%',
    'height': '%HEIGHT%',
    'batch_size': 1,
  }),
  'ks': deskNode('KSampler', {
    'model': ['ckpt', 0],
    'positive': ['pos', 0],
    'negative': ['neg', 0],
    'latent_image': ['latent', 0],
    'seed': '%SEED%',
    'steps': '%STEPS%',
    'cfg': '%CFG%',
    'sampler_name': 'euler',
    'scheduler': 'normal',
    'denoise': 1,
  }),
  'decode': deskNode('VAEDecode', {
    'samples': ['ks', 0],
    'vae': ['ckpt', 2],
  }),
  'save': deskNode('SaveImage', {
    'images': ['decode', 0],
    'filename_prefix': 'fpai',
  }),
};
