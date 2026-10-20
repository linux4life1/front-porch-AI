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

import 'package:front_porch_ai/services/storage/settings/appearance_settings.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// The desktop's resolved app theme for the web: its mode and both token
/// maps. Rides the settings snapshot as `theme` and every
/// `settings_changed` event, so the PWA repaints without asking. Additive:
/// an older PWA ignores the key.
Map<String, Object> webThemeWire(AppearanceSettings appearance) =>
    WebThemeTokens.wire(
      appearance.resolvedPalettes(),
      isDark: appearance.isDark,
    );
