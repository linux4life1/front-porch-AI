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
import 'package:front_porch_ai/ui/story_studio/story_world_lookup.dart';

/// The chat a story starts from (sketch I): one character and one session,
/// or a group chat with its roster (docs/design/stories-from-group-chats.md):
/// then [characterName] is the group's name, [characterId] its first
/// member's id (the default lead) and [members] the roster, cards included.
class StoryChatSource {
  final String characterId;
  final String characterName;
  final String sessionId;
  final String recap;
  final String userName;
  final int messageCount;
  final DateTime? lastAt;
  bool faithful;
  final String? groupId;
  final List<StoryChatMember> members;

  StoryChatSource({
    required this.characterId,
    required this.characterName,
    required this.sessionId,
    required this.recap,
    required this.userName,
    this.messageCount = 0,
    this.lastAt,
    this.faithful = true,
    this.groupId,
    this.members = const [],
  });

  bool get isGroup => groupId != null;

  /// Who joins the cast: the roster, or the one character.
  List<String> get castIds =>
      isGroup ? [for (final m in members) m.id] : [characterId];

  /// "Mira, Dov & Ash", or the character's name.
  String get castLine =>
      isGroup ? joinCastNames(members.map((m) => m.name)) : characterName;
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

  /// Where the story happens: a Living World, as the Idea step picked it.
  StoryWorldPick? world;

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

  /// A faithful retelling takes its genre and mood from the chat: the Shape
  /// step hides both pickers and nothing picked earlier is saved.
  bool get toneFromChat => chatSource?.faithful ?? false;

  /// Shown under Length when a faithful chat is too small for it.
  String? get lengthWarning => toneFromChat
      ? chatLengthWarning(chatSource!.messageCount, proseLength)
      : null;

  void dispose() {
    titleController.dispose();
    conceptController.dispose();
  }

  void loadFrom(
    StoryProject project,
    CharacterRepository charRepo, {
    WorldRepository? worlds,
  }) {
    titleController.text = project.title == 'Untitled Story'
        ? ''
        : project.title;
    conceptController.text = project.concept;
    world = storyWorldPickFromProject(project, worlds);
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
    final groupId = project.chatGroupId;
    final members = <StoryChatMember>[];
    for (final snap in project.characterCardSnapshots) {
      final name = snap['name'] ?? '';
      final role = snap['role'] ?? 'Supporting';
      final id = snap['id'];
      // A group member's snapshot carries its id and its card: the roster
      // is rebuilt from the snapshots, not the library.
      if (groupId != null &&
          id != null &&
          snap['self_insert'] != 'true' &&
          selectedCharacterIds.contains(id)) {
        characterRoles[id] = role;
        members.add(
          StoryChatMember(
            id: id,
            name: name,
            description: snap['description'] ?? '',
            personality: snap['personality'] ?? '',
            scenario: snap['scenario'] ?? '',
            firstMessage: snap['first_message'] ?? '',
            systemPrompt: snap['system_prompt'] ?? '',
          ),
        );
        continue;
      }
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
        characterName: groupId != null
            ? (project.chatGroupName.isEmpty
                  ? 'the group'
                  : project.chatGroupName)
            : name ?? 'the chat',
        sessionId: project.chatHistorySessionIds.first,
        recap: '',
        userName: '',
        faithful: project.faithfulMode,
        groupId: groupId,
        members: members,
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
  /// A group's whole roster joins; its first member leads and the rest are
  /// Supporting (docs/design/stories-from-group-chats.md §1).
  void adoptChat(StoryChatSource source) {
    chatSource = source;
    useChatHistory = true;
    for (final id in source.castIds) {
      selectedCharacterIds.add(id);
      characterRoles.putIfAbsent(
        id,
        () => id == source.characterId ? 'Protagonist' : 'Supporting',
      );
    }
    // Fit the length to the chat unless one was already chosen.
    if (source.faithful &&
        source.messageCount > 0 &&
        proseLength == 'Standard') {
      proseLength = suggestedLengthForChat(source.messageCount);
    }
    if (conceptController.text.trim().isEmpty) {
      final which = source.isGroup ? 'group chat' : 'chat';
      conceptController.text = source.faithful
          ? 'A faithful novelization of the roleplay between '
                '${source.castLine} and ${source.userName}: the real '
                'events of their $which, retold as prose.'
                '${source.recap.trim().isEmpty ? '' : '\n\nWhere the story stands: ${source.recap}'}'
          : 'A story inspired by the roleplay between '
                '${source.castLine} and ${source.userName}.';
    }
  }

  void dropChat() {
    final source = chatSource;
    chatSource = null;
    useChatHistory = false;
    if (source != null) {
      for (final id in source.castIds) {
        selectedCharacterIds.remove(id);
        characterRoles.remove(id);
      }
    }
    // A world that only came along with the chat leaves with it.
    if (world?.fromChat ?? false) world = null;
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
    project.chatGroupId = source?.groupId;
    project.chatGroupName = source?.isGroup ?? false
        ? source!.characterName
        : '';
    project.worldId = world?.placeId;
    project.worldName = world?.worldName ?? '';
    project.includeUserPersona = includeUserPersona;
    project.userPersonaRole = userPersonaRole;

    project.pov = pov;
    // Studio always builds three acts and eight sequences.
    project.actCount = engineMode == StoryEngineMode.studio
        ? StoryPacing.actCount
        : actCount;
    project.selectedGenres = toneFromChat ? [] : selectedGenres.toList();
    project.selectedMoods = toneFromChat ? [] : selectedMoods.toList();
    project.writingStyle = writingStyle;
    project.proseLength = proseLength;
    project.narrativePace = narrativePace;
    project.dialogueDensity = dialogueDensity;
    project.maturityRating = maturityRating;

    final snapshots = <Map<String, String>>[];
    // The group's members first, in roster order, from the roster's own
    // cards; the id on each is what rebuilds the roster on reopen.
    for (final m in source?.members ?? const <StoryChatMember>[]) {
      if (!selectedCharacterIds.contains(m.id)) continue;
      snapshots.add(m.snapshot(characterRoles[m.id] ?? 'Supporting'));
    }
    for (final char in charRepo.characters) {
      if (char.dbId != null && selectedCharacterIds.contains(char.dbId)) {
        snapshots.add({
          'id': char.dbId!,
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
