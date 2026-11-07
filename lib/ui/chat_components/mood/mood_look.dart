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

import 'package:flutter/foundation.dart' show immutable;

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/appearance_options.dart';

/// Appearance → Mood on the character, resolved for the chat surface: the
/// level and the Drama, or [off] while Porch Life's Realism Engine is off
/// (then the row is not even shown). Call sites with the real storage
/// build it once and hand it down, so a widget under test with a fake
/// storage never reaches for a setting the fake does not carry.
@immutable
class MoodLook {
  const MoodLook(this.level, this.drama);

  factory MoodLook.of(StorageService storage) =>
      storage.realismSettings.realismAllowed
      ? MoodLook(
          storage.appearance.moodOnCharacter,
          storage.appearance.moodDrama,
        )
      : off;

  static const MoodLook off = MoodLook(MoodOnCharacter.off, kMoodDramaDefault);

  final MoodOnCharacter level;
  final double drama;

  /// The portrait ring and halo, and the needs bars.
  bool get portraitOn => level.portraitOn;

  /// The speaker's bubbles too.
  bool get bubblesOn => level.bubblesOn;

  @override
  bool operator ==(Object other) =>
      other is MoodLook && other.level == level && other.drama == drama;

  @override
  int get hashCode => Object.hash(level, drama);
}
