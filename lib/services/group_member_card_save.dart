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

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter/foundation.dart' show debugPrint;

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
/// the group and the membership state are left as they are, and so are
/// extensions the card holds none of: a stored value the app cannot read
/// loads as null, and writing that null would erase it.
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
    frontPorchExtensions: ext == null
        ? const Value.absent()
        : Value(jsonEncode(ext.toJson())),
    rawExtensions: raw == null ? const Value.absent() : Value(jsonEncode(raw)),
    updatedAt: Value(DateTime.now()),
  );
}

/// Saves only a group member's Recovery block onto their row, keeping every
/// other extension the row holds now: a copy loaded earlier (Edit group) may
/// be behind a change made since, such as the member's own Afterglow switch.
Future<void> saveGroupMemberRecovery(
  AppDatabase db,
  String id,
  RecoveryProfile recovery,
) async {
  final row = await db
      .customSelect(
        'SELECT front_porch_extensions AS e FROM group_members WHERE id = ?',
        variables: [Variable(id)],
      )
      .getSingleOrNull();
  if (row == null) throw StateError('no group member row $id');
  final raw = row.data['e'] as String?;
  final ext = raw == null || raw.isEmpty
      ? FrontPorchExtensions()
      : FrontPorchExtensions.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  await db.updateGroupMember(
    GroupMembersCompanion(
      id: Value(id),
      frontPorchExtensions: Value(
        jsonEncode(ext.copyWith(recovery: recovery).toJson()),
      ),
      updatedAt: Value(DateTime.now()),
    ),
  );
}

/// Saves only a group member's extensions (chat colours, avatar lock): the
/// rest of the row may have changed since this copy was loaded, in Edit
/// group, and a whole-row write from it would put the old values back.
Future<void> saveGroupMemberExtensions(AppDatabase db, CharacterCard card) {
  final id = card.dbId;
  final ext = card.frontPorchExtensions;
  if (id == null || id.isEmpty || ext == null) {
    throw ArgumentError.value(
      card.name,
      'card',
      'a group member\'s extensions are saved by its row id',
    );
  }
  return db.updateGroupMember(
    GroupMembersCompanion(
      id: Value(id),
      frontPorchExtensions: Value(jsonEncode(ext.toJson())),
      updatedAt: Value(DateTime.now()),
    ),
  );
}

/// The open chat's Afterglow for the member [card] is a copy of, read before
/// a save from an editor that opened the switch at [opened]. An editor
/// holding an older copy (Edit group) that left the switch alone takes the
/// chat's value, so a change made since (Group Settings, the phone) is not
/// put back. Returns the value [settleMemberAfterglow] starts from.
bool liveMemberAfterglow(ChatService chat, CharacterCard card, bool opened) {
  if (!chat.isGroupMode) return opened;
  CharacterCard? live;
  for (final c in chat.groupCharacters) {
    if (c.dbId != null && c.dbId == card.dbId) live = c;
  }
  if (live == null || identical(live, card)) return opened;
  final now = live.frontPorchExtensions?.afterglowEnabled ?? true;
  final ext = card.frontPorchExtensions;
  if (ext != null && ext.afterglowEnabled == opened) {
    card.frontPorchExtensions = ext.copyWith(afterglowEnabled: now);
  }
  return now;
}

/// Settles a member's own Afterglow switch after their editor saved [saved]
/// into the open group chat. The editor sets the switch on the card itself,
/// so the chat would never see it move: the opening value [before] goes back
/// and the chat sets the new one, which clears the member's Lust and cooldown
/// as the Group Settings switch does.
Future<void> settleMemberAfterglow(
  ChatService chat,
  CharacterCard saved,
  bool before,
) async {
  if (!isOpenGroupMember(chat, saved)) return;
  final edited = saved.frontPorchExtensions?.afterglowEnabled ?? true;
  if (edited == before) return;
  saved.frontPorchExtensions =
      (saved.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
        afterglowEnabled: before,
      );
  await chat.setMemberAfterglowEnabled(saved, edited);
}

/// Whether member [id]'s row holds extensions the app cannot read. A card
/// loads those as none, so an editor would build defaults and write them
/// over what is stored.
Future<bool> groupMemberExtensionsUnreadable(AppDatabase db, String id) async {
  final row = await db
      .customSelect(
        'SELECT front_porch_extensions AS e FROM group_members WHERE id = ?',
        variables: [Variable(id)],
      )
      .getSingleOrNull();
  final raw = row?.data['e'] as String?;
  if (raw == null || raw.trim().isEmpty) return false;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded.isEmpty) return false;
    FrontPorchExtensions.fromJson(Map<String, dynamic>.from(decoded));
    return false;
  } catch (_) {
    return true;
  }
}

/// Saves a group member's edited card to its own row. The row is what the
/// group loads its members from, so an edit that only reached the member's
/// PNG, or a library row, was gone the next time the group opened. Stored
/// extensions the app cannot read are kept as they are.
Future<void> saveGroupMemberCard(AppDatabase db, CharacterCard card) async {
  final id = card.dbId;
  if (id == null || id.isEmpty) {
    throw ArgumentError.value(
      card.name,
      'card',
      'a group member is saved by its row id, and this card has none',
    );
  }
  var columns = groupMemberCardColumns(card);
  if (card.frontPorchExtensions != null &&
      await groupMemberExtensionsUnreadable(db, id)) {
    debugPrint(
      '[GroupMember] $id keeps the extensions it could not read; this '
      "save's Realism settings were not written",
    );
    columns = columns.copyWith(frontPorchExtensions: const Value.absent());
  }
  await db.updateGroupMember(columns);
}
