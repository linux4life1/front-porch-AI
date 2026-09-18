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

/// Shared eval engine, post-gen trio (pockets / climax / reply-facts),
/// and tools transport. Pre-gen judge builders live in
/// [ChatServiceWiringEvalJudges].
extension ChatServiceWiringEvals on ChatService {
  // ── LLM Eval Engine (step 9: _fireLLMEval + strip + extract + needs impact cb) ──
  // Plain class (not ChangeNotifier). Owns the central eval firing (streaming/retry/cancel, 4000/0.1/no-reasoning),
  // central strip (completed+unclosed), JSON extractors, evaluateNeedsImpactCall (for needs_impact_evaluator).
  // The 5 realism eval prompt builders + calls (rel/emotion/phys/narr w/ proposed_objective, oneShot) moved to
  // sibling leaf realism_evals.dart (step 10); this engine provides fire/strip/extract cbs to it (granular).
  // objective proposal handling + generateObjectiveTasks + _checkTaskCompletionInBackground moved to
  // sibling leaf objective_proposal.dart (step 11); this engine provides strip cb to it (for 2000 paths).
  // Wired with granular cbs for 1:1 vs group (via impersonation for speaker), test overrides,
  // pending/emotion state, capture, + service deps (rel) .
  // (onNotify/onSaveChat removed in step 10 fix round 1 + step11: oneShot populates pending snapshot;
  // god owns the post-eval _saveChat/notify in pre-turn + baseline paths to avoid double + races;
  // on* dead post step11 objective move, cleaned).
  // 1:1 vs group + oneShot vs normal dispatch/parity preserved exactly (cbs + impersonation temp re-load; qualified).
  LlmEvalEngine _buildLlmEvalEngine() {
    return LlmEvalEngine(
      getActiveCharacter: () => _activeCharacter,
      getActiveGroup: () => _activeGroup,
      getIsObserverMode: () => _observerMode,
      getUserName: () => _userPersonaService.persona.name,
      getRealismEnabled: () => _realismEnabled,
      getMessages: () => _messages,
      // Shared tools transport for the needs-impact eval (one probe per
      // backend identity, app-wide).
      fireToolEval: _fireToolEval,
      probe: _toolProbe,
      getBackendIdentity: () => _evalBackendIdentity,
      getPreferTextEvals: () => _storageService.realismSettings.preferTextEvals,
      getLlmService: () => _sideLaneLlm,
      getIsLocal: () => _sideLaneIsKobold,
      getKoboldService: () {
        final s = _sideLaneLlm;
        return s is KoboldService ? s : null;
      },
      reconnectIfAlive: () async {
        final s = _sideLaneLlm;
        if (s is KoboldService) await s.reconnectIfAlive();
      },
      ensureServerIdle: () async {
        final s = _sideLaneLlm;
        if (s is KoboldService) await s.ensureServerIdle();
      },
      getIsCancellingRealismEval: () => _isCancellingRealismEval,
      getRealismEvalCancelled: () =>
          _realismEvalCancelled || _isStaleGreetingEval(),
      getPendingRealismMetadata: () => _pendingRealismMetadata ?? {},
      setPendingRealismMetadata: _writePendingRealismMetadata,
      captureRealismState: _captureRealismState,
      getCharacterEmotion: () => _characterEmotion,
      setCharacterEmotion: (v) => _characterEmotion = v,
      getEmotionIntensity: () => _emotionIntensity,
      setEmotionIntensity: (v) => _emotionIntensity = v,
      relationshipService: _relationshipService,
    );
  }

  // ── Pockets & Wardrobe (docs/design/pockets-and-preferences.md Part 1) ──
  // Its OWN pass, deliberately: the settled ruling is that Pockets rides no
  // other feature's eval. It shares only the transport — the same
  // probe-and-fallback every other structured eval uses, so a tool-less
  // backend gets the flat-JSON floor for free.
  PocketsEval _buildPocketsEval() {
    return PocketsEval(
      fire:
          ({required debugLabel, required tools, required buildPrompt}) async {
            return fireStructuredEval(
              probe: _toolProbe,
              backendIdentity: _evalBackendIdentity,
              debugLabel: debugLabel,
              tools: tools,
              buildPrompt: buildPrompt,
              callToText: (resp) =>
                  realismToolCallToJson(PocketsEval.kPocketsTool, resp.calls),
              fireToolEval: _fireToolEval,
              toolChoice: PocketsEval.kPocketsTool,
              getPreferTextEvals: () =>
                  _storageService.realismSettings.preferTextEvals,
              fireTextEval: (p, {onChunk}) => _fireLLMEval(
                p,
                repeatPenalty: kScalarEvalRepeatPenalty,
                label: 'pockets',
              ),
            );
          },
    );
  }

  // ── The fused reply-facts call (ReplyFactsEval) ──
  // One round trip for climax + pockets + posture when two or more of them
  // are live; the composition rules that keep every feature on its own gate
  // are documented on the leaf. Same transport wiring as its three siblings —
  // but constructed PER TURN by _prefetchReplyFacts rather than held as a
  // late final: the leaf is a stateless wrapper over this fire closure, and
  // one small allocation per turn is what kept the shell under the god-file
  // ratchet. Not a hot path (once per reply, never per frame).
  ReplyFactsEval _buildReplyFactsEval() {
    return ReplyFactsEval(
      fire:
          ({required debugLabel, required tools, required buildPrompt}) async {
            return fireStructuredEval(
              probe: _toolProbe,
              backendIdentity: _evalBackendIdentity,
              debugLabel: debugLabel,
              tools: tools,
              buildPrompt: buildPrompt,
              callToText: (resp) => realismToolCallToJson(
                ReplyFactsEval.kReplyFactsTool,
                resp.calls,
              ),
              fireToolEval: _fireToolEval,
              toolChoice: ReplyFactsEval.kReplyFactsTool,
              getPreferTextEvals: () =>
                  _storageService.realismSettings.preferTextEvals,
              fireTextEval: (p, {onChunk}) => _fireLLMEval(
                p,
                repeatPenalty: kScalarEvalRepeatPenalty,
                label: 'reply_facts',
              ),
            );
          },
    );
  }

  // ── Afterglow's climax check (its own pass; see ClimaxEval) ──
  // Shares only the transport, never another feature's call — the same
  // probe-and-fallback every structured eval uses, so a tool-less backend gets
  // the flat-JSON floor for free.
  ClimaxEval _buildClimaxEval() {
    return ClimaxEval(
      fire:
          ({required debugLabel, required tools, required buildPrompt}) async {
            return fireStructuredEval(
              probe: _toolProbe,
              backendIdentity: _evalBackendIdentity,
              debugLabel: debugLabel,
              tools: tools,
              buildPrompt: buildPrompt,
              callToText: (resp) =>
                  realismToolCallToJson(ClimaxEval.kClimaxTool, resp.calls),
              fireToolEval: _fireToolEval,
              toolChoice: ClimaxEval.kClimaxTool,
              getPreferTextEvals: () =>
                  _storageService.realismSettings.preferTextEvals,
              fireTextEval: (p, {onChunk}) => _fireLLMEval(
                p,
                repeatPenalty: kScalarEvalRepeatPenalty,
                label: 'climax',
              ),
            );
          },
    );
  }

  /// Tool-calling door shared by both background passes: same eval posture
  /// as _fireLLMEval (low temp, reasoning off). All backends probe — local
  /// KoboldCpp included (Qwen3 etc. call tools fine); incapable models fall
  /// back to the XML floor.
  Future<LlmToolResponse?> _fireToolEval(ToolEvalSpec spec) async {
    return _withWorkerLane(() => _fireToolEvalUnheld(spec));
  }

  Future<LlmToolResponse?> _fireToolEvalUnheld(ToolEvalSpec spec) async {
    final service = _sideLaneLlm;
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
          backendIdentity: _evalBackendIdentity,
          stillWantTools: () =>
              _toolProbe.shouldPostAfterIdle(_evalBackendIdentity),
        ),
        spec.tools,
      ).timeout(timeout);
      recordTraffic(resp);
      return resp;
    } on TimeoutException {
      // The deadline abandoned an in-flight call. On the single-slot local
      // backend that orphan holds the shared idle slot (_pendingRequest), so
      // waitForIdle callers — text evals, the Scene Guest mint — would hang
      // behind it indefinitely; tear it down. (If the server is hung on the
      // orphan, the server-side abort also frees anything queued behind it.)
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
  String get _evalBackendIdentity {
    if (_workerLaneActive) {
      final worker = testWorkerLlmServiceOverride;
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
      return _llmProvider?.workerEvalIdentity ?? '';
    }
    final service = _mouthLlm;
    final remoteApiUrl = service is LlmApiEndpoint
        ? (service as LlmApiEndpoint).apiUrl
        : (testLlmServiceOverride != null && !testIsLocalOverride
              ? _storageService.backendSettings.remoteApiUrl
              : '');
    return evalBackendIdentityFor(
      backendName: service.backendName,
      remoteApiUrl: remoteApiUrl,
      remoteModelName: _storageService.backendSettings.remoteModelName,
      modelPath: _storageService.backendSettings.lastUsedModelPath,
    );
  }

  /// Active tool-support prober behind the sidebar's tool-calling pill:
  /// verdicts land on the same [_toolProbe] the passes use, auto-retests on
  /// backend/model switches, and backs the pill's tap-to-retest.
  ToolSupportTester _buildToolSupportTester() {
    return ToolSupportTester(
      probe: _toolProbe,
      fireToolEval: _fireToolEval,
      getBackendIdentity: () => _evalBackendIdentity,
      isBackendReady: () => _sideLaneLlm.isReady,
      isBusy: () => _isGenerating || (_llmProvider?.gpuSwapBusy ?? false),
      workerLaneReadyForPing: () =>
          _llmProvider?.workerLaneReadyForAutoPing ?? true,
      onNotify: notifyListeners,
      // OpenRouter/Nano-GPT list tool support in their /models metadata, so the
      // auto-test seeds the probe for free instead of pinging the model. Gated
      // to the openRouter backend: oMLX runs at localhost (no metadata) and the
      // resolver returns null for any non-metadata host anyway — those, like
      // local backends, keep the runtime ping.
      fetchMetadataToolVerdict: () async {
        final workerOn = _llmProvider?.workerService != null;
        final type = workerOn
            ? _llmProvider!.workerBackend
            : _llmProvider?.activeBackend;
        if (type != BackendType.openRouter) return null;
        final url = workerOn
            ? resolvedLaneApiUrl(
                _storageService.workerBackendType,
                _storageService.workerRemoteApiUrl,
              )
            : _storageService.backendSettings.remoteApiUrl;
        final model = workerOn
            ? _storageService.workerRemoteModelName
            : _storageService.backendSettings.remoteModelName;
        final caps = await VisionSupportResolver.instance.capabilitiesForRemote(
          apiUrl: url,
          apiKey: _storageService.remoteApiKeyFor(url),
          modelName: model,
        );
        return caps?.toolCalling;
      },
    );
  }

  /// The current model's tool-calling verdict (sidebar pill + web facade).
  ToolCallSupport get toolCallSupport => _toolSupportTester.current;
  bool get isTestingToolSupport => _toolSupportTester.isTesting;

  /// Re-probe the current backend+model's tool support (pill tap).
  Future<void> testToolCalling() => _toolSupportTester.test(force: true);

  bool get toolCallingPaused =>
      _toolProbe.isPausedUntilPing(_evalBackendIdentity);

  /// Same object for chat-state and POST /api/chat/tool-test (additive keys).
  Map<String, dynamic> get toolSupportJson => {
    'state': toolCallSupport.name,
    'testing': isTestingToolSupport,
    'preferText': _storageService.realismSettings.preferTextEvals,
    'paused': toolCallingPaused,
    'checked': _toolSupportTester.checkedThisRun,
  };
}
