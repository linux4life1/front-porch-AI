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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/media/media_door.dart';
import 'package:front_porch_ai/services/chat/doors/realism/realism_graph.dart';
import 'package:front_porch_ai/services/chat/doors/session/session_store.dart';
import 'package:front_porch_ai/services/chat/doors/turn/prompt_assembler.dart';
import 'package:front_porch_ai/services/chat/llm_lanes.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

/// Phase 4 of `_generateResponse`: syncs the late-filled plan sections,
/// renders the final prompt, records the Context Viewer snapshot, builds
/// the stop-sequence list, resolves the LLM service (+ call-mode model
/// swap), builds [GenerationParams], rings the tool doorbell and the forced
/// lookup, and starts the stream; the turn engine's prefill bookkeeping
/// then runs ([PromptShellHooks.enterPrefill]). The body is the one the
/// generation part held (`x` → `t.x` carrier names, see [GenTurn]); zero
/// behaviour change.
///
/// H3 (do not "fix"): `contextLimit` below is the session-resolved
/// [PromptAssembler.contextSize] (the chat service's `contextSize` getter), a
/// DIFFERENT value from the raw backend-settings local of the same name in
/// the RAG phase ([TurnRag]). Do not hoist either onto the carrier or unify
/// the two scopes.
class TurnRequest {
  TurnRequest(this._a, this._d);

  final PromptAssembler _a;
  final PromptDeps _d;

  ChatSessionState get _session => _d.session;
  StorageService get _storageService => _d.services.storage;
  UserPersonaService get _userPersonaService => _d.services.personas;
  LLMProvider? get _llmProvider => _d.services.llmProvider();
  LlmLanes get _lanes => _d.services.lanes;
  SessionStore get _sessions => _d.doors.sessions();
  RealismGraph get _g => _d.doors.graph();
  MediaDoor get _mediaDoor => _d.doors.media();
  PromptHistory get _transcript => _a.history;
  ContextBudgetStore get _contextBudget => _a.budget.store;
  ChatGenerationSettings get _sessionGenSettings => _sessions.genSettings;
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  bool get _callMode => _d.doors.controls().callMode;
  String? get _pendingIdleCue => _d.doors.cast().idle.pendingIdleCue;
  ToolTransportProbe get _toolProbe => _g.transport.probe;
  String get _evalBackendIdentity => _g.transport.backendIdentity;
  String? get _callEvalModelOriginal => _a.callSwap.parkedOriginal;
  set _callEvalModelOriginal(String? v) => _a.callSwap.parkedOriginal = v;

  Future<void> dispatch(GenTurn t) async {
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
    t.plan.section('latest_turn').text = t.latestTurn.isEmpty
        ? ''
        : '\n${t.latestTurn}';
    t.plan.section('memories').text = t.memoriesBlock;
    t.plan.section('idle_cue').text = idleCue != null ? '\n$idleCue' : '';
    t.plan.section('suffix').text = t.suffix;

    final chatSystemPrompt = t.plan.systemText;
    final prompt = t.plan.userText;

    // Context viewer: plan budget/sections (session-persisted on save).
    // The rows are chars/4 shares scaled to the tokenizer's count of the
    // same text (one count; Kobold's own tokenizer, chars/4 elsewhere), so
    // the Total a user compares with the context size is what the send
    // weighs, not an estimate that drifts by model (issue #550's reading).
    final sectionMap = t.plan.sectionTexts();
    final sentTokens = await _transcript.countTokens(sectionMap.values.join());
    _contextBudget.recordLastSend(
      budgetMap: scaleBudgetRows(t.plan.budgetEstimates(), sentTokens),
      sectionMap: sectionMap,
      contextLimit: _a.contextSize,
      droppedMessages: t.droppedMessages,
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
        _session.messages.isNotEmpty &&
        !_session.messages.last.isUser) {
      continueSpeakerName = _session.messages.last.sender;
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
      stopCharacterNames = [_session.activeCharacter!.name];
    }

    final stopList = t.stopList = buildPrioritizedStops(
      configured: g2.resolveStopSequences(_storageService),
      userName: _userPersonaService.persona.name,
      // In impersonate mode the model IS the user, so don't stop on user name
      impersonating: t.mode == GenerationMode.impersonate,
      characterNames: stopCharacterNames,
      continueSpeakerName: continueSpeakerName,
    );

    // Mouth speaks. Side-lane (clerk) may be a different host.
    final llmService = _lanes.mouth;
    final sideLaneLlm = _lanes.sideLane;

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
    final turnImages = await _mediaDoor.buildTurnImages(t.mode);

    GenerationParams paramsOf(
      String p, {
      String? systemPrompt,
      bool? reasoningEnabled,
      int? reasoningMaxTokens,
    }) {
      // A rewrite from a word also writes inside the answer: no thinking.
      final callOrContinue =
          _callMode ||
          t.mode == GenerationMode.continue_ ||
          _a.tokenAlts.isSeeded(t);
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
        kvChat: _session.currentSessionId,
        stillWant: () => !_d.doors.turn().progress.cancelRequested,
        chatMessages: _a.tokenAlts.seededMessages(t, p),
        onLogprobs: _a.tokenAlts.logprobsSink(t),
      );
    }

    var genParams = paramsOf(prompt);

    // Unified tools catalog: in-process web_search / wiki_search plus user
    // recipe cards from <library>/tools/. Continue / autonomous / xml-only
    // skip the round-trip. Regen is a new try (directUserSend). Web search
    // sees only the latest user line. Wiki and recipe cards still see the
    // character prompt. Doorbell/clerk use the eval side lane (not user
    // max-gen / thinking). A ring → clerk loop (cap 3), one collated scrap,
    // then mouth-stream with full character params. No ring → discard
    // doorbell speech and mouth-stream the same way.
    final globalDefault = _storageService.webSearchSettings.webSearchDefault;
    final xmlOnly = _toolProbe.isXmlOnly(_evalBackendIdentity);
    final includeSearch =
        t.forcedWebQuery == null &&
        shouldAdvertiseWebSearch(
          globalDefault: globalDefault,
          directUserSend: t.directUserSend,
          continueMode: t.mode == GenerationMode.continue_,
          toolsUnsupported: xmlOnly,
          autonomousMode: t.autonomous,
        );
    final userCards = t.userToolCards;
    final includeUser = shouldAdvertiseUserTools(
      hasCards: userCards.isNotEmpty,
      directUserSend: t.directUserSend,
      continueMode: t.mode == GenerationMode.continue_,
      toolsUnsupported: xmlOnly,
      autonomousMode: t.autonomous,
    );
    final includeWiki =
        t.forcedWikiQuery == null &&
        shouldAdvertiseWikiSearch(
          wikiUrl: _mediaDoor.wikiBaseUrl,
          directUserSend: t.directUserSend,
          continueMode: t.mode == GenerationMode.continue_,
          toolsUnsupported: xmlOnly,
          autonomousMode: t.autonomous,
        );
    debugPrint(
      '[WebSearch] gate advertise=$includeSearch global=$globalDefault '
      'directUserSend=${t.directUserSend} '
      'continue=${t.mode == GenerationMode.continue_} '
      'autonomous=${t.autonomous} xmlOnly=$xmlOnly '
      'backend=${llmService.backendName}',
    );
    debugPrint(
      '[Tools] gate advertise=$includeUser cards=${userCards.length} '
      'continue=${t.mode == GenerationMode.continue_} '
      'autonomous=${t.autonomous} xmlOnly=$xmlOnly',
    );
    final catalog = buildToolCatalog(
      inProcess: [
        if (includeSearch) inProcessWebSearchTool(),
        if (includeWiki) inProcessWikiSearchTool(),
        if (includeWiki) inProcessWikiPageTool(),
      ],
      userCards: [
        if (includeUser)
          for (final c in userCards) c.toCatalogTool(),
      ],
    );
    final scraps = <String>[];
    if (catalog.tools.isNotEmpty) {
      final jobs = catalogDoorbellJobs(
        mouth: genParams,
        catalog: catalog,
        lastUserMessage: _latestUserLineForDoorbell(),
        wikiWindow: wikiWindowFromMessages(_session.messages),
      );
      if (jobs.isNotEmpty) {
        await _lanes.withWorkerLane(() async {
          for (final job in jobs) {
            final round = await runCatalogRound(
              llm: sideLaneLlm,
              params: job.params,
              catalog: job.catalog,
              search: _mediaDoor.webSearchService,
              wiki: _mediaDoor.wikiSearchService,
              backendIdentity: _evalBackendIdentity,
            );
            if (round.searchReceipt != null) {
              t.searchReceipt = round.searchReceipt;
            }
            if (round.toolReceipt != null) {
              t.toolReceipt = round.toolReceipt;
            }
            final injection = round.injection;
            if (injection != null && injection.isNotEmpty) {
              scraps.add(injection);
            }
          }
        });
      }
    }
    final forced = await _mediaDoor.runForcedLookup(
      webQuery: t.forcedWebQuery,
      wikiQuery: t.forcedWikiQuery,
    );
    if (forced != null) {
      final injection = forced.injection;
      if (injection != null && injection.isNotEmpty) scraps.add(injection);
      if (forced.searchReceipt != null) t.searchReceipt = forced.searchReceipt;
      if (forced.wikiReceipt != null) t.wikiReceipt = forced.wikiReceipt;
    }
    final joined = collateCatalogInjections(scraps);
    if (joined != null && joined.isNotEmpty) {
      t.plan.section('web_search').text = joined;
      genParams = paramsOf(t.plan.userText);
      debugPrint('[Tools] dispatch inject+stream (in-character reply)');
    } else if (catalog.tools.isNotEmpty) {
      debugPrint('[Tools] dispatch no tool result — stream in-character reply');
    }
    // Occupancy wait is load-bearing: catalog `_lanes.withWorkerLane` can nest
    // under a journal hold, and releasing the catalog depth must not let
    // speech start while the mouth is still unloaded.
    await _llmProvider?.waitForWorkerLaneIdle(pinSpeech: true);
    t.stream = llmService.generateStream(genParams);
    _d.doors.turn().enterPrefill(t, prompt);
  }

  /// Latest user line for the web-search doorbell. promptText, so a photo
  /// is the caption marker and a think block is already stripped.
  String _latestUserLineForDoorbell() {
    for (var i = _session.messages.length - 1; i >= 0; i--) {
      if (!_session.messages[i].isUser) continue;
      return _session.messages[i].promptText.trim();
    }
    return '';
  }
}
