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

/// Parse a "WxH" size string into width and height integers.
(int width, int height) _parseSize(String size) {
  final parts = size.split('x');
  if (parts.length == 2) {
    final w = int.tryParse(parts[0]) ?? 1024;
    final h = int.tryParse(parts[1]) ?? 1024;
    return (w, h);
  }
  return (1024, 1024);
}

Map<String, dynamic> _buildA1111PayloadImpl({
  required String prompt,
  required String negativePrompt,
  required int width,
  required int height,
  required int steps,
  required double cfgScale,
  required String samplerName,
  required String scheduler,
  required int seed,
  String? referenceImageB64,
  double denoise = 0.5,
}) {
  final isImg2Img = referenceImageB64 != null && referenceImageB64.isNotEmpty;
  return <String, dynamic>{
    'prompt': prompt,
    'negative_prompt': negativePrompt,
    'width': width,
    'height': height,
    'steps': steps,
    'cfg_scale': cfgScale,
    'sampler_name': samplerName,
    // Only pin the scheduler when the user picked an explicit one. 'Automatic'
    // omits the field so A1111 uses its own default (and older forks that
    // don't know the field never see it). Newer A1111/Forge builds accept
    // `scheduler` alongside `sampler_name`.
    if (scheduler.isNotEmpty && scheduler != 'Automatic')
      'scheduler': scheduler,
    'seed': seed,
    'batch_size': 1,
    if (isImg2Img) 'init_images': [referenceImageB64],
    if (isImg2Img) 'denoising_strength': denoise,
    // NOTE: override_settings is intentionally omitted here.
    // Passing sd_model_checkpoint inside override_settings causes A1111 to
    // attempt a model reload mid-request, which splits tensors across
    // cpu and cuda and throws:
    //   "Expected all tensors to be on the same device"
    // The model switch is already handled by switchLocalModel() above.
  };
}
