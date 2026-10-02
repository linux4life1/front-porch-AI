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
import 'package:front_porch_ai/services/story/story_continuity.dart';
import 'package:front_porch_ai/services/story/story_lenses.dart';
import 'package:front_porch_ai/services/story/story_pacing.dart';
import 'package:front_porch_ai/services/story/story_xml.dart';

/// Turns Studio bible and structure replies into project state. Pure: no
/// model calls, no saving — the pipeline calls these and then persists.
abstract final class StudioParse {
  static const _roles = [
    'Protagonist',
    'Antagonist',
    'Love Interest',
    'Mentor',
    'Supporting',
  ];

  /// "Protagonist — a toll clerk…" → ('Protagonist', 'a toll clerk…').
  static ({String role, String rest}) splitRole(String raw) {
    final text = raw.trim();
    for (final role in _roles) {
      if (text.toLowerCase().startsWith(role.toLowerCase())) {
        final rest = text
            .substring(role.length)
            .replaceFirst(RegExp(r'^[\s—–\-:|.,]+'), '');
        return (role: role, rest: rest.trim());
      }
    }
    final head = text.split(RegExp(r'[—–|:.\n]')).first.trim();
    return head.isNotEmpty && head.split(' ').length <= 3
        ? (role: head, rest: text.substring(head.length).trim())
        : (role: 'Supporting', rest: text);
  }

  static bool _placeholder(String name) =>
      name.isEmpty ||
      name.length > 60 ||
      RegExp(
        r'^(name|full name|character name|only if)',
        caseSensitive: false,
      ).hasMatch(name);

  static List<String> _threadIds(String block, String parent) => StoryXml.list(
    block,
    parent,
    'thread',
  ).map((t) => t.split(' ').first).toList();

  // ── Foundation ─────────────────────────────────────────────────────────

  /// The code-level gate for the foundation reply.
  static String? checkFoundation(String text) {
    if (StoryXml.tag(text, 'status_quo').isEmpty) {
      return 'The answer is missing <status_quo>.';
    }
    if (StoryXml.all(text, 'brief').isEmpty) {
      return 'The answer needs at least one <brief> inside <character_briefs>.';
    }
    return null;
  }

  static void applyFoundation(StoryProject p, String text) {
    final label = StoryXml.tag(text, 'genre_label');
    final mood = StoryXml.tag(text, 'mood_label');
    p.style = StoryStyle(
      genre: p.selectedGenres.isNotEmpty ? p.selectedGenres.join(', ') : label,
      mood: p.selectedMoods.isNotEmpty ? p.selectedMoods.join(', ') : mood,
      writingGuide: StoryXml.tag(text, 'writing_style_description'),
      genreBrief: StoryXml.tag(text, 'genre_classification'),
      toneBrief: StoryXml.tag(text, 'tone_and_atmosphere'),
    );
    p.statusQuo = StoryXml.tag(text, 'status_quo');

    // Voices and portraits the user already chose survive a rebuilt bible.
    final kept = {for (final c in p.cast) c.name.toLowerCase(): c};
    final cast = <StoryCastMember>[
      for (final snap in p.characterCardSnapshots)
        StoryCastMember(
          name: snap['name'] ?? 'Unknown',
          role: snap['role'] ?? 'Supporting',
          description: snap['description'] ?? snap['personality'] ?? '',
        ),
    ];
    StoryCastMember? find(String name) {
      final wanted = name.toLowerCase();
      for (final c in cast) {
        final n = c.name.toLowerCase();
        if (n == wanted || n.split(' ').first == wanted.split(' ').first) {
          return c;
        }
      }
      return null;
    }

    for (final brief in StoryXml.all(text, 'brief')) {
      final name = StoryXml.tag(brief, 'name');
      if (_placeholder(name)) continue;
      final role = splitRole(StoryXml.tag(brief, 'role'));
      final description = [
        StoryXml.tag(brief, 'description'),
        role.rest,
      ].where((s) => s.isNotEmpty).join(' ');
      var member = find(name);
      if (member == null) {
        member = StoryCastMember(
          name: name,
          role: role.role,
          description: description,
        );
        cast.add(member);
      } else if (member.description.isEmpty) {
        member.description = description;
      }
      member.flaw = StoryXml.tag(brief, 'core_flaw');
      member.desire = StoryXml.tag(brief, 'core_desire');
      final cadence = StoryXml.tag(brief, 'vocal_cadence');
      if (cadence.isNotEmpty) member.voiceSample = cadence;
    }
    for (final member in cast) {
      final old = kept[member.name.toLowerCase()];
      if (old == null) continue;
      member.voiceModel = old.voiceModel;
      member.portrait = old.portrait;
    }
    if (cast.isNotEmpty) p.cast = cast;

    if (p.scenes.values.every((s) => s.isEmpty)) p.relationships = [];
    for (final rel in StoryXml.all(text, 'relationship')) {
      StoryContinuity.shift(
        p,
        from: StoryXml.firstTag(rel, const ['from', 'source_id']),
        to: StoryXml.firstTag(rel, const ['to', 'target_id']),
        feeling: StoryXml.firstTag(rel, const ['feeling', 'dynamic_summary']),
        note: StoryXml.tag(rel, 'note'),
        subtext: StoryXml.tag(rel, 'hidden_tension'),
        trust: StoryXml.intTag(rel, 'trust_level'),
        reason: 'Where they start.',
      );
    }

    final uploads = p.lore.where(
      (l) => l.relatedTo.any((r) => r.startsWith('file:')),
    );
    final lore = [...uploads];
    for (final entry in StoryXml.all(
      StoryXml.all(text, 'world_lore', limit: 1).firstOrNull ?? '',
      'entry',
    )) {
      final topic = StoryXml.tag(entry, 'topic');
      final detail = StoryXml.tag(entry, 'detail');
      if (topic.isEmpty || detail.isEmpty) continue;
      if (lore.any((l) => l.topic.toLowerCase() == topic.toLowerCase())) {
        continue;
      }
      lore.add(StoryLoreEntry(topic: topic, detail: detail));
    }
    p.lore = lore;
  }

  // ── Interview ──────────────────────────────────────────────────────────

  static String? checkInterview(String text) =>
      StoryXml.tag(text, 'interview').length < 200
      ? 'The <interview> is missing or far too short.'
      : null;

  static void applyInterview(StoryCastMember member, String text) {
    member.interview = StoryXml.tag(text, 'interview');
    final appearance = StoryXml.tag(text, 'appearance');
    if (appearance.isNotEmpty) member.details['appearance'] = appearance;
    final cadence = StoryXml.tag(text, 'vocal_cadence');
    if (cadence.isNotEmpty) member.voiceSample = cadence;
    final yearning = StoryXml.tag(text, 'core_yearning');
    if (yearning.isNotEmpty) member.desire = yearning;
  }

  // ── Arc ────────────────────────────────────────────────────────────────

  static String? checkArc(String text) {
    if (StoryXml.tag(text, 'inciting_incident').isEmpty) {
      return 'The answer is missing <inciting_incident>.';
    }
    if (StoryXml.all(text, 'thread').isEmpty) {
      return 'The answer needs <thread> blocks inside <narrative_threads>.';
    }
    return null;
  }

  static void applyArc(StoryProject p, String text) {
    final argument = StoryXml.tag(text, 'core_thematic_argument');
    final from = StoryXml.tag(text, 'starting_value_state');
    final to = StoryXml.tag(text, 'ending_value_state');
    p.themes = [
      argument,
      if (from.isNotEmpty || to.isNotEmpty) 'From: $from\nTo: $to',
    ].where((s) => s.isNotEmpty).join('\n');
    p.incitingIncident = StoryXml.tag(text, 'inciting_incident');
    p.twists = StoryXml.tag(text, 'major_surprises_and_twists');

    final threads = <StoryThread>[];
    final block =
        StoryXml.all(text, 'narrative_threads', limit: 1).firstOrNull ?? text;
    for (final t in StoryXml.all(block, 'thread')) {
      final name = StoryXml.tag(t, 'name');
      if (name.isEmpty) continue;
      final id = StoryXml.tag(t, 'thread_id');
      threads.add(
        StoryThread(
          id: id.isEmpty ? 'T${threads.length + 1}' : id,
          name: name,
          description: StoryXml.tag(t, 'description'),
        ),
      );
    }
    if (threads.isNotEmpty) p.threads = threads;

    for (final arc in StoryXml.all(text, 'arc')) {
      final member = p.castByName(
        StoryXml.firstTag(arc, const ['name', 'char_id']),
      );
      if (member == null) continue;
      final lie = StoryXml.tag(arc, 'lie_believed');
      if (lie.isNotEmpty) member.flaw = lie;
      void set(String key, String tag) {
        final v = StoryXml.tag(arc, tag);
        if (v.isNotEmpty) member.details[key] = v;
      }

      set('truth', 'truth_needed');
      set('catalyst', 'arc_catalyst');
      set('arc', 'arc_description');
    }
  }

  // ── Acts and sequences ─────────────────────────────────────────────────

  static String? checkActs(String text) {
    final n = StoryXml.all(text, 'act').length;
    return n == StoryPacing.actCount
        ? null
        : 'There must be exactly ${StoryPacing.actCount} <act> blocks; '
              'the answer has $n.';
  }

  static void applyActs(StoryProject p, String text) {
    final acts = <StoryAct>[];
    for (final a in StoryXml.all(text, 'act').take(StoryPacing.actCount)) {
      final world = StoryXml.tag(a, 'world_building_developments');
      final statuses = StoryXml.tag(a, 'thread_statuses_at_end');
      acts.add(
        StoryAct(
          number: acts.length + 1,
          title: StoryXml.tag(a, 'title'),
          description: [
            StoryXml.firstTag(a, const ['act_mandate', 'description']),
            if (world.isNotEmpty) 'World: $world',
            if (statuses.isNotEmpty) 'Threads at the end: $statuses',
          ].join('\n\n'),
          focusThreadIds: _threadIds(a, 'threads'),
          knots: [
            for (final k in StoryXml.all(a, 'knot'))
              StoryKnot(
                description: StoryXml.tag(k, 'description'),
                interaction: StoryXml.tag(k, 'interaction'),
              ),
          ],
        ),
      );
    }
    p.acts = acts;
    p.actCount = acts.length;
  }

  static String? checkSequences(String text) {
    final want = StoryPacing.sequenceSlots.length;
    final blocks = StoryXml.all(text, 'sequence');
    if (blocks.length != want) {
      return 'There must be exactly $want <sequence> blocks; the answer has '
          '${blocks.length}.';
    }
    final empty = blocks.indexWhere(
      (s) => StoryXml.tag(s, 'dramatic_question').isEmpty,
    );
    return empty == -1
        ? null
        : 'Sequence ${empty + 1} is missing its <dramatic_question>.';
  }

  /// The act of each sequence comes from its slot, not from the model: the
  /// 2 / 4 / 2 split is structural and not open to drift.
  static void applySequences(StoryProject p, String text) {
    final blocks = StoryXml.all(text, 'sequence');
    p.sequences = [
      for (var i = 0; i < StoryPacing.sequenceSlots.length; i++)
        () {
          final slot = StoryPacing.sequenceSlots[i];
          final s = i < blocks.length ? blocks[i] : '';
          final function = StoryXml.tag(s, 'sequence_function');
          return StorySequence(
            number: slot.number,
            act: slot.act,
            title: StoryXml.tag(s, 'title'),
            function: function.isEmpty ? slot.function : function,
            dramaticQuestion: StoryXml.tag(s, 'dramatic_question'),
            description: StoryXml.tag(s, 'description'),
            climax: StoryXml.tag(s, 'sequence_climax'),
            endingHook: StoryXml.tag(s, 'ending_hook'),
            threadIds: _threadIds(s, 'threads_advanced'),
          );
        }(),
    ];
  }

  // ── Scenes ─────────────────────────────────────────────────────────────

  static String? checkScenes(String text, {required int min}) {
    final blocks = StoryXml.all(text, 'scene');
    if (blocks.length < min) {
      return 'There must be at least $min <scene> blocks; the answer has '
          '${blocks.length}.';
    }
    final bad = blocks.indexWhere(
      (s) =>
          StoryXml.tag(s, 'title').isEmpty ||
          StoryXml.tag(s, 'description').isEmpty,
    );
    return bad == -1
        ? null
        : 'Scene ${bad + 1} needs both a <title> and a <description>.';
  }

  /// Scenes for one sequence, capped at [max]. Also adds any genuinely new
  /// characters the planner introduced.
  static List<StoryScene> scenes(
    StoryProject p,
    String text, {
    required int sequence,
    required int max,
  }) {
    for (final c in StoryXml.all(
      StoryXml.all(text, 'new_characters', limit: 1).firstOrNull ?? '',
      'character',
    )) {
      final name = StoryXml.tag(c, 'name');
      if (_placeholder(name) || p.castByName(name) != null) continue;
      p.cast.add(
        StoryCastMember(
          name: name,
          role: splitRole(StoryXml.tag(c, 'role')).role,
          description: StoryXml.tag(c, 'description'),
        ),
      );
    }

    final known = {for (final l in StoryLenses.forProject(p)) l.id};
    final out = <StoryScene>[];
    final block = StoryXml.all(text, 'scenes', limit: 1).firstOrNull ?? text;
    for (final s in StoryXml.all(block, 'scene').take(max)) {
      final tension = (StoryXml.intTag(s, 'valence_score') ?? 1).clamp(-2, 2);
      final lens = StoryLenses.normalizeId(
        StoryXml.firstTag(s, const ['narrative_lens', 'mode_id']),
      );
      final type = StoryXml.tag(s, 'scene_type').toUpperCase();
      final shift = StoryXml.all(s, 'value_shift', limit: 1).firstOrNull ?? '';
      out.add(
        StoryScene(
          id: newStoryId(),
          number: out.length + 1,
          sequence: sequence,
          title: StoryXml.tag(s, 'title'),
          description: StoryXml.tag(s, 'description'),
          location: StoryXml.firstTag(s, const ['setting', 'setting_anchor']),
          castNames: StoryXml.list(
            s,
            'characters_present',
            'character',
          ).map((n) => p.castByName(n)?.name ?? n).toSet().toList(),
          activeThreadIds: _threadIds(s, 'threads_advanced'),
          tension: tension == 0 ? 1 : tension,
          valence: (tension == 0 ? 1 : tension) * 5,
          sceneType: type.contains('REACT') ? 'reaction' : 'action',
          lens: known.contains(lens) ? lens : StoryLenses.baseline,
          valueFrom: StoryXml.tag(shift, 'start_state'),
          valueTo: StoryXml.tag(shift, 'end_state'),
          objective: StoryXml.tag(s, 'scene_objective'),
          pov: StoryXml.tag(s, 'pov_character'),
          commitments: StoryXml.tag(s, 'plot_commitments'),
          entry: StoryXml.tag(s, 'entrance_conditions'),
          exit: StoryXml.tag(s, 'exit_conditions'),
        ),
      );
    }
    return out;
  }
}
