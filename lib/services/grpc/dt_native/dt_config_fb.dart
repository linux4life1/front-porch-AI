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

import 'dart:typed_data';

import 'package:flat_buffers/flat_buffers.dart' as fb;

/// Builds the FlatBuffer `GenerationConfiguration` Draw Things expects in
/// ImageGenerationRequest.configuration — a 1:1 port of
/// `build_config_flatbuffer` + `_build_generation_config` in the Python
/// sidecar (tools/dt-grpc-python/client.py, deleted with the sidecar
/// retirement — see git history). Slot ids AND
/// per-slot defaults must match the generated GenerationConfiguration.py
/// exactly: FlatBuffers omits a field whose value equals its schema default,
/// and the Python side conditionally skips some fields entirely (numFrames,
/// the teaCache block) — both behaviors are replicated here so the server
/// sees identical semantics. Verified by cross-language golden tests.
///
/// Input is the same JSON-ish config map the Dart service already builds for
/// the sidecar (`start_width`, `steps`, `guidance_scale`, ... `loras`), so
/// the native and sidecar paths share one contract.
Uint8List buildGenerationConfig(Map<String, dynamic> cfg) {
  final b = fb.Builder(initialSize: 1024);

  double d(String key, double def) => (cfg[key] as num?)?.toDouble() ?? def;
  int i(String key, int def) => (cfg[key] as num?)?.toInt() ?? def;
  bool bl(String key, bool def) => (cfg[key] as bool?) ?? def;

  final model = (cfg['model'] as String?) ?? '';
  final refinerModel = (cfg['refiner_model'] as String?) ?? '';

  // Strings + child tables must be written before the main table starts.
  final modelOff = model.isNotEmpty ? b.writeString(model) : null;
  final refinerOff = refinerModel.isNotEmpty ? b.writeString(refinerModel) : null;

  // LoRA tables: { file: str@0, weight: f32@1 (def 0.6), mode: i8@2 (def 0) }
  final loraOffsets = <int>[];
  for (final entry in (cfg['loras'] as List?) ?? const []) {
    if (entry is! Map) continue;
    final file = (entry['file'] as String?)?.trim() ?? '';
    if (file.isEmpty) continue;
    final weight = (entry['weight'] as num?)?.toDouble() ?? 1.0;
    final mode = (entry['mode'] as num?)?.toInt() ?? 0;
    final fileOff = b.writeString(file);
    b.startTable(3);
    b.addOffset(0, fileOff);
    b.addFloat32(1, weight, 0.6);
    b.addInt8(2, mode, 0);
    loraOffsets.add(b.endTable());
  }
  final lorasVec = loraOffsets.isNotEmpty ? b.writeList(loraOffsets) : null;

  final teaCache = bl('tea_cache', false);
  final numFrames = i('num_frames', 0);

  // Main table — highest used slot is 82 (cfgZeroStar).
  b.startTable(83);
  b.addUint16(1, i('start_width', 16), 0);
  b.addUint16(2, i('start_height', 16), 0);
  b.addUint32(3, i('seed', 0), 0);
  b.addUint32(4, i('steps', 20), 0);
  b.addFloat32(5, d('guidance_scale', d('cfg_scale', 7.0)), 0.0);
  b.addFloat32(6, d('strength', 1.0), 0.0);
  if (modelOff != null) b.addOffset(7, modelOff);
  b.addInt8(8, i('sampler', 0), 0);
  b.addUint32(9, i('batch_count', 1), 1);
  b.addUint32(10, i('batch_size', 1), 1);
  if (refinerOff != null) b.addOffset(28, refinerOff);
  b.addFloat32(38, d('refiner_start', 0.7), 0.7);
  b.addInt8(17, i('seed_mode', 2), 0);
  // Python: field written only when num_frames > 0 (slot default is 14).
  if (numFrames > 0) b.addUint32(46, numFrames, 14);
  b.addFloat32(49, d('shift', 1.0), 1.0);
  b.addBool(58, bl('preserve_original_after_inpaint', true), true);
  b.addBool(71, bl('resolution_dependent_shift', false), true);
  b.addFloat32(21, d('mask_blur', 1.5), 0.0);
  b.addFloat32(48, d('sharpness', 0.0), 0.0);
  b.addBool(75, teaCache, false);
  if (teaCache) {
    // Python writes the teaCache block only when tea_cache is on.
    b.addFloat32(74, d('tea_cache_threshold', 0.15), 0.06);
    b.addInt32(72, i('tea_cache_start', 2), 5);
    b.addInt32(73, i('tea_cache_end', -1), -1);
    b.addInt32(78, i('tea_cache_max_skip_steps', 3), 3);
  }
  b.addBool(79, bl('causal_inference_enabled', false), false);
  b.addInt32(80, i('causal_inference', 3), 3);
  b.addInt32(81, i('causal_inference_pad', 0), 0);
  if (lorasVec != null) b.addOffset(20, lorasVec);
  b.addBool(82, bl('cfg_zero_star', false), false);

  final root = b.endTable();
  b.finish(root);
  return b.buffer;
}
