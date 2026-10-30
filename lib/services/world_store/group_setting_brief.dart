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

import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/services/world_store/group_world_choice.dart';

/// Soft cap on the brief the Create Group opening generator reads.
const int kGroupSettingBriefChars = 1500;

/// One place or world gets this much of its own description.
const int kGroupSettingBriefProseChars = 300;

/// At most this many always-on facts go in.
const int kGroupSettingBriefFacts = 6;

/// Where a group's first scene happens, for the opening generator: the
/// place new chats start at, the world it is in, the weather, and the
/// always-on lore of that chain (place first). Empty for no world, so the
/// generator invents a setting as it always has.
String groupSettingBrief(
  GroupWorldChoice choice, {
  required World? Function(String id) lookup,
  String? Function(String id)? weatherOf,
}) {
  final setting = choice.settingId == null ? null : lookup(choice.settingId!);
  if (setting == null) return '';
  final root = topWorldOf(setting, lookup);
  final start = setting.id == root.id ? startingPlaceOf(root, lookup) : setting;

  String clip(String text, int max) {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.length <= max ? t : '${t.substring(0, max - 1)}…';
  }

  final out = <String>[
    start.id == root.id
        ? 'The scene starts in ${root.name}.'
        : 'The scene starts at ${start.name}, in ${root.name}.',
    if (start.description.trim().isNotEmpty)
      '${start.name}: ${clip(start.description, kGroupSettingBriefProseChars)}',
    if (start.id != root.id && root.description.trim().isNotEmpty)
      '${root.name}: ${clip(root.description, kGroupSettingBriefProseChars)}',
    if (weatherOf?.call(start.id) case final weather?) 'Weather: $weather.',
  ];
  final facts = <String>[
    for (final w in worldChain(start, lookup))
      for (final e in w.lorebook.entries)
        if (e.enabled && e.constant && e.content.trim().isNotEmpty)
          '- ${clip(e.content, 200)}',
  ].take(kGroupSettingBriefFacts).toList();
  if (facts.isNotEmpty) out.add('Always true here:\n${facts.join('\n')}');

  final brief = out.join('\n');
  return brief.length <= kGroupSettingBriefChars
      ? brief
      : '${brief.substring(0, kGroupSettingBriefChars - 1)}…';
}
