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

/// Real-world absence awareness (living-time-features.md §2) — pure helpers.
///
/// Privacy by design: the ONLY input is the wall-clock gap since the chat's
/// last saved message — data the local DB has always stored. Nothing here is
/// persisted, transmitted, or precise: gaps render as coarse word buckets
/// ("a few days"), never digits, because precision is what makes
/// time-awareness read as surveillance instead of warmth. The story clock is
/// never touched.
class AbsenceTracker {
  AbsenceTracker._(); // static-only

  /// Coarse bucket phrase for [gap], or null below [thresholdHours] (no
  /// banner, no acknowledgment). Words only — no digits, ever.
  static String? bucketPhrase(Duration gap, {int thresholdHours = 24}) {
    final h = gap.inHours;
    if (h < thresholdHours || h < 12) return null;
    if (h < 48) return 'a day';
    if (h < 24 * 7) return 'a few days';
    if (h < 24 * 14) return 'about a week';
    if (h < 24 * 28) return 'a couple of weeks';
    return 'a long while';
  }

  /// The one-shot, opt-in prompt note for the in-character acknowledgment.
  /// Deliberately meta (story clock untouched) and speculation-forbidding:
  /// a character saying "you were gone a while" is warm; "where were you?"
  /// is not.
  static String ackNote(String phrase) =>
      '(Out of story: about $phrase has passed in the real world since the '
      'last exchange. You may acknowledge the gap once, briefly and warmly, '
      'in character — but never guess what {{user}} was doing, never ask '
      'where they were, never imply you were watching or waiting anxiously, '
      'and do not mention it again afterward.)';
}
