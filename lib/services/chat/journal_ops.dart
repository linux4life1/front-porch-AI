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

/// The Journal — transport parsing (docs/design/journal-memory.md §4.3).
///
/// One applier, two front doors, both normalized here into the same
/// [JournalOp] list:
/// - XML tags ([parseJournalOps]/[parseRecap]) — the default, works on any
///   model (local floor);
/// - native tool calls ([parseJournalToolCalls] over [kJournalTools]) — for
///   backends that speak the OpenAI tools protocol (phase 4).
///
/// Forgiving by design: the XML path is regex-based and tolerates missing
/// or single quotes, unknown attributes, interleaved prose, self-closing
/// tags, and an unclosed final `<recap>`; the tools path tolerates unknown
/// tool names, missing/malformed arguments, and ids sent as strings. A
/// garbage response yields zero ops — never an exception (same philosophy
/// as the realism regex extractors in llm_eval_engine.dart).
library;

import 'package:front_porch_ai/services/llm_service.dart' show LlmToolCall;

enum JournalOpAction { add, revise, retire, pin }

/// One memory operation emitted by the maintenance pass.
class JournalOp {
  final JournalOpAction action;

  /// 1-based card handle from the "current entries" list shown in the prompt
  /// (revise/retire/pin). Never a DB id — small models can't echo UUIDs.
  final int? handle;

  /// Normalized category for `add` (about_user / about_us / moment / promise).
  final String category;

  /// Absolute message positions cited via `msgs="12,14"` (provenance and the
  /// deterministic emotion-stamp source; the model is never asked for the
  /// feeling of a new memory).
  final List<int> sourcePositions;

  /// Optional revised feeling on `revise` (the "feelings that heal" hook).
  final String? feeling;

  /// Memory text (add/revise). Empty for retire/pin.
  final String text;

  const JournalOp({
    required this.action,
    this.handle,
    this.category = 'moment',
    this.sourcePositions = const [],
    this.feeling,
    this.text = '',
  });
}

const List<String> kJournalCategories = [
  'about_user',
  'about_us',
  'moment',
  'promise',
];

/// Max stored length of a single memory (keeps cards atomic and the hot-set
/// prompt block small even when a rambly model over-writes).
const int kJournalMemoryMaxChars = 300;

final RegExp _memoryTag = RegExp(
  r'<memory\b([^>]*?)(?:/>|>([\s\S]*?)</memory>)',
  caseSensitive: false,
);
// Quoted (double or single) or bare values; a bare value stops at whitespace
// so `action=delete id=2` parses as two attributes, not one.
final RegExp _attr = RegExp(
  '''(\\w+)\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^\\s"'/>]+))''',
);
final RegExp _recapTag = RegExp(
  r'<recap>\s*([\s\S]*?)\s*</recap>',
  caseSensitive: false,
);
final RegExp _recapOpen = RegExp(r'<recap>\s*([\s\S]*)$', caseSensitive: false);

/// Parse every `<memory .../>` tag into a validated op list. Invalid ops
/// (unknown action, missing handle, empty add/revise text) are dropped.
List<JournalOp> parseJournalOps(String raw) {
  final ops = <JournalOp>[];
  for (final match in _memoryTag.allMatches(raw)) {
    final attrs = <String, String>{};
    for (final a in _attr.allMatches(match.group(1) ?? '')) {
      final value = a.group(2) ?? a.group(3) ?? a.group(4) ?? '';
      attrs[a.group(1)!.toLowerCase()] = value.trim();
    }
    final action = _normalizeAction(attrs['action']);
    if (action == null) continue;

    final handle = int.tryParse(attrs['id'] ?? '');
    var text = (match.group(2) ?? '').trim();
    if (text.length > kJournalMemoryMaxChars) {
      text = text.substring(0, kJournalMemoryMaxChars).trim();
    }

    switch (action) {
      case JournalOpAction.add:
        if (text.isEmpty) continue;
        ops.add(
          JournalOp(
            action: action,
            category: _normalizeCategory(attrs['category']),
            sourcePositions: _parsePositions(attrs['msgs']),
            text: text,
          ),
        );
        break;
      case JournalOpAction.revise:
        if (handle == null || text.isEmpty) continue;
        final feeling = (attrs['feeling'] ?? '').trim().toLowerCase();
        ops.add(
          JournalOp(
            action: action,
            handle: handle,
            feeling: feeling.isEmpty ? null : feeling,
            text: text,
          ),
        );
        break;
      case JournalOpAction.retire:
      case JournalOpAction.pin:
        if (handle == null) continue;
        ops.add(JournalOp(action: action, handle: handle));
        break;
    }
  }
  return ops;
}

/// Extract the `<recap>` paragraph — paired tag first, then the unclosed-tag
/// fallback (mirrors the unclosed-`<think>` trick). Any stray tags inside are
/// stripped so plain prose is guaranteed (the growth pass and the prompt
/// summaryBlock consume this text directly).
String? parseRecap(String raw) {
  var text = _recapTag.firstMatch(raw)?.group(1);
  text ??= _recapOpen.firstMatch(raw)?.group(1);
  if (text == null) return null;
  text = text.replaceAll(_memoryTag, '').replaceAll(RegExp(r'<[^>]*>'), '');
  text = text.trim();
  return text.isEmpty ? null : text;
}

JournalOpAction? _normalizeAction(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'add':
    case 'new':
    case 'create':
      return JournalOpAction.add;
    case 'revise':
    case 'update':
    case 'edit':
      return JournalOpAction.revise;
    case 'retire':
    case 'delete':
    case 'remove':
      return JournalOpAction.retire;
    case 'pin':
      return JournalOpAction.pin;
    default:
      return null;
  }
}

String _normalizeCategory(String? raw) {
  final c = (raw ?? '').trim().toLowerCase().replaceAll('-', '_');
  if (kJournalCategories.contains(c)) return c;
  switch (c) {
    case 'user':
    case 'about_him':
    case 'about_her':
    case 'about_them':
      return 'about_user';
    case 'us':
    case 'relationship':
      return 'about_us';
    case 'promises':
      return 'promise';
    default:
      return 'moment';
  }
}

List<int> _parsePositions(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  return raw
      .split(RegExp(r'[,\s#]+'))
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toList();
}

// ── Tool-calling transport (phase 4) ────────────────────────────────────

/// OpenAI tool schemas for the Journal maintenance pass — one tool per
/// operation the XML transport already supports, plus the recap.
const List<Map<String, dynamic>> kJournalTools = [
  {
    'type': 'function',
    'function': {
      'name': 'add_memory',
      'description':
          'Add one new journal memory: a single first-person sentence about '
          'something durable that just happened.',
      'parameters': {
        'type': 'object',
        'properties': {
          'content': {
            'type': 'string',
            'description': 'The memory, first person, at most 40 words.',
          },
          'category': {
            'type': 'string',
            'enum': kJournalCategories,
          },
          'msgs': {
            'type': 'array',
            'items': {'type': 'integer'},
            'description': 'The #numbered message positions it came from.',
          },
        },
        'required': ['content'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'revise_memory',
      'description':
          'Rewrite an existing journal entry (and optionally how it feels '
          'now) instead of adding a duplicate.',
      'parameters': {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'integer',
            'description': 'The [N] handle of the entry to revise.',
          },
          'content': {'type': 'string'},
          'feeling': {
            'type': 'string',
            'description': 'Optional new feeling, one lowercase word.',
          },
        },
        'required': ['id', 'content'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'retire_memory',
      'description': 'Remove a journal entry that became wrong or irrelevant.',
      'parameters': {
        'type': 'object',
        'properties': {
          'id': {'type': 'integer'},
        },
        'required': ['id'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'pin_memory',
      'description': 'Pin a defining journal entry so it never fades.',
      'parameters': {
        'type': 'object',
        'properties': {
          'id': {'type': 'integer'},
        },
        'required': ['id'],
      },
    },
  },
  {
    'type': 'function',
    'function': {
      'name': 'write_recap',
      'description':
          'Write the updated "where things stand now" recap — present '
          'tense, your voice.',
      'parameters': {
        'type': 'object',
        'properties': {
          'text': {'type': 'string'},
        },
        'required': ['text'],
      },
    },
  },
];

/// Parse tool calls into the same validated ([JournalOp] list, recap) the
/// XML transport produces. Unknown tools and invalid ops are dropped; the
/// last write_recap wins.
(List<JournalOp>, String?) parseJournalToolCalls(List<LlmToolCall> calls) {
  final ops = <JournalOp>[];
  String? recap;

  int? intArg(Map<String, dynamic> args, String key) {
    final v = args[key];
    if (v is int) return v;
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  // Tolerant string read: a local model can put a number/object where text
  // belongs, and `as String?` THROWS on a non-null non-String — aborting the
  // whole multi-owner pass. Coerce instead (realismToolCallToJson does the
  // same).
  String? strArg(Map<String, dynamic> args, String key) {
    final v = args[key];
    if (v == null) return null;
    return v is String ? v : '$v';
  }

  for (final call in calls) {
    final args = call.arguments;
    switch (call.name) {
      case 'add_memory':
        var text = (strArg(args, 'content') ?? '').trim();
        if (text.isEmpty) continue;
        if (text.length > kJournalMemoryMaxChars) {
          text = text.substring(0, kJournalMemoryMaxChars).trim();
        }
        final msgs = args['msgs'];
        ops.add(
          JournalOp(
            action: JournalOpAction.add,
            category: _normalizeCategory(strArg(args, 'category')),
            sourcePositions: msgs is List
                ? msgs
                      .map((m) => m is int ? m : int.tryParse('$m'))
                      .whereType<int>()
                      .toList()
                : _parsePositions(msgs is String ? msgs : null),
            text: text,
          ),
        );
        break;
      case 'revise_memory':
        final handle = intArg(args, 'id');
        var text = (strArg(args, 'content') ?? '').trim();
        if (handle == null || text.isEmpty) continue;
        if (text.length > kJournalMemoryMaxChars) {
          text = text.substring(0, kJournalMemoryMaxChars).trim();
        }
        final feeling = (strArg(args, 'feeling') ?? '').trim().toLowerCase();
        ops.add(
          JournalOp(
            action: JournalOpAction.revise,
            handle: handle,
            feeling: feeling.isEmpty ? null : feeling,
            text: text,
          ),
        );
        break;
      case 'retire_memory':
      case 'pin_memory':
        final handle = intArg(args, 'id');
        if (handle == null) continue;
        ops.add(
          JournalOp(
            action: call.name == 'pin_memory'
                ? JournalOpAction.pin
                : JournalOpAction.retire,
            handle: handle,
          ),
        );
        break;
      case 'write_recap':
        final text = (strArg(args, 'text') ?? '').trim();
        if (text.isNotEmpty) recap = text;
        break;
      default:
        continue; // unknown tool — drop
    }
  }
  return (ops, recap);
}
