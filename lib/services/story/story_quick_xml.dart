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

import 'package:front_porch_ai/services/story/story_json.dart';
import 'package:front_porch_ai/services/story/story_xml.dart';

/// The Quick engine's planning replies as tags, folded into the same maps
/// its JSON parsing always produced — so the stages keep one code path and
/// a model that still answers in JSON still works ([parse] falls back to
/// [StoryJson.parseJson]). Tags survive a small local model's slips where a
/// single lost comma ruins a whole JSON reply.
abstract final class StoryQuickXml {
  static const _lists = {
    'focus_thread_ids',
    'active_thread_ids',
    'cast_names',
    'related_to',
  };
  static const _ints = {
    'number',
    'valence',
    'pacing',
    'valid_from_act',
    'valid_from_scene',
  };

  /// Tags for [stage] ('architect', 'acts', 'scenes', 'beats', 'archivist',
  /// 'validator'), else the JSON the reply may hold, else null.
  static Map<String, dynamic>? parse(String stage, String raw) {
    final text = StoryXml.clean(raw);
    final root = StoryXml.all(text, 'response', limit: 1).firstOrNull ?? text;
    final map = switch (stage) {
      'architect' => _architect(root),
      'acts' => _acts(root),
      'scenes' => _scenes(root),
      'beats' => _beats(root),
      'archivist' => _archivist(root),
      'validator' => _validator(root),
      _ => null,
    };
    return map ?? StoryJson.parseJson(raw);
  }

  static dynamic _value(String block, String name) {
    final v = StoryXml.tag(block, name);
    if (_lists.contains(name)) {
      return v
          .split(RegExp(r'[,\n]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (_ints.contains(name)) {
      return int.tryParse(RegExp(r'-?\d+').firstMatch(v)?.group(0) ?? '') ?? 0;
    }
    return v;
  }

  static Map<String, dynamic> _fields(String block, List<String> names) => {
    for (final n in names) n: _value(block, n),
  };

  static List<Map<String, dynamic>> _each(
    String text,
    String parent,
    String child,
    List<String> names,
  ) {
    final block = StoryXml.all(text, parent, limit: 1).firstOrNull ?? '';
    return [for (final b in StoryXml.all(block, child)) _fields(b, names)];
  }

  static Map<String, dynamic>? _architect(String t) {
    if (!StoryXml.has(t, 'status_quo') && !StoryXml.has(t, 'concept')) {
      return null;
    }
    final style = StoryXml.all(t, 'style', limit: 1).firstOrNull ?? '';
    final protagonist = StoryXml.all(t, 'protagonist', limit: 1).firstOrNull;
    final details = protagonist == null
        ? ''
        : StoryXml.all(protagonist, 'details', limit: 1).firstOrNull ?? '';
    return {
      'concept': StoryXml.tag(t, 'concept'),
      'status_quo': StoryXml.tag(t, 'status_quo'),
      'inciting_incident': StoryXml.tag(t, 'inciting_incident'),
      'themes': StoryXml.tag(t, 'themes'),
      'style': _fields(style, const ['genre', 'mood', 'writing_guide']),
      'threads': _each(t, 'threads', 'thread', const [
        'id',
        'name',
        'description',
      ]),
      if (protagonist != null)
        'protagonist': {
          ..._fields(protagonist, const [
            'name',
            'role',
            'description',
            'voice_sample',
          ]),
          'details': _fields(details, const [
            'history',
            'story_events',
            'goals',
            'evolution',
          ]),
        },
      'world_lore': _each(t, 'world_lore', 'entry', const [
        'topic',
        'detail',
        'related_to',
      ]),
    };
  }

  static Map<String, dynamic>? _acts(String t) {
    final acts = StoryXml.all(
      StoryXml.all(t, 'acts', limit: 1).firstOrNull ?? '',
      'act',
    );
    if (acts.isEmpty) return null;
    return {
      'acts': [
        for (final a in acts)
          {
            ..._fields(a, const [
              'number',
              'title',
              'description',
              'focus_thread_ids',
            ]),
            'knots': _each(a, 'knots', 'knot', const [
              'description',
              'interaction',
            ]),
          },
      ],
    };
  }

  static Map<String, dynamic>? _scenes(String t) {
    final scenes = StoryXml.all(
      StoryXml.all(t, 'scenes', limit: 1).firstOrNull ?? '',
      'scene',
    );
    if (scenes.isEmpty) return null;
    return {
      'scenes': [
        for (final s in scenes)
          {
            ..._fields(s, const [
              'number',
              'title',
              'description',
              'active_thread_ids',
              'location',
              'cast_names',
              'valence',
            ]),
            'causality': _fields(
              StoryXml.all(s, 'causality', limit: 1).firstOrNull ?? '',
              const ['interaction_type', 'description'],
            ),
          },
      ],
      'new_characters': _each(t, 'new_characters', 'character', const [
        'name',
        'role',
        'description',
      ]),
    };
  }

  static const _beatFields = [
    'number',
    'type',
    'description',
    'emotional_shift',
    'valence',
    'pacing',
  ];

  static Map<String, dynamic>? _beats(String t) {
    final beats = _each(t, 'beats', 'beat', _beatFields);
    return beats.isEmpty ? null : {'beats': beats};
  }

  static Map<String, dynamic>? _archivist(String t) {
    if (!StoryXml.has(t, 'cast_updates') && !StoryXml.has(t, 'lore_updates')) {
      return null;
    }
    return {
      'cast_updates': _each(t, 'cast_updates', 'update', const [
        'name',
        'append_history',
        'append_story_events',
        'update_goals',
      ]),
      'lore_updates': _each(t, 'lore_updates', 'entry', const [
        'topic',
        'detail',
        'related_to',
      ]),
    };
  }

  static Map<String, dynamic>? _validator(String t) {
    final valid = StoryXml.tag(t, 'valid').toLowerCase();
    if (valid.isEmpty) return null;
    return {
      'valid': !valid.startsWith('f') && !valid.startsWith('n'),
      'reason': StoryXml.tag(t, 'reason'),
      'rectified_beats': _each(t, 'rectified_beats', 'beat', _beatFields),
    };
  }
}
