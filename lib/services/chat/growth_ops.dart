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

/// Growth Rings — transport parsing (docs/design/growth-rings.md §4.3).
///
/// One applier, two front doors, both normalized here into the same
/// [GrowthOp] list (the journal_ops.dart pattern):
/// - XML tags ([parseGrowthOps]) — the default, works on any model;
/// - native tool calls ([parseGrowthToolCalls] over [kGrowthTools]).
///
/// Forgiving by design: regex attributes tolerate missing/single quotes and
/// interleaved prose; unknown actions/categories normalize or drop; a garbage
/// response yields zero ops — never an exception.
library;

import 'package:front_porch_ai/services/llm_service.dart' show LlmToolCall;

import 'growth_physics.dart';

enum GrowthOpAction { add, reinforce, revise, retire }

/// One ring operation emitted by the growth pass.
class GrowthOp {
  final GrowthOpAction action;

  /// 1-based ring handle from the "current rings" list shown in the prompt
  /// (reinforce/revise/retire). Never a DB id — small models can't echo UUIDs.
  final int? handle;

  /// Normalized category for `add` (trait/stance/habit/skill/scar).
  final String category;

  /// Absolute message positions cited via `src="12,14"` (receipts;
  /// reinforcement appends its citations to the ring's existing receipts).
  final List<int> sourcePositions;

  /// Ring text (add/revise). Empty for reinforce/retire.
  final String text;

  const GrowthOp({
    required this.action,
    this.handle,
    this.category = 'trait',
    this.sourcePositions = const [],
    this.text = '',
  });
}

/// Model-writable categories ([GrowthPhysics.kArchiveCategory] is code-only).
const List<String> kGrowthCategories = [
  'trait',
  'stance',
  'habit',
  'skill',
  'scar',
];

final RegExp _ringTag = RegExp(
  r'<ring\b([^>]*?)(?:/>|>([\s\S]*?)</ring>)',
  caseSensitive: false,
);
final RegExp _attr = RegExp(
  '''(\\w+)\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'/>]+))''',
);

/// Parse every `<ring .../>` tag into a validated op list. Invalid ops
/// (unknown action, missing handle, empty add/revise text) are dropped.
List<GrowthOp> parseGrowthOps(String raw) {
  final ops = <GrowthOp>[];
  for (final match in _ringTag.allMatches(raw)) {
    final attrs = <String, String>{};
    for (final a in _attr.allMatches(match.group(1) ?? '')) {
      final value = a.group(2) ?? a.group(3) ?? a.group(4) ?? '';
      attrs[a.group(1)!.toLowerCase()] = value.trim();
    }
    // A bare <ring category="...">text</ring> with no action is an add — the
    // most natural thing for a small model to emit.
    final action = _normalizeAction(attrs['action'], hasText: (match.group(2) ?? '').trim().isNotEmpty);
    if (action == null) continue;

    final handle = int.tryParse(attrs['id'] ?? '');
    var text = (match.group(2) ?? '').trim();
    if (text.length > GrowthPhysics.kRingMaxChars) {
      text = text.substring(0, GrowthPhysics.kRingMaxChars).trim();
    }

    switch (action) {
      case GrowthOpAction.add:
        if (text.isEmpty) continue;
        ops.add(
          GrowthOp(
            action: action,
            category: normalizeGrowthCategory(attrs['category']),
            sourcePositions: parseGrowthPositions(attrs['src']),
            text: text,
          ),
        );
        break;
      case GrowthOpAction.revise:
        if (handle == null || text.isEmpty) continue;
        ops.add(GrowthOp(action: action, handle: handle, text: text));
        break;
      case GrowthOpAction.reinforce:
        if (handle == null) continue;
        ops.add(
          GrowthOp(
            action: action,
            handle: handle,
            sourcePositions: parseGrowthPositions(attrs['src']),
          ),
        );
        break;
      case GrowthOpAction.retire:
        if (handle == null) continue;
        ops.add(GrowthOp(action: action, handle: handle));
        break;
    }
  }
  return ops;
}

GrowthOpAction? _normalizeAction(String? raw, {required bool hasText}) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'add':
    case 'new':
    case 'create':
      return GrowthOpAction.add;
    case 'reinforce':
    case 'strengthen':
    case 'stronger':
      return GrowthOpAction.reinforce;
    case 'revise':
    case 'update':
    case 'edit':
      return GrowthOpAction.revise;
    case 'retire':
    case 'delete':
    case 'remove':
    case 'outgrown':
      return GrowthOpAction.retire;
    case '':
      return hasText ? GrowthOpAction.add : null;
    default:
      return null;
  }
}

String normalizeGrowthCategory(String? raw) {
  final c = (raw ?? '').trim().toLowerCase().replaceAll('-', '_');
  if (kGrowthCategories.contains(c)) return c;
  switch (c) {
    case 'relationship':
    case 'stance_toward_user':
    case 'attitude':
      return 'stance';
    case 'behavior':
    case 'behaviour':
    case 'routine':
      return 'habit';
    case 'ability':
    case 'knowledge':
      return 'skill';
    case 'wound':
    case 'trauma':
    case 'fear':
      return 'scar';
    default:
      return 'trait';
  }
}

List<int> parseGrowthPositions(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  return raw
      .split(RegExp(r'[,\s#]+'))
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toList();
}

final RegExp _charMacro = RegExp(r'\{\{\s*char\s*\}\}', caseSensitive: false);
final RegExp _userMacro = RegExp(r'\{\{\s*user\s*\}\}', caseSensitive: false);

/// Resolve {{char}}/{{user}} macros in ring text to real names. The pass
/// prompt asks the model to WRITE macros (matching how cards are authored),
/// but rings are STORED resolved — they are displayed verbatim in the
/// timeline/review UI on both surfaces, so placeholders must never reach the
/// DB (the "{{char}} has developed…" bug). Idempotent; a null [charName]
/// (unresolvable owner) leaves {{char}} untouched rather than guessing.
String resolveGrowthMacros(
  String text, {
  String? charName,
  required String userName,
}) {
  var out = text;
  if (charName != null && charName.isNotEmpty) {
    out = out.replaceAll(_charMacro, charName);
  }
  if (userName.isNotEmpty) {
    out = out.replaceAll(_userMacro, userName);
  }
  return out;
}

/// Cheap pre-check for [resolveGrowthMacros] work (also the self-heal probe
/// for rings stored before macro resolution existed).
bool hasGrowthMacros(String text) =>
    _charMacro.hasMatch(text) || _userMacro.hasMatch(text);

// ── Tool-calling transport ─────────────────────────────────────────────

/// OpenAI tool schemas for the growth pass — one tool per operation the XML
/// transport already supports (kJournalTools precedent).
const List<Map<String, dynamic>> kGrowthTools = [
  {
    'type': 'function',
    'function': {
      'name': 'add_ring',
      'description':
          'Record ONE new way the character has grown or changed: a single '
          'third-person sentence describing a durable change, not a one-off '
          'event.',
      'parameters': {
        'type': 'object',
        'properties': {
          'content': {
            'type': 'string',
            'description':
                'The change, third person with {{char}}/{{user}} macros, at '
                'most 30 words.',
          },
          'category': {
            'type': 'string',
            'enum': kGrowthCategories,
          },
          'src': {
            'type': 'array',
            'items': {'type': 'integer'},
            'description': 'The #numbered message positions that show it.',
          },
        },
        'required': ['content'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'reinforce_ring',
      'description':
          'Mark that an existing ring showed up again in these events '
          '(instead of adding a duplicate).',
      'parameters': {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'integer',
            'description': 'The [N] handle of the ring that reappeared.',
          },
          'src': {
            'type': 'array',
            'items': {'type': 'integer'},
            'description': 'The #numbered message positions that show it.',
          },
        },
        'required': ['id'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'revise_ring',
      'description': 'Reword an existing ring whose description drifted.',
      'parameters': {
        'type': 'object',
        'properties': {
          'id': {'type': 'integer'},
          'content': {'type': 'string'},
        },
        'required': ['id', 'content'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'retire_ring',
      'description':
          'Retire a ring the character has outgrown or that events '
          'contradicted.',
      'parameters': {
        'type': 'object',
        'properties': {
          'id': {'type': 'integer'},
        },
        'required': ['id'],
      },
    },
  },
];

/// Parse tool calls into the same validated [GrowthOp] list the XML
/// transport produces. Unknown tools and invalid ops are dropped.
List<GrowthOp> parseGrowthToolCalls(List<LlmToolCall> calls) {
  final ops = <GrowthOp>[];

  int? intArg(Map<String, dynamic> args, String key) {
    final v = args[key];
    if (v is int) return v;
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  // Tolerant string read: `as String?` throws on a non-null non-String
  // (models send numbers/objects where text belongs), aborting the whole
  // pass. Coerce instead — same as journal_ops/realismToolCallToJson.
  String? strArg(Map<String, dynamic> args, String key) {
    final v = args[key];
    if (v == null) return null;
    return v is String ? v : '$v';
  }

  List<int> positions(dynamic v) {
    if (v is List) {
      return v
          .map((m) => m is int ? m : int.tryParse('$m'))
          .whereType<int>()
          .toList();
    }
    return parseGrowthPositions(v is String ? v : null);
  }

  for (final call in calls) {
    final args = call.arguments;
    switch (call.name) {
      case 'add_ring':
        var text = (strArg(args, 'content') ?? '').trim();
        if (text.isEmpty) continue;
        if (text.length > GrowthPhysics.kRingMaxChars) {
          text = text.substring(0, GrowthPhysics.kRingMaxChars).trim();
        }
        ops.add(
          GrowthOp(
            action: GrowthOpAction.add,
            category: normalizeGrowthCategory(strArg(args, 'category')),
            sourcePositions: positions(args['src']),
            text: text,
          ),
        );
        break;
      case 'reinforce_ring':
        final handle = intArg(args, 'id');
        if (handle == null) continue;
        ops.add(
          GrowthOp(
            action: GrowthOpAction.reinforce,
            handle: handle,
            sourcePositions: positions(args['src']),
          ),
        );
        break;
      case 'revise_ring':
        final handle = intArg(args, 'id');
        var text = (strArg(args, 'content') ?? '').trim();
        if (handle == null || text.isEmpty) continue;
        if (text.length > GrowthPhysics.kRingMaxChars) {
          text = text.substring(0, GrowthPhysics.kRingMaxChars).trim();
        }
        ops.add(
          GrowthOp(action: GrowthOpAction.revise, handle: handle, text: text),
        );
        break;
      case 'retire_ring':
        final handle = intArg(args, 'id');
        if (handle == null) continue;
        ops.add(GrowthOp(action: GrowthOpAction.retire, handle: handle));
        break;
      default:
        continue; // unknown tool — drop
    }
  }
  return ops;
}
