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

extension ChatServiceGenerationPlanRegister on ChatService {
  /// Register every section with the plan, in render order. This ONE
  /// list is what the system message, user message, fixed-token count,
  /// and Context Viewer budget map are all rendered from — every lore
  /// bucket is counted (including @depth entries, which are spliced
  /// into history later WITHOUT re-counting, via rendered:false), and
  /// history/memories are budget-fitted afterwards (counted:false).
  void _registerGenerationPlanSections(
    _GenTurn t, {
    required String loreDepthJoined,
    required String objectiveBlock,
    required String worldBlock,
    required String realismBlock,
    required String needsCatastropheBlock,
    required String chanceTimeBlock,
    required String porchNightBlock,
    required String itemIntroBlock,
  }) {
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
    // Untrusted search/MCP dump MUST sit before the speaker prefix
    // (`Name:`). Insertion order is render order; after inject the
    // completion point has to stay the suffix, not wiki junk.
    // Chance Time / porch_night / item_intro stay AFTER suffix.
    plan.add(id: 'web_search', text: '');
    plan.add(
      id: 'regen_critique',
      label: 'Regen Critique',
      text: t.regenCritique,
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
  }

  void _stripContinuePlanSections(_GenTurn t) {
    if (t.mode != GenerationMode.continue_) return;
    final plan = t.plan;
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
    plan.section('web_search').text = '';
    plan.section('regen_critique').text = '';
    // RAG skip is the Continue branch in _retrieveGenerationMemories
    // (zeroing droppedMessages is not enough once tail-open ORs
    // basePosition). Keep this 0 so later budget math does not treat
    // Continue as a drop.
    t.droppedMessages = 0;
  }
}
