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

import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

/// [parseGroupTimeSeed] for [group], with the Story Calendar start its own
/// columns hold (Edit group → Realism Engine, schema v66) over the blob's.
/// A group that set only a start still seeds one, on the default morning.
({
  int dayCount,
  String timeOfDay,
  String? storyStartDate,
  String? storyStartTime,
})?
parseGroupTimeSeedOf(GroupChat group) {
  final blob = parseGroupTimeSeed(
    group.defaultMemberRealismState,
    group.baselineRealismState,
  );
  final date = group.storyStartDate;
  final time = group.storyStartTime;
  if (date == null && time == null) return blob;
  return (
    dayCount: blob?.dayCount ?? 1,
    timeOfDay: blob?.timeOfDay ?? 'morning',
    storyStartDate: date ?? blob?.storyStartDate,
    storyStartTime: time ?? blob?.storyStartTime,
  );
}

/// [definitionJson] with the scene time new chats start at set on its
/// top-level keys, where [parseGroupTimeSeed] reads it. Seeds and every
/// other key are kept; a blob that is not a map starts a fresh one.
String withGroupSceneTime(
  String definitionJson, {
  required String timeOfDay,
  required int dayCount,
}) {
  Map<String, dynamic> map;
  try {
    final raw = jsonDecode(definitionJson);
    map = raw is Map ? Map<String, dynamic>.from(raw) : {};
  } catch (_) {
    map = {};
  }
  map['timeOfDay'] = timeOfDay;
  map['dayCount'] = dayCount;
  return jsonEncode(map);
}
