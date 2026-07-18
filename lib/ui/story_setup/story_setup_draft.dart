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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/story_project.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

/// All the choices the Story Setup wizard collects, held mutably while the
/// user walks the steps, with load-from / apply-to [StoryProject] round-trips.
/// The step widgets mutate this and call their `onChanged` so the wizard page
/// rebuilds; nothing persists until the final "Generate Story Bible".
class StorySetupDraft {
  final titleController = TextEditingController();
  final conceptController = TextEditingController();

  // Story customization.
  String pov = 'Third Person Limited';
  int actCount = 3;
  final Set<String> selectedGenres = {};
  final Set<String> selectedMoods = {};
  String writingStyle = '';
  String proseLength = 'Standard';
  String narrativePace = 'Balanced';
  String dialogueDensity = 'Balanced';
  String maturityRating = 'Mature';

  // AI config.
  PromptTier tier = PromptTier.frontier;
  bool useChatHistory = false;
  bool parallelGeneration = false;
  final Set<String> selectedCharacterIds = {};
  final Map<String, String> characterRoles = {}; // charDbId -> role
  bool includeUserPersona = false;
  String userPersonaRole = 'Protagonist';

  void dispose() {
    titleController.dispose();
    conceptController.dispose();
  }

  void loadFrom(StoryProject project, CharacterRepository charRepo) {
    titleController.text = project.title;
    conceptController.text = project.concept;
    tier = project.promptTier;
    useChatHistory = project.useChatHistory;
    parallelGeneration = project.parallelGeneration;
    selectedCharacterIds.addAll(project.chatHistoryCharacterIds);
    includeUserPersona = project.includeUserPersona;
    userPersonaRole = project.userPersonaRole;
    // Restore roles from snapshots (matched by name).
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

  /// Write every choice onto [project], including the character/persona card
  /// snapshots the pipeline reads (roles ride along).
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
    project.useChatHistory = useChatHistory;
    project.parallelGeneration = parallelGeneration;
    project.chatHistoryCharacterIds = selectedCharacterIds.toList();
    project.includeUserPersona = includeUserPersona;
    project.userPersonaRole = userPersonaRole;

    project.pov = pov;
    project.actCount = actCount;
    project.selectedGenres = selectedGenres.toList();
    project.selectedMoods = selectedMoods.toList();
    project.writingStyle = writingStyle;
    project.proseLength = proseLength;
    project.narrativePace = narrativePace;
    project.dialogueDensity = dialogueDensity;
    project.maturityRating = maturityRating;

    final snapshots = <Map<String, String>>[];
    if (useChatHistory && selectedCharacterIds.isNotEmpty) {
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

const storyRoleOptions = [
  'Protagonist',
  'Antagonist',
  'Supporting',
  'Love Interest',
  'Mentor',
];

const storyPovOptions = [
  'First Person',
  'Third Person Limited',
  'Third Person Omniscient',
];

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

const storyProseLengths = {
  'Short': 'Novella (~20K words)',
  'Standard': 'Novel (~50K words)',
  'Epic': 'Long novel (~80K+ words)',
};

const storyPaceOptions = {
  'Slow Burn': 'Atmospheric, detailed worldbuilding',
  'Balanced': 'Mix of action and reflection',
  'Fast-Paced': 'Tight scenes, rapid plot movement',
};

const storyDialogueOptions = {
  'Sparse': 'Mostly narrative prose',
  'Balanced': 'Even mix of dialogue and prose',
  'Dialogue-Heavy': 'Character-driven, lots of conversation',
};

const storyMaturityOptions = {
  'Clean': 'All ages, no violence or language',
  'Mature': 'Adult themes, moderate violence',
  'Explicit': 'Graphic content, no restrictions',
};

/// Prompt-style names, reworded so they read as "how the prompts are written
/// for your model", not as a model picker (users mistook the old "Large Local
/// Models (70B+)" labels for actually selecting a model — the AI Engine card
/// on the first wizard step is where the real engine lives).
String storyTierName(PromptTier tier) {
  switch (tier) {
    case PromptTier.frontier:
      return 'Full detail — for cloud APIs';
    case PromptTier.largLocal:
      return 'Rich — for big local models (70B+)';
    case PromptTier.smallLocal:
      return 'Simplified — for small local models (7-34B)';
  }
}

String storyTierDescription(PromptTier tier) {
  switch (tier) {
    case PromptTier.frontier:
      return 'The most demanding prompts. Best with GPT, Claude, Gemini or '
          'another remote API.';
    case PromptTier.largLocal:
      return 'Detailed prompts a strong local model can follow — fully '
          'offline.';
    case PromptTier.smallLocal:
      return 'Shorter, stricter prompts so smaller models stay on track. '
          'Story quality may vary.';
  }
}
