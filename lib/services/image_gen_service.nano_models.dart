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

part of 'image_gen_service.dart';

/// Common image generation models for Nano-GPT and similar providers.
/// Always shown so the picker works when `/v1/models` lists text only.
///
/// Snapshot of https://nano-gpt.com/models/image via GET
/// `/api/v1/image-models` (21 Sep 2026). Not a live fetch — refresh this
/// const when Nano's image page changes. `isPaid: false` follows
/// `/api/subscription/v1/image-models` (Pro-included).
const _commonImageModels = <ImageModelInfo>[
  // ── Included with Nano-GPT subscription ──
  ImageModelInfo(
    id: 'step-image-edit-2',
    name: 'Step Image Edit 2',
    isPaid: false,
  ),
  ImageModelInfo(id: 'z-image-turbo', name: 'Z Image Turbo', isPaid: false),
  ImageModelInfo(id: 'qwen-image', name: 'Qwen Image', isPaid: false),
  ImageModelInfo(id: 'hidream', name: 'Hidream', isPaid: false),
  ImageModelInfo(id: 'chroma', name: 'Chroma', isPaid: false),
  // ── Pay-per-prompt ──
  ImageModelInfo(id: 'z-image-base', name: 'Z Image Base'),
  ImageModelInfo(
    id: 'z-image-turbo-image-to-image',
    name: 'Z Image Turbo Image-to-Image',
  ),
  ImageModelInfo(id: 'z-image-turbo-lora', name: 'Z Image Turbo LoRA'),
  ImageModelInfo(id: 'ernie-image', name: 'ERNIE Image'),
  ImageModelInfo(id: 'ernie-image/turbo', name: 'ERNIE Image Turbo'),
  ImageModelInfo(id: 'bria-fibo', name: 'Bria Fibo'),
  ImageModelInfo(id: 'bria-fibo-edit', name: 'Bria Fibo Edit'),
  ImageModelInfo(id: 'bria/fibo-edit-1.5/edit', name: 'Bria FIBO Edit 1.5'),
  ImageModelInfo(
    id: 'bria/fibo-generate-1.5/text-to-image',
    name: 'Bria FIBO Generate 1.5',
  ),
  ImageModelInfo(id: 'bria/product-holding', name: 'Bria Product Holding'),
  ImageModelInfo(id: 'bria/virtual-try-on', name: 'Bria Virtual Try-On'),
  ImageModelInfo(id: 'seedvr2-image', name: 'SeedVR2 Image Upscaler'),
  ImageModelInfo(id: 'anima/text-to-image', name: 'Anima'),
  ImageModelInfo(id: 'anima/text-to-image-lora', name: 'Anima LoRA'),
  ImageModelInfo(
    id: 'clarity-ai-creative-upscaler',
    name: 'Clarity AI Creative Upscaler',
  ),
  ImageModelInfo(
    id: 'clarity-ai-crystal-upscaler',
    name: 'Clarity AI Crystal Upscaler',
  ),
  ImageModelInfo(
    id: 'clarity-ai-flux-upscaler',
    name: 'Clarity AI Flux Upscaler',
  ),
  ImageModelInfo(
    id: 'clarity-ai-pro-upscaler',
    name: 'Clarity AI Pro Upscaler',
  ),
  ImageModelInfo(id: 'bagel', name: 'BAGEL'),
  ImageModelInfo(id: 'seedream-v3', name: 'SeeDream 3.0'),
  ImageModelInfo(id: 'seedream-v4', name: 'Seedream 4.0'),
  ImageModelInfo(id: 'seedream-v4.5', name: 'Seedream 4.5'),
  ImageModelInfo(
    id: 'seedream-4.5-alternative',
    name: 'Seedream 4.5 Alternative',
  ),
  ImageModelInfo(
    id: 'seedream-v4.5-sequential',
    name: 'Seedream 4.5 Sequential',
  ),
  ImageModelInfo(id: 'seedream-5-alternative', name: 'Seedream 5 Alternative'),
  ImageModelInfo(
    id: 'seedream-5-alternative/edit',
    name: 'Seedream 5 Alternative Edit',
  ),
  ImageModelInfo(id: 'seedream-v5.0-lite', name: 'Seedream 5.0 Lite'),
  ImageModelInfo(
    id: 'seedream-v5.0-lite-sequential',
    name: 'Seedream 5.0 Lite Sequential',
  ),
  ImageModelInfo(id: 'bytedance/seedream-v5.0-pro', name: 'Seedream 5.0 Pro'),
  ImageModelInfo(
    id: 'bytedance/seedream/v5/pro/text-to-image',
    name: 'Seedream 5.0 Pro',
  ),
  ImageModelInfo(
    id: 'bytedance/seedream-v5.0-pro/edit',
    name: 'Seedream 5.0 Pro Edit',
  ),
  ImageModelInfo(
    id: 'bytedance/seedream/v5/pro/edit',
    name: 'Seedream 5.0 Pro Edit',
  ),
  ImageModelInfo(id: 'birefnet/v2', name: 'BiRefNet V2'),
  ImageModelInfo(id: 'background-remover', name: 'Background Remover'),
  ImageModelInfo(id: 'runware:107@1', name: 'Flux 1 Krea Dev'),
  ImageModelInfo(id: 'flux-dev-image-to-image', name: 'Flux Dev'),
  ImageModelInfo(id: 'flux-kontext', name: 'Flux Kontext'),
  ImageModelInfo(id: 'runware:106@1', name: 'Flux Kontext Dev'),
  ImageModelInfo(id: 'flux-lightning', name: 'Flux Lightning'),
  ImageModelInfo(id: 'flux-lora', name: 'Flux Lora'),
  ImageModelInfo(id: 'flux-lora/inpainting', name: 'Flux LoRA Inpainting'),
  ImageModelInfo(id: 'flux-pro', name: 'Flux Pro V1'),
  ImageModelInfo(id: 'flux-pro/v1.1', name: 'Flux Pro V1.1'),
  ImageModelInfo(id: 'flux-pro/v1.1-ultra', name: 'Flux Pro V1.1 Ultra'),
  ImageModelInfo(id: 'flux-realism', name: 'Flux Realism'),
  ImageModelInfo(id: 'flux-schnell', name: 'Flux Schnell'),
  ImageModelInfo(id: 'flux-pro/v1/vto', name: 'FLUX Virtual Try-On'),
  ImageModelInfo(id: 'flux-2-dev', name: 'FLUX.2 [dev]'),
  ImageModelInfo(id: 'flux-2-dev-image-to-image', name: 'FLUX.2 [dev] Edit'),
  ImageModelInfo(id: 'flux-2-dev-lora', name: 'FLUX.2 [dev] LoRA'),
  ImageModelInfo(
    id: 'flux-2-dev-lora-image-to-image',
    name: 'FLUX.2 [dev] LoRA Edit',
  ),
  ImageModelInfo(id: 'flux-2-flash', name: 'FLUX.2 [flash]'),
  ImageModelInfo(
    id: 'flux-2-flash-image-to-image',
    name: 'FLUX.2 [flash] Edit',
  ),
  ImageModelInfo(id: 'flux-2-flex', name: 'FLUX.2 [flex]'),
  ImageModelInfo(id: 'flux-2-flex-image-to-image', name: 'FLUX.2 [flex] Edit'),
  ImageModelInfo(id: 'flux-2-klein-4b', name: 'FLUX.2 [klein] 4B'),
  ImageModelInfo(id: 'flux-2-klein-9b', name: 'FLUX.2 [klein] 9B'),
  ImageModelInfo(
    id: 'flux-2-klein-base-4b/text-to-image',
    name: 'FLUX.2 [klein] Base 4B',
  ),
  ImageModelInfo(
    id: 'flux-2-klein-base-4b/edit',
    name: 'FLUX.2 [klein] Base 4B Edit',
  ),
  ImageModelInfo(
    id: 'flux-2-klein-base-4b/edit-lora',
    name: 'FLUX.2 [klein] Base 4B Edit LoRA',
  ),
  ImageModelInfo(
    id: 'flux-2-klein-base-4b/text-to-image-lora',
    name: 'FLUX.2 [klein] Base 4B LoRA',
  ),
  ImageModelInfo(
    id: 'flux-2-klein-base-9b/text-to-image',
    name: 'FLUX.2 [klein] Base 9B',
  ),
  ImageModelInfo(
    id: 'flux-2-klein-base-9b/edit',
    name: 'FLUX.2 [klein] Base 9B Edit',
  ),
  ImageModelInfo(
    id: 'flux-2-klein-base-9b/edit-lora',
    name: 'FLUX.2 [klein] Base 9B Edit LoRA',
  ),
  ImageModelInfo(
    id: 'flux-2-klein-base-9b/text-to-image-lora',
    name: 'FLUX.2 [klein] Base 9B LoRA',
  ),
  ImageModelInfo(id: 'flux-2-max', name: 'FLUX.2 [max]'),
  ImageModelInfo(id: 'flux-2-max-image-to-image', name: 'FLUX.2 [max] Edit'),
  ImageModelInfo(id: 'flux-2-pro', name: 'FLUX.2 [pro]'),
  ImageModelInfo(id: 'flux-2-pro-image-to-image', name: 'FLUX.2 [pro] Edit'),
  ImageModelInfo(id: 'flux-2-turbo', name: 'FLUX.2 [turbo]'),
  ImageModelInfo(
    id: 'flux-2-turbo-image-to-image',
    name: 'FLUX.2 [turbo] Edit',
  ),
  ImageModelInfo(id: 'ghiblify', name: 'Ghiblify'),
  ImageModelInfo(
    id: 'juggernaut-lightning-flux',
    name: 'Juggernaut Lightning Flux',
  ),
  ImageModelInfo(id: 'juggernaut-pro-flux', name: 'Juggernaut Pro Flux'),
  ImageModelInfo(id: 'gemini-flash-edit', name: 'Gemini Image Edit'),
  ImageModelInfo(id: 'imagen-3.0-generate-002', name: 'Imagen V3'),
  ImageModelInfo(id: 'nano-banana', name: 'Nano Banana'),
  ImageModelInfo(id: 'nano-banana-2', name: 'Nano Banana 2'),
  ImageModelInfo(id: 'nano-banana-2-fast', name: 'Nano Banana 2 Fast'),
  ImageModelInfo(id: 'nano-banana-2-lite', name: 'Nano Banana 2 Lite'),
  ImageModelInfo(id: 'nano-banana-edit', name: 'Nano Banana Edit'),
  ImageModelInfo(id: 'nano-banana-pro', name: 'Nano Banana Pro'),
  ImageModelInfo(id: 'nano-banana-pro-edit', name: 'Nano Banana Pro Edit'),
  ImageModelInfo(id: 'nano-banana-pro-ultra', name: 'Nano Banana Pro Ultra'),
  ImageModelInfo(
    id: 'nano-banana-pro-edit-ultra',
    name: 'Nano Banana Pro Ultra Edit',
  ),
  ImageModelInfo(id: 'hidream-e1-1', name: 'HiDream Edit 1.1'),
  ImageModelInfo(id: 'hidream-o1-image', name: 'HiDream O1 Image'),
  ImageModelInfo(id: 'hidream-o1-image-dev', name: 'HiDream O1 Image Dev'),
  ImageModelInfo(id: 'hidream-i1-fast', name: 'HiDream-I1 Fast'),
  ImageModelInfo(id: 'higgsfield-soul', name: 'Higgsfield Soul'),
  ImageModelInfo(id: 'hunyuan-image-3', name: 'Hunyuan Image 3'),
  ImageModelInfo(
    id: 'hunyuan-image-3-instruct',
    name: 'Hunyuan Image 3 Instruct',
  ),
  ImageModelInfo(id: 'ideogram:4@0', name: 'Ideogram 4.0'),
  ImageModelInfo(id: 'ideogram-ai/ideogram-v2', name: 'Ideogram V2'),
  ImageModelInfo(
    id: 'ideogram-ai/ideogram-v2-turbo',
    name: 'Ideogram V2 Turbo',
  ),
  ImageModelInfo(
    id: 'ideogram-v3-generate-transparent',
    name: 'Ideogram V3 Generate Transparent',
  ),
  ImageModelInfo(
    id: 'ideogram-v3-remove-text',
    name: 'Ideogram V3 Remove Text',
  ),
  ImageModelInfo(id: 'ideogram/v4/fast', name: 'Ideogram V4 Fast'),
  ImageModelInfo(id: 'ideogram/v4/instant', name: 'Ideogram V4 Instant'),
  ImageModelInfo(id: 'kling-image-o1', name: 'Kling Image O1'),
  ImageModelInfo(id: 'krea-v2-large/text-to-image', name: 'Krea 2 Large'),
  ImageModelInfo(id: 'krea/v2/large/text-to-image', name: 'Krea 2 Large'),
  ImageModelInfo(id: 'krea-v2-medium/text-to-image', name: 'Krea 2 Medium'),
  ImageModelInfo(id: 'krea/v2/medium/text-to-image', name: 'Krea 2 Medium'),
  ImageModelInfo(
    id: 'krea-v2-medium-turbo/text-to-image',
    name: 'Krea 2 Medium Turbo',
  ),
  ImageModelInfo(id: 'krea-2/turbo', name: 'Krea 2 Turbo'),
  ImageModelInfo(id: 'krea-v2/turbo', name: 'Krea 2 Turbo'),
  ImageModelInfo(id: 'krea-v2/turbo-lora', name: 'Krea 2 Turbo LoRA'),
  ImageModelInfo(id: 'lucid-origin', name: 'Lucid Origin'),
  ImageModelInfo(id: 'longcat-image', name: 'Longcat Image'),
  ImageModelInfo(id: 'longcat-image-edit', name: 'Longcat Image Edit'),
  ImageModelInfo(id: 'meta/muse-image/text-to-image', name: 'Muse Image'),
  ImageModelInfo(id: 'meta/muse-image/edit', name: 'Muse Image Edit'),
  ImageModelInfo(
    id: 'microsoft/mai-image-2.5/text-to-image',
    name: 'MAI-Image-2.5',
  ),
  ImageModelInfo(
    id: 'microsoft/mai-image-2.5/edit',
    name: 'MAI-Image-2.5 Edit',
  ),
  ImageModelInfo(id: 'microsoft/mai-image-2.6', name: 'MAI-Image-2.6'),
  ImageModelInfo(
    id: 'microsoft/mai-image-2.6-flash',
    name: 'MAI-Image-2.6 Flash',
  ),
  ImageModelInfo(id: 'midjourney/text-to-image', name: 'Midjourney'),
  ImageModelInfo(id: 'minimax-h3/text-to-image', name: 'MiniMax H3 Image'),
  ImageModelInfo(id: 'minimax-h3/image-edit', name: 'MiniMax H3 Image Edit'),
  ImageModelInfo(id: 'minimax-image-01', name: 'MiniMax Image-01'),
  ImageModelInfo(id: 'Cropper', name: 'Crop image'),
  ImageModelInfo(id: 'auto-image-selection', name: 'Image Model Recommender'),
  ImageModelInfo(id: 'Upscaler', name: 'Upscaler'),
  ImageModelInfo(
    id: 'nvidia/cosmos-3-super/text-to-image',
    name: 'Cosmos 3 Super',
  ),
  ImageModelInfo(id: 'dall-e-3', name: 'DALL-E-3'),
  ImageModelInfo(id: 'dall-e-3-hd', name: 'DALL-E-3 HD'),
  ImageModelInfo(id: 'gpt-image-1', name: 'GPT 4o Image'),
  ImageModelInfo(id: 'gpt-4o-image', name: 'GPT 4o Image (old)'),
  ImageModelInfo(id: 'gpt-image-1.5', name: 'GPT Image 1.5'),
  ImageModelInfo(id: 'gpt-image-2', name: 'GPT Image 2'),
  ImageModelInfo(
    id: 'openai/gpt-image-2.5/flare/text-to-image',
    name: 'GPT Image 2.5 Flare',
  ),
  ImageModelInfo(
    id: 'openai/gpt-image-2.5/flare/edit',
    name: 'GPT Image 2.5 Flare Edit',
  ),
  ImageModelInfo(
    id: 'openai/gpt-image-2.5/sunburst/text-to-image',
    name: 'GPT Image 2.5 Sunburst',
  ),
  ImageModelInfo(
    id: 'openai/gpt-image-2.5/sunburst/edit',
    name: 'GPT Image 2.5 Sunburst Edit',
  ),
  ImageModelInfo(id: '2dn-pony-v2', name: '2DN Pony v2'),
  ImageModelInfo(id: 'nsfw-gen-illustrious', name: 'Animagine XL 4.0'),
  ImageModelInfo(id: 'atomix-xl', name: 'Atomix XL'),
  ImageModelInfo(id: 'bernini-r/edit-image', name: 'Bernini R Edit Image'),
  ImageModelInfo(id: 'boltning', name: 'Boltning'),
  ImageModelInfo(id: 'boogu-image', name: 'Boogu Image'),
  ImageModelInfo(id: 'boogu-image/edit', name: 'Boogu Image Edit'),
  ImageModelInfo(
    id: 'crystal-clear-xlightning',
    name: 'Crystal Clear Lightning v1.0',
  ),
  ImageModelInfo(id: 'animagine-xl-31', name: 'Crystal Clear XL'),
  ImageModelInfo(
    id: 'cyberrealistic-pony-v9',
    name: 'CyberRealistic Pony v9.0',
  ),
  ImageModelInfo(id: 'cyberrealistic-xl', name: 'CyberRealistic XL'),
  ImageModelInfo(id: 'dreamshaper-v1', name: 'DreamShaper v1'),
  ImageModelInfo(id: 'dreamshaper-xl', name: 'DreamShaper XL'),
  ImageModelInfo(id: 'fluently-xl', name: 'Fluently XL'),
  ImageModelInfo(
    id: 'stable-diffusion-xl-turbo',
    name: 'Fluently XL V3 Lightning',
  ),
  ImageModelInfo(id: 'miusmius-xl', name: 'Flux Artfusion'),
  ImageModelInfo(
    id: 'imagineart/imagineart-2.0-edit-preview/image-to-image',
    name: 'ImagineArt 2.0 Edit Preview',
  ),
  ImageModelInfo(id: 'artiwaifu-diffusion', name: 'Juggernaut XL'),
  ImageModelInfo(id: 'luma/agent/uni-1/v1', name: 'Luma UNI-1'),
  ImageModelInfo(id: 'luma/agent/uni-1/v1/max', name: 'Luma UNI-1 Max'),
  ImageModelInfo(id: 'hassaku-hentai', name: 'Moxie Diffusion XL'),
  ImageModelInfo(id: 'persona:376130@2456367', name: 'Nova Anime XL'),
  ImageModelInfo(id: 'pixelwave', name: 'PixelWave'),
  ImageModelInfo(id: 'infinite-illustrious', name: 'Prefect Pony XL V4.0'),
  ImageModelInfo(
    id: 'aniflatmix-anime-sfwnsfw',
    name: 'RealVisXL V4.0 Lightning',
  ),
  ImageModelInfo(id: 'aniflatmix-anime', name: 'RealVisXL V5.0'),
  ImageModelInfo(id: 'realpony-xl', name: 'RealVisXL V5.0 BakedVae'),
  ImageModelInfo(id: 'rev-animated', name: 'Rev Animated'),
  ImageModelInfo(id: 'SDXL-ArliMix-v1', name: 'SDXL ArliMix V1'),
  ImageModelInfo(id: 'stoiqo-new-reality', name: 'STOIQO New Reality'),
  ImageModelInfo(id: 'wai-illustrious-sdxl', name: 'WAI Illustrious SDXL'),
  ImageModelInfo(id: 'crystal-clear-xl', name: 'Zuki Anime ILL'),
  ImageModelInfo(id: 'playground-v25', name: 'Playground V2.5'),
  ImageModelInfo(id: 'proteus', name: 'Proteus'),
  ImageModelInfo(id: 'pruna-ai/p-image/text-to-image', name: 'P-Image'),
  ImageModelInfo(id: 'prunaai:1@1', name: 'P-Image'),
  ImageModelInfo(id: 'pruna-ai/p-image/edit', name: 'P-Image Edit'),
  ImageModelInfo(id: 'pruna-ai/p-image/edit-lora', name: 'P-Image Edit LoRA'),
  ImageModelInfo(
    id: 'pruna-ai/p-image/text-to-image-lora',
    name: 'P-Image LoRA',
  ),
  ImageModelInfo(id: 'pruna-ai/p-image/upscale', name: 'P-Image Upscale'),
  ImageModelInfo(id: 'qwen-image-2.0', name: 'Qwen Image 2.0'),
  ImageModelInfo(id: 'qwen-image-2.0-pro', name: 'Qwen Image 2.0 Pro'),
  ImageModelInfo(
    id: 'qwen-image-2.0-pro-2026-03-03',
    name: 'Qwen Image 2.0 Pro (2026-03-03)',
  ),
  ImageModelInfo(id: 'qwen-image-2.1/text-to-image', name: 'Qwen Image 2.1'),
  ImageModelInfo(id: 'qwen-image-2.1/edit', name: 'Qwen Image 2.1 Edit'),
  ImageModelInfo(
    id: 'qwen-image-2.1/edit-lora',
    name: 'Qwen Image 2.1 Edit LoRA',
  ),
  ImageModelInfo(
    id: 'qwen-image-2.1/text-to-image-lora',
    name: 'Qwen Image 2.1 LoRA',
  ),
  ImageModelInfo(id: 'qwen-image-2512', name: 'Qwen Image 2512'),
  ImageModelInfo(id: 'qwen-image-3', name: 'Qwen Image 3'),
  ImageModelInfo(id: 'qwen-image-3-pro', name: 'Qwen Image 3 Pro'),
  ImageModelInfo(id: 'qwen-image-max', name: 'Qwen Image Max'),
  ImageModelInfo(id: 'qwen-image-max-edit', name: 'Qwen Image Max Edit'),
  ImageModelInfo(id: 'wan-2.6-image-edit', name: 'WAN 2.6 Image Edit'),
  ImageModelInfo(id: 'wan2.7-image', name: 'WAN 2.7 Image'),
  ImageModelInfo(id: 'wan2.7-image-pro', name: 'WAN 2.7 Image Pro'),
  ImageModelInfo(id: 'recraft-v3', name: 'Recraft V3'),
  ImageModelInfo(id: 'recraft-v4', name: 'Recraft V4'),
  ImageModelInfo(id: 'recraft-v4-pro', name: 'Recraft V4 Pro'),
  ImageModelInfo(
    id: 'recraft-ai/recraft-v4-style/text-to-image',
    name: 'Recraft V4 Style',
  ),
  ImageModelInfo(
    id: 'recraft-ai/recraft-v4-style-pro/text-to-image',
    name: 'Recraft V4 Style Pro',
  ),
  ImageModelInfo(
    id: 'recraft-ai/recraft-v4-style-pro/text-to-vector',
    name: 'Recraft V4 Style Pro Vector',
  ),
  ImageModelInfo(
    id: 'recraft-ai/recraft-v4-style/text-to-vector',
    name: 'Recraft V4 Style Vector',
  ),
  ImageModelInfo(
    id: 'recraft-ai/recraft-v4.1/text-to-image',
    name: 'Recraft V4.1',
  ),
  ImageModelInfo(
    id: 'recraft-ai/recraft-v4.1-pro/text-to-image',
    name: 'Recraft V4.1 Pro',
  ),
  ImageModelInfo(
    id: 'recraft-ai/recraft-v4.1-pro/text-to-vector',
    name: 'Recraft V4.1 Pro Vector',
  ),
  ImageModelInfo(
    id: 'recraft-ai/recraft-v4.1/text-to-image-utility',
    name: 'Recraft V4.1 Utility',
  ),
  ImageModelInfo(
    id: 'recraft-ai/recraft-v4.1-pro/text-to-image-utility',
    name: 'Recraft V4.1 Utility Pro',
  ),
  ImageModelInfo(
    id: 'recraft-ai/recraft-v4.1/text-to-vector',
    name: 'Recraft V4.1 Vector',
  ),
  ImageModelInfo(id: 'reve/2.1/text-to-image', name: 'Reve 2.1 Create'),
  ImageModelInfo(id: 'reve/2.1/edit', name: 'Reve 2.1 Edit'),
  ImageModelInfo(id: 'reve/2.1/remix', name: 'Reve 2.1 Remix'),
  ImageModelInfo(id: 'reve-text-to-image', name: 'ReVE Art'),
  ImageModelInfo(id: 'reve-image-to-image', name: 'ReVE Image-to-Image'),
  ImageModelInfo(id: 'custom-civitai', name: 'Custom CivitAI'),
  ImageModelInfo(id: 'juggernaut-z', name: 'Juggernaut Z'),
  ImageModelInfo(id: 'runwayml-gen4-image', name: 'Runway Gen-4 Image'),
  ImageModelInfo(
    id: 'sensenova-u1-infographic',
    name: 'SenseNova U1 Infographic',
  ),
  ImageModelInfo(id: 'riverflow-2-fast', name: 'Riverflow 2 Fast'),
  ImageModelInfo(id: 'riverflow-2-max', name: 'Riverflow 2 Max'),
  ImageModelInfo(id: 'riverflow-2-standard', name: 'Riverflow 2 Standard'),
  ImageModelInfo(id: 'riverflow-2.0-pro', name: 'Riverflow 2.0 Pro'),
  ImageModelInfo(id: 'stable-diffusion-v35-large', name: 'SD 3.5 Large'),
  ImageModelInfo(
    id: 'stable-diffusion-v35-large/turbo',
    name: 'SD 3.5 Large Turbo',
  ),
  ImageModelInfo(
    id: 'sd3_base_medium.safetensors',
    name: 'Stable Diffusion 3 Medium',
  ),
  ImageModelInfo(id: 'fast-sdxl', name: 'Stable Diffusion XL'),
  ImageModelInfo(id: 'sam3-image', name: 'SAM 3 Image Segmentation'),
  ImageModelInfo(id: 'vidu-q2', name: 'Vidu Q2'),
  ImageModelInfo(id: 'vidu-q2-reference', name: 'Vidu Q2 Reference'),
  ImageModelInfo(id: 'grok-2-image', name: 'Grok 2 Image'),
  ImageModelInfo(id: 'grok-imagine-image', name: 'Grok Imagine Image'),
  ImageModelInfo(
    id: 'xai/grok-imagine-image/v2.0/text-to-image',
    name: 'Grok Imagine Image 2.0',
  ),
  ImageModelInfo(
    id: 'xai/grok-imagine-image/v2.0/edit',
    name: 'Grok Imagine Image 2.0 Edit',
  ),
  ImageModelInfo(
    id: 'xai/grok-imagine-image/quality/text-to-image',
    name: 'Grok Imagine Image Quality',
  ),
  ImageModelInfo(
    id: 'xai/grok-imagine-image/quality/edit',
    name: 'Grok Imagine Image Quality Edit',
  ),
  ImageModelInfo(id: 'glm-image-edit', name: 'GLM Image Edit'),
  ImageModelInfo(id: 'cogview-4', name: 'Z.AI CogView-4'),
  ImageModelInfo(id: 'glm-image', name: 'Z.AI GLM Image'),
];
