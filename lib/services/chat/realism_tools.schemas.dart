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

part of 'realism_tools.dart';

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
/// question ("where did this reply leave them") is unanswerable before the
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
