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

part of 'realism_settings.dart';

extension RealismSettingsLoad on RealismSettings {
  void load() {
    _realismDefault = prefs?.getBool(k('realism_default')) ?? false;
    _nsfwCooldownDefault = prefs?.getBool(k('nsfw_cooldown_default')) ?? false;
    _passageOfTimeDefault =
        prefs?.getBool(k('passage_of_time_default')) ?? true;
    _needsSimDefault = prefs?.getBool(k('needs_sim_default')) ?? true;
    _standaloneClockEnabled =
        prefs?.getBool(k('standalone_clock_enabled')) ?? false;
    _objectivesEnabled = prefs?.getBool(k('objectives_enabled')) ?? true;
    _pocketsEnabled = prefs?.getBool(k('pockets_enabled')) ?? false;
    _standingMoodEnabled = prefs?.getBool(k('standing_mood_enabled')) ?? false;
    _intimateAgencyEnabled =
        prefs?.getBool(k('intimate_agency_enabled')) ?? false;
    _chaosModeDefault = prefs?.getBool(k('chaos_mode_default')) ?? false;
    _sceneGuestDetectionEnabled =
        prefs?.getBool(k('scene_guest_detection_enabled')) ?? true;
    _pocketTransfersEnabled =
        prefs?.getBool(k('pocket_transfers_enabled')) ?? false;
    _adultThemesExplicit = prefs?.getBool(k('adult_themes_enabled'));
    _oneShotMode = switch (prefs?.getString(k('realism_one_shot_mode'))) {
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
    _preferTextEvals = prefs?.getBool(k('prefer_text_evals')) ?? false;
    _weatherEnabled = prefs?.getBool(k('weather_enabled')) ?? true;
    _weatherFahrenheit = prefs?.getBool(k('weather_fahrenheit')) ?? false;
    _absenceBannerEnabled = prefs?.getBool(k('absence_banner_enabled')) ?? true;
    _absenceAckEnabled = prefs?.getBool(k('absence_ack_enabled')) ?? false;
    _absenceThresholdHours = prefs?.getInt(k('absence_threshold_hours')) ?? 24;
    _dreamsEnabled = prefs?.getBool(k('dreams_enabled')) ?? true;
    _ambitionsEnabled = prefs?.getBool(k('ambitions_enabled')) ?? true;
    _plannerEnabled = prefs?.getBool(k('planner_enabled')) ?? false;
    _promiseLedgerEnabled = prefs?.getBool(k('promise_ledger_enabled')) ?? true;

    final bannedJson = prefs?.getString(k('banned_phrases'));
    if (bannedJson != null) {
      try {
        _bannedPhrases = List<String>.from(jsonDecode(bannedJson) as List);
      } catch (_) {
        _bannedPhrases = [];
      }
    }
  }
}
