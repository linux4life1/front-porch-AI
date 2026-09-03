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
  // Present in the schema unconditionally even though the PROMPT only asks for
  // it when the character has ambitions: a tool schema is a fixed contract
  // negotiated once per backend identity, not per turn, and every field here
  // is optional. A character with no ambitions is simply never told to fill it
  // in, and the parse treats absent and "none" identically.
  'serves_ambition': _strField(
    'The number of the ambition the proposed objective is a step toward, or '
    '"none". Only asked for when the character has ambitions.',
  ),
  'fixation_topic': _strField(
    'An intrusive thought the character keeps returning to, or "none".',
  ),
};

final Map<String, Map<String, dynamic>> _oneShotFields = {
  ..._relationshipFields,
  ..._emotionalFields,
  // No `posture`: it moved to its own POST-generation pass on 2026-08-08
  // (see kSceneTimeEvalTools below). One-shot fuses the PRE-generation
  // judges, and posture stopped being one of those.
  // No scene-time fields: the clock decide is post-generation now (same
  // time-only call as the multi-call path). Asking here would double-count.
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

/// Wire list for the three prefix-sharing pre-generation judges.
///
/// llama.cpp / Kobold jinja injects `tools` near the start of the rendered
/// prompt. Three different one-tool lists tokenize three different prefixes
/// and silently defeat `judgePrefix` + `_fireStaggeredRealismEvals`. One
/// identical list + a named `tool_choice` keeps the templated prefix
/// cacheable; `realismToolCallToJson` still filters by the expected name.
final List<Map<String, dynamic>> kJudgeEvalTools = [
  ...kRelationshipEvalTools,
  ...kEmotionalEvalTools,
  ...kNarrativeEvalTools,
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
  // 'activities' and 'intensity' were REMOVED 2026-08-10: nothing in the
  // app has ever read either from the response (the applier consumes the
  // seven deltas + reason, full stop), the text prompt stopped asking in
  // the Tier-1 sweep — but their survival HERE meant every tools-transport
  // needs call still invited the model to fill them, and it did, paying
  // output tokens for fields that went straight to the void (visible in
  // the maintainer's own log: "activities":["sleeping","washing",…]).
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
      // CLIMAX MOVED OUT (2026-08-07). It used to be required here, and the
      // comment below records why — a lesson worth keeping, because the same
      // trap applies to the arousal tool it moved to.
      //
      // It moved because Afterglow depended on it, and this eval early-returns
      // unless BOTH Needs and the Realism Engine are on. Needs is off on most
      // cards (CharacterCard.needsSimEnabled defaults false), so Afterglow
      // silently did nothing for most users who switched it on — while the
      // Porch Life row told them its one dependency (the engine) was met.
      // It now has its own post-generation pass (ClimaxEval) — post-gen
      // because the question is about the REPLY, and standalone so it answers
      // to the Realism Engine and the Afterglow switch and nothing else.
      //
      // The kept lesson: is_climax MUST be required. A model answering a tool call fills in what
      // the schema demands and skips what it does not, and this field was
      // optional — so orgasm detection was silently off on every tools-capable
      // backend. Observed live: the model returned exactly these eight fields
      // and nothing else, with a reason reading "Violet experiences her first
      // orgasm ever ... an overwhelming first climax". It had understood the
      // scene completely; it just never emitted the key, so the refractory
      // never started and the Lust bar stayed pinned at 100/100.
      //
      // This is the SAME failure the text path already learned (see the comment
      // on climaxGuidance in llm_eval_engine.dart: a model "won't guess at an
      // undefined field"). The tools transport re-created it by a different
      // route — the field was defined, but optional. Forcing an explicit
      // true/false is that lesson expressed in schema. refractory_turns rides
      // along because it is meaningless to answer one without the other.
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

/// The POST-generation posture pass (TimeService's `postureOnly` mode). It
/// keeps the full field set because `posture` is the only REQUIRED one and a
/// model that volunteers the others costs nothing — but posture is the only
/// field that pass reads. Until 2026-08-08 this was the fused pre-generation
/// scene-time+posture schema; posture moved out of that call because the
/// question ("where did this reply leave her") is unanswerable before the
/// reply exists.
final List<Map<String, dynamic>> kSceneTimeEvalTools = [
  _tool(
    kSceneTimeTool,
    'Report the character\'s current physical position and stance.',
    _sceneTimeFields,
    const ['posture'],
  ),
];

/// The per-turn clock advance — BOTH drivers, the engine's and the standalone
/// one (TimeService's `timeOnly` mode is only about how much scene framing the
/// PROMPT carries; the schema is one). Deliberately the SAME tool name as the
/// posture variant, so [realismToolCallToJson] and every parse step downstream
/// are literally the same code path; it just drops `posture`. Field
/// definitions are reused from [_sceneTimeFields] rather than restated, so the
/// two variants cannot drift.
final List<Map<String, dynamic>> kSceneTimeOnlyEvalTools = [
  _tool(
    kSceneTimeTool,
    'Report how much in-story time the latest exchange took.',
    {
      'minutes_elapsed': _sceneTimeFields['minutes_elapsed']!,
      'new_day': _sceneTimeFields['new_day']!,
    },
    const ['minutes_elapsed'],
  ),
];

final Map<String, dynamic> _todaySentenceField = _strField(
  'One sentence of what they are doing or planning today, or "none".',
);

/// Scene-time schema when the planner is on. `today_sentence` is REQUIRED so
/// small locals fill it (empty / "none" abandons; omit is the text-path keep).
final List<Map<String, dynamic>> kSceneTimeOnlyEvalToolsWithToday = [
  _tool(
    kSceneTimeTool,
    'Report how much in-story time the latest exchange took, and today\'s plan.',
    {
      'minutes_elapsed': _sceneTimeFields['minutes_elapsed']!,
      'new_day': _sceneTimeFields['new_day']!,
      'today_sentence': _todaySentenceField,
    },
    const ['minutes_elapsed', 'today_sentence'],
  ),
];

/// Planner-on one-shot is the same schema as planner-off: Today is written
/// by the post-generation time-only call, not the fused pre-gen judges.
final List<Map<String, dynamic>> kOneShotEvalToolsWithToday = kOneShotEvalTools;

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

/// Afterglow's climax check (ClimaxEval). Declared HERE rather than in the
/// leaf because [_fieldsByTool] below is what makes the tools transport work
/// at all — an unregistered tool makes [realismToolCallToJson] return null,
/// so the call silently falls back to text on every backend, forever. One
/// definition, registered by construction.
final Map<String, Map<String, dynamic>> kClimaxFields = {
  'is_climax': {
    'type': 'boolean',
    'description': 'True ONLY when the character themselves reached climax.',
  },
  'refractory_turns': _intField(
    'Cooldown turns (3-7) when is_climax is true, else 0.',
  ),
};

/// Own pass — not fused with posture. See [WithUserEval].
final Map<String, Map<String, dynamic>> kWithUserFields = {
  'with_user': {
    'type': 'boolean',
    'description':
        'True ONLY when the character and the user are physically in the '
        'same place right now. Phone / their own home / another room = false.',
  },
};

final List<Map<String, dynamic>> kWithUserEvalTools = [
  _tool(
    kWithUserToolName,
    'Report whether the character is physically with the user.',
    kWithUserFields,
    const ['with_user'],
  ),
];

final List<Map<String, dynamic>> kClimaxEvalTools = [
  _tool(
    kClimaxToolName,
    'Report whether the character reached climax.',
    kClimaxFields,
    // BOTH required — the lesson from the needs tool: a model fills in what
    // the schema demands and skips what it does not, so an optional is_climax
    // was never emitted and detection was silently off on every tools-capable
    // backend.
    const ['is_climax', 'refractory_turns'],
  ),
];

/// Pockets & Wardrobe (PocketsEval). Declared here for the same reason the
/// climax fields are: [_fieldsByTool] is what makes the tools transport work,
/// and an unregistered tool converts to null and falls back to text forever,
/// silently. Pockets shipped that way — its calls never once used tools.
final Map<String, Map<String, dynamic>> kPocketsFields = {
  'inventory_ops': {
    'type': 'array',
    'items': {'type': 'object'},
    'description': 'Every change this reply made to worn/carried items.',
  },
};

/// The fused post-generation reply-facts call (ReplyFactsEval): climax +
/// inventory + posture in ONE tool. Field definitions are REUSED from the
/// standalone tools above so the fused and standalone lanes cannot drift;
/// which fields are REQUIRED is computed per call from which features are
/// live ([kReplyFactsToolsFor]) — the is_climax lesson applied to a composed
/// schema: a model fills in what the schema demands and skips what it does
/// not, so a live feature's fields must be demanded and a disabled feature's
/// must not.
final Map<String, Map<String, dynamic>> kReplyFactsFields = {
  ...kClimaxFields,
  ...kPocketsFields,
  'posture': _strField(
    'Current physical position and location (brief phrase), or "none".',
  ),
};

/// The reply-facts schema for THIS turn's live feature set. Every field is
/// always DEFINED (the registry below is a fixed contract); only the
/// `required` list varies.
List<Map<String, dynamic>> kReplyFactsToolsFor({
  required bool askClimax,
  required bool askPockets,
  required bool askPosture,
}) => [
  _tool(
    kReplyFactsToolName,
    'Report the scene facts this reply changed (climax / inventory / '
    'posture).',
    kReplyFactsFields,
    [
      if (askClimax) ...['is_climax', 'refractory_turns'],
      if (askPockets) 'inventory_ops',
      if (askPosture) 'posture',
    ],
  ),
];

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
