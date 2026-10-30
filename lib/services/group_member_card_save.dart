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

import 'package:drift/drift.dart' show Value;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
// Sibling of this file's own barrel (services.dart lives in this directory).
import 'package:front_porch_ai/services/chat_service.dart';

/// Whether [card] is a member of the group chat open in [chat]. A member is
/// the group's own copy of a character, so an edit to it saves to its
/// group_members row (see [saveGroupMemberCard]), never to the library
/// character it was copied from.
bool isOpenGroupMember(ChatService chat, CharacterCard card) =>
    chat.isGroupMode &&
    chat.groupCharacters.any(
      (c) => identical(c, card) || (c.dbId != null && c.dbId == card.dbId),
    );

/// Every column of a member's row that its card carries. The avatar file,
/// the group and the membership state are left as they are.
GroupMembersCompanion groupMemberCardColumns(CharacterCard card) {
  final ext = card.frontPorchExtensions;
  final raw = card.rawExtensions;
  return GroupMembersCompanion(
    id: Value(card.dbId!),
    name: Value(card.name),
    description: Value(card.description),
    personality: Value(card.personality),
    scenario: Value(card.scenario),
    firstMessage: Value(card.firstMessage),
    mesExample: Value(card.mesExample),
    systemPrompt: Value(card.systemPrompt),
    postHistoryInstructions: Value(card.postHistoryInstructions),
    alternateGreetings: Value(jsonEncode(card.alternateGreetings)),
    tags: Value(jsonEncode(card.tags)),
    ttsVoice: Value(card.ttsVoice),
    lorebook: Value(
      card.lorebook != null ? jsonEncode(card.lorebook!.toJson()) : null,
    ),
    worldNames: Value(jsonEncode(card.allWorldNames)),
    frontPorchExtensions: Value(ext == null ? null : jsonEncode(ext.toJson())),
    rawExtensions: Value(raw == null ? null : jsonEncode(raw)),
    updatedAt: Value(DateTime.now()),
  );
}

/// Saves a group member's edited card to its own row. The row is what the
/// group loads its members from, so an edit that only reached the member's
/// PNG, or a library row, was gone the next time the group opened.
Future<void> saveGroupMemberCard(AppDatabase db, CharacterCard card) {
  final id = card.dbId;
  if (id == null || id.isEmpty) {
    throw ArgumentError.value(
      card.name,
      'card',
      'a group member is saved by its row id, and this card has none',
    );
  }
  return db.updateGroupMember(groupMemberCardColumns(card));
}
