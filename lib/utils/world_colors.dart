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

import 'package:flutter/material.dart';
import 'package:front_porch_ai/utils/persona_colors.dart';

/// Generates consistent, distinct colors for worlds based on their ID.
///
/// This class reuses the PersonaColors palette to maintain visual consistency
/// across the application. Worlds use deterministic color assignment based on
/// their name or ID hash, providing visual distinction without requiring manual
/// color selection.
///
/// When a world is linked to a character, the actual character avatar is
/// displayed instead of using these colors. These colors serve as fallbacks
/// for standalone worlds or when character data is unavailable.
class WorldColors {
  /// Get a consistent color for a given world ID.
  ///
  /// Uses the same palette as PersonaColors to maintain visual harmony
  /// across the application. The color is deterministically selected based
  /// on the hash of the world ID, ensuring the same world always gets
  /// the same color regardless of when or where it's displayed.
  ///
  /// [worldId] - The unique identifier for the world (typically the name).
  static Color getColorForWorld(String worldId) {
    return PersonaColors.getColorForPersona(worldId);
  }
}
