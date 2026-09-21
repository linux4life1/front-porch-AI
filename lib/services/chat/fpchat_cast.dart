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

/// Thin `fpai.cast` list — portable id + name + optional lite tier.
/// No card blobs or avatars. Added with [kFpchatStampVersion] 2.
const String kFpchatCastKey = 'cast';

/// One participant in a Full Front Porch package.
class FpchatCastMember {
  final String id;
  final String name;
  final bool lite;

  const FpchatCastMember({
    required this.id,
    required this.name,
    this.lite = false,
  });
}

/// Encode one roster / scene-guest row. [tier] is omitted for full members.
Map<String, dynamic> encodeFpchatCastMember({
  required String id,
  required String name,
  required bool lite,
}) => {'id': id, 'name': name, if (lite) 'tier': 'lite'};

/// Parse `fpai.cast`. Missing / malformed → empty (legacy packages).
List<FpchatCastMember> parseFpchatCast(dynamic raw) {
  if (raw is! List) return const [];
  final out = <FpchatCastMember>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final m = Map<String, dynamic>.from(e);
    final id = (m['id'] as String? ?? m['stable_group_id'] as String? ?? '')
        .trim();
    final name = (m['name'] as String? ?? '').trim();
    if (id.isEmpty && name.isEmpty) continue;
    final tier = (m['tier'] as String? ?? '').trim().toLowerCase();
    out.add(FpchatCastMember(id: id, name: name, lite: tier == 'lite'));
  }
  return out;
}

/// Match [entry] to an open roster or library card. Portable id first
/// (`stableGroupId` or `dbId`), then display name.
CharacterCard? matchFpchatCastMember(
  Iterable<CharacterCard> cards,
  FpchatCastMember entry,
) {
  if (entry.id.isNotEmpty) {
    for (final c in cards) {
      if (c.stableGroupId == entry.id || c.dbId == entry.id) return c;
    }
  }
  final name = entry.name.trim().toLowerCase();
  if (name.isEmpty) return null;
  for (final c in cards) {
    if (c.name.trim().toLowerCase() == name) return c;
  }
  return null;
}
