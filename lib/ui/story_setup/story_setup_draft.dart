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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story.dart';

/// The chat a story starts from (sketch I): one character, one session.
class StoryChatSource {
  final String characterId;
  final String characterName;
  final String sessionId;
  final String recap;
  final String userName;
  final int messageCount;
  final DateTime? lastAt;
  bool faithful;

  StoryChatSource({
    required this.characterId,
    required this.characterName,
    required this.sessionId,
    required this.recap,
    required this.userName,
    this.messageCount = 0,
    this.lastAt,
    this.faithful = true,
  });
}

/// Everything the New Story flow collects (Idea → Cast → Shape → Engine),
/// held mutably while the user walks the steps. The page saves the project
/// after every step, so backing out keeps the draft and the shelf shows
/// where it stopped.
class StorySetupDraft {
  final titleController = TextEditingController();
  final conceptController = TextEditingController();

  // Idea.
  StoryChatSource? chatSource;

  // Cast.
  final Set<String> selectedCharacterIds = {};
  final Map<String, String> characterRoles = {}; // charDbId -> role
  bool includeUserPersona = false;
  String userPersonaRole = 'Love Interest';
  bool useChatHistory = false;

  // Shape.
  String proseLength = 'Standard';
  StoryFormat storyFormat = StoryFormat.novel;
  String pov = 'Third Person Limited';
  final Set<String> selectedGenres = {};
  final Set<String> selectedMoods = {};
  String writingStyle = '';
  String narrativePace = 'Balanced';
  String dialogueDensity = 'Balanced';
  String maturityRating = 'Mature';

  // Engine.
  StoryEngineMode engineMode = StoryEngineMode.studio;
  int actCount = 3;
  bool reviewEnabled = true;
  bool lensesEnabled = true;
  StoryLaneChoice planningLane = StoryLaneChoice.chat();
  StoryLaneChoice proseLane = StoryLaneChoice.chat();
  StoryLaneChoice reviewLane = StoryLaneChoice.worker();
  PromptTier tier = PromptTier.frontier;

  int get targetWords => targetWordsForLength(proseLength);

  void dispose() {
    titleController.dispose();
    conceptController.dispose();
  }

  void loadFrom(StoryProject project, CharacterRepository charRepo) {
    titleController.text = project.title == 'Untitled Story'
        ? ''
        : project.title;
    conceptController.text = project.concept;
    tier = project.promptTier;
    final fresh = project.concept.trim().isEmpty && project.acts.isEmpty;
    engineMode = fresh ? StoryEngineMode.studio : project.engineMode;
    storyFormat = project.storyFormat;
    planningLane = project.planningLane.copy();
    proseLane = project.proseLane.copy();
    reviewLane = project.reviewLane.copy();
    reviewEnabled = project.reviewEnabled;
    lensesEnabled = project.lensesEnabled;
    useChatHistory = project.useChatHistory;
    selectedCharacterIds.addAll(project.chatHistoryCharacterIds);
    includeUserPersona = project.includeUserPersona;
    if (project.userPersonaRole.isNotEmpty) {
      userPersonaRole = project.userPersonaRole;
    }
    for (final snap in project.characterCardSnapshots) {
      final name = snap['name'] ?? '';
      final role = snap['role'] ?? 'Supporting';
      for (final c in charRepo.characters) {
        if (c.dbId != null &&
            c.name == name &&
            selectedCharacterIds.contains(c.dbId)) {
          characterRoles[c.dbId!] = role;
        }
      }
    }
    if (project.chatHistorySessionIds.isNotEmpty &&
        project.chatHistoryCharacterIds.isNotEmpty) {
      final id = project.chatHistoryCharacterIds.first;
      final name = charRepo.characters
          .where((c) => c.dbId == id)
          .map((c) => c.name)
          .firstOrNull;
      chatSource = StoryChatSource(
        characterId: id,
        characterName: name ?? 'the chat',
        sessionId: project.chatHistorySessionIds.first,
        recap: '',
        userName: '',
        faithful: project.faithfulMode,
      );
    }
    pov = project.pov;
    actCount = project.actCount;
    selectedGenres.addAll(project.selectedGenres);
    selectedMoods.addAll(project.selectedMoods);
    writingStyle = project.writingStyle;
    proseLength = project.proseLength;
    narrativePace = project.narrativePace;
    dialogueDensity = project.dialogueDensity;
    maturityRating = project.maturityRating;
  }

  /// Start from a chat: the character joins the cast as protagonist, the
  /// chat becomes canon, and the title/concept get a sensible seed if empty.
  void adoptChat(StoryChatSource source) {
    chatSource = source;
    useChatHistory = true;
    selectedCharacterIds.add(source.characterId);
    characterRoles.putIfAbsent(source.characterId, () => 'Protagonist');
    if (conceptController.text.trim().isEmpty) {
      conceptController.text = source.faithful
          ? 'A faithful novelization of the roleplay between '
                '${source.characterName} and ${source.userName}: the real '
                'events of their chat, retold as prose.'
                '${source.recap.trim().isEmpty ? '' : '\n\nWhere the story stands: ${source.recap}'}'
          : 'A story inspired by the roleplay between '
                '${source.characterName} and ${source.userName}.';
    }
  }

  void dropChat() {
    final source = chatSource;
    chatSource = null;
    useChatHistory = false;
    if (source != null) {
      selectedCharacterIds.remove(source.characterId);
      characterRoles.remove(source.characterId);
    }
  }

  /// Write every choice onto [project], including the character/persona
  /// card snapshots the pipeline reads (roles ride along).
  void applyTo(
    StoryProject project,
    CharacterRepository charRepo,
    UserPersonaService personaService,
  ) {
    project.title = titleController.text.trim().isEmpty
        ? 'Untitled Story'
        : titleController.text.trim();
    project.concept = conceptController.text.trim();
    project.promptTier = tier;
    project.engineMode = engineMode;
    project.targetWords = targetWords;
    project.storyFormat = storyFormat;
    project.planningLane = planningLane;
    project.proseLane = proseLane;
    project.reviewLane = reviewLane;
    project.reviewEnabled = reviewEnabled;
    project.lensesEnabled = lensesEnabled;
    project.useChatHistory = useChatHistory && selectedCharacterIds.isNotEmpty;
    project.chatHistoryCharacterIds = selectedCharacterIds.toList();
    final source = chatSource;
    project.chatHistorySessionIds = source == null ? [] : [source.sessionId];
    project.faithfulMode = source?.faithful ?? false;
    project.includeUserPersona = includeUserPersona;
    project.userPersonaRole = userPersonaRole;

    project.pov = pov;
    // Studio always builds three acts and eight sequences.
    project.actCount = engineMode == StoryEngineMode.studio
        ? StoryPacing.actCount
        : actCount;
    project.selectedGenres = selectedGenres.toList();
    project.selectedMoods = selectedMoods.toList();
    project.writingStyle = writingStyle;
    project.proseLength = proseLength;
    project.narrativePace = narrativePace;
    project.dialogueDensity = dialogueDensity;
    project.maturityRating = maturityRating;

    final snapshots = <Map<String, String>>[];
    for (final char in charRepo.characters) {
      if (char.dbId != null && selectedCharacterIds.contains(char.dbId)) {
        snapshots.add({
          'name': char.name,
          'description': char.description,
          'personality': char.personality,
          'scenario': char.scenario,
          'first_message': char.firstMessage,
          'system_prompt': char.systemPrompt,
          'role': characterRoles[char.dbId!] ?? 'Supporting',
        });
      }
    }
    if (includeUserPersona) {
      final persona = personaService.persona;
      snapshots.add({
        'name': persona.name,
        'personality': persona.persona,
        'scenario': '',
        'first_message': '',
        'system_prompt': '',
        'role': userPersonaRole,
        'self_insert': 'true',
      });
    }
    project.characterCardSnapshots = snapshots;
  }
}

// ── Option lists shared by the setup steps ──────────────────────────────────
// Stored values are what the prompts read; the labels are what the user
// sees (sketches J–L).

const storyRoleOptions = [
  'Protagonist',
  'Antagonist',
  'Supporting',
  'Love Interest',
  'Mentor',
];

const storyPovOptions = {
  'First Person': 'First person',
  'Third Person Limited': 'Third person, close',
  'Third Person Omniscient': 'Third person, wide',
};

const storyGenreOptions = [
  'Fantasy',
  'Sci-Fi',
  'Romance',
  'Thriller',
  'Horror',
  'Literary Fiction',
  'Mystery',
  'Historical',
  'Comedy',
  'Drama',
  'Adventure',
  'Dystopian',
  'Paranormal',
  'Western',
  'Slice of Life',
];

const storyMoodOptions = [
  'Dark',
  'Light',
  'Gritty',
  'Whimsical',
  'Melancholy',
  'Tense',
  'Hopeful',
  'Bittersweet',
  'Eerie',
  'Nostalgic',
  'Epic',
  'Intimate',
  'Satirical',
];

const storyWritingStyles = [
  'Minimalist',
  'Lyrical/Poetic',
  'Pulpy/Action',
  'Literary',
  'Conversational',
  'Gothic',
  'Hardboiled',
  'Philosophical',
  'Cinematic',
  'Fairy-Tale',
];

const storyLengthOptions = {
  'Short': 'Novella · 30k',
  'Standard': 'Novel · 80k',
  'Epic': 'Epic · 120k',
};

const storyPaceOptions = {
  'Slow Burn': 'Slow',
  'Balanced': 'Even',
  'Fast-Paced': 'Fast',
};

const storyDialogueOptions = {
  'Sparse': 'Sparse',
  'Balanced': 'Balanced',
  'Dialogue-Heavy': 'Heavy',
};

const storyMaturityOptions = {
  'Clean': 'All ages',
  'Mature': 'Mature',
  'Explicit': '18+',
};

const storyTierOptions = {
  PromptTier.frontier: 'Full detail',
  PromptTier.largLocal: 'Rich',
  PromptTier.smallLocal: 'Simplified',
};
