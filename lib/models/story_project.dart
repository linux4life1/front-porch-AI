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

import 'dart:convert';
import 'dart:math';

part 'story_project.director.dart';
part 'story_project.project.dart';
part 'story_project.shape.dart';
part 'story_project.studio.dart';

final _idRandom = Random();

/// A short id for scenes — stable across reorders, unlike a scene's index.
String newStoryId([String prefix = 's']) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '${_idRandom.nextInt(1 << 20).toRadixString(36)}';

/// Prompt complexity tier for story generation.
enum PromptTier {
  frontier, // Cloud APIs — full complex JSON
  largLocal, // 70B+ local — simplified JSON
  smallLocal, // 7-13B local — minimal JSON, quality warning
}

/// A narrative thread that weaves through the story.
class StoryThread {
  String id;
  String name;
  String description;

  StoryThread({
    required this.id,
    required this.name,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
  };

  factory StoryThread.fromJson(Map<String, dynamic> json) => StoryThread(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    description: json['description'] ?? '',
  );
}

/// A character snapshot within a story (isolated from the original card).
class StoryCastMember {
  String name;
  String role;
  String description;
  String? voiceSample;
  String? voiceModel; // TTS voice model ID for read-along narration
  Map<String, String>
  details; // history, story_events, goals, evolution, deep_profile

  /// Studio: the lie they believe, and what they ache for.
  String flaw;
  String desire;

  /// Studio: the character answering interview questions in their own voice.
  String interview;

  /// Portrait image path or data URI; null shows initials.
  String? portrait;

  StoryCastMember({
    required this.name,
    this.role = '',
    this.description = '',
    this.voiceSample,
    this.voiceModel,
    Map<String, String>? details,
    this.flaw = '',
    this.desire = '',
    this.interview = '',
    this.portrait,
  }) : details = details ?? {};

  Map<String, dynamic> toJson() => {
    'name': name,
    'role': role,
    'description': description,
    if (voiceSample != null) 'voice_sample': voiceSample,
    if (voiceModel != null) 'voice_model': voiceModel,
    'details': details,
    if (flaw.isNotEmpty) 'flaw': flaw,
    if (desire.isNotEmpty) 'desire': desire,
    if (interview.isNotEmpty) 'interview': interview,
    if (portrait != null) 'portrait': portrait,
  };

  factory StoryCastMember.fromJson(Map<String, dynamic> json) =>
      StoryCastMember(
        name: json['name'] ?? '',
        role: json['role'] ?? '',
        description: json['description'] ?? '',
        voiceSample: json['voice_sample'],
        voiceModel: json['voice_model'],
        details:
            (json['details'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, v.toString()),
            ) ??
            {},
        flaw: json['flaw']?.toString() ?? '',
        desire: json['desire']?.toString() ?? '',
        interview: json['interview']?.toString() ?? '',
        portrait: json['portrait']?.toString(),
      );
}

/// A lore entry within a story.
class StoryLoreEntry {
  String topic;
  String detail;
  List<String> relatedTo;
  int validFromAct;
  int validFromScene;

  StoryLoreEntry({
    required this.topic,
    required this.detail,
    this.relatedTo = const [],
    this.validFromAct = 1,
    this.validFromScene = 1,
  });

  Map<String, dynamic> toJson() => {
    'topic': topic,
    'detail': detail,
    'related_to': relatedTo,
    'valid_from_act': validFromAct,
    'valid_from_scene': validFromScene,
  };

  factory StoryLoreEntry.fromJson(Map<String, dynamic> json) => StoryLoreEntry(
    topic: json['topic'] ?? '',
    detail: json['detail'] ?? '',
    relatedTo:
        (json['related_to'] as List?)?.map((e) => e.toString()).toList() ?? [],
    validFromAct: (json['valid_from_act'] as num?)?.toInt() ?? 1,
    validFromScene: (json['valid_from_scene'] as num?)?.toInt() ?? 1,
  );
}

/// Style configuration for the story.
class StoryStyle {
  String genre;
  String mood;
  String writingGuide;

  /// Studio: the long-form genre contract and tone direction.
  String genreBrief;
  String toneBrief;

  StoryStyle({
    this.genre = '',
    this.mood = '',
    this.writingGuide = '',
    this.genreBrief = '',
    this.toneBrief = '',
  });

  Map<String, dynamic> toJson() => {
    'genre': genre,
    'mood': mood,
    'writing_guide': writingGuide,
    if (genreBrief.isNotEmpty) 'genre_brief': genreBrief,
    if (toneBrief.isNotEmpty) 'tone_brief': toneBrief,
  };

  factory StoryStyle.fromJson(Map<String, dynamic> json) => StoryStyle(
    genre: json['genre'] ?? '',
    mood: json['mood'] ?? '',
    writingGuide: json['writing_guide'] ?? '',
    genreBrief: json['genre_brief']?.toString() ?? '',
    toneBrief: json['tone_brief']?.toString() ?? '',
  );
}

/// A thread convergence event within an act.
class StoryKnot {
  String description;
  String interaction;

  StoryKnot({required this.description, required this.interaction});

  Map<String, dynamic> toJson() => {
    'description': description,
    'interaction': interaction,
  };

  factory StoryKnot.fromJson(Map<String, dynamic> json) => StoryKnot(
    description: json['description'] ?? '',
    interaction: json['interaction'] ?? '',
  );
}

/// An act within the story structure.
class StoryAct {
  int number;
  String title;
  String description;
  List<String> focusThreadIds;
  List<StoryKnot> knots;

  StoryAct({
    required this.number,
    this.title = '',
    this.description = '',
    this.focusThreadIds = const [],
    this.knots = const [],
  });

  Map<String, dynamic> toJson() => {
    'number': number,
    'title': title,
    'description': description,
    'focus_thread_ids': focusThreadIds,
    'knots': knots.map((k) => k.toJson()).toList(),
  };

  factory StoryAct.fromJson(Map<String, dynamic> json) => StoryAct(
    number: (json['number'] as num?)?.toInt() ?? 1,
    title: json['title'] ?? '',
    description: json['description'] ?? '',
    focusThreadIds:
        (json['focus_thread_ids'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [],
    knots:
        (json['knots'] as List?)?.map((e) => StoryKnot.fromJson(e)).toList() ??
        [],
  );
}

/// Causality info for a scene.
class SceneCausality {
  String interactionType; // Isolation, Collision, Resonance
  String description;

  SceneCausality({this.interactionType = 'Isolation', this.description = ''});

  Map<String, dynamic> toJson() => {
    'interaction_type': interactionType,
    'description': description,
  };

  factory SceneCausality.fromJson(Map<String, dynamic> json) => SceneCausality(
    interactionType: json['interaction_type'] ?? 'Isolation',
    description: json['description'] ?? '',
  );
}

/// A scene within an act.
class StoryScene {
  int number;
  String title;
  String description;
  List<String> activeThreadIds;
  String location;
  List<String> castNames;
  int valence; // -10 to +10
  SceneCausality causality;

  /// Stable id; facts and relationship history point at it. Empty until the
  /// project assigns one (see [StoryProject.normalize]).
  String id;

  /// Global 1-based sequence number; 0 = not placed yet.
  int sequence;

  /// 'action' (someone pursues a goal) or 'reaction' (the aftermath).
  String sceneType;

  /// Narrative lens id; empty = the neutral baseline.
  String lens;

  /// Intensity, -2 (quiet) to +2 (peak).
  int tension;
  String valueFrom;
  String valueTo;
  String objective;
  String pov;

  /// Promises, reveals or terms the prose must deliver exactly.
  String commitments;
  String entry;
  String exit;

  /// What actually happened, written by the archivist after the prose.
  String summary;

  StoryScene({
    required this.number,
    this.title = '',
    this.description = '',
    this.activeThreadIds = const [],
    this.location = '',
    this.castNames = const [],
    this.valence = 0,
    SceneCausality? causality,
    this.id = '',
    this.sequence = 0,
    this.sceneType = '',
    this.lens = '',
    this.tension = 0,
    this.valueFrom = '',
    this.valueTo = '',
    this.objective = '',
    this.pov = '',
    this.commitments = '',
    this.entry = '',
    this.exit = '',
    this.summary = '',
  }) : causality = causality ?? SceneCausality();

  Map<String, dynamic> toJson() => {
    'number': number,
    'title': title,
    'description': description,
    'active_thread_ids': activeThreadIds,
    'location': location,
    'cast_names': castNames,
    'valence': valence,
    'causality': causality.toJson(),
    'id': id,
    'sequence': sequence,
    if (sceneType.isNotEmpty) 'scene_type': sceneType,
    if (lens.isNotEmpty) 'lens': lens,
    if (tension != 0) 'tension': tension,
    if (valueFrom.isNotEmpty) 'value_from': valueFrom,
    if (valueTo.isNotEmpty) 'value_to': valueTo,
    if (objective.isNotEmpty) 'objective': objective,
    if (pov.isNotEmpty) 'pov': pov,
    if (commitments.isNotEmpty) 'commitments': commitments,
    if (entry.isNotEmpty) 'entry': entry,
    if (exit.isNotEmpty) 'exit': exit,
    if (summary.isNotEmpty) 'summary': summary,
  };

  factory StoryScene.fromJson(Map<String, dynamic> json) => StoryScene(
    number: (json['number'] as num?)?.toInt() ?? 1,
    title: json['title'] ?? '',
    description: json['description'] ?? '',
    activeThreadIds:
        (json['active_thread_ids'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [],
    location: json['location'] ?? '',
    castNames:
        (json['cast_names'] as List?)?.map((e) => e.toString()).toList() ?? [],
    valence: (json['valence'] as num?)?.toInt() ?? 0,
    causality: json['causality'] != null
        ? SceneCausality.fromJson(json['causality'])
        : SceneCausality(),
    id: json['id']?.toString() ?? '',
    sequence: (json['sequence'] as num?)?.toInt() ?? 0,
    sceneType: json['scene_type']?.toString() ?? '',
    lens: json['lens']?.toString() ?? '',
    tension: ((json['tension'] as num?)?.toInt() ?? 0).clamp(-2, 2),
    valueFrom: json['value_from']?.toString() ?? '',
    valueTo: json['value_to']?.toString() ?? '',
    objective: json['objective']?.toString() ?? '',
    pov: json['pov']?.toString() ?? '',
    commitments: json['commitments']?.toString() ?? '',
    entry: json['entry']?.toString() ?? '',
    exit: json['exit']?.toString() ?? '',
    summary: json['summary']?.toString() ?? '',
  );
}

/// A beat within a scene — the smallest narrative unit.
class StoryBeat {
  int number;
  String type; // Action, Reaction, Dialogue, Revelation, Resolution
  String description;
  String emotionalShift;
  int valence; // -10 to +10
  int pacing; // 0=Slow, 1=Balanced, 2=Fast

  /// Studio choreography: who acts, who answers, what is left unsaid, and
  /// the one irreversible thing this beat establishes.
  String initiator;
  String reactor;
  String subtext;
  String anchor;

  StoryBeat({
    required this.number,
    this.type = 'Action',
    this.description = '',
    this.emotionalShift = '',
    this.valence = 0,
    this.pacing = 1,
    this.initiator = '',
    this.reactor = '',
    this.subtext = '',
    this.anchor = '',
  });

  Map<String, dynamic> toJson() => {
    'number': number,
    'type': type,
    'description': description,
    'emotional_shift': emotionalShift,
    'valence': valence,
    'pacing': pacing,
    if (initiator.isNotEmpty) 'initiator': initiator,
    if (reactor.isNotEmpty) 'reactor': reactor,
    if (subtext.isNotEmpty) 'subtext': subtext,
    if (anchor.isNotEmpty) 'anchor': anchor,
  };

  factory StoryBeat.fromJson(Map<String, dynamic> json) => StoryBeat(
    number: (json['number'] as num?)?.toInt() ?? 1,
    type: json['type'] ?? 'Action',
    description: json['description'] ?? '',
    emotionalShift: json['emotional_shift'] ?? '',
    valence: (json['valence'] as num?)?.toInt() ?? 0,
    pacing: (json['pacing'] as num?)?.toInt() ?? 1,
    initiator: json['initiator']?.toString() ?? '',
    reactor: json['reactor']?.toString() ?? '',
    subtext: json['subtext']?.toString() ?? '',
    anchor: json['anchor']?.toString() ?? '',
  );
}

/// Prose content for a single beat.
class BeatProse {
  String? draft;
  String? final_;

  /// Set when the continuity check patched this beat; null otherwise.
  ContinuityFix? fix;

  BeatProse({this.draft, this.final_, this.fix});

  Map<String, dynamic> toJson() => {
    if (draft != null) 'draft': draft,
    if (final_ != null) 'final': final_,
    if (fix != null) 'fix': fix!.toJson(),
  };

  factory BeatProse.fromJson(Map<String, dynamic> json) => BeatProse(
    draft: json['draft'],
    final_: json['final'],
    fix: json['fix'] is Map<String, dynamic>
        ? ContinuityFix.fromJson(json['fix'])
        : null,
  );
}
