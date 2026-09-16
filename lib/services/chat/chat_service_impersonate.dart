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

/// User impersonation — generate a message in the user's voice. Extracted verbatim (zero behaviour change) to shrink the god file.
extension ChatServiceImpersonate on ChatService {
  Future<void> impersonateUser({
    String prefix = '',
    required Function(String accumulated) onToken,
  }) async {
    if ((_activeCharacter == null && _activeGroup == null) ||
        _isTurnBusy ||
        _sceneGuest.busy) {
      return;
    }
    if (await _abortIfBackendDown()) return;

    _isGenerating = true;
    _cancelRequested = false;
    notifyListeners();

    try {
      final userName = _userPersonaService.persona.name;

      // Determine the speaking character (needed for prompt construction)
      CharacterCard speakingCharacter;
      if (_activeGroup != null) {
        speakingCharacter = _groupCharacters.first;
      } else {
        speakingCharacter = _activeCharacter!;
      }

      // Build prompt the same way _generateResponse does
      // Path B clean hierarchy (same as the main generation path)
      String systemPrompt;
      if (_activeGroup != null && _activeGroup!.systemPrompt.isNotEmpty) {
        systemPrompt = _activeGroup!.systemPrompt;
      } else if (_activeGroup != null) {
        systemPrompt = _observerMode
            ? observerModeSystemPrompt
            : defaultGroupSystemPrompt;
      } else if (speakingCharacter.systemPrompt.isNotEmpty) {
        systemPrompt = speakingCharacter.systemPrompt;
      } else if (_storageService.generationSettings.systemPrompt.isNotEmpty) {
        systemPrompt = _storageService.generationSettings.systemPrompt;
      } else {
        // All backends speak the OpenAI chat protocol now (KoboldCpp via its
        // /v1/chat/completions door), so use the chat-style default prompt.
        systemPrompt = defaultApiSystemPrompt;
      }

      if (_activeGroup != null) {
        final groupCharPrompt = getSystemPromptForGroupCharacter(
          speakingCharacter,
        ).trim();
        if (groupCharPrompt.isNotEmpty) {
          systemPrompt +=
              '\n\n[Group-specific instructions for ${speakingCharacter.name}]\n$groupCharPrompt';
        } else if (speakingCharacter.systemPrompt.isNotEmpty) {
          systemPrompt +=
              '\n\n[Specific instructions for ${speakingCharacter.name}]\n${speakingCharacter.systemPrompt.trim()}';
        }
      }

      // Lorebook via the shared injector — the same positioned buckets the
      // main generation path uses. Read-only: impersonation never scans or
      // mutates trigger state.
      final loreInjection = _lorebookInjector.buildInjection(
        sessionSeed: _currentSessionId ?? '',
        contextSize: _sessionGenSettings.resolveContextSize(_storageService),
      );
      String loreBefore = loreInjection.beforeChar;
      String loreAfter = loreInjection.afterChar;
      String loreAnTop = loreInjection.authorNoteTop;
      String loreAnBottom = loreInjection.authorNoteBottom;
      String loreExTop = loreInjection.examplesTop;
      String loreExBottom = loreInjection.examplesBottom;
      List<LoreDepthEntry> loreDepth = loreInjection.depthEntries;

      // Persona & scenario
      // Use evolved versions if character evolution is enabled and available
      String personaBlock;
      if (_activeGroup != null) {
        final personas = _groupCharacters
            .map(
              (ch) =>
                  "${ch.name}'s Persona: ${_macroResolver.resolve(
                    _getEffectivePersonality(ch),
                    MacroContext(userName: userName, characterName: ch.name),
                    section: 'persona',
                  )}",
            )
            .toList();
        personaBlock = personas.join('\n');
      } else {
        personaBlock =
            "${speakingCharacter.name}'s Persona: ${_macroResolver.resolve(
              _getEffectivePersonality(speakingCharacter),
              MacroContext(userName: userName, characterName: speakingCharacter.name),
              section: 'persona',
            )}";
      }

      // User persona — inject user's self-description + learned facts
      final userPersonaBlock = await _buildUserPersonaBlock(userName);

      String rawScenario = '';
      if (_activeGroup != null && _activeGroup!.scenario.isNotEmpty) {
        rawScenario = _activeGroup!.scenario;
      } else {
        final scenarioChar = _activeGroup != null
            ? _groupCharacters.first
            : speakingCharacter;
        rawScenario = _getEffectiveScenario(scenarioChar);
      }
      String scenario = rawScenario;

      String history = _buildChatHistory();

      // Suffix + prefix rule: a typed start is an incomplete USER line
      // (Continue-shaped). Character examples / post-history few-shot the
      // character's voice and often repeat "do not write for the user".
      final suffix = impersonateSuffix(userName: userName, prefix: prefix);
      const mesExampleBlock = '';
      const postHistoryBlock = '';

      String authorNoteBlock = '';
      if (_authorNote.isNotEmpty) {
        authorNoteBlock = _buildAuthorNoteBlock();
      }

      // ── Macro resolution pass ──
      // Same full chat context the main generation path uses.
      final macroCtx = _buildChatMacroContext(
        speakingCharacter,
        scenario: scenario,
      );
      systemPrompt = _macroResolver.resolve(
        systemPrompt,
        macroCtx,
        section: 'systemPrompt',
      );
      String loreMacro(String s) =>
          s.isEmpty ? s : _macroResolver.resolve(s, macroCtx, section: 'lore');
      loreBefore = loreMacro(loreBefore);
      loreAfter = loreMacro(loreAfter);
      loreAnTop = loreMacro(loreAnTop);
      loreAnBottom = loreMacro(loreAnBottom);
      loreExTop = loreMacro(loreExTop);
      loreExBottom = loreMacro(loreExBottom);
      loreDepth = [
        for (final d in loreDepth)
          LoreDepthEntry(
            depth: d.depth,
            role: d.role,
            content: loreMacro(d.content),
          ),
      ];
      final loreDepthJoined = loreDepth.map((d) => d.content).join('\n');
      scenario = _macroResolver.resolve(
        scenario,
        macroCtx,
        section: 'scenario',
      );
      final identity = impersonateIdentityBlock(
        userName: userName,
        characterName: speakingCharacter.name,
      );
      final cardFrame = impersonateCardFrame(
        userName: userName,
        characterName: speakingCharacter.name,
      );
      final prefixRule = impersonatePrefixRule(
        userName: userName,
        characterName: speakingCharacter.name,
        prefix: prefix,
      );
      systemPrompt = '$identity$cardFrame$systemPrompt';

      // ── Context Shift: budget-aware history trimming ──
      // Same single-source PromptPlan as the main generation path (spec §7):
      // one section list renders the system text, user text, and fixed count.
      // No state zone here, and that is not a divergence from §6.1: writing
      // the USER's next line needs the card, the scene and the transcript,
      // never the character's private feelings, needs or objectives — this
      // path has never registered those sections at all. Identity + card
      // frame ride the system message (they must outrank "do not write
      // for {{user}}"). Character examples and post-history are omitted.
      final plan = PromptPlan();
      plan.add(id: 'system', inSystem: true, text: '$systemPrompt\n');
      plan.add(id: 'lore.before', inSystem: true, text: loreBefore);
      plan.add(id: 'persona', inSystem: true, text: '$personaBlock\n');
      plan.add(id: 'lore.after', inSystem: true, text: loreAfter);
      plan.add(id: 'user_persona', inSystem: true, text: userPersonaBlock);
      plan.add(
        id: 'scenario',
        inSystem: true,
        text: ScenarioFade.wrapScenario(
          scenario,
          ScenarioFade.strengthForUserMessageCount(
            _messages.where((m) => m.isUser).length,
          ),
        ),
      );
      plan.add(id: 'lore.ex_top', inSystem: true, text: loreExTop);
      plan.add(id: 'examples', inSystem: true, text: mesExampleBlock);
      plan.add(id: 'lore.ex_bottom', inSystem: true, text: loreExBottom);
      plan.add(id: 'start', text: '<START>\n');
      plan.add(id: 'history', text: '', counted: false);
      plan.add(id: 'post_history', text: postHistoryBlock);
      plan.add(id: 'lore.an_top', text: loreAnTop);
      plan.add(id: 'author_note', text: authorNoteBlock);
      plan.add(id: 'lore.an_bottom', text: loreAnBottom);
      plan.add(id: 'lore.depth', text: loreDepthJoined, rendered: false);
      plan.add(id: 'impersonate', text: prefixRule);
      plan.add(id: 'suffix', text: suffix);
      final fixedTokens = await _countTokens(plan.fixedCountText);
      final contextBudget = _sessionGenSettings.resolveContextSize(
        _storageService,
      );
      final generationReserve =
          _sessionGenSettings.resolveMaxLength(_storageService) + 50;
      final historyBudget = contextBudget - fixedTokens - generationReserve;

      if (historyBudget > 0) {
        final result = await _buildChatHistoryWithBudget(
          historyBudget,
          depthLore: loreDepth,
        );
        history = result.history;
      } else if (_messages.isNotEmpty) {
        // Same overflow floor as the main generate path: last user line +
        // everything after (think-stripped). Not raw .text (Nina-class hole).
        history = _overflowContinuityHistory().history;
      }

      // Every backend now speaks the OpenAI chat protocol (local KoboldCpp via
      // its /v1/chat/completions door), so the plan's system zone rides a
      // proper 'system' role message and the transcript zone the 'user' one.
      plan.section('history').text = history;
      final chatSystemPrompt = plan.systemText;
      final prompt = plan.userText;

      // Stop sequences: character names only (not user — we ARE the user).
      // Same prioritized builder as the main generation path — no second
      // stop-assembly path (spec §5e).
      final g = _sessionGenSettings;
      final stopList = buildPrioritizedStops(
        configured: g.resolveStopSequences(_storageService),
        userName: userName,
        impersonating: true,
        characterNames: _activeGroup != null
            ? _groupCharacters.map((c) => c.name).toList()
            : [_activeCharacter!.name],
      );

      final genParams = GenerationParams(
        prompt: prompt,
        systemPrompt: chatSystemPrompt,
        maxLength: g.resolveMaxLength(_storageService),
        minLength: g.resolveMinLength(_storageService),
        minP: g.resolveMinP(_storageService),
        topP: g.resolveTopP(_storageService),
        topK: g.resolveTopK(_storageService),
        dryMultiplier: g.resolveDryMultiplier(_storageService),
        temperature: g.resolveTemperature(_storageService),
        repeatPenalty: g.resolveRepeatPenalty(_storageService),
        repPenTokens: g.resolveRepeatPenaltyTokens(_storageService),
        dynatempRange: g.resolveDynamicTempEnabled(_storageService)
            ? g.resolveDynamicTempRange(_storageService)
            : null,
        xtcThreshold: g.resolveXtcThreshold(_storageService),
        xtcProbability: g.resolveXtcProbability(_storageService),
        stopSequences: stopList,
        reasoningEnabled: false,
        reasoningEffort: g.resolveReasoningEffort(_storageService),
        bannedPhrases: g.resolveBannedPhrases(_storageService).isNotEmpty
            ? g.resolveBannedPhrases(_storageService)
            : null,
      );

      final stream = _mouthGenerateStream(genParams);
      String accumulated = prefix;
      bool inThinkBlock = false;

      await for (final token in stream) {
        if (_cancelRequested) break;
        // Filter out <think>...</think> reasoning blocks entirely
        if (token.contains('<think>')) {
          inThinkBlock = true;
          continue;
        }
        if (token.contains('</think>')) {
          inThinkBlock = false;
          continue;
        }
        if (inThinkBlock) continue;
        accumulated += token;
        // Server stop lists are capped; trim "\nChar:" bleed ourselves.
        final trimmed = trimAtFirstStop(accumulated, stopList);
        if (trimmed != accumulated) {
          accumulated = trimmed;
          onToken(accumulated);
          break;
        }
        onToken(accumulated);
      }

      // Sanitize once at completion (or after user cancel).
      // During streaming the raw text is shown — acceptable because the
      // user can only edit AFTER generation finishes, at which point
      // the sanitized form is presented.
      if (_sessionGenSettings.resolveOutputSanitizerEnabled(_storageService)) {
        final rules = _sessionGenSettings.resolveOutputSanitizerRules(
          _storageService,
        );
        final sanitized = sanitizeOutput(accumulated, rules);
        if (sanitized != accumulated) {
          onToken(sanitized);
        }
      }
    } catch (e) {
      debugPrint('[ChatService] Impersonate error: $e');
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }
}
