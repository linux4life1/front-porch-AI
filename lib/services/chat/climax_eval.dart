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
import 'package:front_porch_ai/services/chat/realism_tools.dart';

/// Climax detection — the one thing that starts Afterglow's refractory.
///
/// WHERE IT RUNS, AND WHY THAT IS NOT NEGOTIABLE. Post-generation, reading the
/// character's actual reply. It has to: the question is "did THIS reply narrate
/// the character's own release", and before generation that reply does not
/// exist. An earlier attempt at this fix moved the check onto the pre-generation
/// arousal eval, which reads the user's message — it would have judged a reply
/// that had not happened yet, lagged a turn behind, re-fired on the same climax
/// still sitting in recent history, and put the pre-gen judge in the business of
/// scoring the character's own words, which the settled rule forbids precisely
/// because a reroll would then reroll it.
///
/// WHY IT IS ITS OWN PASS. It used to ride the needs-impact eval, which opens
/// with `if (!getNeedsSimEnabled() || !getRealismEnabled()) return;`.
/// `CharacterCard.needsSimEnabled` defaults FALSE, so on most cards that eval
/// never ran, climax was never detected, and Afterglow did nothing at all —
/// while the Porch Life row showed its one declared dependency (the engine)
/// satisfied and the switch live. A feature riding another feature's pass
/// silently inherits that pass's gates; that is the same lesson the Pockets
/// ruling records (docs/design/pockets-and-preferences.md).
///
/// Now Afterglow answers to the Realism Engine and its own switch, full stop.
/// The cost of standing alone is one short call per turn while Afterglow is on
/// — stated plainly in the toggle copy, the way Pockets and Promises state
/// theirs.
///
/// FUSED TRANSPORT (2026-08-10, maintainer-approved): when two or more of the
/// post-generation bookkeeping passes (this one, Pockets, posture) are live,
/// their questions ride ONE composed call (ReplyFactsEval) instead of one
/// each. That is a change of TRANSPORT, not of ownership: this pass keeps its
/// own gate, its question is included only when Afterglow itself is on, and
/// the answer flows through this same [parseRefractory] into the same
/// applier. The gate-inheritance trap the paragraph above records cannot
/// recur — no feature's switch appears in another feature's gate.
class ClimaxEval {
  /// Supplied by ChatService: fires through the shared tools-first negotiation
  /// and hands back flat-JSON text, so this leaf owns no transport.
  final Future<String?> Function({
    required String debugLabel,
    required List<Map<String, dynamic>> tools,
    required String Function({required bool toolsMode}) buildPrompt,
  })
  fire;

  const ClimaxEval({required this.fire});

  /// The tool name and schema live in realism_tools.dart, because the
  /// converter's registry there is what makes the tools transport work at all
  /// — a tool it does not know about yields null and falls back to text
  /// silently, forever. Re-exposed here so callers read one name.
  static const kClimaxTool = kClimaxToolName;
  static List<Map<String, dynamic>> get tools => kClimaxEvalTools;

  /// The detection rubric alone — shared VERBATIM between [buildPrompt] and
  /// the fused reply-facts prompt (ReplyFactsEval), so the fused and
  /// standalone transports can never drift in what they ask. Do not re-inline
  /// this into either caller; the fusion parity test pins both.
  ///
  /// [physiology] is the card's character input to the cooldown number
  /// (`physiologyFor`). It was dropped in the August extraction (`e943ba20c`),
  /// which is why every character started refracting at ~6 turns — an empty
  /// slot omits the traits line and the judge defaults to its own bias.
  static String rubric(String charName, [String physiology = '']) =>
      'CLIMAX DETECTION — "is_climax": true ONLY when $charName THEMSELVES '
      'reaches sexual orgasm / release in THIS scene — i.e. the text explicitly '
      'narrates their own climax (coming, finishing, a shuddering or spasming '
      'release, crying out as they tip over the edge, gushing/ejaculating, '
      'going limp or boneless right after the peak). High arousal, being '
      '"close", edging, begging, grinding, foreplay, or ONLY the partner/user '
      'climaxing are NOT a climax for $charName — answer false in those cases.\n'
      '${physiology.isEmpty ? '' : 'Who $charName is — use their traits to decide the cooldown:\n"$physiology"\n'}'
      'When (and only when) "is_climax" is true, also give "refractory_turns" '
      'as an int from 0 to 12 (each is about 15 minutes of story time) for how '
      'long the post-orgasm cooldown should last. A quick climax runs shorter '
      'than a drawn-out or repeated one; a highly sexual character recovers '
      'fast, a reserved one slowly. 0 is a valid, common answer — a character '
      'who could easily go again needs no cooldown. When false, 0.\n\n';

  /// The judge's view of who the character is, for [rubric]'s traits slot:
  /// authored intimate preferences first, then the card's personality; an
  /// empty personality (common on imported cards) falls back to the opening
  /// of the description. Capped at 600 chars — the budget the April
  /// personality-judge shipped with; the post-gen prompt window is tight.
  static String physiologyFor(CharacterCard? card) {
    if (card == null) return '';
    final ext = card.frontPorchExtensions;
    final parts = <String>[
      if ((ext?.intimateInto ?? const []).isNotEmpty)
        'Into: ${ext!.intimateInto.join('; ')}',
      if ((ext?.intimateNotInto ?? const []).isNotEmpty)
        'Not into: ${ext!.intimateNotInto.join('; ')}',
      if (card.personality.trim().isNotEmpty)
        card.personality.trim()
      else if (card.description.trim().isNotEmpty)
        card.description.trim(),
    ];
    final joined = parts.join('\n');
    return joined.length > 600 ? joined.substring(0, 600) : joined;
  }

  /// The criteria matter more than the question. Without them the model —
  /// especially a reasoning model, which will not guess at an undefined field —
  /// almost never answers true, and the Lust bar stays pinned at the top
  /// forever. This text is the one that shipped with the original detector,
  /// kept verbatim because it was already tuned.
  /// [recentExchange] is the last few turns, formatted `sender: text` — the
  /// SAME context the needs-impact eval gave this question before Afterglow
  /// stood on its own, and dropping it was a real regression that CI caught.
  ///
  /// It matters because of who narrates a climax. In roleplay the user very
  /// often writes it — "the wave crests over us both" — and the character's own
  /// reply is a half-line of aftermath. Shown only that reply, the model
  /// answers false and the refractory never starts, which is the exact symptom
  /// this whole fix set out to remove. The verdict is still about the
  /// CHARACTER, and still judged on a reply that already exists; the exchange
  /// is context for reading it, not a second thing to score.
  static String buildPrompt({
    required String charName,
    required String reply,
    required String recentExchange,
    required bool toolsMode,
    String physiology = '',
  }) =>
      'Read the scene below and answer one question about $charName.\n\n'
      '${rubric(charName, physiology)}'
      'The scene:\n$reply\n\n'
      '${recentExchange.trim().isEmpty ? '' : 'Recent exchange for context:\n$recentExchange\n\n'}'
      '${toolsMode ? 'Report by calling the $kClimaxTool tool. Use ONLY the tool — no plain-text reply.' : 'Respond with ONLY a flat JSON object containing "is_climax" and '
                '"refractory_turns". Do NOT use markdown code blocks — raw JSON only.'}';

  /// Forgiving on purpose (local-model floor): tools mode yields a real bool,
  /// text mode may quote it, and a missing refractory falls back to the middle
  /// of the range rather than dropping a climax that was actually reported.
  ///
  /// 0 is a real answer ("no cooldown needed") and must survive: the old
  /// `clamp(1, 10)` turned it into a 15-minute lock, making "no refractory"
  /// inexpressible. 0 applies as no refractory at all
  /// (`Refractory.fromJudgeTurns(0)` is `none`).
  static int? parseRefractory(String? raw) {
    if (raw == null) return null;
    final m = RegExp(
      r'"is_climax"\s*:\s*"?(true|false)"?',
      caseSensitive: false,
    ).firstMatch(raw);
    if (m == null || m.group(1)!.toLowerCase() != 'true') return null;
    final t = RegExp(r'"refractory_turns"\s*:\s*"?(-?\d+)"?').firstMatch(raw);
    return (int.tryParse(t?.group(1) ?? '') ?? 5).clamp(0, 12);
  }

  /// Returns the refractory length when the character climaxed, else null.
  ///
  /// The caller decides whether to run at all (the engine, the Afterglow
  /// switch, a non-empty reply); this leaf consults no settings, so there is
  /// exactly one place the feature is gated.
  Future<int?> detect({
    required String charName,
    required String reply,
    String recentExchange = '',
    String physiology = '',
  }) async {
    if (reply.trim().isEmpty) return null;
    try {
      return parseRefractory(
        await fire(
          debugLabel: 'climax',
          tools: tools,
          buildPrompt: ({required bool toolsMode}) => buildPrompt(
            charName: charName,
            reply: reply,
            recentExchange: recentExchange,
            toolsMode: toolsMode,
            physiology: physiology,
          ),
        ),
      );
    } catch (e) {
      // Never fail a turn over bookkeeping: the reply already happened and the
      // refractory simply does not start. Logged rather than swallowed.
      debugPrint('[Afterglow] climax check failed, no cooldown started: $e');
      return null;
    }
  }
}
