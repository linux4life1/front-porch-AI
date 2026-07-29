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
/// eval, the scene-time/posture eval, the expression reclassifier, and the
/// Scene Guest cast detector).
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

import 'package:front_porch_ai/services/llm_service.dart' show LlmToolCall;
import 'package:front_porch_ai/utils/emotion_labels.dart';

/// Tool names (also referenced by the prompts' tools-mode instruction).
const String kRelationshipTool = 'report_relationship';
const String kEmotionalTool = 'report_emotional_state';
const String kNarrativeTool = 'report_narrative';
const String kOneShotTool = 'report_realism';
const String kNeedsImpactTool = 'report_needs_impact';
const String kSceneTimeTool = 'report_scene_time';
const String kExpressionTool = 'report_expression_label';
const String kCastDetectTool = 'report_detected_character';

Map<String, dynamic> _intField(String description) => {
  'type': 'integer',
  'description': description,
};
Map<String, dynamic> _strField(String description) => {
  'type': 'string',
  'description': description,
};

// Field descriptions stay one-line summaries — the full rubric (ranges,
// anchors, the "real person" rule) lives in the prompt body, which is
// byte-identical between the tools and text transports.
final Map<String, Map<String, dynamic>> _relationshipFields = {
  'relationship_delta': _intField(
    'Warmth shift this turn, by the character\'s own standards.',
  ),
  'bond_reason': _strField(
    'One brief in-character thought explaining the shift, or "none".',
  ),
  'trust_delta': _intField('Trust shift from the user\'s behavior this turn.'),
  'trust_reason': _strField(
    'One brief in-character thought about why, or "none".',
  ),
};

final Map<String, Map<String, dynamic>> _emotionalFields = {
  'emotion': _strField('The dominant emotional state, one nuanced word.'),
  'emotion_intensity': {
    'type': 'string',
    'enum': ['mild', 'moderate', 'strong'],
  },
  'arousal_delta': _intField(
    'Physical desire shift this turn (only when asked for in the prompt).',
  ),
};

final Map<String, Map<String, dynamic>> _narrativeFields = {
  'proposed_objective': _strField(
    'A goal the character independently wants to pursue, or "none".',
  ),
  'fixation_topic': _strField(
    'An intrusive thought the character keeps returning to, or "none".',
  ),
};

final Map<String, Map<String, dynamic>> _oneShotFields = {
  ..._relationshipFields,
  ..._emotionalFields,
  'posture': _strField(
    'Current physical position and location (brief phrase), or "none".',
  ),
  // Scene-time fields ride the fused call so one-shot mode needs no separate
  // per-turn time eval (strict one-shot vs normal parity — same fields, same
  // clamp/floor/backstop applied by TimeService).
  'minutes_elapsed': _intField(
    'In-story minutes the latest exchange took (0-180; 0 only mid-action).',
  ),
  'new_day': {
    'type': 'boolean',
    'description':
        'True ONLY if the conversation explicitly transitioned to the next '
        'day (slept, woke up, scene break). Merely mentioning yesterday or '
        'tomorrow does NOT count.',
  },
  ..._narrativeFields,
  'reason': _strField(
    'One brief sentence naming the key relationship change, or "none".',
  ),
};

Map<String, dynamic> _tool(
  String name,
  String description,
  Map<String, Map<String, dynamic>> fields,
  List<String> required,
) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': description,
    'parameters': {
      'type': 'object',
      'properties': fields,
      'required': required,
    },
  },
};

final List<Map<String, dynamic>> kRelationshipEvalTools = [
  _tool(
    kRelationshipTool,
    'Report how this exchange landed for the character (bond + trust).',
    _relationshipFields,
    const ['relationship_delta', 'trust_delta'],
  ),
];

final List<Map<String, dynamic>> kEmotionalEvalTools = [
  _tool(
    kEmotionalTool,
    'Report what the character truly feels right now.',
    _emotionalFields,
    const ['emotion', 'emotion_intensity'],
  ),
];

final List<Map<String, dynamic>> kNarrativeEvalTools = [
  _tool(
    kNarrativeTool,
    'Report what the character now wants and what lingers with them.',
    _narrativeFields,
    const [],
  ),
];

final List<Map<String, dynamic>> kOneShotEvalTools = [
  _tool(
    kOneShotTool,
    'Report the full realism evaluation for this exchange in one call.',
    _oneShotFields,
    const ['relationship_delta', 'trust_delta', 'emotion', 'emotion_intensity'],
  ),
];

final Map<String, Map<String, dynamic>> _needsImpactFields = {
  'activities': {
    'type': 'array',
    'items': {'type': 'string'},
    'description': 'Activity tags for the scene (e.g. "sexual", "messy").',
  },
  'intensity': _intField('Scene intensity, 1-10.'),
  for (final k in const [
    'hunger',
    'energy',
    'hygiene',
    'fun',
    'social',
    'bladder',
    'comfort',
  ])
    '${k}_delta': _intField('Net signed effect on $k.'),
  'reason': _strField('Brief grounded reason for the deltas.'),
  'is_climax': {
    'type': 'boolean',
    'description':
        'True ONLY when the character themselves reaches climax in this scene.',
  },
  'refractory_turns': _intField(
    'Post-climax cooldown turns (3-7) when is_climax is true, else 0.',
  ),
};

final List<Map<String, dynamic>> kNeedsImpactEvalTools = [
  _tool(
    kNeedsImpactTool,
    'Report the scene\'s net signed effects on the character\'s needs.',
    _needsImpactFields,
    const [
      'hunger_delta',
      'energy_delta',
      'hygiene_delta',
      'fun_delta',
      'social_delta',
      'bladder_delta',
      'comfort_delta',
      'reason',
    ],
  ),
];

final Map<String, Map<String, dynamic>> _sceneTimeFields = {
  'minutes_elapsed': _intField(
    'In-story minutes the latest exchange took (0-180; 0 only mid-action).',
  ),
  'new_day': {
    'type': 'boolean',
    'description':
        'True ONLY if the conversation explicitly transitioned to the next '
        'day (slept, woke up, scene break). Merely mentioning yesterday or '
        'tomorrow does NOT count.',
  },
  'posture': _strField(
    'Current physical position and location (brief phrase), or "none".',
  ),
};

final List<Map<String, dynamic>> kSceneTimeEvalTools = [
  _tool(
    kSceneTimeTool,
    'Report the scene-time verdict and the character\'s current posture.',
    _sceneTimeFields,
    const ['posture'],
  ),
];

final Map<String, Map<String, dynamic>> _expressionFields = {
  'label': {
    'type': 'string',
    'enum': EmotionLabels.all,
    'description': 'The standard expression label the emotion maps to.',
  },
};

final List<Map<String, dynamic>> kExpressionEvalTools = [
  _tool(
    kExpressionTool,
    'Classify the emotion into exactly one standard expression label.',
    _expressionFields,
    const ['label'],
  ),
];

final Map<String, Map<String, dynamic>> _castDetectFields = {
  'name': _strField(
    'The recurring named character\'s proper name. OMIT this field entirely '
    'when there is no such character.',
  ),
  'descriptor': _strField('A short phrase describing who they are.'),
};

final List<Map<String, dynamic>> kCastDetectEvalTools = [
  _tool(
    kCastDetectTool,
    'Report a newly-introduced recurring named side character, or call with '
    'no name when there is none.',
    _castDetectFields,
    const [],
  ),
];

/// The whitelisted keys per tool (anything else the model invents is
/// dropped, mirroring how the regex extractors ignore unknown text keys).
final Map<String, Map<String, Map<String, dynamic>>> _fieldsByTool = {
  kRelationshipTool: _relationshipFields,
  kEmotionalTool: _emotionalFields,
  kNarrativeTool: _narrativeFields,
  kOneShotTool: _oneShotFields,
  kNeedsImpactTool: _needsImpactFields,
  kSceneTimeTool: _sceneTimeFields,
  kExpressionTool: _expressionFields,
  kCastDetectTool: _castDetectFields,
};

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
          if (v is List) {
            out[entry.key] = v.map((e) => e.toString()).toList();
          } else if (v.toString().trim().isNotEmpty) {
            out[entry.key] = [v.toString().trim()];
          }
          break;
        default:
          final s = v.toString().trim();
          if (s.isNotEmpty) out[entry.key] = s;
      }
    }
    if (toolName == kCastDetectTool && (out['name'] as String? ?? '').isEmpty) {
      return '{"name":null}'; // matched call, no name → explicit no-detection
    }
    if (out.isNotEmpty) return jsonEncode(out);
  }
  return null;
}
