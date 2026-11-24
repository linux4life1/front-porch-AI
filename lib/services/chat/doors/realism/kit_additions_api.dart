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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/character/trait_kit.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/growth_kit_seed.dart';
import 'package:front_porch_ai/services/chat_service.dart';

/// The editors' hook for kit entries added mid-chat (`GrowthKitAdditions`).
/// Callers check `GrowthKitSeed.added` first and call only when it is not
/// empty, so a plain save never reaches the realism door (the golden fakes
/// cannot answer an extension member).
extension ChatServiceKitAdditions on ChatService {
  /// [card] was saved with entries appended to its kit; [before] is the kit
  /// as the editor opened it. [groupMemberId] names a group member's copy
  /// (its `group_members` id); null for a library card. Returns the rings
  /// written across that character's chats.
  Future<int> addNewKitEntriesToChats(
    CharacterCard card,
    List<TraitKitEntry> before, {
    String? groupMemberId,
  }) => groupMemberId == null
      ? realism.kitAdditions.forLibraryCard(card, before)
      : realism.kitAdditions.forGroupMember(groupMemberId, card, before);
}

/// After an editor save (desktop or web): when [card]'s kit gained entries
/// since [before], land them in its chats. Never throws — a save that
/// worked stays a success; a failure is logged.
Future<void> spreadNewKitEntries(
  ChatService? chat,
  CharacterCard card,
  List<TraitKitEntry> before, {
  String? groupMemberId,
}) async {
  final now = card.frontPorchExtensions?.traitKit ?? const <TraitKitEntry>[];
  if (chat == null || GrowthKitSeed.added(before, now).isEmpty) return;
  try {
    await chat.addNewKitEntriesToChats(
      card,
      before,
      groupMemberId: groupMemberId,
    );
  } catch (e) {
    debugPrint('[Growth] new kit entries not added to chats: $e');
  }
}
