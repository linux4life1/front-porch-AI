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

/// Native tool calls for the structured Studio stages.
///
/// Tool calling is the primary transport for every planning reply that is
/// a record or a list of records (reviews, continuity checks, edits, beats,
/// scenes, acts, sequences, archives, Director plans). Each tool's schema
/// mirrors the `<response>` tag template its prompt asks for, and
/// [StoryTools.toTags] turns the call's arguments back into that tag text,
/// so the tag readers in studio_parse / story_review / story_director stay
/// the single parser. Tags remain the backup for a host that refuses the
/// tool. Prose stays text: it streams.
///
/// One shared list ([StoryTools.definitions]) is sent on every call with
/// `tool_choice` naming the function, so a KoboldCpp jinja cache keeps its
/// prefix (CLAUDE.md, eval transport).
abstract final class StoryTools {
  // ── Schemas ─────────────────────────────────────────────────────────

  static final review = StoryToolSpec(
    name: 'report_review',
    description:
        'Report the review verdict: findings, PASS or FAIL, and the exact '
        'problems when failing.',
    properties: {
      'critique_analysis': _str('Brief, specific findings.'),
      'status': _enum(['PASS', 'FAIL']),
      'deviation_reasons': _list(
        'reason',
        _str('Only when failing: the exact problem and how to fix it.'),
      ),
    },
    required: ['status'],
  );

  static final continuity = StoryToolSpec(
    name: 'report_continuity',
    description:
        'Report continuity problems between the new passage and what came '
        'before, and whether it passes.',
    properties: {
      'issues': _list('issue', {
        'type': 'object',
        'properties': {
          'severity': _enum(['CRITICAL', 'MAJOR', 'MINOR']),
          'description': _str('What is wrong.'),
          'location': _str('Where in the passage.'),
          'fix_suggestion': _str('The smallest change that fixes it.'),
        },
        'required': ['severity', 'description'],
      }),
      'status': _enum(['PASS', 'FAIL']),
    },
    required: ['status'],
  );

  static final edits = StoryToolSpec(
    name: 'report_edits',
    description:
        'Patch the passage: each edit quotes words exactly as written and '
        'what they become.',
    properties: {
      'edits': _list('edit', {
        'type': 'object',
        'properties': {
          'find': _str(
            'Words copied character for character from the passage — '
            'enough to be unique, as few as possible.',
          ),
          'replace': _str('What they become.'),
        },
        'required': ['find', 'replace'],
      }),
    },
    required: ['edits'],
  );

  static final beats = StoryToolSpec(
    name: 'plan_beats',
    description: 'The beats of this scene, in order.',
    properties: {
      'beats': _list('beat', {
        'type': 'object',
        'properties': {
          'beat_type': _str('Action, Reaction, Dialogue, Revelation…'),
          'initiator': _str('Who acts.'),
          'reactor': _str('Who reacts.'),
          'action': _str('What the initiator does.'),
          'reaction': _str('What the reactor does.'),
          'tactic': _str('How the initiator plays it.'),
          'subtext': _str('What is not said.'),
          'anchor': _str('The concrete image or line this beat turns on.'),
        },
        'required': ['beat_type', 'action'],
      }),
    },
    required: ['beats'],
  );

  static final scenes = StoryToolSpec(
    name: 'plan_scenes',
    description: 'The scenes of this sequence, in order.',
    properties: {
      'scenes': _list('scene', {
        'type': 'object',
        'properties': {
          'title': _str('Scene title.'),
          'valence_score': _int('−10 to +10.'),
          'valence_running_sum': _int('Running sum so far.'),
          'scene_type': _enum(['Action', 'Reaction']),
          'pov_character': _str('Whose eyes.'),
          'characters_present': _list('character', _str('A name.')),
          'threads_advanced': _list('thread', _str('A thread id.')),
          'setting': _str('Where.'),
          'narrative_lens': _str('A lens id, when lenses are on.'),
          'scene_objective': _str('What the scene must achieve.'),
          'description': _str('What happens.'),
          'value_shift': {
            'type': 'object',
            'properties': {
              'start_state': _str('Where the value starts.'),
              'end_state': _str('Where it ends.'),
            },
          },
          'plot_commitments': _str('Promises the scene makes.'),
          'entrance_conditions': _str('What must be true going in.'),
          'exit_conditions': _str('What is true coming out.'),
        },
        'required': ['title', 'description'],
      }),
      'new_characters': _list('character', _namedCharacter),
    },
    required: ['scenes'],
  );

  static final acts = StoryToolSpec(
    name: 'plan_acts',
    description: 'The three acts.',
    properties: {
      'acts': _list('act', {
        'type': 'object',
        'properties': {
          'number': _int('1, 2 or 3.'),
          'title': _str('Act title.'),
          'act_mandate': _str('What the act must do, by heading.'),
          'world_building_developments': _str('What the world reveals.'),
          'threads': _list('thread', _str('A thread id.')),
          'knots': _list('knot', {
            'type': 'object',
            'properties': {
              'description': _str('The convergence.'),
              'interaction': _str('Who meets whom and why it matters.'),
            },
          }),
          'thread_statuses_at_end': _str('Each thread\'s state at the break.'),
        },
        'required': ['number', 'title', 'act_mandate'],
      }),
    },
    required: ['acts'],
  );

  static final sequences = StoryToolSpec(
    name: 'plan_sequences',
    description: 'The eight sequences across the three acts.',
    properties: {
      'sequences': _list('sequence', {
        'type': 'object',
        'properties': {
          'number': _int('1 to 8.'),
          'parent_act': _int('1, 2 or 3.'),
          'title': _str('Sequence title.'),
          'sequence_function': _str('Its job in the arc.'),
          'dramatic_question': _str('The short-term question.'),
          'description': _str('What happens.'),
          'threads_advanced': _list('thread', _str('A thread id.')),
          'sequence_climax': _str('How it peaks.'),
          'ending_hook': _str('What pulls into the next.'),
        },
        'required': ['number', 'parent_act', 'title'],
      }),
    },
    required: ['sequences'],
  );

  static final archive = StoryToolSpec(
    name: 'archive_scene',
    description:
        'Record what the scene changed: its summary, hard facts, how people '
        'now feel about each other, cast and lore updates.',
    properties: {
      'scene_summary': _str('Two or three sentences.'),
      'continuity_facts': _list('fact', {
        'type': 'object',
        'properties': {
          'category': _enum(['Body', 'Object', 'Promise', 'Place', 'Fact']),
          'key': _str('What.'),
          'detail': _str('Is.'),
          'character': _str('Who or where it belongs to.'),
        },
        'required': ['key', 'detail'],
      }),
      'relationship_updates': _list('update', {
        'type': 'object',
        'properties': {
          'from': _str('Who feels.'),
          'to': _str('About whom.'),
          'new_feeling': _str('One or two words.'),
          'note': _str('Two or three words.'),
          'hidden_tension': _str('The unspoken.'),
          'trust_level': _int('0 to 10.'),
          'trigger': _str('What moved it.'),
        },
        'required': ['from', 'to', 'new_feeling'],
      }),
      'cast_updates': _list('update', {
        'type': 'object',
        'properties': {
          'name': _str('Who.'),
          'story_events': _str('What happened to them.'),
          'goals': _str('What they want now.'),
        },
      }),
      'new_characters': _list('character', _namedCharacter),
      'lore_updates': _list('entry', {
        'type': 'object',
        'properties': {'topic': _str('Topic.'), 'detail': _str('Detail.')},
      }),
    },
    required: ['scene_summary'],
  );

  static final sequenceSummary = StoryToolSpec(
    name: 'summarize_sequence',
    description: 'The story so far, after this sequence.',
    properties: {'story_so_far': _str('A rolling summary.')},
    required: ['story_so_far'],
  );

  static final director = StoryToolSpec(
    name: 'plan_director',
    description:
        'Turn the directive into a plan of typed changes the writer can '
        'tick and apply.',
    properties: {
      'evaluation': _str('What the directive asks for and what it touches.'),
      'scope_kind': _enum(['local', 'arc']),
      'consistency_notes': _str('What must stay consistent.'),
      'actions': _list('action', {
        'type': 'object',
        'properties': {
          'action_type': _str('The action type name.'),
          'scene': _str('Scene label like 3.2, when the action has one.'),
          'summary': _str('One line a person can tick.'),
          'details': {
            'type': 'object',
            'properties': {'instructions': _str('Exactly what to change.')},
          },
        },
        'required': ['action_type', 'summary'],
      }),
    },
    required: ['actions'],
  );

  static final all = [
    review,
    continuity,
    edits,
    beats,
    scenes,
    acts,
    sequences,
    archive,
    sequenceSummary,
    director,
  ];

  /// The one tool list every structured call sends.
  static final List<Map<String, dynamic>> definitions = [
    for (final t in all)
      {
        'type': 'function',
        'function': {
          'name': t.name,
          'description': t.description,
          'parameters': {
            'type': 'object',
            'properties': t.properties,
            'required': t.required,
          },
        },
      },
  ];

  // ── Arguments → the tag text the parsers read ───────────────────────

  static String toTags(StoryToolSpec spec, Map<String, dynamic> args) {
    final b = StringBuffer('<response>\n');
    _write(b, args, spec.properties, 1);
    b.write('</response>');
    return b.toString();
  }

  static void _write(
    StringBuffer b,
    Map<String, dynamic> values,
    Map<String, dynamic> schema,
    int depth,
  ) {
    final pad = '  ' * depth;
    for (final entry in values.entries) {
      final key = entry.key;
      final value = entry.value;
      final prop = schema[key];
      if (value == null) continue;
      if (value is List) {
        final itemTag = prop is Map ? prop['x-item'] as String? : null;
        final itemSchema = prop is Map ? prop['items'] as Map? : null;
        b.write('$pad<$key>\n');
        for (final item in value) {
          final tag = itemTag ?? _singular(key);
          if (item is Map) {
            b.write('$pad  <$tag>\n');
            _write(
              b,
              item.cast<String, dynamic>(),
              (itemSchema?['properties'] as Map?)?.cast<String, dynamic>() ??
                  const {},
              depth + 2,
            );
            b.write('$pad  </$tag>\n');
          } else {
            b.write('$pad  <$tag>${_escape(item)}</$tag>\n');
          }
        }
        b.write('$pad</$key>\n');
      } else if (value is Map) {
        b.write('$pad<$key>\n');
        _write(
          b,
          value.cast<String, dynamic>(),
          (prop is Map ? prop['properties'] as Map? : null)
                  ?.cast<String, dynamic>() ??
              const {},
          depth + 1,
        );
        b.write('$pad</$key>\n');
      } else {
        b.write('$pad<$key>${_escape(value)}</$key>\n');
      }
    }
  }

  static String _singular(String key) => key.endsWith('ies')
      ? '${key.substring(0, key.length - 3)}y'
      : key.endsWith('s')
      ? key.substring(0, key.length - 1)
      : key;

  static String _escape(Object v) =>
      v.toString().replaceAll('&', '&amp;').replaceAll('<', '&lt;');

  // ── Schema helpers ──────────────────────────────────────────────────

  static Map<String, dynamic> _str(String description) => {
    'type': 'string',
    'description': description,
  };

  static Map<String, dynamic> _int(String description) => {
    'type': 'integer',
    'description': description,
  };

  static Map<String, dynamic> _enum(List<String> values) => {
    'type': 'string',
    'enum': values,
  };

  /// A list whose items serialize as `<itemTag>` inside the key's tag.
  static Map<String, dynamic> _list(
    String itemTag,
    Map<String, dynamic> items,
  ) => {'type': 'array', 'items': items, 'x-item': itemTag};

  static const Map<String, dynamic> _namedCharacter = {
    'type': 'object',
    'properties': {
      'name': {'type': 'string', 'description': 'Name.'},
      'role': {'type': 'string', 'description': 'Role.'},
      'description': {'type': 'string', 'description': 'Who they are.'},
    },
    'required': ['name'],
  };
}

/// One tool: its name, what it is for, and the JSON schema of its
/// arguments (which mirrors the prompt's tag template).
class StoryToolSpec {
  final String name;
  final String description;
  final Map<String, dynamic> properties;
  final List<String> required;

  const StoryToolSpec({
    required this.name,
    required this.description,
    required this.properties,
    required this.required,
  });
}
