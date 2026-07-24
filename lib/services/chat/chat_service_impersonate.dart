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
        _isGenerating ||
        _guestBusy) {
      return;
    }

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
            ? ChatService.observerModeSystemPrompt
            : ChatService.defaultGroupSystemPrompt;
      } else if (speakingCharacter.systemPrompt.isNotEmpty) {
        systemPrompt = speakingCharacter.systemPrompt;
      } else if (_storageService.generationSettings.systemPrompt.isNotEmpty) {
        systemPrompt = _storageService.generationSettings.systemPrompt;
      } else {
        // All backends speak the OpenAI chat protocol now (KoboldCpp via its
        // /v1/chat/completions door), so use the chat-style default prompt.
        systemPrompt = ChatService.defaultApiSystemPrompt;
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

      // Suffix: user name + any partial text the user typed
      String suffix = "\n$userName:";
      if (prefix.isNotEmpty) {
        suffix = "$suffix $prefix";
      }

      String mesExampleBlock = '';
      if (_activeGroup != null) {
        final examples = _groupCharacters
            .where((ch) => ch.mesExample.isNotEmpty)
            .map(
              (ch) => _macroResolver.resolve(
                ch.mesExample,
                MacroContext(userName: userName, characterName: ch.name),
                section: 'mesExample',
              ),
            )
            .toList();
        if (examples.isNotEmpty) {
          mesExampleBlock = '${examples.join('\n')}\n';
        }
      } else if (speakingCharacter.mesExample.isNotEmpty) {
        mesExampleBlock = '${speakingCharacter.mesExample}\n';
      }

      String postHistoryBlock = '';
      if (_activeGroup == null &&
          speakingCharacter.postHistoryInstructions.isNotEmpty) {
        postHistoryBlock = '${speakingCharacter.postHistoryInstructions}\n';
      }

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
      if (_activeGroup == null && mesExampleBlock.isNotEmpty) {
        mesExampleBlock = _macroResolver.resolve(
          mesExampleBlock,
          macroCtx,
          section: 'mesExample',
        );
      }
      if (postHistoryBlock.isNotEmpty) {
        postHistoryBlock = _macroResolver.resolve(
          postHistoryBlock,
          macroCtx,
          section: 'postHistory',
        );
      }

      // Impersonate instruction — comprehensive guidance for writing as the user
      final impersonateInstruction =
          '[System: You are now writing as $userName (the user), NOT as ${speakingCharacter.name} or any other character. '
          'Compose $userName\'s next message in first person. '
          'Match $userName\'s established voice, personality, and writing style from the conversation so far. '
          'Write only $userName\'s words and actions — never narrate for ${speakingCharacter.name} or other characters. '
          'Do not include meta-commentary, stage directions for others, or break the fourth wall. '
          'Keep the response natural, and consistent with the scene.]\n';

      // ── Context Shift: budget-aware history trimming ──
      // Same single-source PromptPlan as the main generation path (spec §7):
      // one section list renders the system text, user text, and fixed count.
      final plan = PromptPlan();
      plan.add(id: 'system', inSystem: true, text: '$systemPrompt\n');
      plan.add(id: 'lore.before', inSystem: true, text: loreBefore);
      plan.add(id: 'persona', inSystem: true, text: '$personaBlock\n');
      plan.add(id: 'lore.after', inSystem: true, text: loreAfter);
      plan.add(id: 'user_persona', inSystem: true, text: userPersonaBlock);
      plan.add(id: 'scenario', inSystem: true, text: 'Scenario: $scenario\n');
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
      plan.add(id: 'impersonate', text: impersonateInstruction);
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
        final lastMsg = _messages.last;
        history = lastMsg.characterId == '__director__'
            ? '[Director: ${lastMsg.text}]'
            : '${lastMsg.sender}: ${lastMsg.text}';
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

      final llmService =
          testLlmServiceOverride ??
          _llmProvider?.activeService ??
          _koboldService;
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

      final stream = llmService.generateStream(genParams);
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
        onToken(accumulated);
      }
    } catch (e) {
      print('Impersonate error: $e');
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }
}
