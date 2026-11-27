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

// The Afterglow tool schemas (recovery overhaul PR 5): the climax check and
// the fused reply-facts call that carries it. `user_climaxed` made the
// shared schema file cross the 500-line bar, so these blocks moved here —
// verbatim except the new field. The registry stays in
// realism_tool_schemas.dart (it imports this leaf back), because
// [realismToolFieldsByTool] is what makes the tools transport work at all:
// an unregistered tool converts to null and falls back to text on every
// tools-capable backend, silently, forever. Both entries remain registered
// there by construction.

import 'package:front_porch_ai/services/chat/realism_tools/realism_tool_names.dart';
import 'package:front_porch_ai/services/chat/realism_tools/realism_tool_schemas.dart';

// The field/tool builders, mirrored from realism_tool_schemas.dart's
// private ones (file-private helpers cannot cross a library boundary). The
// shapes are pinned field-for-field by the schema tests on both tools.
Map<String, dynamic> _intField(String description) => {
  'type': 'integer',
  'description': description,
};
Map<String, dynamic> _strField(String description) => {
  'type': 'string',
  'description': description,
};

/// The desire fields of the emotional judge (and so of the one-shot judge):
/// Lust's delta and reason, moved here verbatim from realism_tool_schemas.dart
/// so Heat's `contact` (docs/design/heat-meter.md) could join them without
/// that file crossing 500 lines.
///
/// `contact` is a plain string with no `enum`, on purpose: the text salvage
/// (`usableEvalJsonText`) rejects the WHOLE emotional answer when an enum
/// field holds any other word, and a model writing "Teasing" or "light"
/// would cost the turn its mood and Lust. `HeatMeter.parseContact` reads it
/// leniently instead. Optional like `arousal_delta`: missing moves nothing.
final Map<String, Map<String, dynamic>> kDesireToolFields = {
  'arousal_delta': _intField(
    'Physical desire shift this turn (only when asked for in the prompt).',
  ),
  'arousal_reason': _strField(
    'One brief in-character thought explaining the desire shift, or "none".',
  ),
  'contact': _strField(
    'Sexual contact the character receives this turn: none, teasing, '
    'intimate or intense (only when asked for in the prompt).',
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

/// Afterglow's climax check (ClimaxEval). Registered through
/// [realismToolFieldsByTool] in realism_tool_schemas.dart — see the header.
final Map<String, Map<String, dynamic>> kClimaxFields = {
  'is_climax': {
    'type': 'boolean',
    'description': 'True ONLY when the character themselves reached climax.',
  },
  'refractory_turns': _intField(
    'Cooldown turns (0-12, 0 = no cooldown needed) when is_climax is '
    'true, else 0.',
  ),
  // PR 5: the rubric already refuses to call ONLY-a-partner-climax a
  // character climax — recover WHICH partner for free on the same call.
  'user_climaxed': {
    'type': 'boolean',
    'description':
        'True only if the user also climaxed in this reply. Judge it '
        'independently of the character answer.',
  },
};

final List<Map<String, dynamic>> kClimaxEvalTools = [
  _tool(
    kClimaxToolName,
    'Report whether the character reached climax.',
    kClimaxFields,
    // ALL required — the lesson from the needs tool: a model fills in what
    // the schema demands and skips what it does not, so an optional
    // is_climax was never emitted and detection was silently off on every
    // tools-capable backend.
    const ['is_climax', 'refractory_turns', 'user_climaxed'],
  ),
];

/// The fused post-generation reply-facts call (ReplyFactsEval): climax +
/// inventory + posture in ONE tool. Field definitions are REUSED from the
/// standalone tools so the fused and standalone lanes cannot drift;
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
/// always DEFINED (the registry is a fixed contract); only the `required`
/// list varies.
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
      if (askClimax) ...['is_climax', 'refractory_turns', 'user_climaxed'],
      if (askPockets) 'inventory_ops',
      if (askPosture) 'posture',
    ],
  ),
];
