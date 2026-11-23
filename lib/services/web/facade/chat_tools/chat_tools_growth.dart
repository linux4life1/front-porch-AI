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

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'chat_tools_memory.dart';

/// The Boons & Bogies line's rings for [ownerId]: boons then bogies (the
/// desktop line lists them the same way), through the same serializer the
/// Growth panel's endpoint uses, so the sidebar renders the identical card —
/// meter, receipts, pin, undo.
List<Map<String, dynamic>> bbRingsJson(
  ChatService chat,
  String ownerId, {
  required bool allowed,
}) {
  // Porch Life off hides the line, and no owner (no chat open, no active
  // character) owns no rings: the store is keyed by real ids either way, so
  // asking is a guaranteed miss.
  if (!allowed || ownerId.isEmpty) return const [];
  // allRingsFor hands back an unmodifiable list: copy before sorting.
  final rings = [...chat.growthRingsForOwner(ownerId)]
    ..sort(
      (a, b) => (a.category == 'bogey' ? 1 : 0).compareTo(
        b.category == 'bogey' ? 1 : 0,
      ),
    );
  return [
    for (final r in rings)
      if (BoonsBogies.isBoonOrBogey(r) && !r.retired) growthRingToJson(r),
  ];
}
