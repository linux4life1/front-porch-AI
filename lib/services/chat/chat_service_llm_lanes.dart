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

/// The model a studio wizard runs on: null [llm] is the chat model, and a
/// non-empty [remoteModel] is the wizard's own remote pick.
class _StudioToolTarget {
  LLMService? llm;
  String remoteModel = '';
}

/// The tool check a studio wizard asks about its own model (see
/// [ChatServiceLlmLanes.toolCheckFor]). Made on first use.
final Expando<ToolSupportTester> _studioToolTesterOf = Expando(
  'studioToolTester',
);
final Expando<_StudioToolTarget> _studioToolTargetOf = Expando(
  'studioToolTarget',
);

/// Mouth (spoken reply) vs worker (evals / clerk / journal / growth).
extension ChatServiceLlmLanes on ChatService {
  LLMService get _mouthLlm =>
      testLlmServiceOverride ?? _llmProvider?.activeService ?? _koboldService;

  LLMService get _sideLaneLlm =>
      testWorkerLlmServiceOverride ??
      testLlmServiceOverride ??
      _llmProvider?.sideLaneService ??
      _koboldService;

  /// Whether the spoken-reply backend is the local KoboldCpp (a test double
  /// says so through [testIsLocalOverride]).
  bool get _mouthIsLocal => testLlmServiceOverride != null
      ? testIsLocalOverride
      : (_llmProvider?.isLocal ?? true);

  bool get _sideLaneIsKobold {
    if (testWorkerLlmServiceOverride != null) return false;
    if (testLlmServiceOverride != null) return testIsLocalOverride;
    return _llmProvider?.sideLaneIsKobold ?? false;
  }

  /// The chat a reply belongs to, for KoboldCpp's cache. Only a chat reply
  /// carries it ([GenerationParams.kvChat]).
  String? get _kvChatKey => _currentSessionId;

  /// A deleted chat's saved cache is let go. This runs inside the database's
  /// delete: what goes wrong is said in the log and goes no further.
  void _letGoOfDeletedChat(String chat) {
    try {
      _koboldService.forgetChat(chat);
    } on Object catch (e) {
      debugPrint('[Chat] letting go of a deleted chat\'s cache failed: $e');
    }
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

  /// Spoken reply stream. Waits until a GPU swap has restored the mouth.
  Stream<String> _mouthGenerateStream(GenerationParams params) async* {
    final p = _llmProvider;
    if (p != null) await p.waitForWorkerLaneIdle(pinSpeech: true);
    try {
      yield* _mouthLlm.generateStream(params);
    } finally {
      p?.endMouthSpeech();
    }
  }

  /// Unload mouth → run side-lane work → leave worker hot. Speech restores
  /// the mouth via [LLMProvider.waitForWorkerLaneIdle]. No-op when the
  /// worker is off, refused, or a test override owns the lane.
  Future<T> _withWorkerLane<T>(Future<T> Function() work) {
    if (testWorkerLlmServiceOverride != null) return work();
    final p = _llmProvider;
    if (p == null || p.workerService == null) return work();
    return p.withWorkerLane(work);
  }

  Future<void> _openWorkerLane() {
    if (testWorkerLlmServiceOverride != null) return Future<void>.value();
    final p = _llmProvider;
    if (p == null || p.workerService == null) return Future<void>.value();
    return p.openWorkerLane();
  }

  Future<void> _closeWorkerLane() {
    if (testWorkerLlmServiceOverride != null) return Future<void>.value();
    final p = _llmProvider;
    if (p == null || p.workerService == null) return Future<void>.value();
    return p.closeWorkerLane();
  }

  /// The turn was cancelled: its replies that still wait for the engine's
  /// line leave it, and nothing on the wire is touched. True when one left.
  /// Chat replies go out through the mouth, so only the mouth has any.
  bool _dropWaitingReplies() {
    try {
      return _mouthLlm.dropStoppedReplies();
    } catch (e) {
      debugPrint('[Chat] taking a stopped reply out of the line failed: $e');
      return false;
    }
  }

  /// Abort mouth speech and side-lane evals/clerk/journal together: whatever
  /// is on the wire, whoever's it is.
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

  /// The tool-calling verdict for the one model a studio wizard runs on, from
  /// chat's own check (the same ping, filed in the same store the pill
  /// reads). Asks that model when nothing has yet. [via] is the wizard's own
  /// remote pick and [remoteModel] its name; both left out mean the chat
  /// model.
  StudioToolCheck toolCheckFor({LLMService? via, String remoteModel = ''}) {
    final tester = _studioToolTesterFor(via, remoteModel)
      ..onBackendMaybeChanged();
    return (
      support: _toolProbe.supportFor(_studioToolIdentity),
      testing: tester.isTesting,
      backendReady: _studioToolLlm.isReady,
    );
  }

  /// Ask the wizard's model again now (its "Check now").
  Future<void> retestToolsFor({LLMService? via, String remoteModel = ''}) =>
      _studioToolTesterFor(via, remoteModel).test(force: true);

  _StudioToolTarget get _studioToolTarget =>
      _studioToolTargetOf[this] ??= _StudioToolTarget();

  LLMService get _studioToolLlm => _studioToolTarget.llm ?? _mouthLlm;

  String get _studioToolIdentity =>
      _mouthEvalIdentity(remoteModel: _studioToolTarget.remoteModel);

  ToolSupportTester _studioToolTesterFor(LLMService? via, String remoteModel) {
    _studioToolTarget
      ..llm = via
      ..remoteModel = remoteModel;
    return _studioToolTesterOf[this] ??= ToolSupportTester(
      probe: _toolProbe,
      fireToolEval: (ToolEvalSpec spec) => _fireToolEvalUnheld(
        spec,
        via: _studioToolLlm,
        identity: _studioToolIdentity,
      ),
      getBackendIdentity: () => _studioToolIdentity,
      isBackendReady: () => _studioToolLlm.isReady,
      // A running local engine whose model nobody has confirmed: an answer
      // would be filed under the wrong model (see [_localModelPath]).
      modelKnown: () =>
          _studioToolTarget.llm != null ||
          !(_mouthIsLocal &&
              _koboldService.isProcessRunning &&
              (_localModelPath ?? '').isEmpty),
      isBusy: () => _isGenerating || (_llmProvider?.gpuSwapBusy ?? false),
      onNotify: notifyListeners,
    );
  }

  void _disposeStudioToolTester() => _studioToolTesterOf[this]?.dispose();
}
