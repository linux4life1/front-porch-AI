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
import 'package:front_porch_ai/services/story/story_structure.dart';
import 'package:front_porch_ai/services/story/studio_parse.dart';
import 'package:front_porch_ai/services/story/studio_parse_prose.dart';

/// What a structural change still needs from a model: nothing, a surgical
/// patch of existing prose, a rewrite of discarded prose, or fresh prose for
/// a beat that has none.
enum ProseFollowUp { none, patch, rewrite, write }

class DirectorOutcome {
  final String? error;
  final ProseFollowUp followUp;
  final String sceneId;

  /// 0-based beat index, or -1 for the whole scene.
  final int beat;
  final String instruction;

  const DirectorOutcome.done()
    : error = null,
      followUp = ProseFollowUp.none,
      sceneId = '',
      beat = -1,
      instruction = '';

  const DirectorOutcome.failed(this.error)
    : followUp = ProseFollowUp.none,
      sceneId = '',
      beat = -1,
      instruction = '';

  const DirectorOutcome.prose(
    this.followUp,
    this.sceneId, {
    this.beat = -1,
    this.instruction = '',
  }) : error = null;
}

/// The code-only half of applying a Director action. Everything here is
/// synchronous and pure; the pipeline runs the [DirectorOutcome.followUp]
/// prose work afterwards.
abstract final class StoryDirectorApply {
  static DirectorOutcome apply(StoryProject p, DirectorAction a) {
    final d = a.details;
    switch (a.type) {
      case DirectorActionType.modifyStory:
        if (d['title'] != null) p.title = d['title']!;
        if (d['concept'] != null) p.concept = d['concept']!;
        if (d['themes'] != null) p.themes = d['themes']!;
        if (d['status_quo'] != null) p.statusQuo = d['status_quo']!;
        if (d['inciting_incident'] != null) {
          p.incitingIncident = d['inciting_incident']!;
        }
        return const DirectorOutcome.done();

      case DirectorActionType.addCharacter:
        final name = d['name'] ?? d['character'] ?? '';
        if (name.isEmpty) return const DirectorOutcome.failed('no name given');
        if (p.castByName(name) != null) {
          return DirectorOutcome.failed('$name is already in the cast');
        }
        p.cast.add(
          StoryCastMember(
            name: name,
            role: StudioParse.splitRole(d['role'] ?? 'Supporting').role,
            description: d['description'] ?? '',
            flaw: d['core_flaw'] ?? '',
            desire: d['core_desire'] ?? '',
            voiceSample: d['vocal_cadence'],
          ),
        );
        return const DirectorOutcome.done();

      case DirectorActionType.modifyCharacter:
        final member = p.castByName(d['character'] ?? d['name'] ?? '');
        if (member == null) {
          return const DirectorOutcome.failed('character not found');
        }
        final newName = d['name'];
        if (newName != null &&
            newName != member.name &&
            d['character'] != null) {
          _rename(p, member.name, newName);
        }
        if (d['role'] != null) {
          member.role = StudioParse.splitRole(d['role']!).role;
        }
        if (d['description'] != null) member.description = d['description']!;
        if (d['core_flaw'] != null) member.flaw = d['core_flaw']!;
        if (d['core_desire'] != null) member.desire = d['core_desire']!;
        if (d['vocal_cadence'] != null) member.voiceSample = d['vocal_cadence'];
        if (d['secret'] != null) member.details['secret'] = d['secret']!;
        return const DirectorOutcome.done();

      case DirectorActionType.deleteCharacter:
        final member = p.castByName(d['character'] ?? d['name'] ?? '');
        if (member == null) {
          return const DirectorOutcome.failed('character not found');
        }
        p.cast.remove(member);
        p.relationships.removeWhere(
          (r) => r.from == member.name || r.to == member.name,
        );
        for (final ref in p.orderedScenes) {
          ref.scene.castNames = ref.scene.castNames
              .where((n) => n != member.name)
              .toList();
        }
        return const DirectorOutcome.done();

      case DirectorActionType.modifyRelationship:
        final from = d['from'] ?? '';
        final to = d['to'] ?? '';
        if (p.castByName(from) == null || p.castByName(to) == null) {
          return const DirectorOutcome.failed(
            'both people must be in the cast',
          );
        }
        StoryContinuity.shift(
          p,
          from: from,
          to: to,
          feeling: d['feeling'] ?? p.relationship(from, to)?.feeling ?? '',
          note: d['note'] ?? '',
          subtext: d['hidden_tension'] ?? '',
          trust: int.tryParse(d['trust_level'] ?? ''),
          reason: a.summary,
        );
        return const DirectorOutcome.done();

      case DirectorActionType.addLore:
      case DirectorActionType.modifyLore:
        final topic = d['topic'] ?? '';
        final detail = d['detail'] ?? '';
        if (topic.isEmpty || detail.isEmpty) {
          return const DirectorOutcome.failed('topic and detail are required');
        }
        final existing = p.lore
            .where((l) => l.topic.toLowerCase() == topic.toLowerCase())
            .firstOrNull;
        if (existing != null) {
          existing.detail = detail;
        } else {
          p.lore.add(StoryLoreEntry(topic: topic, detail: detail));
        }
        return const DirectorOutcome.done();

      case DirectorActionType.addFact:
        StoryContinuity.record(
          p,
          ContinuityFact(
            category: d['category'] ?? 'Knowledge',
            key: d['key'] ?? a.summary,
            value: d['detail'] ?? d['value'] ?? '',
            entity: d['character'] ?? '',
            sceneId: a.sceneId,
          ),
        );
        return const DirectorOutcome.done();

      case DirectorActionType.modifyAct:
        final act = p.acts.where((x) => x.number == a.act).firstOrNull;
        if (act == null) return const DirectorOutcome.failed('act not found');
        if (d['title'] != null) act.title = d['title']!;
        if (d['act_mandate'] != null) act.description = d['act_mandate']!;
        if (d['description'] != null) act.description = d['description']!;
        return const DirectorOutcome.done();

      case DirectorActionType.modifySequence:
        final seq = p.sequenceByNumber(a.sequence);
        if (seq == null) {
          return const DirectorOutcome.failed('sequence not found');
        }
        if (d['title'] != null) seq.title = d['title']!;
        if (d['dramatic_question'] != null) {
          seq.dramaticQuestion = d['dramatic_question']!;
        }
        if (d['description'] != null) seq.description = d['description']!;
        return const DirectorOutcome.done();

      case DirectorActionType.addScene:
        return _addScene(p, a);

      case DirectorActionType.modifyScene:
        final ref = p.findScene(a.sceneId);
        if (ref == null) return const DirectorOutcome.failed('scene not found');
        _updateScene(p, ref.scene, d);
        final instruction = d['instructions'] ?? '';
        if (instruction.isNotEmpty && p.sceneHasProse(ref.act, ref.index)) {
          return DirectorOutcome.prose(
            ProseFollowUp.patch,
            ref.scene.id,
            instruction: instruction,
          );
        }
        return const DirectorOutcome.done();

      case DirectorActionType.deleteScene:
        final ref = p.findScene(a.sceneId);
        if (ref == null) return const DirectorOutcome.failed('scene not found');
        StoryStructure.removeScene(p, ref.act, ref.index);
        return const DirectorOutcome.done();

      case DirectorActionType.moveScene:
        final ref = p.findScene(a.sceneId);
        if (ref == null) return const DirectorOutcome.failed('scene not found');
        final siblings = p.sceneIndexesInSequence(ref.scene.sequence);
        final position = (int.tryParse(d['to_position'] ?? '') ?? 1) - 1;
        final target = siblings[position.clamp(0, siblings.length - 1)];
        StoryStructure.moveScene(p, ref.act, ref.index, target);
        return const DirectorOutcome.done();

      case DirectorActionType.insertBeat:
        final ref = p.findScene(a.sceneId);
        if (ref == null) return const DirectorOutcome.failed('scene not found');
        final beat = StoryBeat(number: 0);
        _updateBeat(beat, d);
        if (beat.description.isEmpty) {
          return const DirectorOutcome.failed('the new beat has no action');
        }
        StoryStructure.insertBeat(p, ref.act, ref.index, a.beat, beat);
        return p.sceneHasProse(ref.act, ref.index)
            ? DirectorOutcome.prose(
                ProseFollowUp.write,
                ref.scene.id,
                beat: a.beat,
                instruction: d['instructions'] ?? a.summary,
              )
            : const DirectorOutcome.done();

      case DirectorActionType.modifyBeat:
        final ref = p.findScene(a.sceneId);
        if (ref == null) return const DirectorOutcome.failed('scene not found');
        final beats = p.beats['${ref.act}-${ref.index}'] ?? const <StoryBeat>[];
        if (a.beat < 1 || a.beat > beats.length) {
          return const DirectorOutcome.failed('beat not found');
        }
        _updateBeat(beats[a.beat - 1], d);
        return p.beatText(ref.act, ref.index, a.beat - 1) != null
            ? DirectorOutcome.prose(
                ProseFollowUp.patch,
                ref.scene.id,
                beat: a.beat - 1,
                instruction: d['instructions'] ?? a.summary,
              )
            : const DirectorOutcome.done();

      case DirectorActionType.deleteBeat:
        final ref = p.findScene(a.sceneId);
        if (ref == null) return const DirectorOutcome.failed('scene not found');
        StoryStructure.removeBeat(p, ref.act, ref.index, a.beat - 1);
        return const DirectorOutcome.done();

      case DirectorActionType.rewriteProse:
        final ref = p.findScene(a.sceneId);
        if (ref == null) return const DirectorOutcome.failed('scene not found');
        return DirectorOutcome.prose(
          ProseFollowUp.rewrite,
          ref.scene.id,
          beat: a.beat > 0 ? a.beat - 1 : -1,
          instruction: d['instructions'] ?? a.summary,
        );

      case DirectorActionType.editProse:
        final ref = p.findScene(a.sceneId);
        if (ref == null) return const DirectorOutcome.failed('scene not found');
        if (!p.sceneHasProse(ref.act, ref.index)) {
          return const DirectorOutcome.failed('that scene has no prose yet');
        }
        return DirectorOutcome.prose(
          ProseFollowUp.patch,
          ref.scene.id,
          beat: a.beat > 0 ? a.beat - 1 : -1,
          instruction: d['instructions'] ?? a.summary,
        );
    }
  }

  static DirectorOutcome _addScene(StoryProject p, DirectorAction a) {
    final d = a.details;
    final seq = p.sequenceByNumber(a.sequence);
    final act = p.actIndexForSequence(a.sequence);
    if (seq == null || act < 0) {
      return const DirectorOutcome.failed('sequence not found');
    }
    final after = p.findScene(a.sceneId);
    final siblings = p.sceneIndexesInSequence(a.sequence);
    final list = p.scenes[act] ?? const <StoryScene>[];
    int index;
    if (after != null) {
      index = after.index + 1;
    } else if (siblings.isNotEmpty) {
      index = siblings.last + 1;
    } else {
      index = list.indexWhere((s) => s.sequence > a.sequence);
      if (index == -1) index = list.length;
    }
    final scene = StoryScene(number: 0, sequence: a.sequence);
    _updateScene(p, scene, d);
    if (scene.title.isEmpty) scene.title = a.summary;
    if (scene.tension == 0) {
      scene.tension = 1;
      scene.valence = 5;
    }
    StoryStructure.insertScene(p, act, index, scene);
    return const DirectorOutcome.done();
  }

  static void _updateScene(
    StoryProject p,
    StoryScene s,
    Map<String, String> d,
  ) {
    if (d['title'] != null) s.title = d['title']!;
    if (d['description'] != null) s.description = d['description']!;
    if (d['setting'] != null) s.location = d['setting']!;
    if (d['scene_objective'] != null) s.objective = d['scene_objective']!;
    if (d['plot_commitments'] != null) s.commitments = d['plot_commitments']!;
    if (d['pov_character'] != null) s.pov = d['pov_character']!;
    if (d['scene_type'] != null) {
      s.sceneType = d['scene_type']!.toUpperCase().contains('REACT')
          ? 'reaction'
          : 'action';
    }
    if (d['narrative_lens'] != null) {
      s.lens = StoryLenses.normalizeId(d['narrative_lens']!);
    }
    final score = int.tryParse(d['valence_score'] ?? '');
    if (score != null) {
      s.tension = score.clamp(-2, 2);
      s.valence = s.tension * 5;
    }
    if (d['characters'] != null) {
      s.castNames = d['characters']!
          .split(RegExp(r'[,;\n]'))
          .map((n) => n.trim())
          .where((n) => n.isNotEmpty)
          .map((n) => p.castByName(n)?.name ?? n)
          .toList();
    }
  }

  static void _updateBeat(StoryBeat b, Map<String, String> d) {
    if (d['beat_type'] != null) {
      b.type = StudioParseProse.beatType(d['beat_type']!);
    }
    final action = d['action'] ?? d['description'];
    final reaction = d['reaction'];
    if (action != null || reaction != null) {
      b.description = [
        action ?? b.description,
        if (reaction != null && reaction != '—') reaction,
      ].join(' ');
    }
    if (d['initiator'] != null) b.initiator = d['initiator']!;
    if (d['reactor'] != null) {
      b.reactor = d['reactor']! == '—' ? '' : d['reactor']!;
    }
    if (d['tactic'] != null) b.emotionalShift = d['tactic']!;
    if (d['subtext'] != null) b.subtext = d['subtext']!;
    if (d['anchor'] != null) b.anchor = d['anchor']! == '—' ? '' : d['anchor']!;
  }

  /// A renamed character keeps every reference that is not prose.
  static void _rename(StoryProject p, String from, String to) {
    for (final c in p.cast) {
      if (c.name == from) c.name = to;
    }
    for (final r in p.relationships) {
      if (r.from == from) r.from = to;
      if (r.to == from) r.to = to;
    }
    for (final f in p.continuity) {
      if (f.entity == from) f.entity = to;
    }
    for (final ref in p.orderedScenes) {
      ref.scene.castNames = [
        for (final n in ref.scene.castNames) n == from ? to : n,
      ];
      if (ref.scene.pov == from) ref.scene.pov = to;
    }
    for (final beats in p.beats.values) {
      for (final b in beats) {
        if (b.initiator == from) b.initiator = to;
        if (b.reactor == from) b.reactor = to;
      }
    }
  }
}
