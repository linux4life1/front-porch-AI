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

      // Living Worlds — setting prose from Primary ONLY (budget-capped).
      // Lore attachments contribute lorebook entries, not room description.
      final primaryId = _chatPlaceSlots.primaryId;
      final primaryWorld = primaryId == null
          ? null
          : _worldRepository.resolveWorld(primaryId);
      final rawWorld = buildWorldInjection(
        primaryWorld == null ? const <World>[] : [primaryWorld],
      );
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

      _registerGenerationPlanSections(
        t,
        loreDepthJoined: loreDepthJoined,
        objectiveBlock: objectiveBlock,
        worldBlock: worldBlock,
        realismBlock: realismBlock,
        needsCatastropheBlock: needsCatastropheBlock,
        chanceTimeBlock: chanceTimeBlock,
        porchNightBlock: porchNightBlock,
        itemIntroBlock: itemIntroBlock,
      );

      final plan = t.plan;
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

    _stripContinuePlanSections(t);
  }
}
