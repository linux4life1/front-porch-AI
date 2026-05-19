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

import 'package:front_porch_ai/models/lorebook.dart';

/// Model representing a world or lorebook in the application.
///
/// Worlds can be created independently or auto-generated from character imports.
/// When linked to a character, the world inherits the character's avatar path
/// for consistent visual representation in the UI.
class World {
  String name;
  String description;
  Lorebook lorebook;
  
  /// If set, this world was auto-created from a character import.
  /// When linked to a character, we can display the character's actual avatar
  /// instead of a generic globe icon.
  String? linkedCharacterName;
  
  /// Path to the avatar image for this world. Only applicable when
  /// linkedCharacterName is set (world was created from a character).
  /// 
  /// This allows us to display the actual character avatar in world cards
  /// and other UI elements, providing visual consistency between characters
  /// and their associated worlds.
  String? avatarPath;

  World({
    required this.name,
    this.description = '',
    required this.lorebook,
    this.linkedCharacterName,
    this.avatarPath,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'lorebook': lorebook.toJson(),
      if (linkedCharacterName != null) 'linked_character_name': linkedCharacterName,
      if (avatarPath != null) 'avatar_path': avatarPath,
    };
  }

  factory World.fromJson(Map<String, dynamic> json) {
    // Determine name and description
    // Chub/SillyTavern: top-level name/description
    // Front Porch: top-level name/description
    final String name = json['name']?.toString() ?? 'Imported World';
    final String description = json['description']?.toString() ?? '';

    // Determine lorebook
    // Front Porch format: { "lorebook": { "entries": [...] } }
    // SillyTavern/Chub format: { "entries": {...} } (entries at top level)
    Lorebook lorebook;
    if (json['lorebook'] != null) {
      // Front Porch format with explicit lorebook wrapper
      lorebook = Lorebook.fromJson(json['lorebook'] as Map<String, dynamic>);
    } else if (json['entries'] != null) {
      // SillyTavern/Chub format: entries at top level
      // Wrap in a map to pass to Lorebook.fromJson
      lorebook = Lorebook.fromJson({'entries': json['entries']});
    } else {
      lorebook = Lorebook(entries: []);
    }

    return World(
      name: name,
      description: description,
      lorebook: lorebook,
      linkedCharacterName: json['linked_character_name'],
      avatarPath: json['avatar_path'],
    );
  }
}
