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

import 'dart:io';

/// Represents a single avatar image for a character.
/// Characters can have up to 10 avatars, with one marked as prime.
class AvatarImage {
  final String id;
  final String characterId;
  final String filename;
  final String? label;
  final int displayOrder;
  final DateTime createdAt;

  AvatarImage({
    required this.id,
    required this.characterId,
    required this.filename,
    this.label,
    required this.displayOrder,
    required this.createdAt,
  });

  /// Sentinel [label] marking a gallery "look" (a plain alternate avatar the
  /// user picks — a different outfit, a scene) as opposed to an expression image
  /// (which carries an emotion label). Looks are kept OUT of the emotion pipeline
  /// and stored in a separate `looks/` folder, so the two never mix.
  static const String lookLabel = '__look__';

  /// True when this is a gallery look, not an expression image.
  bool get isLook => label == lookLabel;

  /// The character subfolder this image lives in: `looks/` for gallery looks,
  /// `avatars/` for expression images.
  String get subfolder => isLook ? 'looks' : 'avatars';

  /// Resolve this avatar to a [File] given the character's **avatars** directory path.
  /// The [avatarsDirPath] should be the path to the `avatars` subdirectory,
  /// e.g. `.../Characters/Carly/avatars/`. (Expression images only — for looks
  /// use [resolveFile], which picks the right subfolder.)
  File file(String avatarsDirPath) {
    return File('$avatarsDirPath/$filename');
  }

  /// Resolve this avatar to a [File] against the character's BASE folder
  /// (e.g. `.../Characters/Carly/`), automatically choosing `looks/` vs
  /// `avatars/`. The single look-aware resolver — new look-reading code should
  /// use this rather than joining a hard-coded `avatars/` path.
  File resolveFile(String characterBaseDirPath) {
    return File('$characterBaseDirPath/$subfolder/$filename');
  }

  AvatarImage copyWith({
    String? id,
    String? characterId,
    String? filename,
    String? label,
    int? displayOrder,
    DateTime? createdAt,
  }) {
    return AvatarImage(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      filename: filename ?? this.filename,
      label: label ?? this.label,
      displayOrder: displayOrder ?? this.displayOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
