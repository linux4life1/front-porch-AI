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

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/pockets.dart';

/// The Pockets detection pass — ONE short post-generation call that asks a
/// single question: what did this reply change about what the character is
/// wearing and carrying?
///
/// WHY ITS OWN EVAL, and do not re-open this (settled ruling, 2026-08-07;
/// docs/design/pockets-and-preferences.md). An earlier plan had Pockets ride
/// the post-generation needs-impact eval as one extra JSON field, advertised as
/// "zero new LLM calls". That was retracted for a reason of principle and a
/// technical fact, and the fact alone is decisive:
/// `NeedsImpactEvaluator.evaluateAndApply` opens with
/// `if (!getNeedsSimEnabled() || !getRealismEnabled())`, and realismEnabled
/// DEFAULTS FALSE. Riding it would have meant an inventory feature that does
/// nothing until you switch on a bond/trust engine it has no relationship with.
/// "Zero new calls" was only ever true for users who had already opted into
/// both.
///
/// The principle: interleaving one feature's data into another feature's pass
/// is what produced the mess docs/design/feature-independence.md took a day to
/// untangle. Pockets stands alone or it repeats that.
///
/// It reuses INFRASTRUCTURE, which is the correct kind of sharing — the same
/// tools-first negotiation (`fireStructuredEval` + `ToolTransportProbe`) that
/// the realism evals, the Journal pass and Growth all use, so a tool-less
/// backend falls back to the forgiving flat-JSON floor exactly as they do.
///
/// AMENDMENT (2026-08-10, maintainer-approved): the ruling above forbade
/// riding another FEATURE's pass, and its rationale — a feature must never
/// inherit a gate its UI does not declare — is untouched by the fused
/// reply-facts transport (ReplyFactsEval). That call is owned by no feature:
/// it fires when two or more of the bookkeeping passes (this one, climax,
/// posture) are live, includes each question only when that feature's OWN
/// switch is on, and hands the answer to this same [parseOps] and the same
/// applier. Pockets-only users still fire this standalone eval, byte-for-byte
/// — the fused prompt is composed from [wardrobeContext] and [opsRubric], the
/// exact fragments [buildPrompt] uses, so the two can never drift.
class PocketsEval {
  /// Fires the eval and returns the raw text (tools converted to flat JSON, or
  /// the model's own text). Supplied by ChatService so this leaf owns no
  /// transport of its own.
  final Future<String?> Function({
    required String debugLabel,
    required List<Map<String, dynamic>> tools,
    required String Function({required bool toolsMode}) buildPrompt,
  })
  fire;

  const PocketsEval({required this.fire});

  /// The tool schema. One array of ops, nothing else — the narrower the ask,
  /// the better a small local model answers it.
  static List<Map<String, dynamic>> get tools => [
    {
      'type': 'function',
      'function': {
        'name': kPocketsTool,
        'description':
            'Report changes to what the character is wearing or carrying.',
        'parameters': {
          'type': 'object',
          'properties': {
            'inventory_ops': {
              'type': 'array',
              'description':
                  'Every change this reply made. Empty when nothing changed.',
              'items': {
                'type': 'object',
                'properties': {
                  'op': {
                    'type': 'string',
                    'enum': [for (final k in PocketOpKind.values) k.name],
                  },
                  'item': {'type': 'string'},
                  'to': {
                    'type': 'string',
                    'description': 'Who received it (give only).',
                  },
                  'state': {
                    'type': 'string',
                    'description':
                        'New condition (update), or what it became (transform).',
                  },
                  'where': {
                    'type': 'string',
                    'description':
                        'Where it was put, if the scene says (setdown/drop): '
                        '"on the nightstand", "by the door".',
                  },
                },
                'required': ['op', 'item'],
              },
            },
          },
          'required': ['inventory_ops'],
        },
      },
    },
  ];

  static const kPocketsTool = 'report_inventory';

  /// The "what they have right now" lead-in — shared VERBATIM between
  /// [buildPrompt] and the fused reply-facts prompt (ReplyFactsEval), so the
  /// fused and standalone transports can never drift in what they show the
  /// model. Do not re-inline; the fusion parity test pins both callers.
  static String wardrobeContext(String charName, Pockets current) {
    String list(String label, List<PocketItem> items) => items.isEmpty
        ? ''
        : '$label: ${items.map((i) => i.display).join(', ')}\n';

    return 'You are keeping track of what $charName is wearing and carrying.\n\n'
        '${list('Currently wearing', current.worn)}'
        '${list('Currently carrying', current.carrying)}'
        // Only when something IS set aside — most turns nothing is, and an
        // always-on line would be prompt tax for nothing. Callers hand this
        // an already-expired record, so yesterday's clothes never show.
        '${current.setAside.isEmpty ? '' : 'Set aside nearby (still $charName\'s): '
                  '${current.setAside.map((e) => e.item.display).join(', ')}\n'}';
  }

  /// The op vocabulary and rules — the other shared fragment (see
  /// [wardrobeContext] for the contract).
  static String opsRubric({List<String> others = const []}) =>
      // "in the reply or the recent exchange": the old wording said "in it",
      // scoping to the reply alone — which quietly re-opened the very hole
      // recentExchange was added to close (a change the USER narrated was
      // context the model had been told to ignore).
      // "were offered AND DID NOT TAKE" (2026-08-14): the old blanket
      // "were offered" told the model to ignore the user's own gift — "here,
      // take my keys" is an offer, so accepting it scored nothing and the
      // keys never reached the record. That is the ONE way a user can hand a
      // character something by narration (the sidebar's "Hand it over" being
      // the deterministic path), and in a 1:1 it is the only kind of handover
      // there is. An offer left hanging is still correctly ignored.
      '\nWhat changed? Report ONLY changes that actually happened in the '
      'reply or the recent exchange below — not things they merely mentioned, '
      'remembered, wanted, or were offered and did not take. If nothing '
      'changed, report an empty list; that is the common answer and it is '
      'the right one.\n\n'
      'Each change is one op:\n'
      '  wear / remove — clothing put on or taken off. Undressing (for bed, '
      'a bath, a shower) is one remove per worn item, named as listed above — '
      'or a single remove of "clothes" to mean all of it. Wearing nothing is '
      'that remove — never a wear of an item named nothing, nude, or naked. '
      'Changing clothes is a remove for each thing that came off plus a wear '
      'for each thing that went on\n'
      '  pickup / drop — something taken up; or gone for GOOD (thrown away, '
      'lost, destroyed, given up). Taking back something set aside is a '
      'pickup; so is accepting something handed over — by the person they '
      'are talking to or by anyone else\n'
      '  setdown — put down nearby but still theirs: on the table, the '
      'nightstand, by the door. It can be taken back later. Use drop only '
      'when it is gone for good. Include "where" when the scene says '
      '("where": "on the nightstand")\n'
      '${others.isEmpty ? '  give — handed to someone else\n' : '  give — handed to someone else. Put their name in "to", spelled EXACTLY '
                'as it appears here: ${others.join(', ')}. If it went to anyone '
                'else — the person you are talking to, a passer-by, nobody in '
                'particular — leave "to" empty rather than guessing a name from '
                'that list.\n'}'
      '  update — the same item, new condition. Weather, wear and damage '
      'all count, not just food: ("state": "half-eaten"), a dress caught in '
      'the rain ("state": "rain-soaked"), armour after a fight '
      '("state": "dented"), boots after a road ("state": "mud-caked")\n'
      '  transform — the item BECAME something else ("item": "candy bar", '
      '"state": "sweet wrapper")\n\n'
      'Name items the way they are already listed above when they appear '
      'there, so the same thing is not recorded twice.\n\n';

  /// The prompt. Deliberately short: this call runs every turn the feature is
  /// on, so it carries the current record and the reply and nothing else — no
  /// dossier, no relationship standing, none of the context the realism judges
  /// need. It is a bookkeeping question, not a judgement.
  /// [others] is the rest of the cast, by name, when hand-offs are on. Empty
  /// otherwise — and then the model is never invited to name a recipient at
  /// all, because a `to` nobody can resolve is a `to` that does nothing.
  /// [recentExchange] is the last few turns. REQUIRED, and the reason is a
  /// bug that shipped twice: an eval given only the character's reply cannot
  /// see a change the USER narrated. "You step out into the downpour" followed
  /// by a half-line of dialogue leaves the red sundress recorded bone-dry
  /// forever, because nothing in the text the eval was shown says otherwise.
  /// Afterglow's climax check had the identical hole and went red on three
  /// platforms for it.
  static String buildPrompt({
    required String charName,
    required Pockets current,
    required String reply,
    required String recentExchange,
    required bool toolsMode,
    List<String> others = const [],
  }) {
    return '${wardrobeContext(charName, current)}'
        '${opsRubric(others: others)}'
        'The reply:\n$reply\n\n'
        '${recentExchange.trim().isEmpty ? '' : 'Recent exchange for context:\n$recentExchange\n\n'}'
        '${toolsMode ? 'Report by calling the $kPocketsTool tool. Use ONLY the tool — no plain-text reply.' : 'Respond with ONLY a flat JSON object containing "inventory_ops" (an array). '
                  'Do NOT use markdown code blocks — return raw JSON only.'}';
  }

  /// Pull the ops out of whatever came back. Forgiving by design: a local model
  /// may wrap the array, prose around it, or hand back a bare list. Anything
  /// unreadable yields no ops rather than an exception — a bookkeeping pass
  /// must never be able to fail a turn.
  static List<PocketOpReport> parseOps(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    Object? decoded;
    // Take the OUTERMOST JSON value, object or array — decided by whichever
    // bracket appears first, not by a fixed preference.
    //
    // Trying `{...}` first looks harmless and is not: given the bare array
    // `[{"op":"drop","item":"x"}]` that a smaller model hands back, the object
    // pattern happily matches the INNER object, decodes a Map with no
    // `inventory_ops` key, and reports that nothing changed. Silently. Caught
    // by the bare-array test below.
    final firstBrace = raw.indexOf('{');
    final firstBracket = raw.indexOf('[');
    final objectFirst =
        firstBrace != -1 && (firstBracket == -1 || firstBrace < firstBracket);
    for (final pattern
        in objectFirst
            ? [r'\{[\s\S]*\}', r'\[[\s\S]*\]']
            : [r'\[[\s\S]*\]', r'\{[\s\S]*\}']) {
      final m = RegExp(pattern).firstMatch(raw);
      if (m == null) continue;
      try {
        decoded = jsonDecode(m.group(0)!);
        break;
      } catch (_) {
        // Keep trying the other shape rather than giving up on the turn.
      }
    }
    if (decoded == null) return const [];
    final list = decoded is Map ? decoded['inventory_ops'] : decoded;
    return [
      for (final e in list is List ? list : const [])
        ?PocketOpReport.fromJson(e),
    ];
  }

  /// Run the pass and apply what it found, in place. Returns the receipt lines
  /// for the message chips — empty when nothing changed, which is most turns.
  ///
  /// The caller decides whether to run at all (the switch, a non-empty reply);
  /// this leaf does not consult settings, so there is exactly one place the
  /// feature is gated.
  Future<List<String>> evaluateAndApply({
    required String charName,
    required Pockets pockets,
    required String reply,
    required String recentExchange,
    List<String> others = const [],
    void Function(String to, PocketItem item)? onTransfer,
    int day = 0,
    List<PocketEvent>? events,
  }) async {
    if (reply.trim().isEmpty) return const [];
    // Expire BEFORE the prompt is built, not only inside the applier: the
    // model must never be shown yesterday's set-aside clothes, or it will
    // dutifully re-dress them in them.
    pockets.expireSetAside(day);
    try {
      final raw = await fire(
        debugLabel: 'pockets',
        tools: tools,
        buildPrompt: ({required bool toolsMode}) => buildPrompt(
          charName: charName,
          current: pockets,
          reply: reply,
          recentExchange: recentExchange,
          toolsMode: toolsMode,
          others: others,
        ),
      );
      final ops = parseOps(raw);
      if (ops.isEmpty) return const [];
      return applyPocketOps(
        pockets,
        ops,
        onTransfer: onTransfer,
        day: day,
        events: events,
      );
    } catch (e) {
      // Never surface as a failed turn: the reply already happened and the
      // record simply misses one update. Logged rather than swallowed silently.
      debugPrint('[Pockets] eval failed, record unchanged: $e');
      return const [];
    }
  }
}
