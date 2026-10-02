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

/// How a story is generated. Quick is the original one-pass engine; Studio
/// adds interviews, review loops, continuity and relationship tracking.
enum StoryEngineMode { quick, studio }

enum StoryFormat { novel, audioDrama }

/// Which configured model a pipeline job runs on. `worker` falls back to the
/// main model when no worker is configured.
enum StoryModelLane { main, worker }

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

List<String> _stringList(Object? raw) =>
    (raw as List?)?.map((e) => e.toString()).toList() ?? [];

String _str(Object? raw) => raw?.toString() ?? '';

/// A sequence: a run of scenes inside an act bound by one short-term dramatic
/// question. Numbers are 1-based and global across the story.
class StorySequence {
  int number;
  int act;
  String title;
  String function;
  String dramaticQuestion;
  String description;
  String climax;
  String endingHook;
  List<String> threadIds;

  /// Condensed "what happened", written once the sequence is drafted.
  String summary;

  StorySequence({
    required this.number,
    this.act = 1,
    this.title = '',
    this.function = '',
    this.dramaticQuestion = '',
    this.description = '',
    this.climax = '',
    this.endingHook = '',
    List<String>? threadIds,
    this.summary = '',
  }) : threadIds = threadIds ?? [];

  Map<String, dynamic> toJson() => {
    'number': number,
    'act': act,
    'title': title,
    'function': function,
    'dramatic_question': dramaticQuestion,
    'description': description,
    'climax': climax,
    'ending_hook': endingHook,
    'thread_ids': threadIds,
    'summary': summary,
  };

  factory StorySequence.fromJson(Map<String, dynamic> json) => StorySequence(
    number: (json['number'] as num?)?.toInt() ?? 1,
    act: (json['act'] as num?)?.toInt() ?? 1,
    title: _str(json['title']),
    function: _str(json['function']),
    dramaticQuestion: _str(json['dramatic_question']),
    description: _str(json['description']),
    climax: _str(json['climax']),
    endingHook: _str(json['ending_hook']),
    threadIds: _stringList(json['thread_ids']),
    summary: _str(json['summary']),
  );
}

/// One step in how a relationship changed, anchored to the scene that moved it.
class RelationshipShift {
  String sceneId;
  String from;
  String to;
  String reason;

  RelationshipShift({
    this.sceneId = '',
    this.from = '',
    this.to = '',
    this.reason = '',
  });

  Map<String, dynamic> toJson() => {
    'scene_id': sceneId,
    'from': from,
    'to': to,
    'reason': reason,
  };

  factory RelationshipShift.fromJson(Map<String, dynamic> json) =>
      RelationshipShift(
        sceneId: _str(json['scene_id']),
        from: _str(json['from']),
        to: _str(json['to']),
        reason: _str(json['reason']),
      );
}

/// How [from] sees [to]. Directed: A→B and B→A are separate rows.
class StoryRelationship {
  String from;
  String to;

  /// Short label for the matrix cell ("Resentful").
  String feeling;

  /// Two or three words under the label ("owes him").
  String note;

  /// The unspoken tension the prose should carry.
  String subtext;

  /// 0 (hostile) – 10 (complete trust).
  int trust;
  List<RelationshipShift> history;

  StoryRelationship({
    required this.from,
    required this.to,
    this.feeling = '',
    this.note = '',
    this.subtext = '',
    this.trust = 5,
    List<RelationshipShift>? history,
  }) : history = history ?? [];

  Map<String, dynamic> toJson() => {
    'from': from,
    'to': to,
    'feeling': feeling,
    'note': note,
    'subtext': subtext,
    'trust': trust,
    'history': history.map((h) => h.toJson()).toList(),
  };

  factory StoryRelationship.fromJson(Map<String, dynamic> json) =>
      StoryRelationship(
        from: _str(json['from']),
        to: _str(json['to']),
        feeling: _str(json['feeling']),
        note: _str(json['note']),
        subtext: _str(json['subtext']),
        trust: ((json['trust'] as num?)?.toInt() ?? 5).clamp(0, 10),
        history: (json['history'] as List?)
            ?.map((h) => RelationshipShift.fromJson(h as Map<String, dynamic>))
            .toList(),
      );
}

/// A hard fact the story must keep straight, true from [sceneId] onward and,
/// once [retiredSceneId] is set, no longer true from that scene.
class ContinuityFact {
  String category;
  String key;
  String value;
  String entity;
  String sceneId;
  String retiredSceneId;

  ContinuityFact({
    this.category = 'Fact',
    required this.key,
    this.value = '',
    this.entity = '',
    this.sceneId = '',
    this.retiredSceneId = '',
  });

  bool get isRetired => retiredSceneId.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'category': category,
    'key': key,
    'value': value,
    'entity': entity,
    'scene_id': sceneId,
    if (retiredSceneId.isNotEmpty) 'retired_scene_id': retiredSceneId,
  };

  factory ContinuityFact.fromJson(Map<String, dynamic> json) => ContinuityFact(
    category: json['category']?.toString() ?? 'Fact',
    key: _str(json['key']),
    value: _str(json['value']),
    entity: _str(json['entity']),
    sceneId: _str(json['scene_id']),
    retiredSceneId: _str(json['retired_scene_id']),
  );
}

/// A user-authored narrative lens (the built-in set lives in
/// `services/story/story_lenses.dart`).
class StoryLens {
  String id;
  String name;
  String context;
  String prompt;

  StoryLens({
    required this.id,
    this.name = '',
    this.context = '',
    this.prompt = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'context': context,
    'prompt': prompt,
  };

  factory StoryLens.fromJson(Map<String, dynamic> json) => StoryLens(
    id: _str(json['id']),
    name: _str(json['name']),
    context: _str(json['context']),
    prompt: _str(json['prompt']),
  );
}

/// One find → replace applied to a beat by the continuity fixer.
class ProseEdit {
  String find;
  String replace;

  ProseEdit({this.find = '', this.replace = ''});

  Map<String, dynamic> toJson() => {'find': find, 'replace': replace};

  factory ProseEdit.fromJson(Map<String, dynamic> json) =>
      ProseEdit(find: _str(json['find']), replace: _str(json['replace']));
}

/// Record of a surgical continuity fix so the writer can show it and undo it.
class ContinuityFix {
  String reason;

  /// The beat's prose before the fix — what Undo restores.
  String before;
  List<ProseEdit> edits;

  ContinuityFix({this.reason = '', this.before = '', List<ProseEdit>? edits})
    : edits = edits ?? [];

  Map<String, dynamic> toJson() => {
    'reason': reason,
    'before': before,
    'edits': edits.map((e) => e.toJson()).toList(),
  };

  factory ContinuityFix.fromJson(Map<String, dynamic> json) => ContinuityFix(
    reason: _str(json['reason']),
    before: _str(json['before']),
    edits: (json['edits'] as List?)
        ?.map((e) => ProseEdit.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
