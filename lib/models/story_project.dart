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

/// Prompt complexity tier for story generation.
enum PromptTier {
  frontier,   // Cloud APIs — full complex JSON
  largLocal,  // 70B+ local — simplified JSON
  smallLocal, // 7-13B local — minimal JSON, quality warning
}

/// A narrative thread that weaves through the story.
class StoryThread {
  String id;
  String name;
  String description;

  StoryThread({required this.id, required this.name, required this.description});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'description': description};

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
  Map<String, String> details; // history, story_events, goals, evolution, deep_profile

  StoryCastMember({
    required this.name,
    this.role = '',
    this.description = '',
    this.voiceSample,
    this.voiceModel,
    Map<String, String>? details,
  }) : details = details ?? {};

  Map<String, dynamic> toJson() => {
    'name': name,
    'role': role,
    'description': description,
    if (voiceSample != null) 'voice_sample': voiceSample,
    if (voiceModel != null) 'voice_model': voiceModel,
    'details': details,
  };

  factory StoryCastMember.fromJson(Map<String, dynamic> json) => StoryCastMember(
    name: json['name'] ?? '',
    role: json['role'] ?? '',
    description: json['description'] ?? '',
    voiceSample: json['voice_sample'],
    voiceModel: json['voice_model'],
    details: (json['details'] as Map<String, dynamic>?)
        ?.map((k, v) => MapEntry(k, v.toString())) ?? {},
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
    relatedTo: (json['related_to'] as List?)?.map((e) => e.toString()).toList() ?? [],
    validFromAct: (json['valid_from_act'] as num?)?.toInt() ?? 1,
    validFromScene: (json['valid_from_scene'] as num?)?.toInt() ?? 1,
  );
}

/// Style configuration for the story.
class StoryStyle {
  String genre;
  String mood;
  String writingGuide;

  StoryStyle({this.genre = '', this.mood = '', this.writingGuide = ''});

  Map<String, dynamic> toJson() => {
    'genre': genre,
    'mood': mood,
    'writing_guide': writingGuide,
  };

  factory StoryStyle.fromJson(Map<String, dynamic> json) => StoryStyle(
    genre: json['genre'] ?? '',
    mood: json['mood'] ?? '',
    writingGuide: json['writing_guide'] ?? '',
  );
}

/// A thread convergence event within an act.
class StoryKnot {
  String description;
  String interaction;

  StoryKnot({required this.description, required this.interaction});

  Map<String, dynamic> toJson() => {'description': description, 'interaction': interaction};

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
    focusThreadIds: (json['focus_thread_ids'] as List?)?.map((e) => e.toString()).toList() ?? [],
    knots: (json['knots'] as List?)?.map((e) => StoryKnot.fromJson(e)).toList() ?? [],
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

  StoryScene({
    required this.number,
    this.title = '',
    this.description = '',
    this.activeThreadIds = const [],
    this.location = '',
    this.castNames = const [],
    this.valence = 0,
    SceneCausality? causality,
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
  };

  factory StoryScene.fromJson(Map<String, dynamic> json) => StoryScene(
    number: (json['number'] as num?)?.toInt() ?? 1,
    title: json['title'] ?? '',
    description: json['description'] ?? '',
    activeThreadIds: (json['active_thread_ids'] as List?)?.map((e) => e.toString()).toList() ?? [],
    location: json['location'] ?? '',
    castNames: (json['cast_names'] as List?)?.map((e) => e.toString()).toList() ?? [],
    valence: (json['valence'] as num?)?.toInt() ?? 0,
    causality: json['causality'] != null
        ? SceneCausality.fromJson(json['causality'])
        : SceneCausality(),
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

  StoryBeat({
    required this.number,
    this.type = 'Action',
    this.description = '',
    this.emotionalShift = '',
    this.valence = 0,
    this.pacing = 1,
  });

  Map<String, dynamic> toJson() => {
    'number': number,
    'type': type,
    'description': description,
    'emotional_shift': emotionalShift,
    'valence': valence,
    'pacing': pacing,
  };

  factory StoryBeat.fromJson(Map<String, dynamic> json) => StoryBeat(
    number: (json['number'] as num?)?.toInt() ?? 1,
    type: json['type'] ?? 'Action',
    description: json['description'] ?? '',
    emotionalShift: json['emotional_shift'] ?? '',
    valence: (json['valence'] as num?)?.toInt() ?? 0,
    pacing: (json['pacing'] as num?)?.toInt() ?? 1,
  );
}

/// Prose content for a single beat.
class BeatProse {
  String? draft;
  String? final_;

  BeatProse({this.draft, this.final_});

  Map<String, dynamic> toJson() => {
    if (draft != null) 'draft': draft,
    if (final_ != null) 'final': final_,
  };

  factory BeatProse.fromJson(Map<String, dynamic> json) => BeatProse(
    draft: json['draft'],
    final_: json['final'],
  );
}

/// The top-level story project model.
class StoryProject {
  String? dbId; // UUID primary key
  String title;
  String concept;
  String statusQuo;
  String incitingIncident;
  String themes;
  StoryStyle style;
  PromptTier promptTier;
  bool useChatHistory; // Whether to draw from character chat history RAG
  List<String> chatHistoryCharacterIds; // Character embed IDs to pull RAG from
  List<Map<String, String>> characterCardSnapshots; // Snapshotted character card data
  bool parallelGeneration; // Whether to run scene generation in parallel (requires compatible backend)
  bool includeUserPersona; // Whether to include the user's persona as a story character
  String userPersonaRole; // Role for the user persona: 'Protagonist', 'Supporting', etc.

  // ── Story Customization Options ──
  String pov; // 'First Person', 'Third Person Limited', 'Third Person Omniscient'
  int actCount; // 1-5
  List<String> selectedGenres; // Multi-select: Fantasy, Sci-Fi, etc.
  List<String> selectedMoods; // Multi-select: Dark, Light, etc.
  String writingStyle; // Minimalist, Lyrical, Pulpy, Literary, etc.
  String proseLength; // 'Short', 'Standard', 'Epic'
  String narrativePace; // 'Slow Burn', 'Balanced', 'Fast-Paced'
  String dialogueDensity; // 'Sparse', 'Balanced', 'Dialogue-Heavy'
  String maturityRating; // 'Clean', 'Mature', 'Explicit'
  String distilledTimeline; // LLM-distilled event timeline from chat history
  int lastReadPageIndex; // Index of the last read page for resuming text

  List<StoryCastMember> cast;
  List<StoryThread> threads;
  List<StoryLoreEntry> lore;
  List<StoryAct> acts;

  // Scenes indexed by act number (0-based)
  Map<int, List<StoryScene>> scenes;

  // Beats indexed by "actIdx-sceneIdx"
  Map<String, List<StoryBeat>> beats;

  // Prose indexed by "actIdx-sceneIdx-beatIdx"
  Map<String, BeatProse> prose;

  DateTime createdAt;
  DateTime updatedAt;

  StoryProject({
    this.dbId,
    this.title = 'Untitled Story',
    this.concept = '',
    this.statusQuo = '',
    this.incitingIncident = '',
    this.themes = '',
    StoryStyle? style,
    this.promptTier = PromptTier.frontier,
    this.useChatHistory = false,
    this.chatHistoryCharacterIds = const [],
    this.characterCardSnapshots = const [],
    this.parallelGeneration = false,
    this.includeUserPersona = false,
    this.userPersonaRole = 'Protagonist',
    this.pov = 'Third Person Limited',
    this.actCount = 3,
    List<String>? selectedGenres,
    List<String>? selectedMoods,
    this.writingStyle = '',
    this.proseLength = 'Standard',
    this.narrativePace = 'Balanced',
    this.dialogueDensity = 'Balanced',
    this.maturityRating = 'Mature',
    this.distilledTimeline = '',
    this.lastReadPageIndex = 0,
    List<StoryCastMember>? cast,
    List<StoryThread>? threads,
    List<StoryLoreEntry>? lore,
    List<StoryAct>? acts,
    Map<int, List<StoryScene>>? scenes,
    Map<String, List<StoryBeat>>? beats,
    Map<String, BeatProse>? prose,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : style = style ?? StoryStyle(),
        selectedGenres = selectedGenres ?? [],
        selectedMoods = selectedMoods ?? [],
        cast = cast ?? [],
        threads = threads ?? [],
        lore = lore ?? [],
        acts = acts ?? [],
        scenes = scenes ?? {},
        beats = beats ?? {},
        prose = prose ?? {},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Serialize the entire project to JSON string for database storage.
  String toJsonString() => jsonEncode(toJson());

  Map<String, dynamic> toJson() => {
    'title': title,
    'concept': concept,
    'status_quo': statusQuo,
    'inciting_incident': incitingIncident,
    'themes': themes,
    'style': style.toJson(),
    'prompt_tier': promptTier.name,
    'use_chat_history': useChatHistory,
    'chat_history_character_ids': chatHistoryCharacterIds,
    'character_card_snapshots': characterCardSnapshots,
    'parallel_generation': parallelGeneration,
    'include_user_persona': includeUserPersona,
    'user_persona_role': userPersonaRole,
    'pov': pov,
    'act_count': actCount,
    'selected_genres': selectedGenres,
    'selected_moods': selectedMoods,
    'writing_style': writingStyle,
    'prose_length': proseLength,
    'narrative_pace': narrativePace,
    'dialogue_density': dialogueDensity,
    'maturity_rating': maturityRating,
    'distilled_timeline': distilledTimeline,
    'last_read_page_index': lastReadPageIndex,
    'cast': cast.map((c) => c.toJson()).toList(),
    'threads': threads.map((t) => t.toJson()).toList(),
    'lore': lore.map((l) => l.toJson()).toList(),
    'acts': acts.map((a) => a.toJson()).toList(),
    'scenes': scenes.map((k, v) => MapEntry(k.toString(), v.map((s) => s.toJson()).toList())),
    'beats': beats.map((k, v) => MapEntry(k, v.map((b) => b.toJson()).toList())),
    'prose': prose.map((k, v) => MapEntry(k, v.toJson())),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory StoryProject.fromJsonString(String jsonStr) =>
      StoryProject.fromJson(jsonDecode(jsonStr));

  factory StoryProject.fromJson(Map<String, dynamic> json) {
    final scenesMap = <int, List<StoryScene>>{};
    if (json['scenes'] != null) {
      (json['scenes'] as Map<String, dynamic>).forEach((k, v) {
        scenesMap[int.parse(k)] = (v as List).map((s) => StoryScene.fromJson(s)).toList();
      });
    }

    final beatsMap = <String, List<StoryBeat>>{};
    if (json['beats'] != null) {
      (json['beats'] as Map<String, dynamic>).forEach((k, v) {
        beatsMap[k] = (v as List).map((b) => StoryBeat.fromJson(b)).toList();
      });
    }

    final proseMap = <String, BeatProse>{};
    if (json['prose'] != null) {
      (json['prose'] as Map<String, dynamic>).forEach((k, v) {
        proseMap[k] = BeatProse.fromJson(v);
      });
    }

    return StoryProject(
      title: json['title'] ?? 'Untitled Story',
      concept: json['concept'] ?? '',
      statusQuo: json['status_quo'] ?? '',
      incitingIncident: json['inciting_incident'] ?? '',
      themes: json['themes'] ?? '',
      style: json['style'] != null ? StoryStyle.fromJson(json['style']) : null,
      promptTier: PromptTier.values.firstWhere(
        (e) => e.name == json['prompt_tier'],
        orElse: () => PromptTier.frontier,
      ),
      useChatHistory: json['use_chat_history'] ?? false,
      chatHistoryCharacterIds: (json['chat_history_character_ids'] as List?)
          ?.map((e) => e.toString()).toList() ?? [],
      characterCardSnapshots: (json['character_card_snapshots'] as List?)
          ?.map((e) => (e as Map<String, dynamic>).map((k, v) => MapEntry(k, v.toString())))
          .toList() ?? [],
      parallelGeneration: json['parallel_generation'] ?? false,
      includeUserPersona: json['include_user_persona'] ?? false,
      userPersonaRole: json['user_persona_role'] ?? 'Protagonist',
      pov: json['pov'] ?? 'Third Person Limited',
      actCount: (json['act_count'] as num?)?.toInt() ?? 3,
      selectedGenres: (json['selected_genres'] as List?)?.map((e) => e.toString()).toList(),
      selectedMoods: (json['selected_moods'] as List?)?.map((e) => e.toString()).toList(),
      writingStyle: json['writing_style'] ?? '',
      proseLength: json['prose_length'] ?? 'Standard',
      narrativePace: json['narrative_pace'] ?? 'Balanced',
      dialogueDensity: json['dialogue_density'] ?? 'Balanced',
      maturityRating: json['maturity_rating'] ?? 'Mature',
      distilledTimeline: json['distilled_timeline'] ?? '',
      lastReadPageIndex: (json['last_read_page_index'] as num?)?.toInt() ?? 0,
      cast: (json['cast'] as List?)?.map((c) => StoryCastMember.fromJson(c)).toList(),
      threads: (json['threads'] as List?)?.map((t) => StoryThread.fromJson(t)).toList(),
      lore: (json['lore'] as List?)?.map((l) => StoryLoreEntry.fromJson(l)).toList(),
      acts: (json['acts'] as List?)?.map((a) => StoryAct.fromJson(a)).toList(),
      scenes: scenesMap,
      beats: beatsMap,
      prose: proseMap,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
    );
  }
}
