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

import 'kcpps_codec.dart';
import 'kobold_app_config.dart';
import 'kobold_launch_config.dart';
import 'kobold_launch_failure.dart';

/// The config a launch runs for a user's preset: the file as it was written,
/// with only what the app has to own laid over it.
///
/// Laid over: the model the app resolved, the chat template (always on, chat
/// needs it), the vision file (when one was chosen for the model and it
/// exists), and sliding window switched off when the file has it on together
/// with fast forward. [onNote] is told about that last one, and about a
/// forced automatic fit that overrides the file's own layer count.
///
/// [flashAttentionOff]: the ROCm build died on this machine with flash
/// attention on, so it is switched off here too (with a compressed cache
/// back to full size, which needs it), and [onNote] is told.
///
/// A file that does not mention sliding window is left as it is: KoboldCpp's
/// own default then applies. The launch says so when the model has sliding
/// window (see [kSwaLeftToKoboldNote]).
///
/// Everything else is the user's and passes through untouched. Rebuilding
/// the file from the app's typed settings dropped what those cannot hold (a
/// second graphics card, the CUDA options, a MoE layer count) and wrote the
/// app's default wherever the file had left a choice to KoboldCpp.
Map<String, dynamic> kcppsPresetLaunchMap(
  Map<String, dynamic> preset, {
  required String modelPath,
  required String mmprojPath,
  void Function(String note)? onNote,
  bool flashAttentionOff = false,
}) {
  final map = Map<String, dynamic>.of(preset);
  if (modelPath.isNotEmpty) map['model_param'] = modelPath;
  map['jinja'] = true;
  if (mmprojPath.isNotEmpty) map['mmproj'] = mmprojPath;

  // Sliding window together with fast forward degrades the model's output.
  if (kcppsHasSwaOn(map) && map['nofastforward'] != true) {
    map['noswa'] = true;
    onNote?.call(kSwaWithFastForwardNote);
  }
  final forcedFit = kcppsForcedFitNote(map);
  if (forcedFit != null) onNote?.call(forcedFit);

  // The ROCm build died on this machine with flash attention on. A
  // compressed cache needs it, so that goes back to full size too.
  if (flashAttentionOff && kcppsRunsFlashAttention(map)) {
    map['noflashattention'] = true;
    if (KvQuant.parse(map['quantkv']).needsFlashAttention) {
      map['quantkv'] = KvQuant.f16.wire;
    }
    onNote?.call(
      koboldFlashAttentionNote(
        backend: KoboldGpuBackend.cuda,
        rocm: true,
        rocmFailedBefore: true,
      )!,
    );
  }
  return map;
}
