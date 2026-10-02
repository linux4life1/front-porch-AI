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

part of 'story_project.dart';

/// Every change the Director can propose. Wire names are the enum names in
/// SCREAMING_SNAKE_CASE (what the planner model writes).
enum DirectorActionType {
  modifyStory('Story', false),
  addCharacter('Character', false),
  modifyCharacter('Character', false),
  deleteCharacter('Character', false),
  modifyRelationship('Relationship', false),
  addLore('Lore', false),
  modifyLore('Lore', false),
  addFact('Fact', false),
  modifyAct('Act', false),
  modifySequence('Sequence', false),
  addScene('Scene', false),
  modifyScene('Scene', true),
  deleteScene('Scene', true),
  moveScene('Scene', true),
  insertBeat('Beat', true),
  modifyBeat('Beat', true),
  deleteBeat('Beat', true),
  rewriteProse('Prose', true),
  editProse('Prose', true);

  const DirectorActionType(this.kind, this.touchesScene);

  /// Chip label in the plan list.
  final String kind;

  /// True when the action changes one existing scene, so "Protect written
  /// prose" can lock it once that scene has prose.
  final bool touchesScene;

  String get wire =>
      name.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]}').toUpperCase();

  static DirectorActionType? fromWire(String raw) {
    final wanted = raw.trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_');
    for (final t in values) {
      if (t.wire == wanted) return t;
    }
    return null;
  }
}

class DirectorAction {
  DirectorActionType type;

  /// Target scene (stable id), or '' when the action is not scene-scoped.
  String sceneId;

  /// 1-based beat number inside the scene; 0 when not beat-scoped.
  int beat;

  /// 1-based sequence number (add scene / modify sequence); 0 otherwise.
  int sequence;

  /// 1-based act number (modify act); 0 otherwise.
  int act;

  /// One line shown in the plan.
  String summary;
  Map<String, String> details;
  bool enabled;

  /// Blocked by "Protect written prose" — shown, never applied.
  bool locked;

  /// '' until applied; then 'applied' or 'failed: ' plus the reason.
  String result;

  DirectorAction({
    required this.type,
    this.sceneId = '',
    this.beat = 0,
    this.sequence = 0,
    this.act = 0,
    this.summary = '',
    Map<String, String>? details,
    this.enabled = true,
    this.locked = false,
    this.result = '',
  }) : details = details ?? {};

  Map<String, dynamic> toJson() => {
    'type': type.wire,
    'scene_id': sceneId,
    'beat': beat,
    'sequence': sequence,
    'act': act,
    'summary': summary,
    'details': details,
    'enabled': enabled,
    'locked': locked,
    'result': result,
  };

  static DirectorAction? fromJson(Map<String, dynamic> json) {
    final type = DirectorActionType.fromWire(_str(json['type']));
    if (type == null) return null;
    return DirectorAction(
      type: type,
      sceneId: _str(json['scene_id']),
      beat: (json['beat'] as num?)?.toInt() ?? 0,
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      act: (json['act'] as num?)?.toInt() ?? 0,
      summary: _str(json['summary']),
      details: (json['details'] as Map?)?.map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      enabled: json['enabled'] != false,
      locked: json['locked'] == true,
      result: _str(json['result']),
    );
  }
}

/// A proposed set of changes, waiting for the user to tick and apply.
class DirectorPlan {
  String directive;
  String evaluation;

  /// 'local' (a scene or two) or 'arc' (ripples across the story).
  String scope;
  String consistencyNotes;
  List<DirectorAction> actions;

  /// '' = not reviewed, 'consistent', or the reviewer's objection.
  String review;
  DateTime createdAt;

  DirectorPlan({
    this.directive = '',
    this.evaluation = '',
    this.scope = 'local',
    this.consistencyNotes = '',
    List<DirectorAction>? actions,
    this.review = '',
    DateTime? createdAt,
  }) : actions = actions ?? [],
       createdAt = createdAt ?? DateTime.now();

  int get applicableCount =>
      actions.where((a) => a.enabled && !a.locked).length;

  Map<String, dynamic> toJson() => {
    'directive': directive,
    'evaluation': evaluation,
    'scope': scope,
    'consistency_notes': consistencyNotes,
    'actions': actions.map((a) => a.toJson()).toList(),
    'review': review,
    'created_at': createdAt.toIso8601String(),
  };

  factory DirectorPlan.fromJson(Map<String, dynamic> json) => DirectorPlan(
    directive: _str(json['directive']),
    evaluation: _str(json['evaluation']),
    scope: json['scope'] == 'arc' ? 'arc' : 'local',
    consistencyNotes: _str(json['consistency_notes']),
    actions: (json['actions'] as List?)
        ?.map((a) => DirectorAction.fromJson(a as Map<String, dynamic>))
        .whereType<DirectorAction>()
        .toList(),
    review: _str(json['review']),
    createdAt: DateTime.tryParse(_str(json['created_at'])),
  );
}

/// What the "Last applied … Undo that plan" row shows. The pre-apply snapshot
/// itself lives beside the story on disk, not in the project blob.
class DirectorApplied {
  String directive;
  DateTime appliedAt;
  int changeCount;

  DirectorApplied({
    this.directive = '',
    DateTime? appliedAt,
    this.changeCount = 0,
  }) : appliedAt = appliedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'directive': directive,
    'applied_at': appliedAt.toIso8601String(),
    'change_count': changeCount,
  };

  factory DirectorApplied.fromJson(Map<String, dynamic> json) =>
      DirectorApplied(
        directive: _str(json['directive']),
        appliedAt: DateTime.tryParse(_str(json['applied_at'])),
        changeCount: (json['change_count'] as num?)?.toInt() ?? 0,
      );
}
