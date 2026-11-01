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
import 'package:front_porch_ai/services/chat/doors/edits/edit_deps.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// User impersonation: a message in the user's voice, answering the
/// character they are talking to (the last group member who spoke, the
/// open character in 1:1). Read-only on the chat: no lore trigger scan, no
/// Realism, nothing saved.
class Impersonator {
  Impersonator(this._d);

  final EditDeps _d;

  ChatSessionState get _session => _d.session;
  EditServices get _s => _d.services;
  ImpersonatePromptHooks get _p => _d.prompt;
  StorageService get _storage => _s.storage();
  GroupChat? get _activeGroup => _session.activeGroup;
  List<CharacterCard> get _groupCharacters => _session.groupCharacters;
  bool get _observerMode => _session.groupManager?.observerMode ?? false;
  bool get _directing => _activeGroup != null && _observerMode;

  /// Writes the user's next line in their voice, streamed to [onToken].
  Future<void> impersonateUser({
    String prefix = '',
    required Function(String accumulated) onToken,
  }) async {
    if ((_session.activeCharacter == null && _activeGroup == null) ||
        _d.turn.isTurnBusy() ||
        _d.cast.guestBusy()) {
      return;
    }
    if (await _d.turn.abortIfBackendDown()) return;

    _d.turn.setGenerating(true);
    _d.turn.setPhase(GenerationPhase.impersonating);
    _d.turn.setCancelRequested(false);
    _d.notify();

    try {
      final userName = _s.personas().persona.name;

      // The person the user is answering, not whoever happens to be first
      // on the roster. 1:1 is the open character.
      CharacterCard speakingCharacter;
      if (_activeGroup != null) {
        speakingCharacter =
            _impersonateGroupSpeaker() ?? _d.cast.pickPresentSpeaker();
      } else {
        speakingCharacter = _session.activeCharacter!;
      }

      // Build prompt the same way _generateResponse does
      // Path B clean hierarchy (same as the main generation path)
      String systemPrompt;
      if (_activeGroup != null) {
        systemPrompt = _p.groupBasePrompt();
      } else {
        // All backends speak the OpenAI chat protocol now (KoboldCpp via its
        // /v1/chat/completions door), so use the chat-style default prompt.
        systemPrompt = _p.oneToOneBase(speakingCharacter);
      }

      // A group keeps the reply path's system head (base, additions, the
      // mode's FPAI rules). The answered character's card instructions are
      // theirs, not the user's, so they stay out.
      if (_p.amendmentsAllowed()) {
        systemPrompt = _storage.generationSettings.withSystemPromptAddition(
          systemPrompt,
        );
      }
      if (_activeGroup != null) {
        systemPrompt = withGroupSceneRules(systemPrompt, directing: _directing);
      }
      // Directing, the user's next line is a stage direction, not a line
      // spoken in a scene they are not in.
      final directorNote = _activeGroup != null && _directing;

      // Lorebook via the shared injector — the same positioned buckets the
      // main generation path uses. Read-only: impersonation never scans or
      // mutates trigger state.
      final loreInjection = _s.lorebookInjector().buildInjection(
        sessionSeed: _session.currentSessionId ?? '',
        contextSize: _p.sessionGenSettings().resolveContextSize(_storage),
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
        personaBlock = buildGroupRosterLine(
          memberNames: [for (final ch in _groupCharacters) ch.name],
          userName: userName,
          observerMode: _observerMode,
          visitorNames: {
            for (final ch in _groupCharacters)
              if (ch.isLite) ch.name,
          },
        );
      } else {
        personaBlock =
            "${speakingCharacter.name}'s Persona: ${_s.growthDesk().resolvedCardPersonality(speakingCharacter, userName)}";
      }
      final growthBlock = _s.growthDesk().resolvedGrowthBlock(
        speakingCharacter,
        userName,
      );

      // User persona — inject user's self-description + learned facts
      final userPersonaBlock = _directing
          ? ''
          : await _p.userPersonaBlock(userName);

      // Same shared-scene rule as the reply path: the group's scenario,
      // else the anchor member's original one.
      String rawScenario = '';
      if (_activeGroup != null) {
        rawScenario = _activeGroup!.scenario.isNotEmpty
            ? _activeGroup!.scenario
            : (_groupCharacters.firstOrNull?.scenario ?? '');
      } else {
        rawScenario = _s.growthDesk().effectiveScenario(speakingCharacter);
      }
      String scenario = rawScenario;

      String history = _p.chatHistory();

      // Suffix + prefix rule: a typed start is an incomplete USER line
      // (Continue-shaped). Character examples / post-history few-shot the
      // character's voice and often repeat "do not write for the user".
      final suffix = directorNote
          ? impersonateDirectorSuffix(prefix: prefix)
          : impersonateSuffix(userName: userName, prefix: prefix);
      const mesExampleBlock = '';
      var postHistoryBlock = _p.amendmentsAllowed()
          ? _storage.generationSettings.withPostHistoryAddition('')
          : '';

      String authorNoteBlock = '';
      if (_p.authorNote().isNotEmpty) {
        authorNoteBlock = _p.authorNoteBlock();
      }

      // ── Macro resolution pass ──
      // Same full chat context the main generation path uses.
      final macroCtx = _p.macroContext(speakingCharacter, scenario: scenario);
      systemPrompt = _s.macroResolver().resolve(
        systemPrompt,
        macroCtx,
        section: 'systemPrompt',
      );
      String loreMacro(String s) => s.isEmpty
          ? s
          : _s.macroResolver().resolve(s, macroCtx, section: 'lore');
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
      scenario = _s.macroResolver().resolve(
        scenario,
        macroCtx,
        section: 'scenario',
      );
      postHistoryBlock = _s.macroResolver().resolve(
        postHistoryBlock,
        macroCtx,
        section: 'postHistory',
      );
      // Same pass as the reply path: the note is the user's text and may
      // name {{char}} or {{user}}.
      if (authorNoteBlock.isNotEmpty) {
        authorNoteBlock = _s.macroResolver().resolve(
          authorNoteBlock,
          macroCtx,
          section: 'authorNote',
        );
      }
      final identity = directorNote
          ? impersonateDirectorBlock(userName: userName)
          : impersonateIdentityBlock(
              userName: userName,
              characterName: speakingCharacter.name,
            );
      final cardFrame = directorNote
          ? ''
          : _activeGroup != null
          ? impersonateGroupFrame(
              userName: userName,
              characterName: speakingCharacter.name,
            )
          : impersonateCardFrame(
              userName: userName,
              characterName: speakingCharacter.name,
            );
      final prefixRule = directorNote
          ? impersonateDirectorPrefixRule(prefix: prefix)
          : impersonatePrefixRule(
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
      // for {{user}}"). Character examples and card post-history are omitted; global additions remain.
      final plan = PromptPlan();
      plan.add(id: 'system', inSystem: true, text: '$systemPrompt\n');
      plan.add(id: 'persona', inSystem: true, text: '$personaBlock\n');
      plan.add(id: 'user_persona', inSystem: true, text: userPersonaBlock);
      plan.add(id: 'examples', inSystem: true, text: mesExampleBlock);
      plan.add(id: 'start', text: '<START>\n');
      plan.add(id: 'history', text: '', counted: false);
      final afterHistory = openOwnLines([
        loreBefore,
        growthBlock,
        loreAfter,
        ScenarioFade.wrapScenario(
          scenario,
          ScenarioFade.strengthForUserMessageCount(
            _session.messages.where((m) => m.isUser).length,
          ),
        ),
        loreExTop,
        loreExBottom,
        postHistoryBlock,
        loreAnTop,
        authorNoteBlock,
        loreAnBottom,
      ]);
      plan.add(id: 'lore.before', text: afterHistory[0]);
      plan.add(id: 'growth', text: afterHistory[1]);
      plan.add(id: 'lore.after', text: afterHistory[2]);
      plan.add(id: 'scenario', text: afterHistory[3]);
      plan.add(id: 'lore.ex_top', text: afterHistory[4]);
      plan.add(id: 'lore.ex_bottom', text: afterHistory[5]);
      plan.add(id: 'post_history', text: afterHistory[6]);
      plan.add(id: 'lore.an_top', text: afterHistory[7]);
      plan.add(id: 'author_note', text: afterHistory[8]);
      plan.add(id: 'lore.an_bottom', text: afterHistory[9]);
      plan.add(id: 'lore.depth', text: loreDepthJoined, rendered: false);
      plan.add(id: 'impersonate', text: prefixRule);
      plan.add(id: 'suffix', text: suffix);
      final fixedTokens = await _p.countTokens(plan.fixedCountText);
      final contextBudget = _p.sessionGenSettings().resolveContextSize(
        _storage,
      );
      final generationReserve =
          _p.sessionGenSettings().resolveMaxLength(_storage) + 50;
      final historyBudget = contextBudget - fixedTokens - generationReserve;

      if (historyBudget > 0) {
        history = await _p.historyWithin(historyBudget, loreDepth);
      } else if (_session.messages.isNotEmpty) {
        // Same overflow floor as the main generate path: last user line +
        // everything after (think-stripped). Not raw .text (Nina-class hole).
        history = _p.overflowHistory();
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
      final g = _p.sessionGenSettings();
      final stopList = buildPrioritizedStops(
        configured: g.resolveStopSequences(_storage),
        userName: userName,
        impersonating: true,
        characterNames: _activeGroup != null
            ? _groupCharacters.map((c) => c.name).toList()
            : [_session.activeCharacter!.name],
      );

      final genParams = GenerationParams(
        prompt: prompt,
        systemPrompt: chatSystemPrompt,
        maxLength: g.resolveMaxLength(_storage),
        minLength: g.resolveMinLength(_storage),
        minP: g.resolveMinP(_storage),
        topP: g.resolveTopP(_storage),
        topK: g.resolveTopK(_storage),
        dryMultiplier: g.resolveDryMultiplier(_storage),
        temperature: g.resolveTemperature(_storage),
        repeatPenalty: g.resolveRepeatPenalty(_storage),
        repPenTokens: g.resolveRepeatPenaltyTokens(_storage),
        dynatempRange: g.resolveDynamicTempEnabled(_storage)
            ? g.resolveDynamicTempRange(_storage)
            : null,
        xtcThreshold: g.resolveXtcThreshold(_storage),
        xtcProbability: g.resolveXtcProbability(_storage),
        stopSequences: stopList,
        reasoningEnabled: false,
        reasoningEffort: g.resolveReasoningEffort(_storage),
        bannedPhrases: g.resolveBannedPhrases(_storage).isNotEmpty
            ? g.resolveBannedPhrases(_storage)
            : null,
        kvChat: _session.currentSessionId,
        stillWant: () => !_d.turn.cancelRequested(),
      );

      final stream = _d.turn.mouthStream(genParams);
      String accumulated = prefix;
      bool inThinkBlock = false;

      await for (final token in stream) {
        if (_d.turn.cancelRequested()) break;
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
      if (_p.sessionGenSettings().resolveOutputSanitizerEnabled(_storage)) {
        final rules = _p.sessionGenSettings().resolveOutputSanitizerRules(
          _storage,
        );
        final sanitized = sanitizeOutput(accumulated, rules);
        if (sanitized != accumulated) {
          accumulated = sanitized;
          onToken(sanitized);
        }
      }
      if (directorNote) {
        final note = closeDirectorNote(accumulated, prefix: prefix);
        if (note != accumulated) onToken(note);
      }
    } catch (e) {
      debugPrint('[Chat] Impersonate error: $e');
    } finally {
      _d.turn.setGenerating(false);
      _d.turn.setPhase(GenerationPhase.idle);
      _d.notify();
    }
  }

  /// Last character line the user is answering. Skips banners and the
  /// director. Null when nobody has spoken yet.
  CharacterCard? _impersonateGroupSpeaker() {
    for (var i = _session.messages.length - 1; i >= 0; i--) {
      final message = _session.messages[i];
      if (message.isUser || message.isStatusBanner) continue;
      if (message.sender == 'System' || message.characterId == '__director__') {
        continue;
      }
      final card = resolveGroupSpeakerForMessage(_groupCharacters, message);
      if (card != null) return card;
    }
    return null;
  }
}
