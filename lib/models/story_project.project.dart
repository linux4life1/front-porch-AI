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

  /// Living Time §4: when non-empty, the distiller and raw-history fallback
  /// read ONLY these session ids (a single chat) instead of every session for
  /// the character. Additive — old projects deserialize to empty (= all).
  List<String> chatHistorySessionIds;

  /// Living Time §4: faithful-retelling mode — the architect and scene
  /// weaver are constrained to follow the distilled chat events in order
  /// rather than treating them as inspiration.
  bool faithfulMode;
  List<Map<String, String>>
  characterCardSnapshots; // Snapshotted character card data
  bool
  parallelGeneration; // Whether to run scene generation in parallel (requires compatible backend)
  bool
  includeUserPersona; // Whether to include the user's persona as a story character
  String
  userPersonaRole; // Role for the user persona: 'Protagonist', 'Supporting', etc.

  // ── Story Customization Options ──
  String
  pov; // 'First Person', 'Third Person Limited', 'Third Person Omniscient'
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
    this.chatHistorySessionIds = const [],
    this.faithfulMode = false,
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
  }) : style = style ?? StoryStyle(),
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
    'chat_history_session_ids': chatHistorySessionIds,
    'faithful_mode': faithfulMode,
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
    'scenes': scenes.map(
      (k, v) => MapEntry(k.toString(), v.map((s) => s.toJson()).toList()),
    ),
    'beats': beats.map(
      (k, v) => MapEntry(k, v.map((b) => b.toJson()).toList()),
    ),
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
        scenesMap[int.parse(k)] = (v as List)
            .map((s) => StoryScene.fromJson(s))
            .toList();
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
      chatHistorySessionIds: List<String>.from(
        json['chat_history_session_ids'] ?? const [],
      ),
      faithfulMode: json['faithful_mode'] ?? false,
      chatHistoryCharacterIds:
          (json['chat_history_character_ids'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      characterCardSnapshots:
          (json['character_card_snapshots'] as List?)
              ?.map(
                (e) => (e as Map<String, dynamic>).map(
                  (k, v) => MapEntry(k, v.toString()),
                ),
              )
              .toList() ??
          [],
      parallelGeneration: json['parallel_generation'] ?? false,
      includeUserPersona: json['include_user_persona'] ?? false,
      userPersonaRole: json['user_persona_role'] ?? 'Protagonist',
      pov: json['pov'] ?? 'Third Person Limited',
      actCount: (json['act_count'] as num?)?.toInt() ?? 3,
      selectedGenres: (json['selected_genres'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      selectedMoods: (json['selected_moods'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      writingStyle: json['writing_style'] ?? '',
      proseLength: json['prose_length'] ?? 'Standard',
      narrativePace: json['narrative_pace'] ?? 'Balanced',
      dialogueDensity: json['dialogue_density'] ?? 'Balanced',
      maturityRating: json['maturity_rating'] ?? 'Mature',
      distilledTimeline: json['distilled_timeline'] ?? '',
      lastReadPageIndex: (json['last_read_page_index'] as num?)?.toInt() ?? 0,
      cast: (json['cast'] as List?)
          ?.map((c) => StoryCastMember.fromJson(c))
          .toList(),
      threads: (json['threads'] as List?)
          ?.map((t) => StoryThread.fromJson(t))
          .toList(),
      lore: (json['lore'] as List?)
          ?.map((l) => StoryLoreEntry.fromJson(l))
          .toList(),
      acts: (json['acts'] as List?)?.map((a) => StoryAct.fromJson(a)).toList(),
      scenes: scenesMap,
      beats: beatsMap,
      prose: proseMap,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }
}
