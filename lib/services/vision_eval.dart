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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chargen/char_macro.dart';
import 'package:front_porch_ai/services/llm_service.dart';

/// One-shot multimodal eval against the active text LLM (Vision QC and
/// portrait describe for Expression Packs).
///
/// Rides the same OpenAI-compatible chat transports as every other eval:
/// [GenerationParams.images] renders the user message as a multimodal
/// content array (KoboldCpp with an mmproj, OpenRouter,
/// Nano-GPT, vLLM, LM Studio, oMLX all accept it). Uses the standard eval
/// posture — temp 0.1, reasoning explicitly off so hybrid remotes don't
/// think through an image check — then drains the stream the way the
/// realism evals do, strips `<think>` blocks (the shared pure implementation
/// from char_macro.dart), and returns the trimmed text, or null on any
/// transport error or an empty/think-only reply.
Future<String?> fireVisionEval({
  required LLMService llm,
  required String prompt,
  required List<String> imagesB64,
  int maxLength = 1000,
}) async {
  final params = GenerationParams(
    prompt: prompt,
    maxLength: maxLength,
    temperature: 0.1,
    repeatPenalty: 1.15,
    topP: 0.5,
    xtcProbability: 0.0,
    reasoningEnabled: false,
    // The load-bearing "thinking off" knob for hybrid remote models:
    // 0 emits {enabled: false, max_tokens: 0, exclude: true} — same posture
    // as LlmEvalEngine.fireLLMEval.
    reasoningMaxTokens: 0,
    stopSequences: const [],
    images: imagesB64,
  );

  String response = '';
  try {
    await for (final chunk in llm.generateStream(params)) {
      response += chunk;
    }
  } catch (e) {
    debugPrint('[VisionEval] generation failed: $e');
    return null;
  }
  final cleaned = stripThinkBlocks(response);
  return cleaned.isEmpty ? null : cleaned;
}

/// Caption a user-attached chat photo so LATER turns' flattened history can
/// still say what it showed (the actual pixels only ride along on the turn
/// the photo was sent). One short objective description via [fireVisionEval];
/// callers must gate on a vision-capable model first — a blind model would
/// happily hallucinate a caption. Returns null when the file is unreadable
/// or the eval fails; the history marker then stays the generic
/// "[attaches a photo]".
Future<String?> captionChatImage({
  required LLMService llm,
  required String imagePath,
}) async {
  final List<int> bytes;
  try {
    bytes = await File(imagePath).readAsBytes();
  } catch (e) {
    debugPrint('[VisionEval] caption: cannot read $imagePath: $e');
    return null;
  }
  final caption = await fireVisionEval(
    llm: llm,
    prompt:
        'Describe this photo in one or two objective sentences — subjects, '
        'setting, notable details. Reply with the description only, no '
        'preamble.',
    imagesB64: [base64Encode(bytes)],
    maxLength: 160,
  );
  // Single history line: collapse whitespace/newlines the model may emit.
  return caption?.replaceAll(RegExp(r'\s+'), ' ').trim();
}
