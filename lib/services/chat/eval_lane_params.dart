// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Fixed GenerationParams for the eval / clerk side lane. Not user-editable.
// Character mouth streams keep resolveMaxLength and the user's samplers.

import 'package:front_porch_ai/services/llm_service.dart';

/// Shared max tokens for [fireLLMEval] and the catalog doorbell/clerk.
/// Tool selection is retrieval, not the spoken reply — this is the eval
/// budget, not [resolveMaxLength].
const int kEvalLaneMaxLength = 4000;

/// [fireLLMEval] temperature. Clerk copies it so tool choice stays
/// deterministic (does not invent facts).
const double kEvalLaneTemperature = 0.1;

/// [fireLLMEval] top-P.
const double kEvalLaneTopP = 0.5;

/// [fireLLMEval] default repeat penalty (prose-emitting evals). Scalar
/// JSON evals pass [kScalarEvalRepeatPenalty] (1.0) into the same builder.
const double kEvalLaneRepeatPenalty = 1.15;

/// The [fireLLMEval] GenerationParams block. Clerk uses the same numbers
/// with [salvageReasoning] false (tool picks are not the Thought chip).
GenerationParams evalLaneParams({
  required String prompt,
  double repeatPenalty = kEvalLaneRepeatPenalty,
  bool salvageReasoning = true,
  int maxLength = kEvalLaneMaxLength,
  String? systemPrompt,
  List<Map<String, Object>>? chatMessages,
  List<String>? images,
  String? toolChoice,
  bool Function()? stillWantTools,
  String backendIdentity = '',
}) {
  return GenerationParams(
    prompt: prompt,
    maxLength: maxLength,
    minLength: 0,
    temperature: kEvalLaneTemperature,
    repeatPenalty: repeatPenalty,
    topP: kEvalLaneTopP,
    xtcProbability: 0.0,
    reasoningEnabled: false,
    reasoningMaxTokens: 0,
    salvageReasoning: salvageReasoning,
    stopSequences: const [],
    systemPrompt: systemPrompt,
    chatMessages: chatMessages,
    images: images,
    toolChoice: toolChoice,
    stillWantTools: stillWantTools,
    backendIdentity: backendIdentity,
  );
}
