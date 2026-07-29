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

/// Absolute ceiling on the RAG memories block, applied on top of the
/// percentage budget (1:1's 10% / the group's configurable %). The block is
/// verbatim old transcript injected AFTER the history; past ~2,500 tokens
/// models start replaying it as if it were the current scene, so the cap
/// keeps large-context setups (10% of 32k = 3,200) under that line too.
const int kRagMemoryBudgetCapTokens = 1200;

/// User-facing notice for "managed backend stopped + auto-start off". Const
/// so [_abortIfBackendDown]'s dedupe can compare against the last message.
const _kBackendDownNotice =
    'Backend is not running. Start it in Settings → Backend, '
    "or enable 'Auto-start on chat open'.";

/// The core response generation orchestrator (`_generateResponse`): speaker
/// selection, the single per-speaker realism eval trigger (group path), system
/// prompt + context assembly, streaming, and post-generation needs/realism
/// wiring. Extracted verbatim from `chat_service.dart` (zero behaviour change) to
/// shrink the god file — it is a single ~1.4k-line method, kept whole here
/// rather than carved up (which would be a behavioural risk) until a careful,
/// separately-verified decomposition is warranted.
extension ChatServiceGeneration on ChatService {
  /// True when generation must not proceed: the managed local backend is not
  /// running and auto-start on chat open is off. Appends ONE system notice
  /// naming the toggle (deduped against the last message so group
  /// auto-advance and idle retries can't stack copies), so every entry point
  /// — send, regenerate, continue, swipe, group advance, impersonate — fails
  /// the same friendly way instead of a connection error or silent cancel.
  ///
  /// Deliberately does NOT _saveChat: the notice is transient status, and
  /// persisting here from inside _generateResponse would write the transcript
  /// mid-mutation for callers that pop a message before generating (regen
  /// popped the last AI reply, abort saved the hole — permanent data loss).
  /// Callers that pop MUST also run this check BEFORE their pop (regen paths
  /// do); this deep guard is the backstop for the non-mutating entries.
  Future<bool> _abortIfBackendDown() async {
    if (_llmProvider?.hasManagedProcess != true ||
        _storageService.autostartOnChatOpen ||
        _llmProvider?.hasAnyManagedProcessRunning == true) {
      return false;
    }
    if (_messages.isEmpty || _messages.last.text != _kBackendDownNotice) {
      _messages.add(
        ChatMessage(text: _kBackendDownNotice, sender: 'System', isUser: false),
      );
      notifyListeners();
    }
    return true;
  }

  Future<void> _generateResponse(
    GenerationMode mode, {
    CharacterCard? guestSpeaker,
  }) async {
    if (await _abortIfBackendDown()) return;
    final epoch = ++_generationEpoch;
    _isGenerating = true;
    _generationProgress = 0.0;
    _tokensGenerated = 0;
    _maxTokens = _sessionGenSettings.resolveMaxLength(_storageService);
    _generationStartTime = DateTime.now();
    _isBuffering = true;
    _generationPhase = GenerationPhase.preparing;
    _prefillStartTime = null;
    _lastPerfData = null;
    _sentenceBuffer = '';
    notifyListeners();

    // Track original model for call mode swap/restore (needs to be outside try/catch)
    String? _originalModelName;

    try {
      final userName = _userPersonaService.persona.name;

      // Determine the speaking character first (needed for system prompt priority)
      CharacterCard speakingCharacter;
      if (guestSpeaker != null) {
        // Scene Guest (Lite NPC) turn — stays in 1:1 (_activeGroup remains null),
        // the guest speaks in its own bubble. Carries NO Realism/Needs work
        // (see the guestSpeaker == null guards in the post-gen block below).
        speakingCharacter = guestSpeaker;
      } else if (_activeGroup != null) {
        speakingCharacter =
            (mode == GenerationMode.continue_ &&
                _messages.isNotEmpty &&
                !_messages.last.isUser)
            ? _groupCharacters.firstWhere(
                (c) => c.name == _messages.last.sender,
                orElse: () => _pickNextGroupCharacter(),
              )
            : _pickNextGroupCharacter();
      } else {
        speakingCharacter = _activeCharacter!;
      }

      // Pin the realism speaker for the whole turn so prompt injection + decay
      // key on the character actually generating — not nextCharacter (the
      // *upcoming* speaker, null for random turn order). Scene guests carry no
      // realism, so they leave it null. Cleared in the finally below.
      _turnSpeakerIdForRealism = (_activeGroup != null && guestSpeaker == null)
          ? _getCharacterIdFromCard(speakingCharacter)
          : null;

      // SINGLE realism eval path (group trigger): the picked group member gets
      // their per-turn eval here, after selection, as it always has. The 1:1
      // host runs the SAME `_evaluateRealismForUpcomingSpeaker` from sendMessage
      // instead (fresh turns only) so regen — which calls _generateResponse
      // directly — does NOT re-evaluate and drift the host's realism. Lite Scene
      // Guests (guestSpeaker != null) carry no realism.
      if (guestSpeaker == null &&
          _activeGroup != null &&
          _realismActiveThisMode) {
        await _evaluateRealismForUpcomingSpeaker(speakingCharacter);
        // Cancel-aborts-generation, group edition: the dance leaves the
        // cancel flag set for its caller (1:1's sendMessage has the twin
        // check). Consume it and abort the turn before any prompt is built.
        // The entry-state flags must be reset by hand — the normal clears
        // live in the completion path and the catch, which an early return
        // skips (the finally below only clears the speaker pin).
        if (_realismEvalCancelled) {
          _realismEvalCancelled = false;
          _isGenerating = false;
          _isBuffering = false;
          _generationPhase = GenerationPhase.idle;
          _generationStartTime = null;
          await _saveChat();
          notifyListeners();
          return;
        }
      }

      // ── System prompt selection (Path B clean hierarchy) ──
      // 1. Group-level system prompt (if set) — base for the whole group.
      // 2. Per-character group override (if set for the speaker in this group) — appended.
      // 3. Character's normal card system prompt (fallback if no group override for them).
      // 4. (Later) Per-character Author's Note is injected separately with its own strength.
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
        // Every backend now speaks the OpenAI chat protocol (local KoboldCpp
        // via its /v1/chat/completions door), so the server applies the model's
        // instruct template — use the chat-style default system prompt.
        systemPrompt = ChatService.defaultApiSystemPrompt;
      }

      // Path B: When in a group, always attempt to layer the per-character group override
      // (and card fallback) on top. A group prompt no longer completely hides per-char instructions.
      if (_activeGroup != null) {
        final groupCharPrompt = getSystemPromptForGroupCharacter(
          speakingCharacter,
        ).trim();
        if (groupCharPrompt.isNotEmpty) {
          systemPrompt +=
              '\n\n[Group-specific instructions for ${speakingCharacter.name}]\n$groupCharPrompt';
        } else if (speakingCharacter.systemPrompt.isNotEmpty) {
          // Fallback to the character's own card prompt only if no group-specific override
          systemPrompt +=
              '\n\n[Specific instructions for ${speakingCharacter.name}]\n${speakingCharacter.systemPrompt.trim()}';
        }
      }

      // In call mode, inject voice-specific instructions for natural conversation
      if (_callMode &&
          _storageService.sttSettings.callSystemPrompt.isNotEmpty) {
        systemPrompt +=
            '\n\n[Voice Call Mode] ${_storageService.sttSettings.callSystemPrompt}';
      }

      // Lorebook injection: positioned buckets from the injector (group
      // winners → budget fill → per-position ordering). Pure read — the
      // scanner already updated trigger state for this turn.
      final loreInjection = _lorebookInjector.buildInjection(
        sessionSeed: _currentSessionId ?? '',
        contextSize: _sessionGenSettings.resolveContextSize(_storageService),
      );
      _lastLoreOverflow = loreInjection.overflowDropped;
      _lastLoreTokens = loreInjection.approxTokens;
      _lastLoreBudget = loreInjection.budgetTokens;
      if (loreInjection.overflowDropped.isNotEmpty) {
        debugPrint(
          '[Lorebook] ⚠ budget overflow — dropped: '
          '${loreInjection.overflowDropped.join(', ')}',
        );
      }
      String loreBefore = loreInjection.beforeChar;
      String loreAfter = loreInjection.afterChar;
      String loreAnTop = loreInjection.authorNoteTop;
      String loreAnBottom = loreInjection.authorNoteBottom;
      String loreExTop = loreInjection.examplesTop;
      String loreExBottom = loreInjection.examplesBottom;
      List<LoreDepthEntry> loreDepth = loreInjection.depthEntries;

      // Build persona block(s)
      String personaBlock;
      if (_activeGroup != null) {
        personaBlock = _groupCharacters
            .map((ch) {
              final persona = _macroResolver.resolve(
                _getEffectivePersonality(ch),
                MacroContext(userName: userName, characterName: ch.name),
                section: 'persona',
              );
              return "${ch.name}'s Persona: $persona";
            })
            .join('\n');
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

      // Scenario — the group scene is SHARED across the whole cast (one identical
      // scenario), so a group never uses a per-character EVOLVED scenario (that
      // drifts the story). Use the group override if set, else the anchor
      // member's ORIGINAL scenario. A 1:1 still uses its evolved scenario.
      final String rawScenario;
      if (_activeGroup != null) {
        rawScenario = _activeGroup!.scenario.isNotEmpty
            ? _activeGroup!.scenario
            : (_groupCharacters.isNotEmpty
                  ? _groupCharacters.first.scenario
                  : '');
      } else {
        rawScenario = _getEffectiveScenario(speakingCharacter);
      }
      String scenario = rawScenario;
      // A Scene Guest drops into the HOST's ongoing scene — it has no scenario
      // of its own. Blank it here (prompt-only; the shared library card is never
      // mutated, so a /join'd full character keeps its real scenario for when it
      // is the host). This also self-heals legacy guests minted with the host's
      // scenario baked in (the "model thinks the guest IS the host" bug).
      if (guestSpeaker != null) scenario = '';

      String suffix = "";

      if (mode == GenerationMode.normal) {
        suffix = "\n${speakingCharacter.name}:";
      } else if (mode == GenerationMode.impersonate) {
        suffix = "\n$userName:";
      } else if (mode == GenerationMode.continue_) {
        // Suffix will be set after history is built — see below
        suffix = "";
      }

      // Build example dialogues block
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

      // Build post-history instructions block
      String postHistoryBlock = '';
      if (_activeGroup == null &&
          speakingCharacter.postHistoryInstructions.isNotEmpty) {
        postHistoryBlock = '${speakingCharacter.postHistoryInstructions}\n';
      }

      // Author's note — placed right before the character speaks for maximum influence
      String authorNoteBlock = '';
      if (_authorNote.isNotEmpty) {
        authorNoteBlock = _buildAuthorNoteBlock();
      }

      // Per-character Author's Note (group mode only): if the current speaker has
      // a personal note, inject it using the same strength-modulated style.
      // Falls back gracefully (no-op) if absent. Appended after any group-level note.
      if (_activeGroup != null) {
        final charNote = getAuthorNoteForGroupCharacter(speakingCharacter);
        if (charNote.isNotEmpty) {
          // Use per-character strength if set, otherwise fall back to group default
          final s = getAuthorNoteStrengthForGroupCharacter(speakingCharacter);
          final name = speakingCharacter.name;
          String perCharBlock;
          if (s <= 3) {
            perCharBlock =
                "[Author's Note (gentle suggestion for $name): $charNote]\n";
          } else if (s <= 7) {
            perCharBlock = "[Author's Note (for $name): $charNote]\n";
          } else {
            perCharBlock =
                "[Author's Note (IMPORTANT for $name — apply immediately): $charNote]\n";
          }
          authorNoteBlock += perCharBlock;
        }
      }

      // One-shot entrance directive (forked-in character) — hidden, consumed
      // here so it influences only this generation and never persists.
      if (_entranceDirective != null) {
        authorNoteBlock += '[${_entranceDirective!}]\n';
        _entranceDirective = null;
      }

      // ── Scene Guests (Lite NPCs) prompt injection (1:1 only) ───────────
      // Guests speak for themselves in their own bubbles, so the primary must
      // not fully voice/narrate them. A guest turn instead gets a short line
      // grounding it as a visitor in the host's scene.
      if (_activeGroup == null) {
        final hostName = _activeCharacter?.name ?? 'the main character';
        if (guestSpeaker != null) {
          // A guest turn reuses the host's full transcript, so the identity
          // switch must be unmistakable or the model conflates the guest with
          // the host (confirmed even on strong API models). State plainly that
          // everything above belongs to the host/user and the reply is ONLY the
          // guest, and forbid voicing anyone else.
          authorNoteBlock +=
              '[SCENE GUEST TURN. You are now ${guestSpeaker.name}, who is '
              'present in this scene — you are NOT $hostName and NOT $userName. '
              'Everything written above was said and done by $hostName and '
              '$userName; ${guestSpeaker.name} is a separate person. Reply ONLY '
              'as ${guestSpeaker.name}: their own dialogue, actions, and '
              'thoughts, reacting to what just happened. Do NOT write, speak, or '
              'narrate anything for $hostName or $userName.]\n';
        } else if (_sceneGuestCards.isNotEmpty) {
          // Host turn with guests present: hard ban on ventriloquising them, or
          // the host writes the guests' lines too (the "generated both at once"
          // bug). Acknowledging/reacting is allowed; speaking for them is not.
          // The handoff sentence targets the cast-detection case: a promoted
          // guest was detected FROM the host's own narration, so the transcript
          // above is full of the host voicing them — without an explicit "that
          // has ended" the many-shot momentum beats the ban (Discord
          // double-response report, 2026-07-28). The defer clause covers an
          // addressed guest the sendMessage vocative router didn't catch.
          final names = _sceneGuestCards.map((g) => g.name).join(', ');
          authorNoteBlock +=
              '[Also present in the scene: $names — each is a separate '
              'character played by another actor, replying in their own '
              'separate messages. Do NOT write any dialogue, actions, or inner '
              'thoughts for them — not a single line. If earlier messages '
              'above included lines spoken by these characters, that has '
              'ended: from now on they speak only for themselves. Stay '
              'entirely as $hostName; you may have $hostName notice or react '
              'to them, but never put words or actions on them. If $userName '
              'just addressed one of them, reply only with $hostName\'s own '
              'brief reaction and leave the answer to that character.]\n';
        }
        // One-shot guest departure (armed by /exit) — narrated by the primary
        // on this turn only, then cleared so it never persists.
        if (guestSpeaker == null && _pendingGuestDeparture != null) {
          authorNoteBlock +=
              '[${_pendingGuestDeparture!} leaves the scene; '
              'write them exiting naturally.]\n';
          _pendingGuestDeparture = null;
        }
      }

      // Build summary block if available. Role frame (spec §6): the recap is
      // the plot spine; the journal carries feelings; RAG carries exact lines.
      // Leading \n: post-transcript blocks carry their own separator because
      // history has no trailing newline (same convention as memoriesBlock).
      // The "not new prose" clause is the recap's anti-echo guard for its
      // post-transcript seat (Grok review: a bare recap right before the
      // reply is narrative-continue bait — models restate it).
      String summaryBlock = '';
      if (_summary.isNotEmpty) {
        summaryBlock =
            '\n[The story so far (a recap for memory — not new prose; do '
            'not continue or restate it): $_summary]\n';
      }

      // The Journal — the upcoming speaker's pinned + hot memory cards, with
      // their felt emotions (strictly this chat's cards; guests never
      // journal). Built HERE, before the fixed-content token count below, so
      // history budgeting accounts for it (async, unlike the sync builders).
      String journalBlock = '';
      // Two-tier memory (living-time-features.md §8): positions the journal
      // expanded verbatim this turn — RAG retrieval below excludes them so
      // the exact lines never ride the prompt twice.
      var expandedJournalPositions = const <int>{};
      if (_storageService.memorySettings.journalEnabled &&
          guestSpeaker == null &&
          _currentSessionId != null) {
        final journal = await _journalInjection.buildJournalBlock(
          characterId: _getCharacterIdFromCard(speakingCharacter),
          characterName: speakingCharacter.name,
          userName: userName,
          // Cold-card resurfacing query — same last-3-messages recipe as RAG
          // retrieval below (built separately: that one runs after continue
          // mode pops the tail message, this one before).
          queryText: _messages.reversed
              .take(3)
              .map((m) => '${m.sender}: ${m.displayText}')
              .join('\n'),
          messageCount: _messages.length,
        );
        journalBlock = journal.text;
        expandedJournalPositions = journal.expandedPositions;
      }

      // ── Continue mode: remove the last message from history ──
      // For continue mode, we exclude the last message from the chat history
      // and place it as the prompt suffix so the LLM continues from it naturally.
      // Wrapped in try-finally to guarantee restoration even on exception.
      ChatMessage? _continuePoppedMessage;
      if (mode == GenerationMode.continue_ && _messages.isNotEmpty) {
        _continuePoppedMessage = _messages.removeLast();
        final partial = _continuePoppedMessage.text;
        // For Continue: feed straight existing messages as the prompt (per user request).
        // The suffix is the raw text of the message being continued (no re-added "Sender: " label).
        // This makes the continuation prompt contain the plain previous messages + the exact
        // partial text to extend, so the model continues the string directly without beginning
        // the output with "Rachel:" or the speaker name.
        // CRITICAL RULE: Strictly forbid the model from writing *anything* for {{user}} (actions, dialogue, thoughts, "he said", "you feel", etc.).
        // This is a cardinal sin in AI RP. Only extend the provided partial text from the current speaker's POV and voice.
        // The user's name is interpolated directly (not {{user}}): this rule
        // rides the suffix together with the partial message text, and running
        // the macro resolver over user/model-authored content would
        // double-process any {{...}} it happens to contain. Sanitized so a
        // name carrying brackets/newlines can't break the [rule] framing.
        final safeUser = userName.replaceAll(RegExp(r'[\n\r\[\]]'), ' ').trim();
        final ruleUser = safeUser.isEmpty ? 'the user' : safeUser;
        suffix =
            "\n[CRITICAL RULE: The text below is an incomplete response from the *current speaker only*. You MUST ONLY generate more text that continues *this exact response* in the speaker's voice, style, and perspective. NEVER write any dialogue, actions, thoughts, narration, or descriptions for $ruleUser or from $ruleUser's point of view. NEVER add new speaker labels or switch characters. Only append to the text below. Stop if it would require $ruleUser content.]\n" +
            partial;
      }

      // ── Macro resolution pass ──
      // Full chat context: card fields, group roster, last messages, idle
      // clock, and the {{setvar}}/{{getvar}} stores.
      final macroCtx = _buildChatMacroContext(
        speakingCharacter,
        scenario: scenario,
      );
      systemPrompt = _macroResolver.resolve(
        systemPrompt,
        macroCtx,
        section: 'systemPrompt',
      );
      // Lore buckets are macro-resolved individually (same 'lore' section
      // seeding the old single block used).
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
      // personaBlock and group-mode examples are resolved per-character above
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

      // Declare variables before try block so they're accessible after finally
      String history = '';
      int droppedMessages = 0;
      int historyBudget = 0;
      // The wheel hub (spec §7): every prompt section registers here once;
      // the system message, user message, fixed-token count, and Context
      // Viewer budget map all render from this ONE list. Built inside the
      // try (blocks must exist first), used through the rest of the turn.
      PromptPlan? promptPlan;

      // Ensure the popped message is always restored, even if prompt assembly throws
      try {
        history = _buildChatHistory(depthLore: loreDepth);

        // ── Context Shift: budget-aware history trimming ──

        // Realism / internal state block — the words-only composer
        // (lib/services/chat/prompt_injection/realism_state_injection.dart):
        // salience-gated natural language only, no simulation scalars. Macro-
        // resolved HERE (spec §5a) — the fragments carry {{user}}, and this
        // block previously reached the model with the braces literal.
        String realismBlock = '';
        if (_realismActiveThisMode) {
          final rawRealism = _getRealismStateInjection();
          realismBlock = rawRealism.isEmpty
              ? ''
              : _macroResolver.resolve(
                  rawRealism,
                  macroCtx,
                  section: 'realism',
                );
        }

        // Living Worlds — place prose from attached worlds (budget-capped).
        final attachedWorlds = [
          for (final id in _chatWorldIds)
            if (_worldRepository.resolveWorld(id) != null)
              _worldRepository.resolveWorld(id)!,
        ];
        // Fallback: group template worlds when chat_worlds not yet seeded.
        if (attachedWorlds.isEmpty && _activeGroup != null) {
          for (final ref in _activeGroup!.worldIds) {
            final w = _worldRepository.resolveWorld(ref);
            if (w != null) attachedWorlds.add(w);
          }
        }
        final rawWorld = buildWorldInjection(attachedWorlds);
        final worldBlock = rawWorld.isEmpty
            ? ''
            : _macroResolver.resolve(rawWorld, macroCtx, section: 'world');

        // Chance Time injection — independent of realism mode
        final chanceTimeBlock = _getChanceTimeInjection();

        // LLMerta Mafia-night force-ack (Chance Time register). Re-arms from
        // diary if needed; stays armed through regen of this AI message until
        // the *next* user send clears it.
        final porchDiaryId = _getCharacterIdFromCard(speakingCharacter);
        final porchSessionId = _currentSessionId;
        if (porchSessionId != null) {
          await _porchMemoryImport.ensureArmedForDiary(
            sessionId: porchSessionId,
            diaryCharacterId: porchDiaryId,
          );
        }
        final porchNightRaw = _porchMemoryImport.takeInjectionForDiary(
          porchDiaryId,
        );
        final porchNightBlock = porchNightRaw.isEmpty
            ? ''
            : _macroResolver.resolve(
                porchNightRaw,
                macroCtx,
                section: 'realism',
              );

        // Objective injection — always injected regardless of realism mode
        // Must sit in a fixed prompt section so it is NEVER trimmed by the budget system.
        // (thin delegation to author_note_builder per step 8; state/CRUD in god)
        final objectiveBlock = _getObjectiveInjection();

        // Mandatory Needs Catastrophe — when a hard-event need hit 0 during the
        // decay tick, the character's body/state fails in a specific way and the
        // reply must open on it. The narrative carries its own evidence, so this
        // wrapper stays generic: firm but short (heavy "YOU MUST" walls read as
        // jailbreak-fight energy and can backfire), and it never puppets {{user}}.
        String needsCatastropheBlock = '';
        if (_needsSimulation.pendingCatastrophe != null) {
          // Macro-resolved (spec §5a): previously the {{user}}/{{char}}
          // placeholders in this wrapper reached the model literally.
          needsCatastropheBlock = _macroResolver.resolve(
            '[SCENE EVENT — CANON, happening this turn]\n'
            '${_needsSimulation.pendingCatastrophe}\n'
            'Open the reply with this event as it happens; do not skip it, '
            'soften it to a near-miss, or fade past it. Narrate only what this '
            'specific event makes observable, then let the scene continue from '
            'its consequences. Do NOT decide {{user}}\'s actions, words, or '
            'feelings — write only {{char}} and the surroundings.]\n',
            macroCtx,
            section: 'realism',
          );
          // Consume it for this generation
          _needsSimulation.consumePendingCatastrophe();
        }

        // Register every section with the plan, in render order. This ONE
        // list is what the system message, user message, fixed-token count,
        // and Context Viewer budget map are all rendered from — every lore
        // bucket is counted (including @depth entries, which are spliced
        // into history later WITHOUT re-counting, via rendered:false), and
        // history/memories are budget-fitted afterwards (counted:false).
        final plan = promptPlan = PromptPlan();
        // ── system message ──
        plan.add(
          id: 'system',
          label: 'System Prompt',
          inSystem: true,
          text: '$systemPrompt\n',
        );
        plan.add(
          id: 'lore.before',
          label: 'Lorebook',
          inSystem: true,
          text: loreBefore,
        );
        plan.add(
          id: 'persona',
          label: 'Persona',
          inSystem: true,
          text: '$personaBlock\n',
        );
        plan.add(
          id: 'lore.after',
          label: 'Lorebook',
          inSystem: true,
          text: loreAfter,
        );
        plan.add(id: 'user_persona', inSystem: true, text: userPersonaBlock);
        plan.add(
          id: 'scenario',
          label: 'Scenario',
          inSystem: true,
          text: 'Scenario: $scenario\n',
        );
        plan.add(
          id: 'lore.ex_top',
          label: 'Lorebook',
          inSystem: true,
          text: loreExTop,
        );
        plan.add(
          id: 'examples',
          label: 'Examples',
          inSystem: true,
          text: mesExampleBlock,
        );
        plan.add(
          id: 'lore.ex_bottom',
          label: 'Lorebook',
          inSystem: true,
          text: loreExBottom,
        );
        // ── user message (transcript + tail) ──
        plan.add(id: 'start', text: '<START>\n');
        plan.add(
          id: 'history',
          label: 'Chat History',
          text: '',
          counted: false, // budget-fitted against fixedCountText
        );
        // Retrieved memories sit AFTER the transcript (Phase 3, measured):
        // retrieval changes this block every turn, and a changing block
        // BEFORE the history rewrote the prompt's middle each turn — a full
        // re-prefill of the whole transcript on every model (ContextShift
        // can't fix a middle edit). Measured on Gemma-4-31B (SWA): 2.62s →
        // 0.40s mean prompt-process, ~15s → ~1.2s wall on typical turns.
        // The echo risk of sitting nearer the generation point is carried by
        // the block's own framing ("reference only, do not revisit").
        plan.add(
          id: 'memories',
          label: 'Retrieved Memories',
          text: '',
          counted: false, // budget-fitted by the RAG joint cap below
        );
        // The recap and the Journal ALSO sit after the transcript (audit
        // finding #4's remainder, same mechanism as memories above): the
        // journal block re-sorts with the speaker's mood and re-warms cold
        // cards EVERY turn, and the recap rewrites every journal pass — as
        // pre-history sections they rewrote the prompt's head, forcing a
        // full re-prefill of the whole transcript on every local backend
        // (KoboldCpp, oMLX, LM Studio; prefix caches need byte-identical
        // heads). Post-history, mood re-ordering is cache-free. Render order
        // memories → recap → journal puts the feelings channel closest to
        // the generation point, matching its "truer guide" role frame.
        // Their fixed-count slot is unchanged (history/memories are excluded
        // from fixedCountText); the only fixed-count delta is each block's
        // new separator newline (≤1 token), so history budgeting is intact.
        plan.add(id: 'summary', label: 'Summary', text: summaryBlock);
        plan.add(id: 'journal', label: 'Journal', text: journalBlock);
        plan.add(
          id: 'post_history',
          label: 'Post-History',
          text: postHistoryBlock,
        );
        plan.add(id: 'lore.an_top', label: 'Lorebook', text: loreAnTop);
        plan.add(
          id: 'author_note',
          label: 'Author\'s Note',
          text: authorNoteBlock,
        );
        plan.add(id: 'lore.an_bottom', label: 'Lorebook', text: loreAnBottom);
        plan.add(
          id: 'lore.depth',
          label: 'Lorebook',
          text: loreDepthJoined,
          rendered: false, // spliced into the history lines, paid for here
        );
        plan.add(id: 'objectives', label: 'Objectives', text: objectiveBlock);
        plan.add(id: 'world', label: 'World / Place', text: worldBlock);
        plan.add(id: 'realism', label: 'Realism Mode', text: realismBlock);
        plan.add(
          id: 'catastrophe',
          label: 'Needs Catastrophe',
          text: needsCatastropheBlock,
        );
        plan.add(
          id: 'idle_cue',
          text: '',
          counted: false, // set after budgeting; rides the +50 reserve margin
        );
        plan.add(id: 'suffix', text: suffix);
        plan.add(id: 'chance_time', text: chanceTimeBlock);
        // High-recency with Chance Time so the first post-import reply
        // cannot bury the Mafia night (docs/design/llmerta-porch-memories.md §7b).
        plan.add(id: 'porch_night', text: porchNightBlock);

        final fixedTokens = await _countTokens(plan.fixedCountText);
        final contextBudget = _sessionGenSettings.resolveContextSize(
          _storageService,
        );
        final generationReserve =
            _sessionGenSettings.resolveMaxLength(_storageService) +
            50; // +50 safety margin
        historyBudget = contextBudget - fixedTokens - generationReserve;

        if (historyBudget > 0) {
          final result = await _buildChatHistoryWithBudget(
            historyBudget,
            depthLore: loreDepth,
          );
          history = result.history;
          droppedMessages = result.droppedCount;
        }
        // If budget is zero or negative, fixed sections already fill the context — use minimal history
        if (historyBudget <= 0 && _messages.isNotEmpty) {
          // Include at least the last message for continuity
          final lastMsg = _messages.last;
          history = lastMsg.characterId == '__director__'
              ? '[Director: ${lastMsg.text}]'
              : '${lastMsg.sender}: ${lastMsg.text}';
          droppedMessages = _messages.length - 1;
        }
      } finally {
        // ── Restore the popped continue message back into the list ──
        if (_continuePoppedMessage != null) {
          _messages.add(_continuePoppedMessage);
        }
      }

      final plan = promptPlan;
      if (mode == GenerationMode.continue_) {
        // Drop the needs/realism/relationship/chaos/objective/catastrophe state injections
        // for Continue. Per user request: the continue prompt should be straight existing
        // messages (the plain history transcript + the partial text to continue from).
        // The runtime state blocks make the continuation feel injected and discordant.
        plan.section('realism').text = '';
        plan.section('chance_time').text = '';
        plan.section('objectives').text = '';
        plan.section('catastrophe').text = '';
        // Also skip RAG "earlier memories" for pure straight continuation.
        droppedMessages = 0;
      }

      // ── RAG Memory Retrieval ──
      // When messages are dropped from context, search for relevant past memories
      // Skip retrieval for brand new chats to prevent old memories from interfering
      String memoriesBlock = '';

      final effectiveRagEnabled = _activeGroup != null
          ? groupRagEnabled
          : _storageService.memorySettings.ragEnabled;

      if (_isNewChat) {
        debugPrint(
          '[RAG:Chat] Skipping memory retrieval - new chat in progress',
        );
      } else if (droppedMessages > 0 &&
          _memoryService != null &&
          effectiveRagEnabled) {
        debugPrint(
          '[RAG:Chat] ── Prompt assembly: $droppedMessages messages dropped, triggering retrieval ──',
        );
        try {
          // Use last 3 messages as the query
          final queryMessages = _messages.reversed
              .take(3)
              .map((m) => '${m.sender}: ${m.displayText}')
              .join('\n');

          // Scene Guests Phase 4: a guest turn retrieves the GUEST's own
          // episodic memories (keyed on the guest id), not the host's. The
          // injection format/budget below is shared — only the source id swaps.
          final sourceIds = await _getMemorySourceIds(guest: guestSpeaker);
          debugPrint('[RAG:Chat] Memory source IDs: $sourceIds');

          // Session isolation: only the speaker's OWN id (always sourceIds.first)
          // is session-scoped, so a prior chat with this same character can no
          // longer bleed its locations/storyline into this one. Any explicit
          // cross-character sources that follow keep their intended cross-session
          // reach. Applies identically to 1:1 and group (same retrieve() path).
          final selfSourceId = sourceIds.isNotEmpty ? sourceIds.first : '';

          // Retrieval limit: groups use the per-session group setting; 1:1
          // uses the user's "Memories per turn" slider (memory panel + web).
          // The slider was previously DEAD here — 1:1 silently rode the group
          // default (8) and turning it down did nothing. 0 = "All" on both.
          final retrievalLimit = _activeGroup != null
              ? groupRetrievalCount
              : _storageService.memorySettings.ragRetrievalCount;

          final rawMemories = await _memoryService!.retrieve(
            queryText: queryMessages,
            sourceCharacterIds: sourceIds,
            currentSessionId: _currentSessionId ?? '',
            inContextStart:
                droppedMessages, // only search messages that are out of context
            limit: retrievalLimit == 0 ? 9999 : retrievalLimit,
            characterPriorities: currentGroupRAGPriorities,
            sessionScopedCharacterIds: selfSourceId.isEmpty
                ? const {}
                : {selfSourceId},
          );
          // Two-tier memory dedupe: the journal expanded these exact lines
          // above — never pay for them twice.
          final memories = RetrievedMemory.excludingPositions(
            rawMemories,
            expandedJournalPositions,
            currentSessionId: _currentSessionId ?? '',
          );
          if (memories.length < rawMemories.length) {
            debugPrint(
              '[RAG:Chat] Deduped ${rawMemories.length - memories.length} '
              'retrieval(s) already expanded by the journal',
            );
          }

          if (memories.isNotEmpty) {
            // Cap memory injection to the group's (or global) memory budget % of context.
            // The summary carries the weight of context compression; RAG only
            // supplements with specific details the summary missed. Too much
            // RAG (2500+ tokens) overwhelms the model and causes it to
            // reference stale events as if they're current ("going back in
            // time") — so the percentage is ALSO capped absolutely: 10% of a
            // 32k context is 3,200 tokens, past the documented failure line.
            final contextSize = _storageService.backendSettings.contextSize;
            final budgetFraction = _activeGroup != null
                ? (groupMemoryBudgetPercent / 100.0)
                : 0.10;
            final memoryBudget = math.min(
              (contextSize * budgetFraction).round(),
              kRagMemoryBudgetCapTokens,
            );
            final includedMemories = <String>[];
            int usedTokens = 0;
            for (final m in memories) {
              final memTokens = (m.content.length / 4).ceil();
              if (usedTokens + memTokens > memoryBudget &&
                  includedMemories.isNotEmpty) {
                debugPrint(
                  '[RAG:Chat] ⚠ Trimmed ${memories.length - includedMemories.length} memories to fit budget ($memoryBudget tokens)',
                );
                break;
              }
              usedTokens += memTokens;
              includedMemories.add('- ${m.content}');
            }
            if (includedMemories.isNotEmpty) {
              // Role frame (spec §6): RAG = exact earlier lines, reference
              // only — the journal outranks it on feelings, the recap on plot.
              // Leading '\n' because this now follows the history transcript,
              // whose last line carries no trailing newline.
              String buildBlock(List<String> mems) =>
                  '\n[Exact earlier lines from this chat (already happened — '
                  'reference only, do not revisit):\n${mems.join('\n')}]\n';
              memoriesBlock = buildBlock(includedMemories);

              // Budget accounting fix (spec §5f): memories were previously
              // injected WITHOUT being counted — history had already filled
              // its budget, so every RAG turn overshot the context and the
              // server trimmed the prompt head (the character card). Real-
              // count the block, trim trailing memories if the chars/4
              // estimates undershot the cap, then re-walk history with the
              // remainder so fixed + history + memories + reserve <= context.
              // Trim can go all the way to EMPTY: a single retrieved memory
              // larger than the whole memory budget must drop the block
              // entirely rather than ship over budget (review finding — the
              // packing loop above always admits the first memory).
              // JOINT cap (review finding): memories must fit the memory
              // budget AND leave a strictly positive history remainder —
              // memories are paid for out of the SAME space history uses, so
              // a block that survives only by starving history re-opens the
              // overshoot this fix exists to close. Trim goes all the way to
              // EMPTY (a lone oversize memory is dropped, never shipped over
              // budget). historyBudget <= 0 means the fixed sections already
              // fill the context — no room for memories at all.
              int memTokens = await _countTokens(memoriesBlock);
              while (memTokens > 0 &&
                  (memTokens > memoryBudget ||
                      historyBudget - memTokens <= 0)) {
                includedMemories.removeLast();
                memoriesBlock = includedMemories.isEmpty
                    ? ''
                    : buildBlock(includedMemories);
                memTokens = memoriesBlock.isEmpty
                    ? 0
                    : await _countTokens(memoriesBlock);
              }
              if (memTokens > 0) {
                // Re-walk history with the remainder (strictly positive here;
                // _buildChatHistoryWithBudget treats <= 0 as UNLIMITED) so
                // fixed + history + memories + reserve <= context.
                final rebudget = await _buildChatHistoryWithBudget(
                  historyBudget - memTokens,
                  depthLore: loreDepth,
                );
                history = rebudget.history;
                // Keep the retrieval's inContextStart lag (spec: messages
                // evicted by this second walk become retrievable next turn);
                // the budget map below reports the final dropped count.
                droppedMessages = rebudget.droppedCount;
                debugPrint(
                  '[RAG:Chat] ✅ Injecting ${includedMemories.length}/${memories.length} memories ($memTokens tokens real, budget: $memoryBudget)',
                );
              } else {
                debugPrint(
                  '[RAG:Chat] ⚠ Dropped all ${memories.length} memories — no '
                  'room inside the context budget this turn',
                );
              }
            }
          } else {
            debugPrint('[RAG:Chat] No relevant memories found for this turn');
          }
        } catch (e) {
          debugPrint('[RAG:Chat] ✗ RAG retrieval failed: $e');
        }
      } else if (droppedMessages > 0 &&
          _storageService.memorySettings.ragEnabled) {
        debugPrint(
          '[RAG:Chat] ⚠ $droppedMessages messages dropped but RAG not operational (service=${_memoryService != null}, operational=${_memoryService?.isOperational ?? false})',
        );
      }

      // Realism injection was already computed above for budget

      // Inject fourth-wall idle cue if Dynamic Responses triggered.
      // Placed in the user-prompt body (not system prompt) so it sits right
      // before the generation point — local models often ignore system-role
      // instructions but follow the last content in the user message.
      final idleCue = _pendingIdleCue;
      if (idleCue != null) {
        suffix = '\n${speakingCharacter.name}: *';
      }

      // Sync the late-filled sections, then render everything from the plan.
      // Every backend speaks the OpenAI chat protocol (local KoboldCpp via
      // its /v1/chat/completions door), so the system zone rides a proper
      // 'system' role message and the transcript zone the 'user' message —
      // the server applies the model's instruct template server-side.
      plan.section('history').text = history;
      plan.section('memories').text = memoriesBlock;
      plan.section('idle_cue').text = idleCue != null ? '\n$idleCue' : '';
      plan.section('suffix').text = suffix;

      final chatSystemPrompt = plan.systemText;
      final prompt = plan.userText;

      // Context viewer: full prompt + per-section budget, straight from the
      // plan (no third hand-built copy to drift).
      _lastAssembledPrompt = plan.fullText;
      _lastPromptBudget = {
        ...plan.budgetEstimates(),
        if (droppedMessages > 0) 'Dropped Messages': droppedMessages,
      };

      // Stop sequences, priority-ordered (stop_sequences.dart) so transports
      // that cap the server-side list keep the most important entries: user
      // stops, then custom stops, then character names, then defaults. The
      // client-side mid-stream trim below always enforces the FULL list.
      final g2 = _sessionGenSettings;

      // For Continue mode, do *not* stop on the current speaker's name.
      // This lets the model produce long, natural extensions of the existing message
      // in that character's voice without the name stop cutting it off mid-continuation.
      // We still stop on other speakers or the user (to catch unwanted new turns).
      String? continueSpeakerName;
      if (mode == GenerationMode.continue_ &&
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
          (c) => identical(c, speakingCharacter),
        );
        if (idx < 0) idx = names.indexOf(speakingCharacter.name);
        stopCharacterNames = idx >= 0
            ? [...names.sublist(idx + 1), ...names.sublist(0, idx + 1)]
            : names;
      } else {
        stopCharacterNames = [_activeCharacter!.name];
      }

      final stopList = buildPrioritizedStops(
        configured: g2.resolveStopSequences(_storageService),
        userName: _userPersonaService.persona.name,
        // In impersonate mode the model IS the user, so don't stop on user name
        impersonating: mode == GenerationMode.impersonate,
        characterNames: stopCharacterNames,
        continueSpeakerName: continueSpeakerName,
      );

      // Get the active LLM service (local or remote)
      final llmService =
          testLlmServiceOverride ??
          _llmProvider?.activeService ??
          _koboldService;

      // For call mode with a dedicated call model, temporarily swap the model
      if (_callMode &&
          _storageService.sttSettings.callModelName.isNotEmpty &&
          _llmProvider != null &&
          !_llmProvider!.isLocal) {
        _originalModelName = _llmProvider!.openRouterService.modelName;
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
      final turnImages = await buildTurnImages(mode);

      final genParams = GenerationParams(
        prompt: prompt,
        systemPrompt: chatSystemPrompt,
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
        reasoningEnabled: (_callMode || mode == GenerationMode.continue_)
            ? false
            : g2.resolveReasoningEnabled(_storageService),
        reasoningEffort: g2.resolveReasoningEffort(_storageService),
        // Force zero thinking budget on Continue (and call mode) for providers like OpenRouter/Nano-GPT.
        // This tells supported models (Kimi K2 Thinking, DeepSeek hybrid reasoning models, certain Qwen3 etc.)
        // to spend 0 tokens on internal reasoning and answer directly, preventing the model from dumping
        // its next analysis/think block into the visible character response.
        reasoningMaxTokens: (_callMode || mode == GenerationMode.continue_)
            ? 0
            : null,
        bannedPhrases: g2.resolveBannedPhrases(_storageService).isNotEmpty
            ? g2.resolveBannedPhrases(_storageService)
            : null,
        images: turnImages,
      );

      // Get streaming response from whichever backend is active
      final stream = llmService.generateStream(genParams);

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
      Timer? _perfPoller;
      final isLocalBackend = _llmProvider == null || _llmProvider!.isLocal;
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

        _perfPoller = Timer.periodic(const Duration(seconds: 2), (_) async {
          if (_generationPhase != GenerationPhase.prefilling) {
            _perfPoller?.cancel();
            _perfPoller = null;
            return;
          }
          final perf = await _koboldService.fetchPerf();
          if (perf != null) {
            _lastPerfData = perf;
            notifyListeners();
          }
        });
      }

      String accumulatedResponse = "";
      bool stopFound = false;
      _tokenBuffer.clear();
      _displayedTokenCount = 0;
      _tokenTimestamps.clear();
      bool streamDone = false;
      DateTime? _thinkStartTime;
      bool _thinkStarted = false;
      bool _thinkEnded = false;

      // Determine message identity. The stream target is captured ONCE by
      // reference — every later write (flush, think timestamps, sanitizer,
      // needs re-stamp, TTS) goes through it instead of _messages.last. The
      // list can shift under a long turn (dream insert, deletes, another
      // send: none of those are hard-blocked while a turn winds down), and
      // positional writes are how an aborted reply overwrote a dream banner
      // (2026-07-28). A write to a message deleted mid-turn lands on the
      // detached object — harmless and invisible.
      String originalText = '';
      String targetSender;
      bool isUserTarget;
      final ChatMessage streamTarget;

      if (mode == GenerationMode.continue_) {
        streamTarget = _messages.last;
        originalText = streamTarget.text;
        targetSender = streamTarget.sender;
        isUserTarget = streamTarget.isUser;
        // Merge metadata if continuing
        if (_pendingRealismMetadata != null) {
          streamTarget.activeMetadata ??= {};
          streamTarget.activeMetadata!.addAll(_pendingRealismMetadata!);
          _pendingRealismMetadata = null;
        }
      } else {
        targetSender = mode == GenerationMode.normal
            ? speakingCharacter.name
            : _userPersonaService.persona.name;
        isUserTarget = mode == GenerationMode.impersonate;
        // A Scene Guest turn carries NO Realism/Needs, so its message must never
        // inherit _pendingRealismMetadata — which still holds the HOST turn's
        // verification result (the leftover "✓ Director accepted" chip), bond
        // deltas, etc. Guests get clean (null) metadata.
        final initialMetadata =
            (guestSpeaker != null || _pendingRealismMetadata == null)
            ? null
            : Map<String, dynamic>.from(_pendingRealismMetadata!);
        debugPrint(
          '[Realism:Metadata] PRE-GEN attach (needs_deltas + any post-gen '
          'deltas are added AFTER this): '
          'bond_delta=${initialMetadata?['bond_delta']}, '
          'keys=${initialMetadata?.keys.toList()}',
        );
        streamTarget = ChatMessage(
          text: "",
          sender: targetSender,
          isUser: isUserTarget,
          characterId: mode == GenerationMode.normal
              ? _getCharacterIdForCard(speakingCharacter)
              : null,
          metadata: initialMetadata,
          swipeMetadata: initialMetadata != null ? [initialMetadata] : null,
        );
        _messages.add(streamTarget);
        _pendingRealismMetadata = null;
      }

      // Helper to update the visible message from buffer
      void _flushBufferToDisplay() {
        if (epoch != _generationEpoch) return; // stale generation
        if (_tokenBuffer.isEmpty && _displayedTokenCount == 0) return;
        // Build displayed text from all tokens up to _displayedTokenCount
        final displayTokens = _tokenBuffer.take(_displayedTokenCount).join();
        String displayText;
        if (mode == GenerationMode.continue_) {
          displayText = originalText + displayTokens;
        } else {
          displayText = displayTokens.trimLeft();
        }
        // CRITICAL: Modify the captured stream target in place (never
        // _messages.last — the list can shift mid-turn) to preserve
        // thinkingStartTime and other metadata.
        streamTarget.text = displayText;
        notifyListeners();
      }

      // Read display buffer settings — disable for remote APIs (they're fast enough)
      final isRemoteBackend = _llmProvider != null && !_llmProvider!.isLocal;
      final bufferEnabled = isRemoteBackend
          ? false
          : _storageService.uiSettings.displayBufferEnabled;
      final targetTps = _storageService.uiSettings.targetDisplayTps;

      // Drain timer: displays tokens at the user-configured constant rate
      void _startDrainTimer() {
        if (_drainTimer != null) return;
        final interval = Duration(milliseconds: (1000.0 / targetTps).round());
        _drainTimer = Timer.periodic(interval, (_) {
          if (epoch != _generationEpoch) {
            _drainTimer?.cancel();
            _drainTimer = null;
            return;
          } // stale
          if (_displayedTokenCount < _tokenBuffer.length) {
            _displayedTokenCount++;
            _flushBufferToDisplay();
          } else if (streamDone) {
            // Stream finished and buffer fully drained
            _drainTimer?.cancel();
            _drainTimer = null;
          }
          // If buffer is caught up but stream still running, timer ticks idly until more tokens arrive
        });
      }

      // Consume the stream — tokens go into buffer (or display immediately)
      await for (final token in stream) {
        if (_cancelRequested) break;
        accumulatedResponse += token;
        _tokensGenerated++;
        _tokenTimestamps.add(DateTime.now());

        // ── Phase transition: first token marks end of prefill ──
        if (_tokensGenerated == 1) {
          _perfPoller?.cancel();
          _perfPoller = null;
          // Fetch final perf data so we know how long prefill really took
          if (isLocalBackend) {
            _koboldService.fetchPerf().then((perf) {
              if (perf != null) {
                _lastPerfData = perf;
              }
            });
          }
          _prefillStartTime = null;
        }

        // Broadcast token to external listeners (SSE bridge)
        _tokenBroadcast.add(token);
        _generationProgress = _maxTokens > 0
            ? (_tokensGenerated / _maxTokens).clamp(0.0, 1.0)
            : 0.0;

        // Sentence streaming: accumulate tokens and emit complete sentences
        _sentenceBuffer += token;

        // Split strategy:
        // 1. Always split at sentence boundaries: . ! ? followed by space, or \n
        // 2. For long buffers (>80 chars / ~15 words), also split at clause
        //    boundaries: ", " "; " " — " " - " to keep TTS chunks short (~1-3s)
        bool emitted = true;
        while (emitted) {
          emitted = false;

          // First try sentence boundaries
          final sentenceEnd = RegExp(r'[.!?]\s|[.!?]$|\n');
          if (sentenceEnd.hasMatch(_sentenceBuffer)) {
            final match = sentenceEnd.firstMatch(_sentenceBuffer)!;
            final sentence = _sentenceBuffer.substring(0, match.end).trim();
            _sentenceBuffer = _sentenceBuffer.substring(match.end);
            if (sentence.isNotEmpty) {
              _sentenceBroadcast.add(sentence);
              emitted = true;
            }
            continue;
          }

          // For long buffers, split at clause boundaries to keep TTS fast
          if (_sentenceBuffer.length > 80) {
            final clauseEnd = RegExp(r',\s|;\s|\s[—–-]\s');
            if (clauseEnd.hasMatch(_sentenceBuffer)) {
              // Find the LAST clause boundary to maximize chunk size
              Match? lastMatch;
              for (final m in clauseEnd.allMatches(_sentenceBuffer)) {
                if (m.start > 30) lastMatch = m; // at least 30 chars per chunk
              }
              if (lastMatch != null) {
                final chunk = _sentenceBuffer
                    .substring(0, lastMatch.end)
                    .trim();
                _sentenceBuffer = _sentenceBuffer.substring(lastMatch.end);
                if (chunk.isNotEmpty) {
                  _sentenceBroadcast.add(chunk);
                  emitted = true;
                }
              }
            }
          }
        }

        // Client-side safety trim check (mid-stream)
        for (final stop in stopList) {
          if (accumulatedResponse.contains(stop)) {
            int index = accumulatedResponse.indexOf(stop);
            final trimmedTotal = accumulatedResponse.substring(0, index);
            final previousTotal = _tokenBuffer.join();
            final lastTokenContribution = trimmedTotal.substring(
              previousTotal.length.clamp(0, trimmedTotal.length),
            );
            if (lastTokenContribution.isNotEmpty) {
              _tokenBuffer.add(lastTokenContribution);
            }
            accumulatedResponse = trimmedTotal;
            stopFound = true;
            break;
          }
        }

        if (!stopFound) {
          _tokenBuffer.add(token);
        }

        // Track think timing
        if (!_thinkStarted && accumulatedResponse.contains('<think>')) {
          _thinkStarted = true;
          _thinkStartTime = DateTime.now();
          _generationPhase = GenerationPhase.thinking;
          streamTarget.thinkingStartTime =
              _thinkStartTime.millisecondsSinceEpoch;
        }
        if (_thinkStarted &&
            !_thinkEnded &&
            accumulatedResponse.contains('</think>')) {
          _thinkEnded = true;
          // Transition out of thinking to buffering/generating
          _generationPhase = bufferEnabled
              ? GenerationPhase.buffering
              : GenerationPhase.generating;
          if (_thinkStartTime != null) {
            streamTarget.thinkingDurationMs = DateTime.now()
                .difference(_thinkStartTime)
                .inMilliseconds;
            // Keep thinkingStartTime for fallback display logic in UI
          }
        }
        // If no thinking involved, first token transitions directly
        if (!_thinkStarted && _tokensGenerated == 1) {
          _generationPhase = bufferEnabled
              ? GenerationPhase.buffering
              : GenerationPhase.generating;
        }

        if (bufferEnabled) {
          // Calculate current rolling TPS (last 3 seconds)
          final now = DateTime.now();
          final cutoff = now.subtract(const Duration(seconds: 3));
          final recentCount = _tokenTimestamps
              .where((t) => t.isAfter(cutoff))
              .length;
          final windowStart =
              _tokenTimestamps.where((t) => t.isAfter(cutoff)).firstOrNull ??
              _generationStartTime!;
          final windowElapsed =
              now.difference(windowStart).inMilliseconds / 1000.0;
          final currentTps = (recentCount >= 2 && windowElapsed > 0)
              ? recentCount / windowElapsed
              : (_tokensGenerated > 0
                    ? _tokensGenerated /
                          (now
                                  .difference(_generationStartTime!)
                                  .inMilliseconds /
                              1000.0)
                    : 0.0);

          if (_drainTimer == null && _tokensGenerated >= 10) {
            // Not yet draining — calculate when to start
            // Buffer target = how many tokens fill the configured duration
            final bufferDuration =
                _storageService.uiSettings.bufferDurationSeconds;
            int bufferTarget;
            if (currentTps > 0) {
              bufferTarget = (currentTps * bufferDuration).round().clamp(
                5,
                _maxTokens,
              );
            } else {
              bufferTarget = 30; // Fallback if TPS unknown
            }

            if (_tokenBuffer.length >= bufferTarget) {
              _isBuffering = false;
              _generationPhase = GenerationPhase.generating;
              _startDrainTimer();
            }
          } else if (_drainTimer != null) {
            // Already draining — check if buffer is running low
            final remaining = _tokenBuffer.length - _displayedTokenCount;
            if (remaining <= 3 && !streamDone) {
              // Buffer critically low — pause drain to rebuild
              _drainTimer?.cancel();
              _drainTimer = null;
              _isBuffering = true;
              _generationPhase = GenerationPhase.buffering;
            }
          }
        } else {
          // No buffer: display tokens immediately
          _isBuffering = false;
          _generationPhase = GenerationPhase.generating;
          _displayedTokenCount = _tokenBuffer.length;
          _flushBufferToDisplay();
        }

        // Update TPS/progress in the bar even during buffering
        notifyListeners();

        if (stopFound) break;
      }

      // Mark stream as done
      streamDone = true;
      _isBuffering = false;

      if (_cancelRequested) {
        // Cancelled mid-stream: do NOT drain the undisplayed backlog. A
        // think-heavy turn can hold minutes of buffered tokens, and draining
        // them after Stop is how an aborted reply kept "dumping" (and, via
        // the positional last-message writes, how one landed inside a dream
        // banner — 2026-07-28). Keep exactly what's on screen.
      } else if (!bufferEnabled) {
        // No buffer: everything already displayed
        _displayedTokenCount = _tokenBuffer.length;
        _flushBufferToDisplay();
      } else if (_drainTimer == null) {
        // Buffer never started draining (genTps < targetTps) — start now with all tokens ready
        _startDrainTimer();
        // Wait for drain to complete (Stop pressed mid-drain halts it)
        while (_displayedTokenCount < _tokenBuffer.length &&
            !_cancelRequested) {
          await Future.delayed(const Duration(milliseconds: 16));
        }
        _drainTimer?.cancel();
        _drainTimer = null;
      } else {
        // Drain already running — wait for it to finish (or Stop to halt it)
        while (_displayedTokenCount < _tokenBuffer.length &&
            !_cancelRequested) {
          await Future.delayed(const Duration(milliseconds: 16));
        }
        _drainTimer?.cancel();
        _drainTimer = null;
      }

      // User cancel (stream-loop break above, or Stop during the drain):
      // halt the turn HERE — no finalize, no lorebook scan, no post-turn
      // evals on an aborted reply. Mirrors the catch path's treatAsCancel:
      // keep the displayed partial so regen/continue work, save, signal done.
      if (_cancelRequested) {
        _drainTimer?.cancel();
        _drainTimer = null;
        _tokenBuffer.clear();
        _isGenerating = false;
        _cancelRequested = false;
        _generationProgress = 0.0;
        _isBuffering = false;
        _generationPhase = GenerationPhase.idle;
        _prefillStartTime = null;
        _prefillPromptTokens = 0;
        _generationStartTime = null;
        _perfPoller?.cancel();
        _perfPoller = null;
        _tokenBroadcast.add('__DONE__');
        if (_sentenceBuffer.trim().isNotEmpty) {
          _sentenceBroadcast.add(_sentenceBuffer.trim());
          _sentenceBuffer = '';
        }
        _sentenceBroadcast.add('__DONE__');
        if (_originalModelName != null && _llmProvider != null) {
          _llmProvider!.openRouterService.configure(
            modelName: _originalModelName,
          );
        }
        await _saveChat();
        notifyListeners();
        return;
      }

      _isGenerating = false;
      _cancelRequested = false;
      _generationProgress = 0.0;
      _isBuffering = false;
      _generationPhase = GenerationPhase.idle;
      _prefillStartTime = null;
      _prefillPromptTokens = 0;
      _generationStartTime = null;
      _perfPoller?.cancel();
      _perfPoller = null;

      // Fetch final perf stats from KoboldCPP for post-generation display
      if (isLocalBackend) {
        _koboldService.fetchPerf().then((perf) {
          if (perf != null) _lastPerfData = perf;
        });
      }

      // Signal generation complete to SSE listeners
      _tokenBroadcast.add('__DONE__');

      // Flush remaining sentence buffer and signal done to sentence listeners
      if (_sentenceBuffer.trim().isNotEmpty) {
        _sentenceBroadcast.add(_sentenceBuffer.trim());
        _sentenceBuffer = '';
      }
      _sentenceBroadcast.add('__DONE__');

      notifyListeners();

      // Only finalize if this generation is still current
      if (epoch == _generationEpoch) {
        String finalResponse = accumulatedResponse.trim();

        // SillyTavern-like safety net for Continue (and call mode): even after requesting
        // enabled:false + max_tokens:0 + exclude:true on the provider, some thinking models
        // (Kimi 2.6:thinking etc.) can still emit stray <think> or reasoning text.
        // Strip it from the final text before it becomes part of the character's message.
        // This matches ST's "Strip Reasoning Tags" behavior as a client-side backstop.
        if (mode == GenerationMode.continue_ || _callMode) {
          finalResponse = _stripThinkBlocks(finalResponse);
        }

        // ── Output Sanitizer ──────────────────────────────────────────────
        // NOTE: This runs BEFORE _lorebookScanner.scanLatest() below, so
        // lorebook keyword triggers operate on the sanitized text. If a rule
        // replaces text that a lorebook keyword was matching, the trigger
        // would stop matching. This is intentional — sanitized output is the
        // "final" text that enters history and is scanned for lore.
        if (g2.resolveOutputSanitizerEnabled(_storageService)) {
          final rules = g2.resolveOutputSanitizerRules(_storageService);
          finalResponse = sanitizeOutput(finalResponse, rules);
          streamTarget.text = finalResponse;
        }

        // Snapshot which entries were already triggered before scanning the AI response.
        // We will only decrement those — newly AI-triggered entries must keep their
        // full depth budget so they are visible on the next user turn.
        // Covers the full scanned universe (incl. group book + group worlds).
        final preAiTriggered = <LorebookEntry>{
          for (final ref in _collectLoreRefs(inheritOverride: true))
            if (ref.entry.isTriggered && !ref.entry.constant) ref.entry,
        };

        if (finalResponse.isNotEmpty &&
            _messages.isNotEmpty &&
            identical(_messages.last, streamTarget)) {
          // scanLatest reads the LAST message — only valid while the streamed
          // message still holds that position (a mid-turn insert/delete can
          // shift it; scanning someone else's text would trigger wrong lore).
          _lorebookScanner.scanLatest();
        }

        // Decrement only entries that were active before the AI response.
        // This preserves full depth for lore discovered in the AI's own words.
        // Thin delegation (preAi set computed in god for snapshot; scanner owns decrement).
        _lorebookScanner.decrementLoreDepthForEntries(preAiTriggered);

        // Save session after AI message is complete
        await _saveChat();

        // ── Scene Guest (Lite NPC) parity guard ──────────────────────────
        // A guest turn must NOT touch the active character's Realism Engine,
        // Needs simulation, inter-character feelings, time, chips, or the
        // periodic (facts/evolution/summary/RAG) evaluators. The guest carries
        // no such state. Everything from here through the periodic evals is
        // gated so guest presence/turns leave the primary's state untouched.
        // (Lorebook scan + _saveChat above still ran for the guest.)
        if (guestSpeaker == null) {
          // Phase 2: Update hidden inter-character feelings for the speaker who
          // just responded, based on what was said in the recent exchange.
          // This makes the invisible tracking react to actual dialogue.
          if (_activeGroup != null &&
              !_observerMode &&
              finalResponse.isNotEmpty) {
            // Use the ACTUAL speaker of this turn, not a by-name lookup with a
            // first-member fallback — duplicate display names would otherwise
            // route this member's inter-character feelings to the wrong card.
            final speakerId = _getCharacterIdFromCard(speakingCharacter);
            if (speakerId.isNotEmpty) {
              _relationshipService
                  .updateInterCharacterFeelingsFromRecentExchange(speakerId);
              // (old checkpoint call removed in v30) // persist the hidden relationship changes
            }
          }

          // For group non-observer turns, temporarily re-impersonate the speaker of the *just generated*
          // response so the post-gen needs checks (now _runPostGenNeedsChecks thin to
          // _needsImpactEvaluator) use the correct _activeCharacter (for name, personality/stance
          // in the consolidated needs impact prompt). The pre-speaker-eval left the *scalars*
          // (incl. needs vector) loaded for this speaker but restored the _activeCharacter pointer
          // to the prior speaker; the thin delegate relies on the pointer for cbs. We restore the
          // pointer after the checks (scalars remain correct for the persist below).
          CharacterCard? prePostActiveChar;
          if (_activeGroup != null && !_observerMode) {
            prePostActiveChar = _activeCharacter;
            _activeCharacter = speakingCharacter;
            final sid = _getCharacterIdFromCard(speakingCharacter);
            if (sid.isNotEmpty) {
              _loadGroupRealismIntoScalars(sid);
            }
          }

          await _runPostGenNeedsChecks(finalResponse);

          // Re-stamp the needs vector inside THIS message's realism_state snapshot
          // with the now-final (post-impact) vector. The snapshot was captured
          // during the pre-generation realism eval — BEFORE _runPostGenNeedsChecks
          // applied this turn's needs impact (scene rewards like a bath's +Hygiene).
          // Every other field in it is already the final post-turn value; only the
          // needs vector was frozen pre-impact. Consumers that restore a message's
          // realism_state as a baseline — regenerating a LATER message, navigating
          // swipes, objective checks — would otherwise revert this turn's accepted
          // needs deltas (the reported "Hygiene snaps back after regenerating the
          // next message"). metadata and swipeMetadata[i] share one map instance, so
          // this in-place update sticks and persists. 1:1 and group alike: the
          // per-speaker vector is loaded above and is final here (before the group
          // persist below).
          if (_needsSimEnabled &&
              !streamTarget.isUser &&
              _needsSimulation.vector.isNotEmpty) {
            final rs = streamTarget.activeMetadata?['realism_state'];
            if (rs is Map && rs['needs'] is Map) {
              (rs['needs'] as Map)['vector'] = Map<String, int>.from(
                _needsSimulation.vector,
              );
            }
          }

          if (prePostActiveChar != null) {
            _activeCharacter = prePostActiveChar;
          }

          // For group non-observer, persist the post-scene + long-gen-decay needs changes (and any
          // other scalars mutated by the checks) back into _groupRealism for this speaker. This is
          // what makes sidebar member cards + getNeedsForGroupCharacter() + future loads see the
          // effects of the just-generated response. (Pre-eval saved the pre-turn state for bond/etc;
          // this captures the *response* effects on needs.)
          if (_activeGroup != null &&
              !_observerMode &&
              finalResponse.isNotEmpty &&
              _messages.isNotEmpty) {
            // The ACTUAL speaker of this turn — not a by-name lookup with a
            // first-member fallback (duplicate display names would persist the
            // critical scalar save to the wrong member's _groupRealism entry).
            final sid = _getCharacterIdFromCard(speakingCharacter);
            if (sid.isNotEmpty) {
              _saveScalarsIntoGroupRealism(sid);
            }
          }

          // Per-message needs chips for whoever just spoke. Lives here (not in
          // sendMessage) so EVERY speaker gets them — group auto-advance, /speak
          // and chime-ins reach _generateResponse but never sendMessage's old
          // chip block, which is why only the first responder showed chips.
          // Normal turns only; regen/continue manage their own chips.
          if (mode == GenerationMode.normal) {
            await _attachNeedsDeltaChipToLastMessage();
          }

          // Journal maintenance pass if due (fire-and-forget): memory cards +
          // recap in one call. Card ownership is derived from the window's
          // message characterIds (immune to the prePostActiveChar restore
          // dance above); only the recap voice is best-effort at trigger time
          // in group non-obs (same caveat the old summary had).
          _maybeRunJournalPass();

          // Growth pass if due (fire-and-forget): ring ops per owner —
          // members AND 1:1 scene guests who spoke in the window (guest
          // growth rides this shared pass; there is no per-guest trigger).
          // Cursor-based like the journal, so it is naturally regen-safe.
          _maybeRunGrowthPass();

          // Promise/debt ledger (Train B) — fire-and-forget on new turns only.
          // Keyword gate + open-list gate live inside the service so most
          // turns cost nothing. Regen/continue never invent commitments.
          if (mode == GenerationMode.normal) {
            _maybeRunPromiseDebtPass();
          }

          // Embed messages for RAG memory (fire-and-forget)
          _maybeEmbedMessages();

          // Periodic evaluations coordinator (Scene Guest cast detection).
          // NEW-TURN work — only on a normal generation, never on
          // regen/continue (which replay or extend an existing turn).
          if (mode == GenerationMode.normal) {
            _maybeRunPeriodicEvals();
          }
        } // end Scene Guest parity guard (guestSpeaker == null)

        // (Task completion check now runs pre-generation in sendMessage)

        // TTS auto-play: speak the new character message automatically
        if (_ttsService != null &&
            _storageService.ttsSettings.ttsEnabled &&
            _storageService.ttsSettings.ttsAutoPlay &&
            !streamTarget.isUser &&
            _messages.contains(streamTarget)) {
          final lastMsg = streamTarget;
          final msgId = 'msg_${_messages.indexOf(streamTarget)}';
          // Resolve per-character voice, falling back to global default
          String? voiceKey;
          if (_activeGroup != null) {
            final charMatch = _groupCharacters
                .where((c) => c.name == lastMsg.sender)
                .firstOrNull;
            voiceKey = charMatch?.ttsVoice;
          } else {
            voiceKey = _activeCharacter?.ttsVoice;
          }
          _ttsService!.speak(
            lastMsg.displayText,
            voiceKey: voiceKey,
            messageId: msgId,
          );
        }

        // Auto-play: if director mode is active, queue the next character
        if (_autoPlayActive && _observerMode && _activeGroup != null) {
          // If TTS is active, wait for it to finish before starting the delay
          if (_ttsService != null && _ttsService!.isSpeaking) {
            _waitForTtsThenContinue();
          } else {
            final delayMs = (directorDelaySec * 1000).round();
            Future.delayed(Duration(milliseconds: delayMs), () {
              if (_autoPlayActive && !_isGenerating) {
                _autoPlayNext();
              }
            });
          }
        }
      }

      // Restore original model if swapped for call mode
      if (_originalModelName != null && _llmProvider != null) {
        _llmProvider!.openRouterService.configure(
          modelName: _originalModelName,
        );
      }
    } catch (e) {
      final wasCancelled = _cancelRequested;
      _drainTimer?.cancel();
      _drainTimer = null;
      _tokenBuffer.clear();
      _isGenerating = false;
      _cancelRequested = false;
      _generationProgress = 0.0;
      _isBuffering = false;
      _generationPhase = GenerationPhase.idle;
      _prefillStartTime = null;
      _prefillPromptTokens = 0;
      _generationStartTime = null;

      // "Connection closed before full header was received" is thrown by the http package
      // when the HTTP client is closed mid-stream (either by abortGeneration() or a process
      // crash/restart). Treat it the same as a user cancel — keep the partial response.
      final treatAsCancel = wasCancelled || looksLikeBackendUnreachable(e);

      // User-initiated cancel (or forced client close) — keep the partial response, no error message
      if (treatAsCancel) {
        // Signal clean completion to SSE listeners
        _tokenBroadcast.add('__DONE__');
        if (_sentenceBuffer.trim().isNotEmpty) {
          _sentenceBroadcast.add(_sentenceBuffer.trim());
          _sentenceBuffer = '';
        }
        _sentenceBroadcast.add('__DONE__');

        // Restore original model if swapped for call mode
        if (_originalModelName != null && _llmProvider != null) {
          _llmProvider!.openRouterService.configure(
            modelName: _originalModelName,
          );
        }

        // Save the partial response so regen/continue work
        await _saveChat();
        notifyListeners();
        return;
      }

      // Build user-friendly error message
      String errorMsg = e.toString();
      // Strip Dart's "Exception: " prefix for cleaner display
      errorMsg = errorMsg.replaceFirst(RegExp(r'^Exception:\s*'), '');

      if (errorMsg.contains('STREAMING_NOT_SUPPORTED') ||
          errorMsg.contains('HTTP 405')) {
        errorMsg =
            'HTTP 405: The server does not support this request. '
            'If streaming is enabled, try disabling it in Settings > Generation Settings. '
            'Also verify your API URL is correct.';
      } else if (errorMsg.contains('Backend process crashed')) {
        errorMsg =
            'The backend crashed (likely out of VRAM). '
            'Try reducing GPU layers or context size in Settings.';
      } else if (errorMsg.contains('timed out') ||
          errorMsg.contains('TimeoutException')) {
        errorMsg =
            'Request timed out. The model may be too large or the server too slow.';
      } else if (errorMsg.contains('Connection closed before full header') ||
          (errorMsg.contains('ClientException') &&
              errorMsg.contains('closed'))) {
        errorMsg =
            'The connection to the backend was closed unexpectedly. '
            'The model may still be loading — wait for the green ready indicator and try again. '
            'If this persists, the backend may have run out of VRAM.';
      }

      _messages.add(
        ChatMessage(text: errorMsg, sender: "System", isUser: false),
      );

      // Signal error to SSE listeners
      _tokenBroadcast.add('__ERROR__');

      // Restore original model if swapped for call mode
      if (_originalModelName != null && _llmProvider != null) {
        _llmProvider!.openRouterService.configure(
          modelName: _originalModelName,
        );
      }

      notifyListeners();
    } finally {
      // The per-turn realism speaker pin lives only while we generate. Clear it
      // on every exit (normal completion, early return, or error) so the next
      // turn's pre-pick window (e.g. _applyMoodDecay) keeps its prior
      // nextCharacter-based behaviour instead of seeing a stale speaker.
      _turnSpeakerIdForRealism = null;
    }
  }
}
