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
import 'classic_lust_setting.dart';
import 'realism_allowed_setting.dart';
import 'time_skip_bridge_setting.dart';

export 'classic_lust_setting.dart';
export 'realism_allowed_setting.dart';
export 'time_skip_bridge_setting.dart';

/// The Realism switches that read their preference live, with no load step:
/// one place for `RealismSettings` to take them from, so the settings class
/// itself stays under the 500-line cap as switches are added.
abstract class RealismLivePrefs
    with
        SettingsBase,
        TimeSkipBridgeSetting,
        RealismAllowedSetting,
        ClassicLustSetting {}
