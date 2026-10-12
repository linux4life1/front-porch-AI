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

import 'package:front_porch_ai/services/storage/settings/realism_settings.dart';

/// The once-only flag for the imported-card Needs clean-up
/// (`imported_needs_cleanup.dart`). Read live, not cached in
/// [RealismSettings.load]: it is read once per launch, after the settings
/// have loaded. Uses only the public prefs seam of [RealismSettings].
extension RealismSettingsImportStamp on RealismSettings {
  bool get importedNeedsStampCleared =>
      prefs?.getBool(k('imported_needs_stamp_cleared')) ?? false;

  Future<void> markImportedNeedsStampCleared() async {
    await prefs?.setBool(k('imported_needs_stamp_cleared'), true);
  }
}
