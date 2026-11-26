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

/// The Boons & Bogies share of one owner's Growth pass
/// (docs/design/boons-and-bogies.md §3.2, ruling 18):
///
/// - **The coping verdict.** Absence is not coping (§3 amendment, #764): a
///   bogey the pass says nothing about is "not offered" and holds — no fade,
///   no advance. It wears down only on a `cope` verdict that cites a message
///   from this window where the character met the flaw's moment and handled
///   it, the same evidence bar a boon needs to grow. Copes are ring physics
///   like the fade they replace, so they apply at pass time in both modes
///   and never park in the review list.
/// - **The participation freeze.** An opted-out owner's boons and bogies
///   leave the pass entirely (not shown, never faded, never proposed), while
///   their ordinary rings keep today's physics (ruling 10).
library;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/llm_service.dart' show LlmToolCall;

import 'growth_boons_bogies.dart';
import 'growth_ops.dart';

/// One coping verdict: the 1-based ring handle from the pass prompt and the
/// messages that show the character handling the flaw.
class GrowthCope {
  const GrowthCope({required this.handle, this.sourcePositions = const []});

  final int handle;
  final List<int> sourcePositions;
}

/// What one Growth reply carries: ring ops for the applier, copes for the
/// pass's physics step.
typedef GrowthPassReply = ({List<GrowthOp> ops, List<GrowthCope> copes});

/// An empty reply: the model answered and recorded nothing.
const GrowthPassReply kEmptyGrowthReply = (ops: [], copes: []);

final RegExp _ringTag = RegExp(
  r'<ring\b([^>]*?)(?:/>|>[\s\S]*?</ring>)',
  caseSensitive: false,
);
final RegExp _attr = RegExp(
  '''(\\w+)\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'/>]+))''',
);

const Set<String> _copeActions = {
  'cope',
  'coped',
  'coping',
  'resist',
  'resisted',
  'overcame_moment',
};

/// Every `<ring action="cope" id="N" src="…"/>` tag in [raw]. The ring ops
/// parser drops these (unknown action), so the two readers never overlap.
List<GrowthCope> parseGrowthCopes(String raw) {
  final copes = <GrowthCope>[];
  for (final match in _ringTag.allMatches(raw)) {
    final attrs = <String, String>{};
    for (final a in _attr.allMatches(match.group(1) ?? '')) {
      final value = a.group(2) ?? a.group(3) ?? a.group(4) ?? '';
      attrs[a.group(1)!.toLowerCase()] = value.trim();
    }
    final action = (attrs['action'] ?? '').trim().toLowerCase();
    if (!_copeActions.contains(action)) continue;
    final handle = int.tryParse(attrs['id'] ?? '');
    if (handle == null) continue;
    copes.add(
      GrowthCope(
        handle: handle,
        sourcePositions: parseGrowthPositions(attrs['src']),
      ),
    );
  }
  return copes;
}

/// The tool twin of the XML `cope` tag, offered only when Boons & Bogies is
/// on for the owner.
const Map<String, dynamic> kGrowthCopeTool = {
  'type': 'function',
  'function': {
    'name': 'cope_with_ring',
    'description':
        'A bogey (flaw) had its moment in a NEW message in this window and '
        'the character handled it. Cite that message. Do not call this for a '
        'flaw the scene simply never touched.',
    'parameters': {
      'type': 'object',
      'properties': {
        'id': {
          'type': 'integer',
          'description': 'The [N] handle of the bogey.',
        },
        'src': {
          'type': 'array',
          'items': {'type': 'integer'},
          'description': 'The #numbered message positions that show it.',
        },
      },
      'required': ['id', 'src'],
    },
  },
};

/// [parseGrowthCopes] for native tool calls.
List<GrowthCope> parseGrowthToolCopes(List<LlmToolCall> calls) {
  final copes = <GrowthCope>[];
  for (final call in calls) {
    if (call.name != 'cope_with_ring') continue;
    final rawId = call.arguments['id'];
    final handle = rawId is int ? rawId : int.tryParse('$rawId'.trim());
    if (handle == null) continue;
    final src = call.arguments['src'];
    copes.add(
      GrowthCope(
        handle: handle,
        sourcePositions: src is List
            ? src
                  .map((m) => m is int ? m : int.tryParse('$m'))
                  .whereType<int>()
                  .toList()
            : parseGrowthPositions(src is String ? src : null),
      ),
    );
  }
  return copes;
}

/// The ring ids [copes] may wear down this pass, each with the in-window
/// messages it cited: in-range handles naming a bogey, each citing at least
/// one message inside this window. A rewound re-check has no new messages,
/// so it copes with nothing. The messages ride along so an Overcome the
/// cope earns (phase 7) cites them and a rewrite of them drops it.
Map<String, List<int>> resolveGrowthCopes(
  List<GrowthCope> copes,
  List<GrowthRingData> activeRings, {
  required int windowStart,
  required int windowLength,
  required bool rewound,
}) {
  if (rewound) return const {};
  final end = windowStart + windowLength;
  final ids = <String, List<int>>{};
  for (final cope in copes) {
    if (cope.handle < 1 || cope.handle > activeRings.length) continue;
    final ring = activeRings[cope.handle - 1];
    if (!BoonsBogies.isBogey(ring)) continue;
    final inWindow = [
      for (final p in cope.sourcePositions)
        if (p >= windowStart && p < end) p,
    ];
    if (inWindow.isNotEmpty) {
      (ids[ring.id] ??= <int>[]).addAll(inWindow);
    }
  }
  return ids;
}

/// One owner's rings as the pass sees them. [shown] is what the prompt
/// lists (handles index it); [frozenIds] are the opted-out owner's boons and
/// bogies, held out of the prompt and exempt from fade (ruling 18).
typedef GrowthBbView = ({List<GrowthRingData> shown, Set<String> frozenIds});

GrowthBbView growthBbView(List<GrowthRingData> allRings, {required bool bbOn}) {
  final active = allRings.where((r) => !r.retired);
  if (bbOn) return (shown: active.toList(), frozenIds: const {});
  return (
    shown: active.where((r) => !BoonsBogies.isBoonOrBogey(r)).toList(),
    frozenIds: {
      for (final r in active)
        if (BoonsBogies.isBoonOrBogey(r)) r.id,
    },
  );
}

/// An opted-out owner proposes no new boons or bogies: bogey adds drop here
/// (the prompt never offered the category, but a model may still emit it).
/// New skills stay plain skills through [GrowthOwnerProposals.boonsBogies].
List<GrowthOp> growthOpsForFrozen(List<GrowthOp> ops) => [
  for (final op in ops)
    if (!(op.action == GrowthOpAction.add &&
        op.category == BoonsBogies.kCategoryBogey))
      op,
];
