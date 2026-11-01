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

import 'package:front_porch_ai/services/chat/doors/realism/eval_transport.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';
import 'package:front_porch_ai/services/chat/tool_eval_spec.dart';
import 'package:front_porch_ai/services/chat/tool_support_tester.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/worker_backend.dart';

/// The two model lanes a chat runs on: the mouth (the spoken reply) and the
/// worker (evals, the clerk, the Journal and Growth), with the test doubles
/// that stand in for either, and the tool check a studio wizard asks about
/// its own model.
///
/// Every input is read live: the provider is wired after the service is
/// built, and tests set the overrides on a running service.
class LlmLanes {
  LlmLanes({
    required KoboldService Function() kobold,
    required this.provider,
    required this.testMouth,
    required this.testWorker,
    required this.testIsLocal,
    required this.isGenerating,
    required this.transport,
    required this.notify,
  }) : _kobold = kobold;

  final KoboldService Function() _kobold;
  final LLMProvider? Function() provider;

  /// Test-only doubles for the chat model and the worker, and whether the
  /// chat double counts as the local engine.
  final LLMService? Function() testMouth;
  final LLMService? Function() testWorker;
  final bool Function() testIsLocal;

  /// Tokens are streaming (a studio check waits for the reply).
  final bool Function() isGenerating;

  /// The shared tools transport the studio check files its verdict in.
  final EvalTransport Function() transport;
  final void Function() notify;

  KoboldService get _koboldService => _kobold();

  /// The spoken-reply backend.
  LLMService get mouth =>
      testMouth() ?? provider()?.activeService ?? _koboldService;

  /// The side lane: the worker when one is on, else the chat model.
  LLMService get sideLane =>
      testWorker() ??
      testMouth() ??
      provider()?.sideLaneService ??
      _koboldService;

  /// Whether the spoken-reply backend is the local KoboldCpp (a test double
  /// says so through [testIsLocal]).
  bool get mouthIsLocal =>
      testMouth() != null ? testIsLocal() : (provider()?.isLocal ?? true);

  /// Whether the spoken-reply model is the user's own (see
  /// [LLMProvider.modelIsLocal]); a test double says so through
  /// [testIsLocal].
  bool get mouthModelIsLocal =>
      testMouth() != null ? testIsLocal() : (provider()?.modelIsLocal ?? true);

  /// Whether the model that runs the Realism evals is the user's own: the
  /// helper while its lane is on, else the chat model. One-Shot Auto reads
  /// it, beside the same lane's tool verdict.
  bool get evalModelIsLocal {
    if (!workerLaneActive) return mouthModelIsLocal;
    final worker = testWorker();
    if (worker == null) return provider()?.workerModelIsLocal ?? true;
    return evalLaneIsHomeNetwork(
      worker is KoboldService ? 'kobold' : 'openRouter',
      worker is LlmApiEndpoint ? (worker as LlmApiEndpoint).apiUrl : '',
    );
  }

  bool get sideLaneIsKobold {
    if (testWorker() != null) return false;
    if (testMouth() != null) return testIsLocal();
    return provider()?.sideLaneIsKobold ?? false;
  }

  bool get workerLaneActive =>
      testWorker() != null ||
      (testMouth() == null && (provider()?.workerService != null));

  /// Spoken reply stream. Waits until a GPU swap has restored the mouth.
  Stream<String> mouthGenerateStream(GenerationParams params) async* {
    final p = provider();
    if (p != null) await p.waitForWorkerLaneIdle(pinSpeech: true);
    try {
      yield* mouth.generateStream(params);
    } finally {
      p?.endMouthSpeech();
    }
  }

  /// Unload mouth → run side-lane work → leave worker hot. Speech restores
  /// the mouth via [LLMProvider.waitForWorkerLaneIdle]. No-op when the
  /// worker is off, refused, or a test override owns the lane.
  Future<T> withWorkerLane<T>(Future<T> Function() work) {
    if (testWorker() != null) return work();
    final p = provider();
    if (p == null || p.workerService == null) return work();
    return p.withWorkerLane(work);
  }

  Future<void> openWorkerLane() {
    if (testWorker() != null) return Future<void>.value();
    final p = provider();
    if (p == null || p.workerService == null) return Future<void>.value();
    return p.openWorkerLane();
  }

  Future<void> closeWorkerLane() {
    if (testWorker() != null) return Future<void>.value();
    final p = provider();
    if (p == null || p.workerService == null) return Future<void>.value();
    return p.closeWorkerLane();
  }

  /// KoboldCpp's idle wait, or null when no provider is wired.
  Future<void>? mouthIdle() => provider()?.koboldService.waitForIdle();

  /// The turn was cancelled: its replies that still wait for the engine's
  /// line leave it, and nothing on the wire is touched. True when one left.
  /// Chat replies go out through the mouth, so only the mouth has any.
  bool dropWaitingReplies() {
    try {
      return mouth.dropStoppedReplies();
    } catch (e) {
      debugPrint('[Chat] taking a stopped reply out of the line failed: $e');
      return false;
    }
  }

  /// Abort mouth speech and side-lane evals/clerk/journal together: whatever
  /// is on the wire, whoever's it is.
  void abortAll() {
    final m = mouth;
    final side = sideLane;
    try {
      m.abortGeneration();
    } catch (_) {}
    if (!identical(side, m)) {
      try {
        side.abortGeneration();
      } catch (_) {}
    }
  }

  // ── The studio wizards' tool check ────────────────────────────────────

  /// The model a studio wizard runs on: null is the chat model, and a
  /// non-empty remote name is the wizard's own remote pick.
  LLMService? _studioLlm;
  String _studioRemoteModel = '';
  ToolSupportTester? _studioTester;

  /// The tool-calling verdict for the one model a studio wizard runs on, from
  /// chat's own check (the same ping, filed in the same store the pill
  /// reads). With [autoAsk] it asks that model when nothing has yet; the
  /// World from Wiki wizard passes false, because on oMLX or LM Studio a
  /// ping loads the model, and the maintainer wants no load until Next
  /// (its Next and Check now go through [retestToolsFor]). [via] is the
  /// wizard's own remote pick and [remoteModel] its name; both left out
  /// mean the chat model.
  StudioToolCheck toolCheckFor({
    LLMService? via,
    String remoteModel = '',
    bool autoAsk = true,
  }) {
    final tester = _studioToolTesterFor(via, remoteModel);
    if (autoAsk) tester.onBackendMaybeChanged();
    return (
      support: transport().probe.supportFor(_studioToolIdentity),
      testing: tester.isTesting,
      backendReady: _studioToolLlm.isReady,
    );
  }

  /// Ask the wizard's model again now (its "Check now").
  Future<void> retestToolsFor({LLMService? via, String remoteModel = ''}) =>
      _studioToolTesterFor(via, remoteModel).test(force: true);

  LLMService get _studioToolLlm => _studioLlm ?? mouth;

  String get _studioToolIdentity =>
      transport().mouthIdentity(remoteModel: _studioRemoteModel);

  ToolSupportTester _studioToolTesterFor(LLMService? via, String remoteModel) {
    _studioLlm = via;
    _studioRemoteModel = remoteModel;
    return _studioTester ??= ToolSupportTester(
      probe: transport().probe,
      fireToolEval: (ToolEvalSpec spec) => transport().fireToolEvalUnheld(
        spec,
        via: _studioToolLlm,
        identity: _studioToolIdentity,
      ),
      getBackendIdentity: () => _studioToolIdentity,
      isBackendReady: () => _studioToolLlm.isReady,
      // A running local engine whose model nobody has confirmed: an answer
      // would be filed under the wrong model (see
      // [EvalTransport.localModelPath]).
      modelKnown: () =>
          _studioLlm != null ||
          !(mouthIsLocal &&
              _koboldService.isProcessRunning &&
              (transport().localModelPath ?? '').isEmpty),
      isBusy: () => isGenerating() || (provider()?.gpuSwapBusy ?? false),
      onNotify: notify,
      onForcedRetest: () {
        final service = _studioToolLlm;
        if (service is KoboldService) service.toolCrashGuard.clear();
      },
    );
  }

  /// Releases the studio check's tester, if one was made.
  void dispose() => _studioTester?.dispose();
}
