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

/// What kind of Chance Time event this is. Drives the wheel's reveal (label,
/// emoji) and how the wheel spreads its eight slots across kinds.
enum ChaosCategory {
  fortune('🎉', 'Fortune!'),
  misfortune('💀', 'Misfortune'),
  chaos('⚡', 'Chaos!'),
  wildCard('🔮', 'Wild Card'),
  slapstick('🎪', 'Slapstick!'),
  social('💬', 'Social Scene'),
  weather('🌩️', 'Change in the Air'),
  plotHook('🗝️', 'Plot Twist'),
  needs('🚽', 'Body Betrayal'),
  spicy('🌶️', 'Spicy!');

  const ChaosCategory(this.emoji, this.label);

  final String emoji;
  final String label;
}

/// One Chance Time event. [text] carries `{{char}}` (the responding
/// character), and may carry `{{user}}` or `{{other}}` (a second cast member,
/// group chats only). [adult] events only reach the wheel when the chat's
/// spicy switch is on AND the app-wide 18+ themes switch is on.
class ChaosEvent {
  const ChaosEvent(this.category, this.text, {this.adult = false});

  final ChaosCategory category;
  final String text;
  final bool adult;

  /// Whether the event names a second cast member and so needs a group.
  bool get needsPartner => text.contains('{{other}}');

  /// Whether the event names the user, which an observer-mode group lacks.
  bool get involvesUser => text.contains('{{user}}');
}
