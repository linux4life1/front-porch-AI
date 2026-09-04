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

/// Phase 4 of `_generateResponse` (see chat_service_generation.dart): syncs
/// the late-filled plan sections, renders the final prompt, records the
/// Context Viewer snapshot, builds the stop-sequence list, resolves the LLM
/// service (+ call-mode model swap), builds [GenerationParams], and starts
/// the stream (plus the prefill perf poller). Extracted verbatim (mechanical
/// `x` → `t.x` carrier rename only — see `_GenTurn`) from the single
/// ~1.9k-line `_generateResponse` method during the god-file split
/// (docs/design/god-file-elimination.md). Zero behaviour change.
///
/// H3 (do not "fix"): [contextSize] below is the bare ChatService GETTER
/// (`contextSize` on `ChatService`, session-resolved), a DIFFERENT value from
/// the raw backend-settings local of the same name in the RAG phase
/// (`chat_service_generation_rag.dart`). Do not hoist either onto the
/// carrier or unify the two scopes.
extension ChatServiceGenerationRequest on ChatService {
  Future<void> _dispatchGeneration(_GenTurn t) async {
    // Realism injection was already computed above for budget

    // Inject fourth-wall idle cue if Dynamic Responses triggered.
    // Placed in the user-prompt body (not system prompt) so it sits right
    // before the generation point — local models often ignore system-role
    // instructions but follow the last content in the user message.
    final idleCue = _pendingIdleCue;
    if (idleCue != null) {
      t.suffix = '\n${t.speakingCharacter.name}: *';
    }

    // Sync the late-filled sections, then render everything from the plan.
    // Every backend speaks the OpenAI chat protocol (local KoboldCpp via
    // its /v1/chat/completions door), so the system zone rides a proper
    // 'system' role message and the transcript zone the 'user' message —
    // the server applies the model's instruct template server-side.
    t.plan.section('history').text = t.history;
    t.plan.section('memories').text = t.memoriesBlock;
    t.plan.section('idle_cue').text = idleCue != null ? '\n$idleCue' : '';
    t.plan.section('suffix').text = t.suffix;

    final chatSystemPrompt = t.plan.systemText;
    final prompt = t.plan.userText;

    // Context viewer: plan budget/sections (session-persisted on save).
    _contextBudget.recordLastSend(
      budgetMap: {
        ...t.plan.budgetEstimates(),
        if (t.droppedMessages > 0) 'Dropped Messages': t.droppedMessages,
      },
      sectionMap: t.plan.sectionTexts(),
      contextLimit: contextSize,
    );

    // Stop sequences, priority-ordered (stop_sequences.dart) so transports
    // that cap the server-side list keep the most important entries: user
    // stops, then custom stops, then character names, then defaults. The
    // client-side mid-stream trim below always enforces the FULL list.
    final g2 = t.g2 = _sessionGenSettings;

    // For Continue mode, do *not* stop on the current speaker's name.
    // This lets the model produce long, natural extensions of the existing message
    // in that character's voice without the name stop cutting it off mid-continuation.
    // We still stop on other speakers or the user (to catch unwanted new turns).
    String? continueSpeakerName;
    if (t.mode == GenerationMode.continue_ &&
        _messages.isNotEmpty &&
        !_messages.last.isUser) {
      continueSpeakerName = _messages.last.sender;
    }

    // Group rosters are rotated so the soonest next speakers come first —
    // they are the likeliest voices the model bleeds into, so their name
    // stops must survive a capped transport.
    List<String> stopCharacterNames;
    if (_activeGroup != null) {
      final names = _groupCharacters.map((c) => c.name).toList();
      // Rotate by IDENTITY, not display name — duplicate display names
      // would lock onto the first twin and rotate around the wrong seat
      // (review finding). Name lookup only as a fallback.
      var idx = _groupCharacters.indexWhere(
        (c) => identical(c, t.speakingCharacter),
      );
      if (idx < 0) idx = names.indexOf(t.speakingCharacter.name);
      stopCharacterNames = idx >= 0
          ? [...names.sublist(idx + 1), ...names.sublist(0, idx + 1)]
          : names;
    } else {
      stopCharacterNames = [_activeCharacter!.name];
    }

    final stopList = t.stopList = buildPrioritizedStops(
      configured: g2.resolveStopSequences(_storageService),
      userName: _userPersonaService.persona.name,
      // In impersonate mode the model IS the user, so don't stop on user name
      impersonating: t.mode == GenerationMode.impersonate,
      characterNames: stopCharacterNames,
      continueSpeakerName: continueSpeakerName,
    );

    // Get the active LLM service (local or remote)
    final llmService =
        testLlmServiceOverride ?? _llmProvider?.activeService ?? _koboldService;

    // For call mode with a dedicated call model, temporarily swap the model.
    // When sendMessage already swapped for the pre-generation evals (the
    // safe speed lane), ADOPT that swap into the turn carrier instead of
    // re-capturing: reading modelName now would record the CALL model as the
    // "original" and every restore site would restore to the wrong model.
    if (_callEvalModelOriginal != null) {
      t.originalModelName = _callEvalModelOriginal;
      _callEvalModelOriginal = null;
    } else if (_callMode &&
        _storageService.sttSettings.callModelName.isNotEmpty &&
        _llmProvider != null &&
        !_llmProvider!.isLocal) {
      t.originalModelName = _llmProvider!.openRouterService.modelName;
      _llmProvider!.openRouterService.configure(
        modelName: _storageService.sttSettings.callModelName,
      );
    }

    // ── Current-turn photo attachment ─────────────────────────────────
    // Turn-scoped in [buildTurnImages]: the photo's pixels ride only on the
    // response that directly answers the turn it was sent on (fresh turn,
    // regenerate, first group speaker, or continue of that reply) and never
    // on a later idle/AFK, group auto-advance, or guest turn. Blind backends
    // get null and rely on the history marker from _formatHistoryLine.
    final turnImages = await buildTurnImages(t.mode);

    GenerationParams paramsOf(
      String p, {
      String? systemPrompt,
      bool? reasoningEnabled,
      int? reasoningMaxTokens,
    }) {
      final callOrContinue = _callMode || t.mode == GenerationMode.continue_;
      return GenerationParams(
        prompt: p,
        systemPrompt: systemPrompt ?? chatSystemPrompt,
        maxLength: g2.resolveMaxLength(_storageService),
        minLength: g2.resolveMinLength(_storageService),
        minP: g2.resolveMinP(_storageService),
        topP: g2.resolveTopP(_storageService),
        topK: g2.resolveTopK(_storageService),
        dryMultiplier: g2.resolveDryMultiplier(_storageService),
        temperature: g2.resolveTemperature(_storageService),
        repeatPenalty: g2.resolveRepeatPenalty(_storageService),
        repPenTokens: g2.resolveRepeatPenaltyTokens(_storageService),
        dynatempRange: g2.resolveDynamicTempEnabled(_storageService)
            ? g2.resolveDynamicTempRange(_storageService)
            : null,
        xtcThreshold: g2.resolveXtcThreshold(_storageService),
        xtcProbability: g2.resolveXtcProbability(_storageService),
        stopSequences: stopList,
        reasoningEnabled:
            reasoningEnabled ??
            (callOrContinue
                ? false
                : (_llmProvider != null && !_llmProvider!.isLocal)
                ? reasoningEffortThinkingOn(
                    _llmProvider!.openRouterService.modelName,
                    g2.resolveReasoningEnabled(_storageService),
                  )
                : g2.resolveReasoningEnabled(_storageService)),
        reasoningEffort: g2.resolveReasoningEffort(_storageService),
        // Force zero thinking budget on Continue (and call mode) for providers like OpenRouter/Nano-GPT.
        // This tells supported models (Kimi K2 Thinking, DeepSeek hybrid reasoning models, certain Qwen3 etc.)
        // to spend 0 tokens on internal reasoning and answer directly, preventing the model from dumping
        // its next analysis/think block into the visible character response.
        reasoningMaxTokens: reasoningMaxTokens ?? (callOrContinue ? 0 : null),
        bannedPhrases: g2.resolveBannedPhrases(_storageService).isNotEmpty
            ? g2.resolveBannedPhrases(_storageService)
            : null,
        images: turnImages,
      );
    }

    var genParams = paramsOf(prompt);

    // Model-initiated web_search: a silent think-to-search round, then the
    // in-character stream. The immutable direct-send bit is a fail-closed
    // allow-list: group follow-ups, guests, cast, regen, Continue, and idle
    // never advertise the tool. xml-only → stream. Read the Porch Life global
    // here — not at chat-open seed — so flipping it on activates this turn.
    final globalDefault = _storageService.webSearchSettings.webSearchDefault;
    final xmlOnly = _toolProbe.isXmlOnly(_evalBackendIdentity);
    final advertise = shouldAdvertiseWebSearch(
      globalDefault: globalDefault,
      directUserSend: t.directUserSend,
      continueMode: t.mode == GenerationMode.continue_,
      toolsUnsupported: xmlOnly,
      autonomousMode: t.autonomous,
    );
    debugPrint(
      '[WebSearch] gate advertise=$advertise global=$globalDefault '
      'directUserSend=${t.directUserSend} '
      'continue=${t.mode == GenerationMode.continue_} '
      'autonomous=${t.autonomous} xmlOnly=$xmlOnly '
      'backend=${llmService.backendName}',
    );
    if (advertise) {
      // Decision phase is not the reply: drop the `Name:` suffix so the
      // model thinks instead of completing dialogue, force thinking on
      // (call mode keeps the speed lane), ignore any canned text.
      final savedSuffix = t.plan.section('suffix').text;
      t.plan.section('suffix').text = '';
      final decisionPrompt = webSearchDecisionPrompt(t.plan.userText);
      t.plan.section('suffix').text = savedSuffix;
      final round = await runWebSearchRound(
        llm: llmService,
        params: paramsOf(
          decisionPrompt,
          systemPrompt: webSearchDecisionSystemPrompt(chatSystemPrompt),
          reasoningEnabled: !_callMode,
          reasoningMaxTokens: _callMode ? 0 : null,
        ),
        search: _webSearchService,
      );
      t.searchReceipt = round.receipt;
      if (round.injection != null && round.injection!.isNotEmpty) {
        t.plan.section('web_search').text = round.injection!;
        genParams = paramsOf(t.plan.userText);
        debugPrint('[WebSearch] dispatch inject+stream (in-character reply)');
      } else {
        debugPrint(
          '[WebSearch] dispatch no lookup — stream in-character reply',
        );
      }
      t.stream = llmService.generateStream(genParams);
    } else {
      t.stream = llmService.generateStream(genParams);
    }

    // ── Phase: Prefilling ──
    // The HTTP request is now in flight. For KoboldCPP, the model is
    // processing the prompt (prefill/eval). No tokens arrive until
    // prefill finishes. Poll /api/extra/perf for real-time status.
    _generationPhase = GenerationPhase.prefilling;
    _prefillStartTime = DateTime.now();
    _prefillPromptTokens = (prompt.length / 4).ceil(); // Rough placeholder
    notifyListeners();

    // If using local KoboldCPP, poll /api/extra/perf during prefill
    // to get real prompt processing metrics.
    final isLocalBackend = t.isLocalBackend =
        _llmProvider == null || _llmProvider!.isLocal;
    if (isLocalBackend) {
      // Get REAL token count from the model's tokenizer (async, updates UI when done)
      _koboldService.countTokens(prompt).then((realCount) {
        if (_generationPhase == GenerationPhase.prefilling && realCount > 0) {
          _prefillPromptTokens = realCount;
          debugPrint(
            '[Prefill] Actual token count from tokenizer: $realCount (was ~${(prompt.length / 4).ceil()} est)',
          );
          notifyListeners();
        }
      });

      t.perfPoller = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (_generationPhase != GenerationPhase.prefilling) {
          t.perfPoller?.cancel();
          t.perfPoller = null;
          return;
        }
        final perf = await _koboldService.fetchPerf();
        if (perf != null) {
          _lastPerfData = perf;
          notifyListeners();
        }
      });
    }
  }

  /// Pre-turn half of the call-model swap (voice call safe speed lane): the
  /// old swap fired only in the request phase, so every pre-generation LLM
  /// call of a voice turn — the realism judges, the standalone clock, the
  /// objective check — still waited on the full-size main model, which is
  /// where the "Thinking…" silence actually lived. sendMessage enters the
  /// swap before that work; the request phase above adopts it into
  /// [_GenTurn.originalModelName], whose existing restore sites (postgen,
  /// stream-cancel, catch) put the main model back. Same gate as the
  /// in-request swap — every backend that carries the model as a request
  /// parameter (remote APIs AND oMLX, which rides openRouterService;
  /// isLocal is true only for managed KoboldCpp, where a swap would mean a
  /// process restart per turn).
  void _enterCallEvalModelSwap() {
    if (_callEvalModelOriginal != null) return; // already parked this turn
    if (!_callMode ||
        _storageService.sttSettings.callModelName.isEmpty ||
        _llmProvider == null ||
        _llmProvider!.isLocal) {
      return;
    }
    _callEvalModelOriginal = _llmProvider!.openRouterService.modelName;
    _llmProvider!.openRouterService.configure(
      modelName: _storageService.sttSettings.callModelName,
    );
  }

  /// Abandon half: restores the main model when a swapped turn never reaches
  /// the request phase (eval cancelled) or the call ends with a swap parked
  /// (the callMode setter calls this on every call end, belt and braces).
  void _exitCallEvalModelSwap() {
    final original = _callEvalModelOriginal;
    if (original == null || _llmProvider == null) return;
    _callEvalModelOriginal = null;
    _llmProvider!.openRouterService.configure(modelName: original);
  }
}
