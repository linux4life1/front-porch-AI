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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/prompts/studio_prose_prompts.dart';
import 'package:front_porch_ai/services/story/story_continuity.dart';
import 'package:front_porch_ai/services/story/story_json.dart';
import 'package:front_porch_ai/services/story/story_xml.dart';

/// Turns Studio beat, prose and archivist replies into project state. Pure.
abstract final class StudioParseProse {
  static String _dash(String v) =>
      (v == '—' || v == '-' || v.toLowerCase() == 'none') ? '' : v;

  /// "ACTION/KINETIC" → "Action"; anything unknown → "Action".
  static String beatType(String raw) {
    final t = raw.toLowerCase();
    for (final type in StudioProsePrompts.beatTypes) {
      if (t.contains(type.toLowerCase().substring(0, 5))) return type;
    }
    return 'Action';
  }

  static int _pacing(String type) => switch (type) {
    'Environment' || 'Reflection' || 'Memory' => 0,
    'Action' || 'Transition' => 2,
    _ => 1,
  };

  static String? checkBeats(String text, {required int min}) {
    final blocks = StoryXml.all(text, 'beat');
    if (blocks.length < min) {
      return 'There must be at least $min <beat> blocks; the answer has '
          '${blocks.length}.';
    }
    final bad = blocks.indexWhere((b) => StoryXml.tag(b, 'action').isEmpty);
    return bad == -1 ? null : 'Beat ${bad + 1} is missing its <action>.';
  }

  static List<StoryBeat> beats(
    String text, {
    required int max,
    int tension = 0,
  }) {
    final out = <StoryBeat>[];
    for (final b in StoryXml.all(text, 'beat').take(max)) {
      final type = beatType(StoryXml.tag(b, 'beat_type'));
      final reaction = _dash(StoryXml.tag(b, 'reaction'));
      out.add(
        StoryBeat(
          number: out.length + 1,
          type: type,
          description: [
            StoryXml.tag(b, 'action'),
            reaction,
          ].where((s) => s.isNotEmpty).join(' '),
          emotionalShift: StoryXml.tag(b, 'tactic'),
          initiator: _dash(StoryXml.tag(b, 'initiator')),
          reactor: _dash(StoryXml.tag(b, 'reactor')),
          subtext: StoryXml.tag(b, 'subtext'),
          anchor: _dash(StoryXml.tag(b, 'anchor')),
          valence: tension * 5,
          pacing: _pacing(type),
        ),
      );
    }
    return out;
  }

  /// The prose inside `<prose_text>`, or the whole cleaned reply when the
  /// model skipped the wrapper. Reasoning blocks never survive.
  static String prose(String raw) {
    final cleaned = StoryXml.clean(raw);
    final inner = StoryXml.all(cleaned, 'prose_text', limit: 1);
    if (inner.isNotEmpty) return StoryXml.decode(inner.first).trim();
    final open = RegExp(
      '<prose_text>',
      caseSensitive: false,
    ).firstMatch(cleaned);
    final body = open == null ? cleaned : cleaned.substring(open.end);
    return StoryJson.stripThinkTags(
      body,
    ).replaceAll(RegExp('</?prose_text>', caseSensitive: false), '').trim();
  }

  /// Apply the archivist's reading of a finished scene.
  static void applyArchive(StoryProject p, int act, int index, String text) {
    final scene = p.scenes[act]![index];
    final summary = StoryXml.tag(text, 'scene_summary');
    if (summary.isNotEmpty) scene.summary = summary;

    for (final f in StoryXml.all(text, 'fact')) {
      StoryContinuity.record(
        p,
        ContinuityFact(
          category: StoryXml.tag(f, 'category'),
          key: StoryXml.tag(f, 'key'),
          value: StoryXml.firstTag(f, const ['detail', 'value']),
          entity: _dash(StoryXml.firstTag(f, const ['character', 'entity'])),
          sceneId: scene.id,
        ),
      );
    }

    String section(String name) =>
        StoryXml.all(text, name, limit: 1).firstOrNull ?? '';

    for (final u in StoryXml.all(section('relationship_updates'), 'update')) {
      StoryContinuity.shift(
        p,
        from: StoryXml.tag(u, 'from'),
        to: StoryXml.tag(u, 'to'),
        feeling: StoryXml.tag(u, 'new_feeling'),
        note: StoryXml.tag(u, 'note'),
        subtext: StoryXml.tag(u, 'hidden_tension'),
        trust: StoryXml.intTag(u, 'trust_level'),
        sceneId: scene.id,
        reason: StoryXml.tag(u, 'trigger'),
      );
    }

    for (final u in StoryXml.all(section('cast_updates'), 'update')) {
      final member = p.castByName(StoryXml.tag(u, 'name'));
      if (member == null) continue;
      final events = StoryXml.tag(u, 'story_events');
      if (events.isNotEmpty) {
        final old = member.details['story_events'] ?? '';
        member.details['story_events'] = old.isEmpty
            ? '- $events'
            : '$old\n- $events';
      }
      final goals = StoryXml.tag(u, 'goals');
      if (goals.isNotEmpty) member.details['goals'] = goals;
    }

    for (final c in StoryXml.all(section('new_characters'), 'character')) {
      final name = StoryXml.tag(c, 'name');
      if (name.isEmpty || name.length > 60 || p.castByName(name) != null) {
        continue;
      }
      p.cast.add(
        StoryCastMember(
          name: name,
          role: StoryXml.tag(c, 'role'),
          description: StoryXml.tag(c, 'description'),
        ),
      );
    }

    for (final e in StoryXml.all(section('lore_updates'), 'entry')) {
      final topic = StoryXml.tag(e, 'topic');
      final detail = StoryXml.tag(e, 'detail');
      if (topic.isEmpty || detail.isEmpty) continue;
      if (p.lore.any((l) => l.topic.toLowerCase() == topic.toLowerCase())) {
        continue;
      }
      p.lore.add(
        StoryLoreEntry(
          topic: topic,
          detail: detail,
          validFromAct: act + 1,
          validFromScene: index + 1,
        ),
      );
    }
  }
}
