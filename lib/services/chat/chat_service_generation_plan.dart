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

/// The STATE ZONE (docs/design/prompt-state-injection.md §6.1) — the blocks
/// that describe the world and the character rather than the conversation:
/// the recap, the Journal, the objective, the world, the character-state
/// block and the needs catastrophe.
///
/// ALL SIX RIDE THE USER TURN, AFTER THE TRANSCRIPT. That seat is measured,
/// not chosen. Everything registered ahead of the transcript has to be
/// byte-identical from turn to turn or the local prefix cache breaks at the
/// first differing byte and re-processes everything after it — which is the
/// whole transcript. Measured on the maintainer's gemma-4-31B (Q8, M5 Max) on
/// a 5.4k-token prompt, five consecutive turns, each arm given a unique
/// session nonce so none of them could inherit a warm cache slot from another
/// (§8d):
///
///   zone here, after the transcript   508 of 5.5k tokens re-prefilled/turn
///   zone in the leading system msg   5020 of 5.5k tokens re-prefilled/turn
///
/// i.e. 9.3x the wall clock per reply, every reply, for as long as the chat
/// lives. Only the state zone itself is ever re-read from this seat; from the
/// other one the whole conversation is.
///
/// The system-message placement was tried on 2026-08-08 (to stop models
/// reading the app's bookkeeping as something the human typed) and REVERTED
/// the same day, because no amount of de-churning can buy the prefix back: the
/// Journal's mood-congruent ordering re-sorts the hot set whenever the
/// speaker's emotion FAMILY changes, and the 600-token budget then renders a
/// different card set. Replayed over the maintainer's own 200-card diary
/// against one real chat's 42 recorded emotion values, the journal block held
/// its bytes on 24 of 41 turn transitions and changed them on 17 — 41% of
/// replies; across every real chat in that library, 543 of 873 transitions.
/// The ordering is a deliberate feature and stays, so the zone stays here and
/// pays for attribution in WORDS instead — see [buildStateZoneFrame]. That
/// frame is not free either, but it is ~121 tokens added to a zone that is
/// re-read anyway (508 → 629 tokens/turn), against ~4,500.
///
/// Membership is declared once, here, and read by the frame's salience gate
/// and by the continue-mode strip — a new state block joins the contract by
/// being added to this list, not by being remembered in three places.
const List<String> kStateZoneSectionIds = [
  'summary',
  'journal',
  'objectives',
  'world',
  'realism',
  'catastrophe',
];

/// Phase 2 of `_generateResponse` (see chat_service_generation.dart):
/// Continue-mode message pop, the macro resolution pass, the realism/world/
/// Chance Time/porch-night/objective/catastrophe state blocks, PromptPlan
/// registration (the "wheel hub" every section renders from), and the
/// fixed-token/history-budget walk. Extracted verbatim (mechanical `x` →
/// `t.x` carrier rename only — see `_GenTurn`) from the single ~1.9k-line
/// `_generateResponse` method during the god-file split
/// (docs/design/god-file-elimination.md). Zero behaviour change.
extension ChatServiceGenerationPlan on ChatService {
  Future<void> _buildGenerationPlan(_GenTurn t) async {
    // ── Continue mode: remove the last message from history ──
    // For continue mode, we exclude the last message from the chat history
    // and place it as the prompt suffix so the LLM continues from it naturally.
    // Wrapped in try-finally to guarantee restoration even on exception.
    ChatMessage? _continuePoppedMessage;
    if (t.mode == GenerationMode.continue_ && _messages.isNotEmpty) {
      _continuePoppedMessage = _messages.removeLast();
      // Think-stripped / photo-aware (promptText), same contract as history
      // lines — raw .text re-injects closed <think> plans into the Continue
      // suffix (Nina-class hole on the Continue path only; audit P0.2).
      final partial = _continuePoppedMessage.promptText;
      // For Continue: feed straight existing messages as the prompt (per user request).
      // The suffix is the text being continued (no re-added "Sender: " label).
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
      final safeUser = t.userName.replaceAll(RegExp(r'[\n\r\[\]]'), ' ').trim();
      final ruleUser = safeUser.isEmpty ? 'the user' : safeUser;
      t.suffix =
          "\n[CRITICAL RULE: The text below is an incomplete response from the *current speaker only*. You MUST ONLY generate more text that continues *this exact response* in the speaker's voice, style, and perspective. NEVER write any dialogue, actions, thoughts, narration, or descriptions for $ruleUser or from $ruleUser's point of view. NEVER add new speaker labels or switch characters. Only append to the text below. Stop if it would require $ruleUser content.]\n" +
          padContinuePartial(partial);
    }

    // ── Macro resolution pass ──
    // Full chat context: card fields, group roster, last messages, idle
    // clock, and the {{setvar}}/{{getvar}} stores.
    final macroCtx = _buildChatMacroContext(
      t.speakingCharacter,
      scenario: t.scenario,
    );
    t.systemPrompt = _macroResolver.resolve(
      t.systemPrompt,
      macroCtx,
      section: 'systemPrompt',
    );
    // Lore buckets are macro-resolved individually (same 'lore' section
    // seeding the old single block used).
    String loreMacro(String s) =>
        s.isEmpty ? s : _macroResolver.resolve(s, macroCtx, section: 'lore');
    t.loreBefore = loreMacro(t.loreBefore);
    t.loreAfter = loreMacro(t.loreAfter);
    t.loreAnTop = loreMacro(t.loreAnTop);
    t.loreAnBottom = loreMacro(t.loreAnBottom);
    t.loreExTop = loreMacro(t.loreExTop);
    t.loreExBottom = loreMacro(t.loreExBottom);
    t.loreDepth = [
      for (final d in t.loreDepth)
        LoreDepthEntry(
          depth: d.depth,
          role: d.role,
          content: loreMacro(d.content),
        ),
    ];
    final loreDepthJoined = t.loreDepth.map((d) => d.content).join('\n');
    // personaBlock and group-mode examples are resolved per-character above
    t.scenario = _macroResolver.resolve(
      t.scenario,
      macroCtx,
      section: 'scenario',
    );
    if (_activeGroup == null && t.mesExampleBlock.isNotEmpty) {
      t.mesExampleBlock = _macroResolver.resolve(
        t.mesExampleBlock,
        macroCtx,
        section: 'mesExample',
      );
    }
    if (t.postHistoryBlock.isNotEmpty) {
      t.postHistoryBlock = _macroResolver.resolve(
        t.postHistoryBlock,
        macroCtx,
        section: 'postHistory',
      );
    }

    // Ensure the popped message is always restored, even if prompt assembly throws
    try {
      t.history = _buildChatHistory(depthLore: t.loreDepth);

      // ── Context Shift: budget-aware history trimming ──

      // Realism / internal state block — the words-only composer
      // (lib/services/chat/prompt_injection/realism_state_injection.dart):
      // salience-gated natural language only, no simulation scalars. Macro-
      // resolved HERE (spec §5a) — the fragments carry {{user}}, and this
      // block previously reached the model with the braces literal.
      // BUILT UNCONDITIONALLY since 2026-08-08, and that is the fix for a
      // whole class of "the switch is on and nothing happens".
      //
      // This used to be wrapped in `if (_realismActiveThisMode)`. The composer
      // had already been taught to gate each of its eleven fragments
      // individually — its own comment says a blanket early return "silently
      // deleted all eleven fragments, including the four that are not realism
      // features" — but that blanket gate had simply MOVED here, to the caller,
      // where the composer's careful per-fragment gating never got to run.
      //
      // So with the Realism Engine off, every one of these was built and thrown
      // away: Pockets & Wardrobe (Porch Life: "works alone"), Likes & Dislikes
      // (whose fragment is commented "DELIBERATELY NOT REALISM-GATED"),
      // Ambitions ("needs Objectives"), Promises ("needs the Journal"), the
      // real-absence note that was lifted out of TimeInjection to escape
      // exactly this kind of gate, and the story clock's own time and weather
      // lines — which meant the standalone clock spent an LLM call every turn
      // to advance a clock whose reading could never reach the model.
      //
      // The engine's OWN fragments are unaffected: they answer to
      // `_characterStateEnabled` inside the composer, wired to
      // `_realismActiveThisMode`, so Director mode and AFK auto-response stay
      // exactly as silent as they were.
      final rawRealism = _getRealismStateInjection();
      final realismBlock = rawRealism.isEmpty
          ? ''
          : _macroResolver.resolve(rawRealism, macroCtx, section: 'realism');

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

      // Continue must not consume one-shots: it strips them from the wire
      // after this block, so taking them here burned Chance Time / item
      // intro / porch-night / catastrophe forever. Leave them armed for
      // the next real Send.
      final skipOneShots = t.mode == GenerationMode.continue_;

      // Chance Time injection — independent of realism mode
      final chanceTimeBlock = skipOneShots ? '' : _getChanceTimeInjection();

      // Hand-added item one-shots (gift / the surprise Easter egg) — same
      // register as Chance Time: a bracketed directive at maximum recency.
      // Inside the realism-state block it was read as background and ignored
      // (maintainer report, 2026-08-13).
      final itemIntroBlock = skipOneShots
          ? ''
          : _inventoryInjection.buildItemIntroInjection();

      // LLMerta Mafia-night force-ack (Chance Time register). Re-arms from
      // diary if needed; stays armed through regen of this AI message until
      // the *next* user send clears it.
      final porchDiaryId = _getCharacterIdFromCard(t.speakingCharacter);
      final porchSessionId = _currentSessionId;
      if (porchSessionId != null) {
        await _porchMemoryImport.ensureArmedForDiary(
          sessionId: porchSessionId,
          diaryCharacterId: porchDiaryId,
        );
      }
      final porchNightRaw = skipOneShots
          ? ''
          : _porchMemoryImport.takeInjectionForDiary(porchDiaryId);
      final porchNightBlock = porchNightRaw.isEmpty
          ? ''
          : _macroResolver.resolve(porchNightRaw, macroCtx, section: 'realism');

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
      if (!skipOneShots && _needsSimulation.pendingCatastrophe != null) {
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
      final plan = t.plan = PromptPlan();
      // ── system message ──
      plan.add(
        id: 'system',
        label: 'System Prompt',
        inSystem: true,
        text: '${t.systemPrompt}\n',
      );
      plan.add(
        id: 'lore.before',
        label: 'Lorebook',
        inSystem: true,
        text: t.loreBefore,
      );
      plan.add(
        id: 'persona',
        label: 'Persona',
        inSystem: true,
        text: '${t.personaBlock}\n',
      );
      plan.add(
        id: 'lore.after',
        label: 'Lorebook',
        inSystem: true,
        text: t.loreAfter,
      );
      plan.add(id: 'user_persona', inSystem: true, text: t.userPersonaBlock);
      plan.add(
        id: 'scenario',
        label: 'Scenario',
        inSystem: true,
        text: ScenarioFade.wrapForChat(t.scenario, _messages),
      );
      plan.add(
        id: 'lore.ex_top',
        label: 'Lorebook',
        inSystem: true,
        text: t.loreExTop,
      );
      plan.add(
        id: 'examples',
        label: 'Examples',
        inSystem: true,
        text: t.mesExampleBlock,
      );
      plan.add(
        id: 'lore.ex_bottom',
        label: 'Lorebook',
        inSystem: true,
        text: t.loreExBottom,
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
      // ── the state zone opens here (kStateZoneSectionIds, top of file) ──
      // The recap and the Journal sit after the transcript (audit finding
      // #4's remainder, same mechanism as memories above): the journal block
      // re-sorts with the speaker's mood and re-warms cold cards EVERY turn,
      // and the recap rewrites every journal pass — as pre-history sections
      // they rewrote the prompt's head, forcing a full re-prefill of the
      // whole transcript on every local backend (KoboldCpp, oMLX, LM Studio;
      // prefix caches need byte-identical heads). Post-history, mood
      // re-ordering is cache-free. Render order memories → recap → journal
      // puts the feelings channel closest to the generation point, matching
      // its "truer guide" role frame. Their fixed-count slot is unchanged
      // (history/memories are excluded from fixedCountText); the only
      // fixed-count delta is each block's separator newline (≤1 token), so
      // history budgeting is intact.
      //
      // Re-measured 2026-08-08 when this seat was briefly given up for the
      // leading system message and taken straight back: 508 vs 5,020 tokens
      // re-prefilled per warm turn on gemma-4-31B (9.3x the wall clock per
      // reply), and de-churning cannot recover it because the journal's own
      // mood ordering moves the bytes on 41% of real turns. The attribution
      // that move was chasing is bought in words by the state_frame section
      // below. Full numbers: the kStateZoneSectionIds doc and §6.1/§8d of
      // docs/design/prompt-state-injection.md.
      plan.add(id: 'state_frame', label: 'State Frame', text: '');
      plan.add(id: 'summary', label: 'Summary', text: t.summaryBlock);
      plan.add(id: 'journal', label: 'Journal', text: t.journalBlock);
      plan.add(
        id: 'post_history',
        label: 'Post-History',
        text: t.postHistoryBlock,
      );
      plan.add(id: 'lore.an_top', label: 'Lorebook', text: t.loreAnTop);
      plan.add(
        id: 'author_note',
        label: 'Author\'s Note',
        text: t.authorNoteBlock,
      );
      plan.add(id: 'lore.an_bottom', label: 'Lorebook', text: t.loreAnBottom);
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
      plan.add(id: 'suffix', text: t.suffix);
      plan.add(id: 'chance_time', text: chanceTimeBlock);
      // High-recency with Chance Time so the first post-import reply
      // cannot bury the Mafia night (docs/design/llmerta-porch-memories.md §7b).
      plan.add(id: 'porch_night', text: porchNightBlock);
      // Hand-added item one-shots ride the same tail (see the fetch above).
      plan.add(id: 'item_intro', text: itemIntroBlock);

      // The zone is introduced only when it actually has something in it
      // (salience gating — a quiet turn stays quiet, and a frame introducing
      // nothing is pure noise). Run after every section is registered, and
      // BEFORE fixedCountText is counted, so the frame is paid for in the
      // history budget.
      if (kStateZoneSectionIds.any((id) => plan.section(id).text.isNotEmpty)) {
        plan.section('state_frame').text = buildStateZoneFrame(
          userName: t.userName,
          characterName: t.speakingCharacter.name,
        );
      }

      final fixedTokens = await _countTokens(plan.fixedCountText);
      final contextBudget = _sessionGenSettings.resolveContextSize(
        _storageService,
      );
      final generationReserve =
          _sessionGenSettings.resolveMaxLength(_storageService) +
          50; // +50 safety margin
      t.historyBudget = contextBudget - fixedTokens - generationReserve;

      if (t.historyBudget > 0) {
        final result = await _buildChatHistoryWithBudget(
          t.historyBudget,
          depthLore: t.loreDepth,
        );
        t.history = result.history;
        t.droppedMessages = result.droppedCount;

        // ── THE RECAP ONLY EARNS ITS PLACE WHEN IT COVERS WHAT THE
        //    TRANSCRIPT NO LONGER SHOWS ────────────────────────────────────
        //
        // `droppedCount == 0 && basePosition == 0` means every message in
        // this chat is in the prompt below. A tail-open can fit its 24-row
        // window with droppedCount 0 while hundreds of earlier lines sit
        // behind basePosition — those still need the recap. The recap
        // otherwise describes nothing the model cannot read directly: a
        // second, COMPRESSED, and (because it only rewrites on a Journal
        // pass) OLDER account of the very same events.
        // That is not memory, it is a contradiction generator: measured on
        // the maintainer's real chats, "recap" was named in 19 of the 461
        // conflict sentences a reasoning model produced, and the modal
        // complaint was the recap disagreeing with the scene.
        //
        // Rewording it did not help — an A/B on Kimi 2.6 over 32 historical
        // turns moved the recap-conflict rate 33% -> 33% (p=1.00), because
        // the contradiction is REAL and no phrasing removes a true one. So
        // the block is dropped instead, on exactly the turns where it can
        // only do harm. Where it does carry unseen history it is untouched.
        //
        // Deliberately keyed on the fitted result rather than the Journal
        // cursor: the cursor says how much has been READ, this says how much
        // is VISIBLE, and visibility is the thing that makes the recap
        // redundant. It also degrades correctly on a huge context (nothing
        // dropped -> no recap needed) and on a tiny one (lots dropped ->
        // recap matters most).
        if (recapIsRedundant(
          dropped: t.droppedMessages,
          basePosition: _history.basePosition,
        )) {
          plan.section('summary').text = '';
          // The frame was decided ABOVE, while the recap still had text, so
          // re-run its salience gate here or a turn whose only state was the
          // recap ships a sentence introducing an empty zone.
          if (kStateZoneSectionIds.every(
            (id) => plan.section(id).text.isEmpty,
          )) {
            plan.section('state_frame').text = '';
          }
        }
      }
      // Zero/negative budget: last user line + everything after it (think-
      // stripped). Raw lastMsg.text re-injects <think> (audit 2026-08-11).
      if (t.historyBudget <= 0 && _messages.isNotEmpty) {
        final overflow = _overflowContinuityHistory();
        t.history = overflow.history;
        t.droppedMessages = overflow.droppedCount;
      }
    } finally {
      // ── Restore the popped continue message back into the list ──
      if (_continuePoppedMessage != null) {
        _messages.add(_continuePoppedMessage);
      }
    }

    final plan = t.plan;
    if (t.mode == GenerationMode.continue_) {
      // Continue is plain transcript + the partial being extended — no
      // state-zone blocks. The old strip only cleared realism/chance/
      // objectives/catastrophe and left summary/journal/world (and often
      // the frame) fighting the partial (release audit 2026-08-11). Clear
      // every kStateZoneSectionIds member + chance_time by membership.
      for (final id in kStateZoneSectionIds) {
        plan.section(id).text = '';
      }
      plan.section('chance_time').text = '';
      plan.section('state_frame').text = '';
      // Porch Night is registered outside kStateZoneSectionIds (force-ack
      // table-talk, not a permanent state fragment). Leaving it armed made
      // Continue inject "HARD REQUIRED OPENING / first 2–4 sentences" into
      // a pure append (full-codebase audit 2026-08-11 P0.3).
      plan.section('porch_night').text = '';
      // Item one-shots are the same class: a Continue extends the reply that
      // already reacted — re-injecting would have them notice the same thing
      // twice in one message.
      plan.section('item_intro').text = '';
      // RAG skip is the Continue branch in _retrieveGenerationMemories
      // (zeroing droppedMessages is not enough once tail-open ORs
      // basePosition). Keep this 0 so later budget math does not treat
      // Continue as a drop.
      t.droppedMessages = 0;
    }
  }
}
