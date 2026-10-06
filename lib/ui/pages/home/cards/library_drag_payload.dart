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

/// What a held, picked card carries when it is dragged: every pick, not
/// just the card under the pointer (library phase 3). Keys are the
/// selection keys: character stableGroupIds and group ids.
class LibraryDragPayload {
  const LibraryDragPayload({
    required this.characterIds,
    required this.groupIds,
  });

  final Set<String> characterIds;
  final Set<String> groupIds;

  int get count => characterIds.length + groupIds.length;
}

/// How many cards a drag carries: the picks, or the one card of an
/// ordinary single-card drag. Zero for anything the library cannot move.
int libraryDragCount(Object? data) => switch (data) {
  LibraryDragPayload(:final count) => count,
  CharacterCard() || GroupChat() => 1,
  _ => 0,
};
