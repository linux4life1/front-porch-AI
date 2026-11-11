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
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/group_member_card_save.dart';

/// What the group editor page (desktop) and its web twin do to a chat that is
/// open on the group being edited, after the group's row is saved.
///
/// The page edits the group's DEFINITION. A chat open on the group holds its
/// own copy of that definition and saves it back later (adding a member,
/// the turn order), so an edit that stopped at the row would be put back by
/// the chat. These helpers carry the definition onto the chat's copy, apply
/// the few things that should take effect now (name, prompts, turn order),
/// and never touch a live switch: a default edited here is what the NEXT chat
/// starts from (docs/design/one-chat-ux.md, ruling 5).

/// The chat open on [groupId] when it is a group chat, else null.
GroupChat? openGroupOf(ChatService? chat, String groupId) {
  if (chat == null || !chat.isGroupMode) return null;
  final live = chat.activeGroup;
  return live != null && live.id == groupId ? live : null;
}

/// Copies the saved definition [from] onto the chat's copy [to], field by
/// field. The portable stable id and the chaos flags stay the chat's own
/// when [from] carries none (the page never edits them).
void copyGroupDefinition(GroupChat from, GroupChat to) {
  to
    ..name = from.name
    ..turnOrder = from.turnOrder
    ..autoAdvance = from.autoAdvance
    ..directorMode = from.directorMode
    ..firstMessage = from.firstMessage
    ..alternateGreetings = List.of(from.alternateGreetings)
    ..greetingSeeds = List.of(from.greetingSeeds)
    ..scenario = from.scenario
    ..systemPrompt = from.systemPrompt
    ..defaultMemberRealismState = from.defaultMemberRealismState
    ..baselineRealismState = from.baselineRealismState
    ..characterSystemPrompts = Map.of(from.characterSystemPrompts)
    ..worldIds = List.of(from.worldIds)
    ..loreWorldIds = from.loreWorldIds == null
        ? null
        : List.of(from.loreWorldIds!)
    ..groupLorebook = from.groupLorebook
    ..inheritCharacterLorebooks = from.inheritCharacterLorebooks;
  if (from.stableId != null) to.stableId = from.stableId;
}

/// Carries a saved definition onto the chat open on the same group, if any.
/// Returns true when a chat was open on it.
///
/// Applied now: the group name, scenario, system prompt and lorebooks (the
/// prompt reads the chat's copy), the turn order (through the chat, which
/// restarts the rotation as `/turnorder` does) and each member's group-level
/// system prompt. Every member's live switch is written first so the group
/// defaults just saved cannot reach into the open chat. Start in Director and
/// the opening lines are for the next chat; the chat's Director switch is
/// not touched.
Future<bool> applySavedGroupToOpenChat(
  ChatService chat,
  GroupChat saved,
) async {
  final live = openGroupOf(chat, saved.id);
  if (live == null) return false;
  chat.entryDoor.members.holdMemberSwitches();
  final turnChanged = live.turnOrder != saved.turnOrder;
  copyGroupDefinition(saved, live);
  if (turnChanged) {
    await chat.setGroupTurnOrder(saved.turnOrder == TurnOrder.random, null);
  }
  for (final member in List.of(chat.groupCharacters)) {
    final id = chat.characterIdFor(member);
    final want = saved.characterSystemPrompts[id] ?? '';
    if (chat.getSystemPromptForGroupCharacter(member).trim() != want.trim()) {
      chat.setSystemPromptForGroupCharacter(member, want);
    }
  }
  return true;
}

/// Carries a member's saved defaults (their card's extensions: Afterglow and
/// Pockets for new chats, Recovery, Needs starting values and pace) onto the
/// chat's copy of the member. The card the page edited replaces the chat's
/// copy, as the member editor's save does, with its Afterglow DEFAULT put
/// through the chat so the member's live switch (and their Lust and recovery)
/// stay as they are. [afterglowBefore] is the default the page opened with.
Future<void> applyMemberDefaultsToOpenChat(
  ChatService chat,
  CharacterCard saved,
  bool afterglowBefore,
) async {
  if (!isOpenGroupMember(chat, saved)) return;
  chat.entryDoor.members.holdMemberSwitches();
  final edited = saved.frontPorchExtensions?.afterglowEnabled ?? true;
  if (edited != afterglowBefore) {
    saved.frontPorchExtensions =
        (saved.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
          afterglowEnabled: afterglowBefore,
        );
  }
  chat.refreshActiveCharacterCard(saved);
  if (edited != afterglowBefore) {
    await chat.setMemberAfterglowEnabled(saved, edited);
  }
}
