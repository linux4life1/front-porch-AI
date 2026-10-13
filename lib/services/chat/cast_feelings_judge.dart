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

import 'package:front_porch_ai/services/chat/eval_json_merge.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';

/// The largest step one reply moves a feeling, either way.
const int kCastFeelingsMaxDelta = 4;

/// The char→char judge: how a group member's reply moved their hidden
/// feelings toward the other members it involved.
///
/// It replaces a keyword scan that scored "love" or "stupid" anywhere in the
/// recent text, whoever said it and about whom. Like that scan, it runs
/// post-generation on the speaker's own reply: it reads what the speaker
/// said and did to the others, never the user's message, so the rule that
/// evals score the user's message is untouched. Directing or not, the cast's
/// feelings for each other move the same way.
///
/// Its own tool, not one of the three prefix-sharing judges. The caller keeps
/// the keyword scan as the floor when this call fails.
class CastFeelingsJudge {
  /// Supplied by ChatService: the shared tools-first negotiation, returning
  /// flat-JSON text. This leaf owns no transport.
  final Future<String?> Function({
    required String debugLabel,
    required List<Map<String, dynamic>> tools,
    required String Function({required bool toolsMode}) buildPrompt,
  })
  fire;

  const CastFeelingsJudge({required this.fire});

  static String buildPrompt({
    required String speakerName,
    required List<String> otherNames,
    required String reply,
    required String recentExchange,
    required bool toolsMode,
  }) =>
      'In a group roleplay scene, $speakerName just replied. Judge how this '
      'reply shows $speakerName\'s feelings toward each of these characters '
      'changing: ${otherNames.join(', ')}.\n\n'
      'Count only what $speakerName says or does to or about them in this '
      'reply: warmth, kindness, gratitude or closeness is positive; '
      'contempt, cruelty, insults, coldness or betrayal is negative. Use a '
      'delta from -$kCastFeelingsMaxDelta to $kCastFeelingsMaxDelta (small '
      'moments 1 or -1, strong ones 3 or 4). Leave out anyone the reply does '
      'not involve. Ignore feelings toward anyone not in that list.\n\n'
      '${recentExchange.trim().isEmpty ? '' : 'Recent exchange for context:\n$recentExchange\n\n'}'
      '$speakerName\'s reply:\n$reply\n\n'
      '${toolsMode ? 'Report by calling the $kCastFeelingsToolName tool, with an empty list when the reply moves no one. Use ONLY the tool — no plain-text reply.' : 'Respond with ONLY this JSON: {"feelings": [{"name": "<character>", "delta": <int>}]}, with an empty list when the reply moves no one. Raw JSON only, no markdown.'}';

  /// Deltas by the names in [otherNames] (matched without case), clamped.
  /// Null when the answer is unreadable, so the caller can fall back.
  static Map<String, int>? parse(String? raw, List<String> otherNames) {
    if (raw == null) return null;
    final obj = parseEvalJsonObject(raw);
    final list = obj?['feelings'];
    if (list is! List) return null;
    final byLower = {for (final n in otherNames) n.trim().toLowerCase(): n};
    final out = <String, int>{};
    for (final item in list) {
      if (item is! Map) continue;
      final name = byLower[item['name']?.toString().trim().toLowerCase()];
      final d = item['delta'];
      final delta = d is num ? d.round() : int.tryParse('${d ?? ''}'.trim());
      if (name == null || delta == null || delta == 0) continue;
      out[name] = delta.clamp(-kCastFeelingsMaxDelta, kCastFeelingsMaxDelta);
    }
    return out;
  }

  /// The judged deltas by name, or null when the call or its answer failed.
  Future<Map<String, int>?> judge({
    required String speakerName,
    required List<String> otherNames,
    required String reply,
    String recentExchange = '',
  }) async {
    if (reply.trim().isEmpty || otherNames.isEmpty) return const {};
    try {
      return parse(
        await fire(
          debugLabel: 'cast_feelings',
          tools: kCastFeelingsEvalTools,
          buildPrompt: ({required bool toolsMode}) => buildPrompt(
            speakerName: speakerName,
            otherNames: otherNames,
            reply: reply,
            recentExchange: recentExchange,
            toolsMode: toolsMode,
          ),
        ),
        otherNames,
      );
    } catch (e) {
      debugPrint('[CastFeelings] judge failed, keyword floor runs: $e');
      return null;
    }
  }
}
