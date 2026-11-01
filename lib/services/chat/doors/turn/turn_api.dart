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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/llm_lanes.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';

export 'package:front_porch_ai/services/chat/doors/turn/greeting_eval_gate.dart'
    show testPostGreetingEvalEntered;

/// The turn engine's old public names (bodies in [TurnEngine] and its
/// leaves). The status members test doubles override (isGenerating,
/// isTurnBusy, the progress numbers) stay on the shell as forwarders.
extension ChatServiceTurn on ChatService {
  /// External consumers (the web server's StreamHub) listen to this for
  /// real-time token streaming.
  Stream<String> get tokenStream => turnEngine.progress.tokenBroadcast.stream;

  /// Emits complete sentences as they're detected during LLM token streaming.
  /// Used by call mode to start TTS on the first sentence immediately.
  Stream<String> get sentenceStream =>
      turnEngine.progress.sentenceBroadcast.stream;

  /// True while the turn's awaited post-generation work is still settling
  /// (see [TurnProgress.isSettlingTurn]).
  bool get isSettlingTurn => turnEngine.progress.isSettlingTurn;

  /// Continue the last bot reply (body in [TurnStops.continueGeneration]).
  Future<void> continueGeneration() => turnEngine.stops.continueGeneration();

  /// Stop the reply being written (body in [TurnStops.stopGeneration]).
  void stopGeneration() => turnEngine.stops.stopGeneration();

  /// Cancel an in-flight Realism eval or post-gen tick. No-op when idle.
  Future<void> cancelRealismEval() => turnEngine.stops.cancelRealismEval();

  /// Manual "Mark kept / broken" from the diary's Promises tab and the web
  /// Promises panel (body in [PromiseLedger.resolvePromiseManually]).
  Future<bool> resolvePromiseManually({
    required String characterId,
    required String cardId,
    required bool kept,
  }) => turnEngine.promises.resolvePromiseManually(
    characterId: characterId,
    cardId: cardId,
    kept: kept,
  );

  /// Force an immediate cast-detection scan (`/scan`; body in
  /// [TurnEntry.runCastDetectionNow]).
  Future<bool> runCastDetectionNow() => turnEngine.entry.runCastDetectionNow();

  /// Test-only: mark the in-flight post-gen as rejected so lite/engine
  /// finalize can prove they skip wear (same flag the settling yield sets).
  @visibleForTesting
  void debugRequestPostGenAbort() =>
      turnEngine.progress.postGenAbortRequested = true;
}

/// The model lanes' test surface and the studio wizards' tool check (bodies
/// in [LlmLanes], the lanes the turn streams on). No fake overrides them.
extension ChatServiceLlmLanes on ChatService {
  LlmLanes get _lanes => turnEngine.deps.services.lanes;

  @visibleForTesting
  LLMService get debugMouthLlm => _lanes.mouth;

  @visibleForTesting
  LLMService get debugSideLaneLlm => _lanes.sideLane;

  @visibleForTesting
  String get debugEvalBackendIdentity => realism.transport.backendIdentity;

  @visibleForTesting
  bool get debugOneShotActive => controlsDoor.oneShotActive;

  @visibleForTesting
  void debugMarkEvalToolsSupported() =>
      realism.transport.probe.markSupported(debugEvalBackendIdentity);

  @visibleForTesting
  Future<String?> debugFireSideLaneEval(String prompt) =>
      realism.transport.fireLLMEval(prompt, label: 'test-worker');

  /// The tool-calling verdict for the one model a studio wizard runs on
  /// (see [LlmLanes.toolCheckFor]).
  StudioToolCheck toolCheckFor({
    LLMService? via,
    String remoteModel = '',
    bool autoAsk = true,
  }) =>
      _lanes.toolCheckFor(via: via, remoteModel: remoteModel, autoAsk: autoAsk);

  /// Ask the wizard's model again now (its "Check now").
  Future<void> retestToolsFor({LLMService? via, String remoteModel = ''}) =>
      _lanes.retestToolsFor(via: via, remoteModel: remoteModel);
}
