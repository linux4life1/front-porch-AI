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

part of '../chat_service.dart';

/// Standing Mood — the ONE place the baseline is derived, gated and read.
///
/// A leaf rather than four lines in the shell on purpose: chat_service.dart is
/// at 970 of the CI-enforced 1000-line ceiling, and this is exactly the
/// cohesive-chunk-in-a-part the ratchet exists to encourage.
///
/// Everything here is synchronous and free. [MoodBaseline] is derived from
/// state other features already computed; there is no eval, no store and no
/// schema, which is also why the whole feature can be switched off with no
/// migration and no residue.
extension ChatServiceMood on ChatService {
  /// The speaker's standing mood, or neutral when the feature is off.
  ///
  /// Gated HERE and nowhere else — the derivation leaf consults no settings,
  /// so a second gate cannot appear later and disagree with this one. (Same
  /// discipline as `_runPocketsPass`.)
  ///
  /// Reads the CURRENT speaker's needs so a group member's mood is their own:
  /// `needsSimulation.vector` is already loaded with the evaluated speaker's
  /// values by the per-speaker group dance, exactly as the needs chips read it.
  MoodBaseline get _standingMood {
    if (!_storageService.realismSettings.standingMoodEnabled) {
      return MoodBaseline.neutral;
    }
    return deriveMoodBaseline(
      // Empty when the simulation is off, and that is correct rather than
      // degraded: the clock and the weather still have something to say about
      // their day.
      needs: _needsSimEnabled ? _needsSimulation.vector : const {},
      timeOfDay: _clockRunning ? _timeService.timeOfDay : '',
      weather: currentWeather,
    );
  }

  /// What they walked in carrying, for display. Empty when the feature is off
  /// or the day is unremarkable.
  ///
  /// The class member is a one-line forwarder in the shell, NOT this getter,
  /// and that is load-bearing: extension members are statically dispatched, so
  /// a `FakeChatService implements ChatService` in the golden harness cannot
  /// override one — the call reaches into ChatService privates and throws
  /// NoSuchMethodError mid-build, rendering an error box. That is exactly how
  /// `objectivesActive` took the character_state goldens down at 87% earlier
  /// today. See the fake-pinned note in the ChatService class doc.
  String get standingMoodSummaryImpl => _standingMood.summary;

  /// The prompt fragment, empty when there is nothing to say (which is most of
  /// the time — a rested, fed character on a mild afternoon has no standing
  /// mood, and that IS the neutral case rather than a missing one).
  String buildStandingMoodInjection() => _standingMood.injection;

  /// Stamp the baseline onto the turn's realism metadata so the mood chip can
  /// explain itself.
  ///
  /// The mood chip was the only chip in the app with no hover reason — bond,
  /// trust, every need, the verifier and Chance Time all carry one, and it
  /// alone said "Mood: wistful" with nothing behind it. It could not have one
  /// before: the emotional eval returns a label and an intensity, never a
  /// cause, and adding an `emotion_reason` field would have changed the eval
  /// (and its cost) on every path. The standing mood supplies the honest
  /// answer for free — not "why they feel this", which nothing knows, but what
  /// they walked in carrying, which is exactly the missing half.
  ///
  /// Absent when neutral, so the chip renders unchanged rather than showing an
  /// empty tooltip.
  void stampStandingMood(Map<String, dynamic> metadata) {
    final mood = _standingMood;
    if (mood.isNeutral) return;
    metadata['mood_context'] = mood.toJson();
  }
}
