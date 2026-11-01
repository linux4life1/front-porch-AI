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
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';

/// Open a 1:1 and the loading cover (bodies in [ChatEntry], [EntryCover]).
extension ChatServiceChatEntry on ChatService {
  /// Raise the chat page's loading cover before any await.
  void beginSessionLoad() => entryDoor.cover.beginSessionLoad();

  /// Drop the loading cover. Safe when it is already down.
  void endSessionLoad() => entryDoor.cover.endSessionLoad();

  Future<void> setActiveCharacter(CharacterCard? character) =>
      entryDoor.chat.setActiveCharacter(character);

  /// True while forked-in character entrances are still playing. The
  /// composer mirrors sendMessage's early return on it, so it does not
  /// consume an attached photo for a turn sendMessage would drop.
  bool get entrancesInFlight => entryDoor.entrancesInFlight;
}

/// Open a group (body in [GroupEntry]).
extension ChatServiceGroupEntry on ChatService {
  /// Enter group chat mode with the given GroupChat definition.
  Future<void> setActiveGroup(
    GroupChat group, {
    GroupChatRepository? groupRepo,
  }) => entryDoor.group.setActiveGroup(group, groupRepo: groupRepo);

  /// Wired by main.dart so that group member loading works for all call
  /// sites (creation, home taps, fork, etc.) without every caller having to
  /// pass the repo.
  void setGroupChatRepository(GroupChatRepository repo) =>
      entryDoor.groupRepository = repo;

  /// The library character a group member came from, or null.
  CharacterCard? originLibraryCardFor(CharacterCard member) =>
      entryDoor.roster.originLibraryCardFor(member);
}

/// Per-member realism and Needs reads (bodies in [GroupMemberReads]) and
/// Director Mode (bodies in [GroupDirector]).
extension ChatServiceGroupRead on ChatService {
  String? getEmotionForGroupCharacter(CharacterCard character) =>
      entryDoor.reads.getEmotionForGroupCharacter(character);

  Map<String, dynamic>? getRealismStateForGroupCharacter(
    CharacterCard character,
  ) => entryDoor.reads.getRealismStateForGroupCharacter(character);

  Map<String, int> getNeedsForGroupCharacter(CharacterCard character) =>
      entryDoor.reads.getNeedsForGroupCharacter(character);

  int getAffectionForGroupCharacter(CharacterCard character) =>
      entryDoor.reads.getAffectionForGroupCharacter(character);

  int getLongTermForGroupCharacter(CharacterCard character) =>
      entryDoor.reads.getLongTermForGroupCharacter(character);

  int getTrustForGroupCharacter(CharacterCard character) =>
      entryDoor.reads.getTrustForGroupCharacter(character);

  String? getFixationForGroupCharacter(CharacterCard character) =>
      entryDoor.reads.getFixationForGroupCharacter(character);

  int getArousalForGroupCharacter(CharacterCard character) =>
      entryDoor.reads.getArousalForGroupCharacter(character);

  ({String chip, bool soft, int minutes}) getRefractoryForGroupCharacter(
    CharacterCard character,
  ) => entryDoor.reads.getRefractoryForGroupCharacter(character);

  bool get expressionsEnabled => entryDoor.reads.expressionsEnabled;

  String? expressionLabelFor(CharacterCard character) =>
      entryDoor.reads.expressionLabelFor(character);

  String? getEmotionIntensityForGroupCharacter(CharacterCard character) =>
      entryDoor.reads.getEmotionIntensityForGroupCharacter(character);

  MoodState? getMoodForGroupCharacter(CharacterCard character) =>
      entryDoor.reads.getMoodForGroupCharacter(character);

  int? getFixationLifespanForGroupCharacter(CharacterCard character) =>
      entryDoor.reads.getFixationLifespanForGroupCharacter(character);

  List<(String, int)> getTopUrgentNeedsForGroupCharacter(
    CharacterCard character, {
    int count = 2,
  }) => entryDoor.reads.getTopUrgentNeedsForGroupCharacter(
    character,
    count: count,
  );

  void resetRealismForGroupCharacter(CharacterCard character) =>
      entryDoor.reads.resetRealismForGroupCharacter(character);

  /// Realism is on in a group chat, Director Mode included.
  bool get isGroupRealismActive => entryDoor.reads.isGroupRealismActive;

  double get directorDelaySec => entryDoor.director.directorDelaySec;
  set directorDelaySec(double value) =>
      entryDoor.director.directorDelaySec = value;

  double get savedDirectorDelay => entryDoor.director.savedDirectorDelay;

  Future<void> setSavedDirectorDelay(double seconds) =>
      entryDoor.director.setSavedDirectorDelay(seconds);

  bool get autoPlayActive => entryDoor.director.autoPlayActive;

  /// Who speaks next in group mode, or null for random turn order.
  CharacterCard? get nextCharacter => entryDoor.director.nextCharacter;

  void setObserverMode(bool value) => entryDoor.director.setObserverMode(value);

  void startAutoPlay() => entryDoor.director.startAutoPlay();

  void pauseAutoPlay() => entryDoor.director.pauseAutoPlay();

  void stopAutoPlay() => entryDoor.director.stopAutoPlay();

  bool get autoPlayPaused => entryDoor.director.autoPlayPaused;

  int? get autoChatTurnsLeft => entryDoor.director.autoChatTurnsLeft;

  int get savedDirectorTurnBudget => entryDoor.director.savedDirectorTurnBudget;

  Future<void> setSavedDirectorTurnBudget(int turns) =>
      entryDoor.director.setSavedDirectorTurnBudget(turns);
}

/// A member's settings in this group (bodies in [GroupMemberSettings]).
extension ChatServiceGroupSettings on ChatService {
  bool get groupRagEnabled => entryDoor.members.groupRagEnabled;

  int get groupRetrievalCount => entryDoor.members.groupRetrievalCount;

  double get groupMemoryBudgetPercent =>
      entryDoor.members.groupMemoryBudgetPercent;

  Map<String, double> get currentGroupRAGPriorities =>
      entryDoor.members.currentGroupRAGPriorities;

  double ragPriorityForGroupCharacter(CharacterCard c) =>
      entryDoor.members.ragPriorityForGroupCharacter(c);

  void setRAGPriorityForGroupCharacter(CharacterCard c, double priority) =>
      entryDoor.members.setRAGPriorityForGroupCharacter(c, priority);

  void setGroupRAGEnabled(bool value) =>
      entryDoor.members.setGroupRAGEnabled(value);

  void setGroupRetrievalCount(int value) =>
      entryDoor.members.setGroupRetrievalCount(value);

  void setGroupMemoryBudgetPercent(double value) =>
      entryDoor.members.setGroupMemoryBudgetPercent(value);

  bool get isGroupTurnOrderRandom => entryDoor.members.isGroupTurnOrderRandom;

  bool get isGroupNsfwEnabled => entryDoor.members.isGroupNsfwEnabled;

  /// Whether Afterglow runs for [member] in this chat.
  bool afterglowRunsFor(CharacterCard member) =>
      entryDoor.members.afterglowRunsFor(member);

  Future<void> setGroupTurnOrder(
    bool random,
    List<CharacterCard>? customOrder,
  ) => entryDoor.members.setGroupTurnOrder(random, customOrder);

  String getAuthorNoteForGroupCharacter(CharacterCard c) =>
      entryDoor.members.getAuthorNoteForGroupCharacter(c);

  int getAuthorNoteStrengthForGroupCharacter(CharacterCard c) =>
      entryDoor.members.getAuthorNoteStrengthForGroupCharacter(c);

  void setAuthorNoteForGroupCharacter(
    CharacterCard c,
    String note, {
    int? strength,
  }) => entryDoor.members.setAuthorNoteForGroupCharacter(
    c,
    note,
    strength: strength,
  );

  String getSystemPromptForGroupCharacter(CharacterCard c) =>
      entryDoor.members.getSystemPromptForGroupCharacter(c);

  void setSystemPromptForGroupCharacter(CharacterCard c, String prompt) =>
      entryDoor.members.setSystemPromptForGroupCharacter(c, prompt);
}

/// The 1:1 to group fork (body in [GroupFork]).
extension ChatServiceGroupMembership on ChatService {
  /// Fork the current 1:1 chat into a new group chat, copying all messages.
  /// The original 1:1 session remains untouched.
  Future<GroupChat?> forkToGroupChat(
    List<CharacterCard> additionalCharacters,
    GroupChatRepository groupRepo, {
    String? groupName,
    String? scenario,
    TurnOrder turnOrder = TurnOrder.roundRobin,
    Map<String, ({String text, bool creative})> entrances = const {},
    Set<String> liteArrivalKeys = const {},
  }) => entryDoor.fork.forkToGroupChat(
    additionalCharacters,
    groupRepo,
    groupName: groupName,
    scenario: scenario,
    turnOrder: turnOrder,
    entrances: entrances,
    liteArrivalKeys: liteArrivalKeys,
  );
}

/// Live add and remove (bodies in [GroupRoster]).
extension ChatServiceGroupMembers on ChatService {
  /// Add a character to the currently active group chat.
  Future<bool> addCharacterToGroup(
    CharacterCard character,
    GroupChatRepository groupRepo, {
    bool asLite = false,
  }) => entryDoor.roster.addCharacterToGroup(
    character,
    groupRepo,
    asLite: asLite,
  );

  /// Remove a character from the active group chat (collapsing to a 1:1
  /// when one member is left).
  Future<bool> removeCharacterFromGroup(
    CharacterCard character,
    GroupChatRepository groupRepo,
  ) => entryDoor.roster.removeCharacterFromGroup(character, groupRepo);
}
