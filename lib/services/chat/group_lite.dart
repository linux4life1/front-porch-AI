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

import 'package:front_porch_ai/models/models.dart';

/// Soft group member (Approach A′): a real roster row whose card still
/// carries `frontPorchExtensions.tier == 'lite'`. Soft members stay in
/// `_groupCharacters` for turn pick / Away. Feelings and full Realism
/// use [fullGroupCharacters] only — do not drop soft from the roster.
bool isSoftGroupMember(CharacterCard card) => card.isLite;

/// Full (non-lite) members. Feelings graph, ≤4 gate, and realism seeds
/// only. The live roster is still the unfiltered list.
List<CharacterCard> fullGroupCharacters(Iterable<CharacterCard> cards) => [
  for (final c in cards)
    if (!c.isLite) c,
];

/// Inter-character feelings fire when the group has 2–4 **full** members.
/// Soft guests do not count toward the cap and never join the graph.
bool shouldTrackInterCharacterAmong(Iterable<CharacterCard> members) {
  final n = fullGroupCharacters(members).length;
  return n >= 2 && n <= 4;
}

/// Clone [src] (or a fresh default) and set or clear the Scene Guest tier.
/// [copyWith] cannot clear `tier` (`tier ?? this.tier`), so promote clones
/// through JSON then writes `tier = null`.
FrontPorchExtensions cloneFrontPorchTier(
  FrontPorchExtensions? src, {
  required bool lite,
}) {
  final ext = src == null
      ? FrontPorchExtensions()
      : FrontPorchExtensions.fromJson(src.toJson());
  ext.tier = lite ? 'lite' : null;
  return ext;
}

/// JSON for a `group_members.frontPorchExtensions` column.
String? encodeMemberFrontPorch(FrontPorchExtensions? ext) =>
    ext == null ? null : jsonEncode(ext.toJson());

/// Names already on the porch: group roster ∪ present 1:1 guests.
Set<String> presentSceneNames({
  Iterable<CharacterCard> members = const [],
  Iterable<CharacterCard> guests = const [],
}) => {
  for (final c in members) c.name.trim().toLowerCase(),
  for (final g in guests) g.name.trim().toLowerCase(),
};
