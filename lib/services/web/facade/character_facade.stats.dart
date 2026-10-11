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

part of 'character_facade.dart';

extension CharacterFacadeStats on CharacterFacade {
  /// "Your chats together" for the character editor, or null when [id] is
  /// not a library character. Same counts as the desktop Details tab.
  Future<Map<String, dynamic>?> stats(String id) async {
    final exists = await (_db.select(
      _db.characters,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (exists == null) return null;
    return (await loadCharacterStats(_db, id)).toJson();
  }
}
