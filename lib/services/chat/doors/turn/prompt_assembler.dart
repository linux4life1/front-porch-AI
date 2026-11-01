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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';

import 'call_model_swap.dart';
import 'context_budget.dart';
import 'gen_turn.dart';
import 'history_window.dart';
import 'plan_register.dart';
import 'prompt_blocks.dart';
import 'prompt_deps.dart';
import 'prompt_source.dart';
import 'rag_sources.dart';
import 'turn_blocks.dart';
import 'turn_plan.dart';
import 'turn_rag.dart';
import 'turn_request.dart';
import 'turn_token_alts.dart';

export 'call_model_swap.dart';
export 'context_budget.dart';
export 'gen_turn.dart';
export 'history_window.dart';
export 'plan_register.dart';
export 'prompt_blocks.dart';
export 'prompt_deps.dart';
export 'prompt_source.dart';
export 'rag_sources.dart';
export 'turn_blocks.dart';
export 'turn_plan.dart';
export 'turn_rag.dart';
export 'turn_request.dart';
export 'turn_token_alts.dart';

/// Builds a reply's prompt and request from the open chat: the blocks
/// ([TurnBlocks]), the macro pass, the state zone and the plan
/// ([TurnPlan], [PlanRegister]), the history window with its chunked
/// eviction anchor ([PromptHistory]), RAG retrieval and its receipt
/// ([TurnRag], [RagSources]), and the request with the tool doorbell and
/// the forced lookup ([TurnRequest]). The four phases run in that fixed
/// order on one [GenTurn]; the turn engine streams what [dispatch] starts.
///
/// It also owns what the other prompt paths share with the reply: the
/// prompt source ([PromptSource]), the prompt blocks and the chat's macro
/// context ([PromptBlocks], read by impersonate and the lore key pass), the
/// Context Viewer budget ([ContextBudget]), the voice call's model swap
/// ([CallModelSwap]) and the turn side of token alternatives
/// ([TurnTokenAlts]).
///
/// Not a notifier: the budget refresh, the Author's Note and the prompt
/// picker call the service's own notify ([PromptDeps.notify]), as the parts
/// it replaces did.
class PromptAssembler {
  PromptAssembler(this._d);

  final PromptDeps _d;

  /// Central macro resolver for prompt template expansion.
  final MacroResolver macros = MacroResolver();

  /// In-memory clock for {{idle_duration}} — set on each user send; null
  /// after a restart (the macro passes through untouched then).
  DateTime? lastUserMessageAt;

  /// Names of lore entries dropped by the token budget on the last
  /// generation, plus the meter numbers the sidebar shows.
  List<String> lastLoreOverflow = const [];
  int lastLoreTokens = 0;
  int lastLoreBudget = 0;

  late final PromptSource source = PromptSource(_d);
  late final PromptBlocks blocks = PromptBlocks(this, _d);
  late final PromptHistory history = PromptHistory(_d);
  late final ContextBudget budget = ContextBudget(this, _d);
  late final PlanRegister register = PlanRegister(this, _d);
  late final RagSources ragSources = RagSources(_d);
  late final CallModelSwap callSwap = CallModelSwap(_d);
  late final TurnTokenAlts tokenAlts = TurnTokenAlts(_d);
  late final TurnBlocks _blocksPhase = TurnBlocks(this, _d);
  late final TurnPlan _planPhase = TurnPlan(this, _d);
  late final TurnRag _ragPhase = TurnRag(this, _d);
  late final TurnRequest _requestPhase = TurnRequest(this, _d);

  /// The open chat's context size, its own setting first.
  int get contextSize =>
      _d.doors.sessions().genSettings.resolveContextSize(_d.services.storage);

  /// 1:1 guest turn **or** a soft group member speaking. Do not set
  /// `guestSpeaker` for the latter — that skip would drop Away / pick.
  bool isLiteTurn(GenTurn t) =>
      t.guestSpeaker != null ||
      _d.doors.cast().roster.speakerIsSoft(t.speakingCharacter);

  // ── The turn's four phases, in this order (`late` carrier fields make an
  // out-of-order call a loud LateInitializationError) ──

  /// Phase 1: system prompt, lore, persona, scenario, examples, notes,
  /// recap and Journal.
  Future<void> assembleBlocks(GenTurn t) => _blocksPhase.assemble(t);

  /// Phase 2: Continue's pop, the macro pass, the state zone, the plan and
  /// the history budget.
  Future<void> buildPlan(GenTurn t) => _planPhase.build(t);

  /// Phase 3: RAG retrieval and the joint memory/history budget.
  Future<void> retrieveMemories(GenTurn t) => _ragPhase.retrieve(t);

  /// Phase 4: render, record the Context Viewer send, build the request,
  /// ring the doorbell and start the stream.
  Future<void> dispatch(GenTurn t) => _requestPhase.dispatch(t);

  // ── Shared with impersonate, the lore key pass and the estimate ──

  /// The chat's macro context for [speaking] (see [PromptBlocks]).
  MacroContext macroContext(CharacterCard speaking, {String? scenario}) =>
      blocks.macroContext(speaking, scenario: scenario);

  /// Token count with the model's tokenizer, or chars/4 for remote APIs.
  Future<int> countTokens(String text) => history.countTokens(text);

  /// The transcript that fits [budget] tokens, with depth lore placed.
  Future<String> historyWithin(
    int budget,
    List<LoreDepthEntry> depthLore,
  ) async => (await history.buildChatHistoryWithBudget(
    budget,
    depthLore: depthLore,
  )).history;
}
