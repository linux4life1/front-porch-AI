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

/// Phase 1 of `_generateResponse` (see chat_service_generation.dart): the
/// system prompt + lorebook + persona + scenario + examples + Scene-Guest +
/// summary + Journal prompt-section assembly. Extracted verbatim (mechanical
/// `x` → `t.x` carrier rename only — see `_GenTurn`) from the single
/// ~1.9k-line `_generateResponse` method during the god-file split
/// (docs/design/god-file-elimination.md). Zero behaviour change.
extension ChatServiceGenerationBlocks on ChatService {
  Future<void> _assembleGenerationBlocks(_GenTurn t) async {
    // ── System prompt selection (Path B clean hierarchy) ──
    // 1. Group-level system prompt (if set) — base for the whole group.
    // 2. Per-character group override (if set for the speaker in this group) — appended.
    // 3. Character's normal card system prompt (fallback if no group override for them).
    // 4. (Later) Per-character Author's Note is injected separately with its own strength.
    if (_activeGroup != null && _activeGroup!.systemPrompt.isNotEmpty) {
      t.systemPrompt = _activeGroup!.systemPrompt;
    } else if (_activeGroup != null) {
      t.systemPrompt = _observerMode
          ? observerModeSystemPrompt
          : defaultGroupSystemPrompt;
    } else if (t.speakingCharacter.systemPrompt.isNotEmpty) {
      t.systemPrompt = t.speakingCharacter.systemPrompt;
    } else if (_storageService.generationSettings.systemPrompt.isNotEmpty) {
      t.systemPrompt = _storageService.generationSettings.systemPrompt;
    } else {
      // Every backend now speaks the OpenAI chat protocol (local KoboldCpp
      // via its /v1/chat/completions door), so the server applies the model's
      // instruct template — use the chat-style default system prompt.
      t.systemPrompt = defaultApiSystemPrompt;
    }

    // Path B: When in a group, always attempt to layer the per-character group override
    // (and card fallback) on top. A group prompt no longer completely hides per-char instructions.
    if (_activeGroup != null) {
      final groupCharPrompt = getSystemPromptForGroupCharacter(
        t.speakingCharacter,
      ).trim();
      if (groupCharPrompt.isNotEmpty) {
        t.systemPrompt +=
            '\n\n[Group-specific instructions for ${t.speakingCharacter.name}]\n$groupCharPrompt';
      } else if (t.speakingCharacter.systemPrompt.isNotEmpty) {
        // Fallback to the character's own card prompt only if no group-specific override
        t.systemPrompt +=
            '\n\n[Specific instructions for ${t.speakingCharacter.name}]\n${t.speakingCharacter.systemPrompt.trim()}';
      }
    }

    // In call mode, inject voice-specific instructions for natural conversation
    if (_callMode && _storageService.sttSettings.callSystemPrompt.isNotEmpty) {
      t.systemPrompt +=
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
    t.loreBefore = loreInjection.beforeChar;
    t.loreAfter = loreInjection.afterChar;
    t.loreAnTop = loreInjection.authorNoteTop;
    t.loreAnBottom = loreInjection.authorNoteBottom;
    t.loreExTop = loreInjection.examplesTop;
    t.loreExBottom = loreInjection.examplesBottom;
    t.loreDepth = loreInjection.depthEntries;

    // Build persona block(s)
    if (_activeGroup != null) {
      t.personaBlock = _groupCharacters
          .map((ch) {
            final persona = _macroResolver.resolve(
              _getEffectivePersonality(ch),
              MacroContext(userName: t.userName, characterName: ch.name),
              section: 'persona',
            );
            return "${ch.name}'s Persona: $persona";
          })
          .join('\n');
    } else {
      t.personaBlock =
          "${t.speakingCharacter.name}'s Persona: ${_macroResolver.resolve(
            _getEffectivePersonality(t.speakingCharacter),
            MacroContext(userName: t.userName, characterName: t.speakingCharacter.name),
            section: 'persona',
          )}";
    }

    // User persona — inject user's self-description + learned facts
    t.userPersonaBlock = await _buildUserPersonaBlock(t.userName);

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
      rawScenario = _getEffectiveScenario(t.speakingCharacter);
    }
    t.scenario = rawScenario;
    // A Scene Guest drops into the HOST's ongoing scene — it has no scenario
    // of its own. Blank it here (prompt-only; the shared library card is never
    // mutated, so a /join'd full character keeps its real scenario for when it
    // is the host). This also self-heals legacy guests minted with the host's
    // scenario baked in (the "model thinks the guest IS the host" bug).
    if (t.guestSpeaker != null) t.scenario = '';

    t.suffix = "";

    if (t.mode == GenerationMode.normal) {
      t.suffix = "\n${t.speakingCharacter.name}:";
    } else if (t.mode == GenerationMode.impersonate) {
      t.suffix = "\n${t.userName}:";
    } else if (t.mode == GenerationMode.continue_) {
      // Suffix will be set after history is built — see below
      t.suffix = "";
    }

    // Build example dialogues block
    if (_activeGroup != null) {
      final examples = _groupCharacters
          .where((ch) => ch.mesExample.isNotEmpty)
          .map(
            (ch) => _macroResolver.resolve(
              ch.mesExample,
              MacroContext(userName: t.userName, characterName: ch.name),
              section: 'mesExample',
            ),
          )
          .toList();
      if (examples.isNotEmpty) {
        t.mesExampleBlock = '${examples.join('\n')}\n';
      }
    } else if (t.speakingCharacter.mesExample.isNotEmpty) {
      t.mesExampleBlock = '${t.speakingCharacter.mesExample}\n';
    }

    // Build post-history instructions block
    if (_activeGroup == null &&
        t.speakingCharacter.postHistoryInstructions.isNotEmpty) {
      t.postHistoryBlock = '${t.speakingCharacter.postHistoryInstructions}\n';
    }

    // Author's note — placed right before the character speaks for maximum influence
    if (_authorNote.isNotEmpty) {
      t.authorNoteBlock = _buildAuthorNoteBlock();
    }

    // Per-character Author's Note (group mode only): if the current speaker has
    // a personal note, inject it using the same strength-modulated style.
    // Falls back gracefully (no-op) if absent. Appended after any group-level note.
    if (_activeGroup != null) {
      final charNote = getAuthorNoteForGroupCharacter(t.speakingCharacter);
      if (charNote.isNotEmpty) {
        // Use per-character strength if set, otherwise fall back to group default
        final s = getAuthorNoteStrengthForGroupCharacter(t.speakingCharacter);
        final name = t.speakingCharacter.name;
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
        t.authorNoteBlock += perCharBlock;
      }
    }

    // One-shot entrance directive (forked-in character) — hidden, consumed
    // here so it influences only this generation and never persists.
    if (_entranceDirective != null) {
      t.authorNoteBlock += '[${_entranceDirective!}]\n';
      _entranceDirective = null;
    }

    // ── Scene Guests (Lite NPCs) prompt injection (1:1 only) ───────────
    // Guests speak for themselves in their own bubbles, so the primary must
    // not fully voice/narrate them. A guest turn instead gets a short line
    // grounding it as a visitor in the host's scene.
    if (_activeGroup == null) {
      final hostName = _activeCharacter?.name ?? 'the main character';
      if (t.guestSpeaker != null) {
        // A guest turn reuses the host's full transcript, so the identity
        // switch must be unmistakable or the model conflates the guest with
        // the host (confirmed even on strong API models). Also pin the
        // latest user line: long adventures + guest RAG/recap made DeepSeek
        // answer an older "Magus, tell me about the spell" instead of the
        // line just sent (Discord 2026-08-15).
        var latestUser = '';
        var latestHost = '';
        for (final m in _messages.reversed) {
          if (m.sender == 'System') continue;
          if (m.isUser) {
            latestUser = m.promptText.trim();
            break;
          }
          if (latestHost.isEmpty && !_isGuestAuthoredMessage(m)) {
            latestHost = m.displayText.trim();
          }
        }
        t.authorNoteBlock += buildGuestTurnNote(
          guestName: t.guestSpeaker!.name,
          hostName: hostName,
          userName: t.userName,
          latestUserText: latestUser,
          latestHostText: latestHost,
        );
      } else if (_sceneGuest.cards.isNotEmpty) {
        // Host turn with guests present: hard ban on ventriloquising them, or
        // the host writes the guests' lines too (the "generated both at once"
        // bug). Acknowledging/reacting is allowed; speaking for them is not.
        // The handoff sentence targets the cast-detection case: a promoted
        // guest was detected FROM the host's own narration, so the transcript
        // above is full of the host voicing them — without an explicit "that
        // has ended" the many-shot momentum beats the ban (Discord
        // double-response report, 2026-07-28). The defer clause covers an
        // addressed guest the sendMessage vocative router didn't catch.
        final names = _sceneGuest.cards.map((g) => g.name).join(', ');
        t.authorNoteBlock +=
            '[Also present in the scene: $names — each is a separate '
            'character played by another actor, replying in their own '
            'separate messages. Do NOT write any dialogue, actions, or inner '
            'thoughts for them — not a single line. If earlier messages '
            'above included lines spoken by these characters, that has '
            'ended: from now on they speak only for themselves. Stay '
            'entirely as $hostName; you may have $hostName notice or react '
            'to them, but never put words or actions on them. If ${t.userName} '
            'just addressed one of them, reply only with $hostName\'s own '
            'brief reaction and leave the answer to that character.]\n';
      }
      // One-shot guest departure (armed by /exit) — narrated by the primary
      // on this turn only, then cleared so it never persists.
      if (t.guestSpeaker == null && _sceneGuest.pendingDeparture != null) {
        t.authorNoteBlock +=
            '[${_sceneGuest.pendingDeparture!} leaves the scene; '
            'write them exiting naturally.]\n';
        _sceneGuest.pendingDeparture = null;
      }
    }

    // Build summary block if available. Role frame (spec §6): the recap is
    // the plot spine; the journal carries feelings; RAG carries exact lines.
    // The text lives in buildRecapBlock (prompt_injection/recap_injection.dart)
    // — read its doc before changing the wording; the head is what scopes the
    // recap to the past, and it is the only thing keeping this block from
    // reading as a competing claim about NOW.
    //
    // It takes the recap and nothing else. It used to also take the lag in
    // messages behind the Journal pass cursor (_summaryLastIndex vs
    // _messages.length) to decide whether to stamp the block "the conversation
    // has moved on since it was written" — that stamp measured as a NET
    // NEGATIVE (models quoted it back as the contradiction) and was deleted,
    // taking the derivation with it.
    // Guests never journal; a stale host recap is a competing claim about
    // NOW. Reasoning + RAG already pull them onto old beats (Discord
    // 2026-08-15); do not also hand them "Where we are".
    t.summaryBlock = t.guestSpeaker != null
        ? ''
        : buildRecapBlock(recap: _summary);

    // Cued query for journal cold-resurface AND RAG (not last-3 live lines
    // alone). Guests skip both. Compose even when the Journal toggle is off
    // so RAG still searches by feeling / fixation / last words.
    if (t.guestSpeaker == null && _currentSessionId != null) {
      final speakerId = _getCharacterIdFromCard(t.speakingCharacter);
      final cards = speakerId.isEmpty
          ? const <JournalMemoryData>[]
          : await _journalStore.cardsFor(_currentSessionId!, speakerId);
      // Cover-drop uses THIS-BEAT injected gist only (set after the
      // journal block builds). The whole cabinet here would eat a
      // fallen-off fact that shares filler with a cold card.
      t.journalCoverLines = const [];
      t.ragHotJournalLine =
          JournalPhysics.topHotJournalLine(cards, _characterEmotion) ?? '';
      t.ragQuery = composeRagQuery(
        emotion: _characterEmotion,
        fixation: _relationshipService.activeFixation,
        hotJournalLine: t.ragHotJournalLine,
        lastWords: lastWordsFromMessages(_messages),
      );
    }

    // The Journal — the upcoming speaker's pinned + hot memory cards, with
    // their felt emotions (strictly this chat's cards; guests never
    // journal). Built HERE, before the fixed-content token count below, so
    // history budgeting accounts for it (async, unlike the sync builders).
    // Two-tier memory (living-time-features.md §8): positions the journal
    // expanded verbatim this turn — RAG retrieval below excludes them so
    // the exact lines never ride the prompt twice.
    if (_storageService.memorySettings.journalEnabled &&
        t.guestSpeaker == null &&
        _currentSessionId != null) {
      await _ensureBirthdayState();
      final journal = await _journalInjection.buildJournalBlock(
        characterId: _getCharacterIdFromCard(t.speakingCharacter),
        characterName: t.speakingCharacter.name,
        userName: t.userName,
        // Cued query (emotion + fixation + top hot card + last words),
        // not the last-3 live lines. promptText still rides lastWords so
        // photo captions reach cold-resurface the way they reach RAG.
        queryText: t.ragQuery,
        lastWords: lastSpokenLineFromMessages(_messages),
        messageCount: _messages.length,
      );
      t.journalBlock = journal.text;
      t.expandedJournalPositions = journal.expandedPositions;
      if (journal.text.isNotEmpty) {
        t.journalCoverLines = journal.injectedContents;
      }
    }
  }
}
