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

import 'package:front_porch_ai/services/chat/climax_eval.dart';
import 'package:front_porch_ai/services/chat/pockets.dart';
import 'package:front_porch_ai/services/chat/pockets_eval.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

/// The fused reply-facts call — Afterglow's climax check, Pockets & Wardrobe,
/// and the posture pass in ONE post-generation round trip, fired when two or
/// more of them are live for the turn.
///
/// WHY THIS IS NOT THE PIGGYBACKING THE POCKETS RULING FORBIDS (settled
/// 2026-08-07, re-opened by the maintainer 2026-08-10 with the rationale
/// satisfied — see the amendment on [PocketsEval]). That ruling was about one
/// feature riding another FEATURE's pass and silently inheriting its gates:
/// climax rode the needs-impact eval, needs defaults off, so Afterglow was
/// dead on most cards while its row showed green. This call is owned by no
/// feature. The composition rules, each load-bearing:
///
///   * FIRE = OR of the individual gates, and only at two or more. A single
///     live feature keeps firing its own standalone eval, byte-for-byte —
///     nobody's cost or prompt changes until fusion actually saves a call.
///   * PROMPT SECTIONS compose per feature, from the SAME fragment builders
///     the standalone prompts use ([ClimaxEval.rubric],
///     [PocketsEval.wardrobeContext] + [PocketsEval.opsRubric],
///     [TimeService.postureQuestion]) — parity by construction, the
///     RealismPromptBuilder pattern.
///   * SCHEMA `required` is computed per call from the live gates
///     ([kReplyFactsToolsFor]): a model fills in what the schema demands and
///     skips what it does not (the is_climax lesson), so a live feature's
///     fields are demanded and a disabled feature's never are. The field
///     DEFINITIONS are fixed (the converter registry is a fixed contract).
///   * CONSUMPTION is the three features' existing key-scoped parsers
///     ([ClimaxEval.parseRefractory], [PocketsEval.parseOps],
///     [TimeService.parsePosture]) reading the one canonical JSON text —
///     exactly how the one-shot realism eval feeds the relationship,
///     emotional and narrative parsers from one reply. The appliers, chips,
///     swipe/regen rewind and gates do not move.
///
/// FAILURE IS SHARED, AND THAT IS THE ACCEPTED COST: one failed fused call
/// loses all three answers for the turn. Each pass already has a
/// deterministic floor for its own call failing (no cooldown started, record
/// unchanged, stance keeps its last value), so the failure mode is the same
/// shape as today, just correlated. The caller signals it with an EMPTY
/// carrier rather than a null one, so the passes skip instead of paying two
/// or three fallback calls on a backend that just demonstrated it is down.
///
/// Deliberately NOT fused here: the needs-impact eval. It is a judgement call
/// with its own magnitude rubric, strength scaling and Director-authority
/// path — mixing that into three short bookkeeping questions is where small
/// local models start degrading the bookkeeping answers. Fold it in later
/// only behind a capability gate, if at all.
class ReplyFactsEval {
  /// Fires the eval and returns the raw text (tools converted to flat JSON,
  /// or the model's own text). Supplied by ChatService so this leaf owns no
  /// transport — the same probe-and-fallback contract its three siblings use.
  final Future<String?> Function({
    required String debugLabel,
    required List<Map<String, dynamic>> tools,
    required String Function({required bool toolsMode}) buildPrompt,
  })
  fire;

  const ReplyFactsEval({required this.fire});

  /// Registered in realism_tools' converter registry — an unregistered tool
  /// silently falls back to text forever (the Pockets day-one bug).
  static const kReplyFactsTool = kReplyFactsToolName;

  /// The composed prompt. [pockets] non-null means the inventory question is
  /// asked; [askClimax]/[askPosture] gate their sections the same way. Every
  /// section is the standalone prompt's own fragment, verbatim — including the
  /// climax rubric's [physiology] slot, which the caller fills from the reply
  /// speaker's card.
  static String buildPrompt({
    required String charName,
    required String reply,
    required String recentExchange,
    required bool toolsMode,
    required bool askClimax,
    Pockets? pockets,
    List<String> others = const [],
    bool askPosture = false,
    String emotionCtx = '',
    String postureCtx = '',
    String displayClock = '',
    String physiology = '',
  }) {
    final askPockets = pockets != null;
    final keys = [
      if (askClimax) ...['"is_climax"', '"refractory_turns"'],
      if (askPockets) '"inventory_ops" (an array)',
      if (askPosture) '"posture"',
    ];
    return 'Answer each of the independent bookkeeping questions below about '
        '$charName\'s latest reply. They are separate records — answer all of '
        'them.\n\n'
        '${askPockets ? '${PocketsEval.wardrobeContext(charName, pockets)}${PocketsEval.opsRubric(others: others)}' : ''}'
        '${askClimax ? ClimaxEval.rubric(charName, physiology) : ''}'
        '${askPosture ? TimeService.postureQuestion(charName: charName, emotionCtx: emotionCtx, postureCtx: postureCtx, displayClock: displayClock) : ''}'
        'The reply:\n$reply\n\n'
        '${recentExchange.trim().isEmpty ? '' : 'Recent exchange for context:\n$recentExchange\n\n'}'
        '${toolsMode ? 'Report by calling the $kReplyFactsTool tool. Use ONLY the tool — no plain-text reply.' : 'Respond with ONLY a flat JSON object containing ${keys.join(', ')}. '
                  'Do NOT use markdown code blocks — return raw JSON only.'}';
  }

  /// Fire the fused call and return the raw canonical text, or null on any
  /// failure. The caller decides whether fusion applies at all (the two-or-
  /// more rule and every feature gate live there); this leaf consults no
  /// settings, the same contract its three siblings keep.
  Future<String?> fetch({
    required String charName,
    required String reply,
    required String recentExchange,
    required bool askClimax,
    Pockets? pockets,
    List<String> others = const [],
    bool askPosture = false,
    String emotionCtx = '',
    String postureCtx = '',
    String displayClock = '',
    String physiology = '',
  }) async {
    if (reply.trim().isEmpty) return null;
    try {
      return await fire(
        debugLabel: 'reply_facts',
        tools: kReplyFactsToolsFor(
          askClimax: askClimax,
          askPockets: pockets != null,
          askPosture: askPosture,
        ),
        buildPrompt: ({required bool toolsMode}) => buildPrompt(
          charName: charName,
          reply: reply,
          recentExchange: recentExchange,
          toolsMode: toolsMode,
          askClimax: askClimax,
          pockets: pockets,
          others: others,
          askPosture: askPosture,
          emotionCtx: emotionCtx,
          postureCtx: postureCtx,
          displayClock: displayClock,
          physiology: physiology,
        ),
      );
    } catch (e) {
      // Never fail a turn over bookkeeping — the passes read an empty answer
      // as "skip this turn", the same floor each of their own calls has.
      debugPrint('[ReplyFacts] fused eval failed, passes skip this turn: $e');
      return null;
    }
  }
}
