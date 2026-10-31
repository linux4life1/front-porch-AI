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
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/world_store/world_store.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// The switches a group member's editor shows as the group's, read-only: a
/// group has one of each, set in Group Settings (the open chat) or Edit
/// group (its new chats), never a second copy per member.
class GroupWideValues {
  const GroupWideValues({
    required this.realism,
    required this.needs,
    required this.chaos,
    required this.afterglow,
    required this.timeOfDay,
    required this.dayCount,
    this.settingName,
    this.readsMemberLorebooks = false,
    this.open = false,
    this.chaosFromPorchLife = false,
    this.needsOffInPorchLife = false,
  });

  final bool realism;
  final bool needs;
  final bool chaos;
  final bool afterglow;

  /// A StoryClock period (`late_morning`); [timeLabel] is how it reads.
  final String timeOfDay;
  final int dayCount;

  /// The group's Setting world, where its chats meet. Null when it has none.
  final String? settingName;

  /// Lore → "Inherit character lorebooks".
  final bool readsMemberLorebooks;

  /// Read from the open chat (its own switches), not the group's settings
  /// for new chats.
  final bool open;

  /// New chats: Porch Life's Chaos default is on, so they start with Chaos
  /// whatever the group was made with.
  final bool chaosFromPorchLife;

  /// Porch Life runs no Needs: no chat runs it, whatever this chat (or the
  /// group, for its new chats) chose; that choice is kept.
  final bool needsOffInPorchLife;

  /// "Late morning, Day 3".
  String get timeLabel {
    final words = timeOfDay.replaceAll('_', ' ').trim();
    final period = words.isEmpty
        ? 'Morning'
        : '${words[0].toUpperCase()}${words.substring(1)}';
    return '$period, Day $dayCount';
  }

  Map<String, dynamic> toJson() => {
    'realism': realism,
    'needs': needs,
    'chaos': chaos,
    'afterglow': afterglow,
    'timeOfDay': timeOfDay,
    'dayCount': dayCount,
    'timeLabel': timeLabel,
    'settingName': settingName,
    'readsMemberLorebooks': readsMemberLorebooks,
    'open': open,
    'chaosFromPorchLife': chaosFromPorchLife,
    'needsOffInPorchLife': needsOffInPorchLife,
  };
}

/// The name of [group]'s Setting world in [worlds], or null.
String? groupSettingNameIn(GroupChat group, WorldRepository? worlds) {
  if (worlds == null) return null;
  try {
    final id = groupWorldChoiceIn(group, worlds).settingId;
    return id == null ? null : worlds.worldById(id)?.name;
  } catch (_) {
    return null;
  }
}

/// The open group chat's own switches and clock: what its next turn runs.
/// While Porch Life's [needsSimDefault] is off no chat runs Needs; the chat's
/// own choice still shows, with that said.
GroupWideValues groupWideValuesOfChat(
  ChatService chat, {
  required bool needsSimDefault,
  WorldRepository? worlds,
}) {
  final group = chat.activeGroup;
  return GroupWideValues(
    realism: chat.realismEnabled,
    needs: chat.needsSimEnabled,
    chaos: chat.chaosModeService.chaosModeEnabled,
    afterglow: chat.afterglowChatSwitch,
    timeOfDay: chat.timeService.timeOfDay,
    dayCount: chat.timeService.dayCount,
    settingName: group == null ? null : groupSettingNameIn(group, worlds),
    readsMemberLorebooks: group?.inheritCharacterLorebooks ?? false,
    open: true,
    needsOffInPorchLife: !needsSimDefault,
  );
}

/// A group's settings for new chats, from its definition's realism blobs
/// ([defaultMemberJson], [baselineJson]): how its next New Chat starts.
/// New Chat seeds Chaos as the group's [chaos] OR Porch Life's
/// [chaosModeDefault], and Needs only while Porch Life's [needsSimDefault]
/// is on (ChatService's group entry and New Chat).
GroupWideValues groupWideValuesOfTemplate({
  required String defaultMemberJson,
  required String baselineJson,
  required bool chaos,
  required bool chaosModeDefault,
  required bool needsSimDefault,
  String? settingName,
  bool readsMemberLorebooks = false,
}) {
  ({bool realismOn, bool needsOn}) realism;
  try {
    realism = groupTemplateRealismOf(defaultMemberJson);
  } catch (_) {
    // A blob the app cannot read starts new chats without member seeds.
    realism = (realismOn: false, needsOn: false);
  }
  final time = parseGroupTimeSeed(defaultMemberJson, baselineJson);
  return GroupWideValues(
    realism: realism.realismOn,
    needs: needsSimDefault && realism.realismOn && realism.needsOn,
    chaos: chaos || chaosModeDefault,
    afterglow: groupAfterglowIn(defaultMemberJson),
    timeOfDay: time?.timeOfDay ?? 'morning',
    dayCount: time?.dayCount ?? 1,
    settingName: settingName,
    readsMemberLorebooks: readsMemberLorebooks,
    chaosFromPorchLife: chaosModeDefault,
    needsOffInPorchLife: !needsSimDefault,
  );
}
