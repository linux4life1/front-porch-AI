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

import 'dart:async';

import 'package:front_porch_ai/services/capability/vision_support_resolver.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/worker_backend.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// A structured eval's fire: the flat-JSON text of a tool call or of the
/// model's own reply (see [fireStructuredEval]).
typedef StructuredEvalFire =
    Future<String?> Function({
      required String debugLabel,
      required List<Map<String, dynamic>> tools,
      required String Function({required bool toolsMode}) buildPrompt,
    });

/// The tools transport every structured eval shares: native tool call
/// first, then the text floor (no GBNF on the floor). One probe per backend
/// identity, app-wide, so a backend answers "can you speak tools?" at most
/// once per run across Realism, the Journal and Growth.
class EvalTransport {
  EvalTransport(this._g);

  final RealismGraph _g;

  /// Shared tools-vs-text probe (one verdict per backend identity).
  final ToolTransportProbe probe = ToolTransportProbe();

  /// The chat model's key in the eval identity, read from its file once per
  /// model and per engine load.
  final LocalModelKeys _modelKeys = LocalModelKeys();

  StorageService get _storageService => _g.deps.services.storage;
  KoboldService get _koboldService => _g.deps.services.kobold;
  LLMProvider? get _llmProvider => _g.deps.services.llmProvider();

  /// The one structured-eval fire for [toolChoice]: tools first, then the
  /// text door at the scalar repeat penalty under [label].
  StructuredEvalFire structured(String toolChoice, String label) =>
      ({required debugLabel, required tools, required buildPrompt}) =>
          fireStructuredEval(
            probe: probe,
            backendIdentity: backendIdentity,
            debugLabel: debugLabel,
            tools: tools,
            buildPrompt: buildPrompt,
            callToText: (resp) => realismToolCallToJson(toolChoice, resp.calls),
            fireToolEval: fireToolEval,
            toolChoice: toolChoice,
            getPreferTextEvals: () =>
                _storageService.realismSettings.preferTextEvals,
            fireTextEval: (p, {onChunk}) => _g.transport.fireLLMEval(
              p,
              repeatPenalty: kScalarEvalRepeatPenalty,
              label: label,
            ),
          );

  /// The realism/eval text door: [LlmEvalEngine.fireLLMEval] on the worker
  /// lane. No GBNF: the JSON answers ride regex extraction and stop
  /// sequences (the grammar went in the 0.9.8 clean port).
  Future<String?> fireLLMEval(
    String prompt, {
    void Function(String)? onChunk,
    double repeatPenalty = 1.15,
    String label = 'eval',
    bool salvageReasoning = true,
    int? maxLength,
    Duration? wallClockTimeout,
    bool abortClientOnStop = false,
    bool Function(String accumulated)? stopWhen,
    void Function()? onGuardAbort,
  }) => _g.lanes.withWorkerLane(
    () => _g.llmEvalEngine.fireLLMEval(
      prompt,
      onChunk: onChunk,
      repeatPenalty: repeatPenalty,
      label: label,
      salvageReasoning: salvageReasoning,
      maxLength: maxLength,
      wallClockTimeout: wallClockTimeout,
      abortClientOnStop: abortClientOnStop,
      stopWhen: stopWhen,
      onGuardAbort: onGuardAbort,
    ),
  );

  /// Tool-calling door shared by the background passes: same eval posture
  /// as the text door (low temp, reasoning off). All backends probe — local
  /// KoboldCpp included (Qwen3 etc. call tools fine); incapable models fall
  /// back to the text floor.
  Future<LlmToolResponse?> fireToolEval(ToolEvalSpec spec) async {
    var reached = false;
    try {
      return await _g.lanes.withWorkerLane(() {
        reached = true;
        return fireToolEvalUnheld(spec);
      });
    } catch (e) {
      // A lane that could not be prepared (the helper model did not load)
      // never asked the model. That says nothing about its tool calls, and
      // read as an answer it would brand the model text-only and be kept.
      if (reached || isToolTransportFailure(e)) rethrow;
      throw LlmToolTransportException('$e');
    }
  }

  /// [via] and [identity] send it to another model than the side lane's (the
  /// chat model while a helper holds the lane); null keeps the side lane.
  Future<LlmToolResponse?> fireToolEvalUnheld(
    ToolEvalSpec spec, {
    LLMService? via,
    String? identity,
  }) async {
    final service = via ?? _g.lanes.sideLane;
    final id = identity ?? backendIdentity;
    // [EvalTraffic]: label from the named choice, never tools.first — after
    // kJudgeEvalTools that would always be report_relationship.
    final trafficWatch = Stopwatch()..start();
    void recordTraffic(LlmToolResponse? resp) => EvalTraffic.current.record(
      label: spec.toolChoice ?? 'tool',
      lane: 'tools',
      promptChars: spec.prompt.length,
      outputChars: resp == null
          ? 0
          : resp.text.length +
                resp.calls.fold(0, (a, c) => a + c.arguments.length * 16),
      ms: trafficWatch.elapsedMilliseconds,
    );
    final named = spec.toolChoice != null && spec.toolChoice!.isNotEmpty;
    // Named judges use the whole-call deadline: OpenRouter thinking
    // endpoints regularly exceed the 180s between-chunk guard that 512-token
    // scalar tools used to share.
    final timeout = named || spec.maxLength > kScalarToolMaxTokens
        ? kEvalToolCallTimeout
        : kEvalStreamChunkTimeout;
    try {
      // OpenRouterService.generateStructuredJson is generateWithTools (public
      // OR = dedicated tools path; Nano keeps the probe soup). Kobold / fakes
      // stay on generateWithTools. Kept off LLMService so fakes need no stub.
      final evalCall = service is OpenRouterService
          ? service.generateStructuredJson
          : service.generateWithTools;
      final resp = await evalCall(
        GenerationParams(
          prompt: spec.prompt,
          maxLength: spec.maxLength,
          temperature: 0.1,
          repeatPenalty: spec.repeatPenalty,
          topP: 0.5,
          xtcProbability: 0.0,
          reasoningEnabled: false,
          // Explicit thinking-off: Nano-GPT/OpenRouter only receive the
          // disable signal when the reasoning block is present, and it is
          // only emitted when a reasoning field is set. Without this a
          // ":thinking" model (e.g. Kimi K2.6) keeps reasoning during the
          // journal tool call, which returns tool calls only intermittently
          // (the "had to regen twice" symptom). 0 → {enabled:false,
          // max_tokens:0, exclude:true}, the strongest disable signal.
          reasoningMaxTokens: 0,
          // Keep the think channel on mandatory models so a 400-then-
          // exclude path cannot swallow the JSON / tool call (Kimi 2.6).
          salvageReasoning: true,
          stopSequences: const [],
          toolChoice: spec.toolChoice,
          onChunk: spec.onChunk,
          cancel: spec.cancel,
          backendIdentity: id,
          stillWantTools: () => probe.shouldPostAfterIdle(id),
        ),
        spec.tools,
      ).timeout(timeout);
      recordTraffic(resp);
      return resp;
    } on TimeoutException {
      // The deadline abandoned an in-flight call. On the single-slot local
      // backend that orphan holds the line to the engine, so everything
      // queued — text evals, the Scene Guest mint — would hang behind it
      // indefinitely; tear it down. (If the server is hung on the orphan,
      // the server-side abort also frees anything queued behind it.)
      // Remote backends don't serialize on the slot — nothing to release.
      if (service is KoboldService) service.abortGeneration();
      // The wall time was spent whether or not an answer came back.
      recordTraffic(null);
      rethrow;
    }
  }

  /// Endpoint+model identity key for the shared tools/one-shot probes.
  /// Worker lane uses a prefixed key so its verdict never lands on the
  /// mouth model's pill.
  String get backendIdentity {
    if (_g.lanes.workerLaneActive) {
      final worker = _g.lanes.testWorker();
      if (worker != null) {
        final url = worker is LlmApiEndpoint
            ? (worker as LlmApiEndpoint).apiUrl
            : '';
        return workerEvalIdentityFor(
          backendName: worker.backendName,
          remoteApiUrl: url,
          remoteModelName: 'test-worker',
          modelPath: null,
        );
      }
      final provider = _llmProvider;
      if (provider == null) return '';
      return provider.workerEvalIdentityNamed(
        modelKey: _workerNamedByEngine ? _localModelKeyNow : null,
      );
    }
    return mouthIdentity();
  }

  /// The chat model's identity. [remoteModel] names another model on the same
  /// remote host (a studio wizard's own pick); empty means chat's own.
  String mouthIdentity({String remoteModel = ''}) {
    final service = _g.lanes.mouth;
    final remoteApiUrl = service is LlmApiEndpoint
        ? (service as LlmApiEndpoint).apiUrl
        : (_g.lanes.testMouth() != null && !_g.lanes.testIsLocal()
              ? _storageService.backendSettings.remoteApiUrl
              : '');
    // The model is named by what names it: a local one by its file (name and
    // size, not folder), a remote one by its host and name. Each leaves out
    // the other's leftovers (the remote name typed last week, the local file
    // picked last month); they would send a known model to be tested again.
    final local = _g.lanes.mouthIsLocal;
    return evalBackendIdentityFor(
      backendName: service.backendName,
      remoteApiUrl: remoteApiUrl,
      remoteModelName: local
          ? ''
          : (remoteModel.isNotEmpty
                ? remoteModel
                : _storageService.backendSettings.remoteModelName),
      modelPath: local ? _localModelKeyNow : null,
    );
  }

  /// The local model the eval identity names: the one whose answers the
  /// engine gives. With nothing running, the one the next start loads. The
  /// app's record of the picked model is not it while an engine runs: a pick
  /// changes the record at once and the engine answers with the old weights
  /// until a reload has been asked for, done and read back, so an answer filed
  /// under the record would belong to another model. While the engine is
  /// still loading nothing can be asked, so it names the model it was asked to
  /// load (the pill shows what is known of it). Null for a running engine
  /// that is ready on a model nobody has confirmed: its load has not been read
  /// back, or it went back to another after a reload that did not take.
  String? get localModelPath {
    final kobold = _koboldService;
    if (!kobold.isProcessRunning) {
      return _storageService.backendSettings.lastUsedModelPath;
    }
    return kobold.answeringModelPath ??
        (kobold.modelReady ? null : kobold.loadedModelPath);
  }

  /// The local model's key in the eval identity; see [localModelPath]. An
  /// unknown is its own key, never kept and never asked on its own.
  String get _localModelKeyNow {
    final kobold = _koboldService;
    final path = localModelPath;
    if (path == null || path.isEmpty) {
      return kobold.isProcessRunning
          ? unknownLocalModelKey(kobold.loadGeneration)
          : '';
    }
    return _modelKeys.of(path, stamp: kobold.residentGeneration);
  }

  /// A local helper the lane does not swap in (the chat model is not a local
  /// one, so nothing is unloaded to make room) answers with whatever the
  /// engine runs, not with the file the helper setting names. It is named,
  /// and held back while unknown, the way the chat model is. One the lane
  /// swaps in is named by its own model, which the swap puts there and checks.
  bool get _workerNamedByEngine {
    final provider = _llmProvider;
    return _g.lanes.workerLaneActive &&
        _g.lanes.testWorker() == null &&
        provider != null &&
        provider.workerBackend == BackendType.kobold &&
        !provider.workerGpuSwapAvailable;
  }

  /// True while the local engine is ready on a model nobody has confirmed.
  bool get localModelUnknown =>
      (_g.lanes.workerLaneActive
          ? _workerNamedByEngine
          : _g.lanes.mouthIsLocal) &&
      _koboldService.isProcessRunning &&
      (localModelPath ?? '').isEmpty;

  /// Settled tool-calling verdicts outlive the run, each "no" stamped with the
  /// app and (for the local engine) the KoboldCpp version it was given under.
  void wireToolVerdicts() {
    probe
      ..store = _storageService.toolVerdictSettings
      ..stampFor = (identity) => toolVerdictStamp(
        engineVersion: _identityIsLocalEngine(identity)
            ? _llmProvider?.backendManager.localVersion
            : null,
      );
  }

  /// Whether [identity] is one whose answers come from the local engine: the
  /// chat model's when the chat backend is local, the worker's when it is.
  bool _identityIsLocalEngine(String identity) => identity.startsWith('worker|')
      ? _llmProvider?.workerBackend == BackendType.kobold
      : _g.lanes.mouthIsLocal;

  // ── The sidebar's tool-calling pill and the web facade ────────────────

  /// The current model's tool-calling verdict.
  ToolCallSupport get toolCallSupport => _g.toolSupportTester.current;
  bool get isTestingToolSupport => _g.toolSupportTester.isTesting;

  /// Re-probe the current backend+model's tool support (pill tap).
  Future<void> testToolCalling() => _g.toolSupportTester.test(force: true);

  bool get toolCallingPaused => probe.isPausedUntilPing(backendIdentity);

  /// Same object for chat-state and POST /api/chat/tool-test (additive keys).
  Map<String, dynamic> get toolSupportJson => {
    'state': toolCallSupport.name,
    'testing': isTestingToolSupport,
    'preferText': _storageService.realismSettings.preferTextEvals,
    'paused': toolCallingPaused,
    'checked': _g.toolSupportTester.checkedThisRun,
    'saved': probe.isKept(backendIdentity),
  };
}

/// The transport and the sidebar pill's prober.
extension RealismTransportWiring on RealismGraph {
  EvalTransport buildTransport() => EvalTransport(this);

  /// Active tool-support prober behind the sidebar's tool-calling pill:
  /// verdicts land on the same probe the passes use, auto-retests on
  /// backend/model switches, and backs the pill's tap-to-retest.
  ToolSupportTester buildToolSupportTester() {
    final storage = deps.services.storage;
    LLMProvider? provider() => deps.services.llmProvider();
    return ToolSupportTester(
      probe: transport.probe,
      fireToolEval: transport.fireToolEval,
      getBackendIdentity: () => transport.backendIdentity,
      isBackendReady: () => lanes.sideLane.isReady,
      modelKnown: () => !transport.localModelUnknown,
      isBusy: () =>
          deps.hooks.isGenerating() || (provider()?.gpuSwapBusy ?? false),
      workerLaneReadyForPing: () =>
          provider()?.workerLaneReadyForAutoPing ?? true,
      onNotify: deps.notify,
      onForcedRetest: deps.services.kobold.toolCrashGuard.clear,
      // OpenRouter/Nano-GPT list tool support in their /models metadata, so the
      // auto-test seeds the probe for free instead of pinging the model. Gated
      // to the openRouter backend: oMLX runs at localhost (no metadata) and the
      // resolver returns null for any non-metadata host anyway — those, like
      // local backends, keep the runtime ping.
      fetchMetadataToolVerdict: () async {
        final workerOn = provider()?.workerService != null;
        final type = workerOn
            ? provider()!.workerBackend
            : provider()?.activeBackend;
        if (type != BackendType.openRouter) return null;
        final url = workerOn
            ? resolvedLaneApiUrl(
                storage.workerBackendType,
                storage.workerRemoteApiUrl,
              )
            : storage.backendSettings.remoteApiUrl;
        final model = workerOn
            ? storage.workerRemoteModelName
            : storage.backendSettings.remoteModelName;
        final caps = await VisionSupportResolver.instance.capabilitiesForRemote(
          apiUrl: url,
          apiKey: storage.remoteApiKeyFor(url),
          modelName: model,
        );
        return caps?.toolCalling;
      },
    );
  }
}
