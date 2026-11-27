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

import '../settings_base.dart';

/// Porch Life → Afterglow → Classic Lust bar (docs/design/heat-meter.md §8).
///
/// Off (the default) is Heat: Lust is desire, Heat is closeness to release
/// and has its own bar. On keeps the pre-Heat behaviour for those who want
/// it: Lust alone, with its old wording, decides when a character finishes,
/// the judge is not asked about contact, and no Heat bar shows. Turning it on
/// hides Heat and keeps its value, so turning it off again resumes it.
///
/// Read live from the preferences, so there is no load step to keep in step.
mixin ClassicLustSetting on SettingsBase {
  static const _key = 'classic_lust_enabled';

  bool get classicLustEnabled => prefs?.getBool(k(_key)) ?? false;

  /// Heat runs: the default, and whenever the classic bar is off.
  bool get heatEnabled => !classicLustEnabled;

  Future<void> setClassicLustEnabled(bool value) async {
    await prefs?.setBool(k(_key), value);
    notify();
  }
}
