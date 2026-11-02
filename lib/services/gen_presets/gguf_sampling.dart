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

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/gen_presets/sampler_values.dart';
import 'package:front_porch_ai/utils/gguf_reader.dart';

/// The model author's samplers that llama.cpp's converter writes into a GGUF
/// under `general.sampling.*`, from the model's `generation_config.json`
/// (llama.cpp #17120). Older files carry none.
SamplerValues samplingFromGgufMeta(Map<String, dynamic>? meta) {
  if (meta == null) return const SamplerValues();
  double? d(String k) {
    final v = meta['general.sampling.$k'];
    return v is num && v.isFinite ? v.toDouble() : null;
  }

  int? i(String k) {
    final v = meta['general.sampling.$k'];
    return v is num && v.isFinite ? v.round() : null;
  }

  final lastN = i('penalty_last_n');
  return SamplerValues(
    temperature: d('temp'),
    topK: i('top_k'),
    topP: d('top_p'),
    minP: d('min_p'),
    xtcProbability: d('xtc_probability'),
    xtcThreshold: d('xtc_threshold'),
    repeatPenalty: d('penalty_repeat'),
    // -1 means "the whole context" in llama.cpp, which the app cannot say.
    repeatPenaltyTokens: lastN != null && lastN > 0 ? lastN : null,
  );
}

/// Reads [samplingFromGgufMeta] from the header of the file at [path]. Empty
/// when the file is missing or unreadable.
Future<SamplerValues> readGgufSampling(String path) async {
  final file = File(path);
  if (!await file.exists()) return const SamplerValues();
  RandomAccessFile? raf;
  try {
    raf = await file.open(mode: FileMode.read);
    // general.* keys come before the tokenizer, well inside this window.
    final bytes = await raf.read(4 * 1024 * 1024);
    return samplingFromGgufMeta(GGUFFileReader.parseMetadataBytes(bytes));
  } catch (e) {
    debugPrint('[GenPresets] could not read samplers from $path: $e');
    return const SamplerValues();
  } finally {
    await raf?.close();
  }
}
