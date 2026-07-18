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

/// Pure builders for the bundled ComfyUI workflow graphs (ComfyUI API format:
/// node-id → {class_type, inputs}). Extracted from ComfyUiService so the client
/// stays under the file-size cap; these are stateless, deterministic, and
/// unit-tested. The same graph shape covers SD1.5 and SDXL checkpoints (only the
/// latent size differs, and that comes from the configured size).
class ComfyWorkflow {
  ComfyWorkflow._();

  /// Build the bundled txt2img workflow. When [loraName] is set, a LoraLoader is
  /// spliced between the checkpoint and the sampler/text-encoders.
  static Map<String, dynamic> buildTxt2ImgWorkflow({
    required String model,
    required String prompt,
    required String negativePrompt,
    required int width,
    required int height,
    required int steps,
    required double cfgScale,
    required int seed,
    required String samplerName,
    required String scheduler,
    String loraName = '',
    double loraWeight = 0.8,
  }) => _build(
    model: model,
    prompt: prompt,
    negativePrompt: negativePrompt,
    width: width,
    height: height,
    steps: steps,
    cfgScale: cfgScale,
    seed: seed,
    samplerName: samplerName,
    scheduler: scheduler,
    loraName: loraName,
    loraWeight: loraWeight,
  );

  /// Build the bundled img2img workflow: identical graph to txt2img except the
  /// empty latent is replaced by a LoadImage → VAEEncode of the already-uploaded
  /// [initImageName] (as returned by `ComfyUiService.uploadImage`), and the
  /// KSampler denoises from it at [denoise] (0 = keep the reference, 1 = ignore
  /// it) instead of the txt2img fixed 1.0.
  static Map<String, dynamic> buildImg2ImgWorkflow({
    required String model,
    required String prompt,
    required String negativePrompt,
    required int steps,
    required double cfgScale,
    required int seed,
    required String samplerName,
    required String scheduler,
    required String initImageName,
    required double denoise,
    String loraName = '',
    double loraWeight = 0.8,
  }) => _build(
    model: model,
    prompt: prompt,
    negativePrompt: negativePrompt,
    // Width/height are ignored in the img2img graph (the latent size comes from
    // the encoded reference), but the shared builder still wants them.
    width: 1024,
    height: 1024,
    steps: steps,
    cfgScale: cfgScale,
    seed: seed,
    samplerName: samplerName,
    scheduler: scheduler,
    loraName: loraName,
    loraWeight: loraWeight,
    initImageName: initImageName,
    denoise: denoise,
  );

  /// Shared builder behind [buildTxt2ImgWorkflow] and [buildImg2ImgWorkflow]. An
  /// empty [initImageName] yields txt2img (empty latent, denoise pinned to 1.0);
  /// a non-empty one yields img2img (LoadImage → VAEEncode, denoise = [denoise]).
  static Map<String, dynamic> _build({
    required String model,
    required String prompt,
    required String negativePrompt,
    required int width,
    required int height,
    required int steps,
    required double cfgScale,
    required int seed,
    required String samplerName,
    required String scheduler,
    String loraName = '',
    double loraWeight = 0.8,
    String initImageName = '',
    double denoise = 1.0,
  }) {
    final hasLora = loraName.isNotEmpty;
    final isImg2Img = initImageName.isNotEmpty;
    // Model/clip source for the sampler + prompts: the checkpoint directly,
    // or the LoRA loader when one is selected.
    final modelSrc = hasLora ? ['lora', 0] : ['ckpt', 0];
    final clipSrc = hasLora ? ['lora', 1] : ['ckpt', 1];
    return {
      'ckpt': {
        'class_type': 'CheckpointLoaderSimple',
        'inputs': {'ckpt_name': model},
      },
      if (hasLora)
        'lora': {
          'class_type': 'LoraLoader',
          'inputs': {
            'lora_name': loraName,
            'strength_model': loraWeight,
            'strength_clip': loraWeight,
            'model': ['ckpt', 0],
            'clip': ['ckpt', 1],
          },
        },
      'pos': {
        'class_type': 'CLIPTextEncode',
        'inputs': {'text': prompt, 'clip': clipSrc},
      },
      'neg': {
        'class_type': 'CLIPTextEncode',
        'inputs': {'text': negativePrompt, 'clip': clipSrc},
      },
      // Latent source: txt2img starts from an empty latent; img2img loads the
      // uploaded reference and VAE-encodes it so the sampler denoises from it.
      if (isImg2Img) ...{
        'init_image': {
          'class_type': 'LoadImage',
          'inputs': {'image': initImageName},
        },
        'latent': {
          'class_type': 'VAEEncode',
          'inputs': {
            'pixels': ['init_image', 0],
            'vae': ['ckpt', 2],
          },
        },
      } else
        'latent': {
          'class_type': 'EmptyLatentImage',
          'inputs': {'width': width, 'height': height, 'batch_size': 1},
        },
      'sampler': {
        'class_type': 'KSampler',
        'inputs': {
          'seed': seed,
          'steps': steps,
          'cfg': cfgScale,
          'sampler_name': samplerName,
          'scheduler': scheduler,
          'denoise': isImg2Img ? denoise : 1.0,
          'model': modelSrc,
          'positive': ['pos', 0],
          'negative': ['neg', 0],
          'latent_image': ['latent', 0],
        },
      },
      'decode': {
        'class_type': 'VAEDecode',
        'inputs': {
          'samples': ['sampler', 0],
          'vae': ['ckpt', 2],
        },
      },
      'save': {
        'class_type': 'SaveImage',
        'inputs': {
          'filename_prefix': 'FrontPorchAI',
          'images': ['decode', 0],
        },
      },
    };
  }
}
