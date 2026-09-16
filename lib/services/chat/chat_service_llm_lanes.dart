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

part of '../chat_service.dart';

/// Mouth (spoken reply) vs worker (evals / clerk / journal / growth).
extension ChatServiceLlmLanes on ChatService {
  LLMService get _mouthLlm =>
      testLlmServiceOverride ?? _llmProvider?.activeService ?? _koboldService;

  LLMService get _sideLaneLlm =>
      testWorkerLlmServiceOverride ??
      testLlmServiceOverride ??
      _llmProvider?.sideLaneService ??
      _koboldService;

  bool get _sideLaneIsKobold {
    if (testWorkerLlmServiceOverride != null) return false;
    if (testLlmServiceOverride != null) return testIsLocalOverride;
    return _llmProvider?.sideLaneIsKobold ?? false;
  }

  bool get _workerLaneActive =>
      testWorkerLlmServiceOverride != null ||
      (testLlmServiceOverride == null && (_llmProvider?.workerService != null));

  @visibleForTesting
  LLMService get debugMouthLlm => _mouthLlm;

  @visibleForTesting
  LLMService get debugSideLaneLlm => _sideLaneLlm;

  @visibleForTesting
  String get debugEvalBackendIdentity => _evalBackendIdentity;

  @visibleForTesting
  Future<String?> debugFireSideLaneEval(String prompt) =>
      _fireLLMEval(prompt, label: 'test-worker');

  /// Stop mouth speech and side-lane evals/clerk/journal together.
  void _abortAllLanes() {
    final mouth = _mouthLlm;
    final side = _sideLaneLlm;
    try {
      mouth.abortGeneration();
    } catch (_) {}
    if (!identical(side, mouth)) {
      try {
        side.abortGeneration();
      } catch (_) {}
    }
  }
}
