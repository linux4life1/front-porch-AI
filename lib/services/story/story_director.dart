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
import 'package:front_porch_ai/services/story/story_xml.dart';

/// Reading a Director plan and deciding what "Protect written prose" locks.
abstract final class StoryDirector {
  /// Actions that discard or restructure prose. With protection on they are
  /// shown but locked for any scene that has prose. `modifyScene` and
  /// `editProse` are not here: they patch lines in place.
  static const destructive = {
    DirectorActionType.deleteScene,
    DirectorActionType.moveScene,
    DirectorActionType.insertBeat,
    DirectorActionType.modifyBeat,
    DirectorActionType.deleteBeat,
    DirectorActionType.rewriteProse,
  };

  static final _detailTag = RegExp(r'<([a-z_]+)>([\s\S]*?)</\1>');

  static String? check(String text) => StoryXml.all(text, 'action').isEmpty
      ? 'The plan needs at least one <action> inside <actions>.'
      : null;

  /// Parse the planner's reply. Scene labels ("3.2") are resolved to scene
  /// ids here, so the plan keeps pointing at the same scenes even if an
  /// earlier action in it inserts or removes one. Actions with an unknown
  /// type or a scene that does not exist are dropped.
  static DirectorPlan parsePlan(
    StoryProject p,
    String text, {
    required String directive,
  }) {
    final plan = DirectorPlan(
      directive: directive,
      evaluation: StoryXml.tag(text, 'evaluation'),
      scope: StoryXml.tag(text, 'scope_kind').toLowerCase().contains('arc')
          ? 'arc'
          : 'local',
      consistencyNotes: StoryXml.tag(text, 'consistency_notes'),
    );
    for (final block in StoryXml.all(text, 'action')) {
      final type = DirectorActionType.fromWire(
        StoryXml.tag(block, 'action_type'),
      );
      if (type == null) continue;
      final detailsBlock =
          StoryXml.all(block, 'details', limit: 1).firstOrNull ?? '';
      // Targets live outside <details>; several detail fields reuse the
      // same tag names (<scene>, <character>).
      final outer = block.replaceAll(
        RegExp(r'<details>[\s\S]*?</details>', caseSensitive: false),
        '',
      );
      final details = <String, String>{
        for (final m in _detailTag.allMatches(detailsBlock))
          m.group(1)!: StoryXml.decode(m.group(2)!).trim(),
      }..removeWhere((_, v) => v.isEmpty);

      final character = StoryXml.tag(outer, 'character');
      if (character.isNotEmpty) {
        details.putIfAbsent('character', () => character);
      }

      final sceneLabel = StoryXml.tag(outer, 'scene');
      final ref = p.sceneByLabel(sceneLabel);
      if (type.touchesScene && ref == null) continue;

      var sequence = StoryXml.intTag(outer, 'sequence') ?? 0;
      var sceneId = ref?.scene.id ?? '';
      if (type == DirectorActionType.addScene) {
        if (ref != null && sequence == 0) sequence = ref.scene.sequence;
        if (p.sequenceByNumber(sequence) == null) continue;
      }
      if (type == DirectorActionType.addFact) {
        sceneId =
            p.sceneByLabel(details['scene'] ?? sceneLabel)?.scene.id ?? '';
      }

      final summary = StoryXml.tag(outer, 'summary');
      plan.actions.add(
        DirectorAction(
          type: type,
          sceneId: sceneId,
          beat: StoryXml.intTag(outer, 'beat') ?? 0,
          sequence: sequence,
          act: StoryXml.intTag(outer, 'act') ?? 0,
          summary: summary.isNotEmpty
              ? summary
              : (details['instructions'] ?? details['title'] ?? type.kind),
          details: details,
        ),
      );
    }
    return plan;
  }

  /// Lock (or unlock) the actions protection forbids, given what is written
  /// right now.
  static void applyProtection(StoryProject p, DirectorPlan plan, bool protect) {
    for (final action in plan.actions) {
      final ref = p.findScene(action.sceneId);
      action.locked =
          protect &&
          destructive.contains(action.type) &&
          ref != null &&
          p.sceneHasProse(ref.act, ref.index);
    }
  }

  /// "3.2: Night on the roof" style prefix for the plan list, or ''.
  static String target(StoryProject p, DirectorAction a) {
    final ref = p.findScene(a.sceneId);
    if (ref != null) {
      final beat = a.beat > 0 ? ' beat ${a.beat}' : '';
      return '${p.sceneLabel(ref.act, ref.index)} ${ref.scene.title}$beat';
    }
    if (a.details['character'] != null) return a.details['character']!;
    if (a.sequence > 0) return 'Sequence ${a.sequence}';
    if (a.act > 0) return 'Act ${a.act}';
    return '';
  }
}
