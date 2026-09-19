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

/// Engine eval tools — the tool-calling transport for every structured eval
/// whose downstream consumes flat-JSON text (the journal_ops/growth_ops
/// pattern applied to the Realism Engine's judge calls, the needs-impact
/// eval, the scene-time eval, the posture pass, the expression
/// reclassifier, and the Scene Guest cast detector).
///
/// Design: tools are a RELIABLE WAY TO OBTAIN THE SAME JSON the evals have
/// always parsed. A successful tool call is converted by
/// [realismToolCallToJson] into the exact flat-JSON text the prompt's text
/// mode requests, and then flows through the UNCHANGED downstream pipeline —
/// batch collection, the Director/verifier, the regex/JSON extractors, and
/// the delta appliers. Nothing about parsing, clamping, parity (one-shot vs
/// multi-call, 1:1 vs group), or side effects moves; only the fragile step —
/// fishing valid JSON out of a free-text stream — gains a typed lane.
///
/// Backends that can't (or won't) speak tools fall back to the streaming
/// text path via the shared ToolTransportProbe (one probe per backend+model
/// identity per run, shared with the Journal and Growth passes).
library;

import 'dart:convert';

import 'package:front_porch_ai/services/services.dart' show LlmToolCall;
import 'package:front_porch_ai/utils/utils.dart';

part 'realism_tools.schemas.dart';

/// Tool names (also referenced by the prompts' tools-mode instruction).
const String kRelationshipTool = 'report_relationship';
const String kEmotionalTool = 'report_emotional_state';
const String kNarrativeTool = 'report_narrative';
const String kOneShotTool = 'report_realism';
const String kNeedsImpactTool = 'report_needs_impact';
const String kSceneTimeTool = 'report_scene_time';
const String kExpressionTool = 'report_expression_label';
const String kCastDetectTool = 'report_detected_character';
const String kClimaxToolName = 'report_climax';
const String kPocketsToolName = 'report_inventory';
const String kReplyFactsToolName = 'report_reply_facts';
const String kWithUserToolName = 'report_with_user';

Map<String, dynamic> _intField(String description) => {
  'type': 'integer',
  'description': description,
};
Map<String, dynamic> _strField(String description) => {
  'type': 'string',
  'description': description,
};

/// The whitelisted keys per tool (anything else the model invents is
/// dropped, mirroring how the regex extractors ignore unknown text keys).
final Map<String, Map<String, Map<String, dynamic>>> _fieldsByTool = {
  kRelationshipTool: _relationshipFields,
  kEmotionalTool: _emotionalFields,
  kNarrativeTool: _narrativeFields,
  kOneShotTool: {..._oneShotFields, 'today_sentence': _todaySentenceField},
  kNeedsImpactTool: _needsImpactFields,
  kSceneTimeTool: {..._sceneTimeFields, 'today_sentence': _todaySentenceField},
  kExpressionTool: _expressionFields,
  kCastDetectTool: _castDetectFields,
  kClimaxToolName: kClimaxFields,
  kPocketsToolName: kPocketsFields,
  kReplyFactsToolName: kReplyFactsFields,
  kWithUserToolName: kWithUserFields,
};

/// Is [toolName] known to the converter?
///
/// Exposed for the registry guard: an unregistered tool makes
/// [realismToolCallToJson] return null on every call, so the feature silently
/// uses the text transport forever. Pockets shipped that way. Cheap to assert,
/// impossible to notice otherwise.
bool toolIsRegistered(String toolName) => _fieldsByTool.containsKey(toolName);

/// Convert the first matching tool call into the canonical flat-JSON text
/// the text transport would have produced — the single normalization point
/// that lets everything downstream stay byte-identical. Returns null when no
/// usable call is present (caller then salvages the plain text or falls back).
///
/// Forgiving by design (the journal/growth tolerance rules): unknown tools
/// are skipped, unknown argument keys dropped, ints accepted as num or
/// numeric string, bools as bool or "true"/"false", arrays coerced to string
/// lists, everything else coerced to string. An empty sanitized map is a
/// failure (null), never an empty JSON object — EXCEPT the cast-detect tool,
/// where a matched call without a name IS the "no detection" answer and
/// yields the canonical `{"name":null}` its parser expects.
String? realismToolCallToJson(String toolName, List<LlmToolCall> calls) {
  final fields = _fieldsByTool[toolName];
  if (fields == null) return null;
  for (final call in calls) {
    if (call.name != toolName) continue;
    final out = <String, dynamic>{};
    for (final entry in call.arguments.entries) {
      final spec = fields[entry.key];
      if (spec == null) continue; // unknown key — drop
      final v = entry.value;
      if (v == null) continue;
      switch (spec['type']) {
        case 'integer':
          final n = v is num ? v.round() : int.tryParse(v.toString().trim());
          if (n != null) out[entry.key] = n;
          break;
        case 'boolean':
          if (v is bool) {
            out[entry.key] = v;
          } else {
            final s = v.toString().trim().toLowerCase();
            if (s == 'true' || s == 'false') out[entry.key] = s == 'true';
          }
          break;
        case 'array':
          // An array of OBJECTS passes through intact; only arrays of scalars
          // get stringified.
          //
          // The blanket `e.toString()` below was written when every array here
          // was a list of strings (`activities`). Pockets then declared
          // `inventory_ops` as a list of objects, and stringifying those would
          // produce Dart map literals — `{op: pickup, item: keys}` — which are
          // not JSON, do not decode, and are silently dropped by the op parser.
          // The feature was saved from that only because its tool was never
          // registered below, so the whole call converted to null and fell back
          // to text. Registering it without this branch would have turned a
          // working fallback into silent data loss.
          final itemType = (spec['items'] as Map?)?['type'];
          if (v is List && itemType == 'object') {
            out[entry.key] = [
              for (final e in v)
                if (e is Map) Map<String, dynamic>.from(e),
            ];
          } else if (v is List) {
            out[entry.key] = v.map((e) => e.toString()).toList();
          } else if (v.toString().trim().isNotEmpty) {
            out[entry.key] = [v.toString().trim()];
          }
          break;
        default:
          final s = v.toString().trim();
          // Empty today_sentence is abandon (same clamp as the JSON path).
          // Other string fields still treat empty as omit.
          if (s.isNotEmpty || entry.key == 'today_sentence') {
            out[entry.key] = s;
          }
      }
    }
    if (toolName == kCastDetectTool && (out['name'] as String? ?? '').isEmpty) {
      return '{"name":null}'; // matched call, no name → explicit no-detection
    }
    if (out.isNotEmpty) return jsonEncode(out);
  }
  return null;
}
