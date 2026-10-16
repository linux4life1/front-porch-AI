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

import 'dart:convert';

import 'package:front_porch_ai/services/chat/chaos/chaos_frequency.dart';
import 'package:front_porch_ai/services/storage/settings/realism/one_shot_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every persisted Realism / Porch Life pref, read once with its default.
/// [RealismSettings.load] copies this into its fields.
class RealismPrefsSnapshot {
  final bool realismDefault;
  final bool nsfwCooldownDefault;
  final bool passageOfTimeDefault;
  final bool needsSimDefault;
  final bool standaloneClockEnabled;
  final bool objectivesEnabled;
  final bool pocketsEnabled;
  final bool standingMoodEnabled;
  final bool intimateAgencyEnabled;
  final bool chaosModeDefault;
  final ChaosFrequency chaosFrequency;
  final bool sceneGuestDetectionEnabled;
  final bool pocketTransfersEnabled;
  final bool? adultThemesExplicit;
  final OneShotMode oneShotMode;
  final bool preferTextEvals;
  final bool weatherEnabled;
  final bool weatherFahrenheit;
  final bool absenceBannerEnabled;
  final bool userMessagesOnRight;
  final bool absenceAckEnabled;
  final int absenceThresholdHours;
  final bool dreamsEnabled;
  final bool ambitionsEnabled;
  final bool plannerEnabled;
  final bool promiseLedgerEnabled;

  /// Null when no list was ever stored (keep the in-memory default).
  final List<String>? bannedPhrases;

  RealismPrefsSnapshot.read(SharedPreferences? prefs, String Function(String) k)
    : realismDefault = prefs?.getBool(k('realism_default')) ?? false,
      nsfwCooldownDefault = prefs?.getBool(k('nsfw_cooldown_default')) ?? false,
      passageOfTimeDefault =
          prefs?.getBool(k('passage_of_time_default')) ?? true,
      needsSimDefault = prefs?.getBool(k('needs_sim_default')) ?? true,
      standaloneClockEnabled =
          prefs?.getBool(k('standalone_clock_enabled')) ?? false,
      // (objective_stale_threshold, the old "retire after N" picker, is no
      // longer read: one "overtaken" answer from the goal sync replaced it.)
      objectivesEnabled = prefs?.getBool(k('objectives_enabled')) ?? true,
      pocketsEnabled = prefs?.getBool(k('pockets_enabled')) ?? false,
      standingMoodEnabled = prefs?.getBool(k('standing_mood_enabled')) ?? false,
      intimateAgencyEnabled =
          prefs?.getBool(k('intimate_agency_enabled')) ?? false,
      chaosModeDefault = prefs?.getBool(k('chaos_mode_default')) ?? false,
      chaosFrequency = ChaosFrequency.fromName(
        prefs?.getString(k('chaos_frequency')),
      ),
      sceneGuestDetectionEnabled =
          prefs?.getBool(k('scene_guest_detection_enabled')) ?? true,
      pocketTransfersEnabled =
          prefs?.getBool(k('pocket_transfers_enabled')) ?? false,
      adultThemesExplicit = prefs?.getBool(k('adult_themes_enabled')),
      oneShotMode = _readOneShotMode(prefs, k),
      preferTextEvals = prefs?.getBool(k('prefer_text_evals')) ?? false,
      weatherEnabled = prefs?.getBool(k('weather_enabled')) ?? true,
      weatherFahrenheit = prefs?.getBool(k('weather_fahrenheit')) ?? false,
      absenceBannerEnabled =
          prefs?.getBool(k('absence_banner_enabled')) ?? true,
      userMessagesOnRight =
          prefs?.getBool(k('user_messages_on_right')) ?? false,
      absenceAckEnabled = prefs?.getBool(k('absence_ack_enabled')) ?? false,
      absenceThresholdHours = prefs?.getInt(k('absence_threshold_hours')) ?? 24,
      dreamsEnabled = prefs?.getBool(k('dreams_enabled')) ?? true,
      ambitionsEnabled = prefs?.getBool(k('ambitions_enabled')) ?? true,
      plannerEnabled = prefs?.getBool(k('planner_enabled')) ?? false,
      promiseLedgerEnabled =
          prefs?.getBool(k('promise_ledger_enabled')) ?? true,
      bannedPhrases = _readBannedPhrases(prefs, k);

  static OneShotMode _readOneShotMode(
    SharedPreferences? prefs,
    String Function(String) k,
  ) => switch (prefs?.getString(k('realism_one_shot_mode'))) {
    'on' => OneShotMode.on,
    'off' => OneShotMode.off,
    'auto' => OneShotMode.auto,
    // Pre-tri-state install: an explicit true was a deliberate opt-in and
    // stays ON. false was the old default and indistinguishable from
    // "never touched", so it becomes Auto — the new default, which only
    // ever differs from off on a remote backend that has proven tools.
    _ =>
      (prefs?.getBool(k('realism_one_shot_eval')) ?? false)
          ? OneShotMode.on
          : OneShotMode.auto,
  };

  static List<String>? _readBannedPhrases(
    SharedPreferences? prefs,
    String Function(String) k,
  ) {
    final bannedJson = prefs?.getString(k('banned_phrases'));
    if (bannedJson == null) return null;
    try {
      return List<String>.from(jsonDecode(bannedJson) as List);
    } catch (_) {
      return [];
    }
  }
}
