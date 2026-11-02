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

/// The limits the Recent shelf offers. [kStudioRecentKeepAll] never trims;
/// [kStudioRecentOff] holds only the newest picture (so the phone can still
/// insert or download it) and hides the shelf. Starred pictures never count.
const int kStudioRecentKeepAll = -1;
const int kStudioRecentOff = 0;
const int kStudioRecentDefault = 50;
const List<int> kStudioRecentChoices = [
  50,
  200,
  kStudioRecentKeepAll,
  kStudioRecentOff,
];

/// Image Studio's Recent shelf: how many unstarred pictures it keeps, and an
/// optional folder the user chose for them (empty = the app's own folder).
mixin StudioRecentPrefs on SettingsBase {
  int _studioRecentLimit = kStudioRecentDefault;
  String _studioRecentFolder = '';

  int get studioRecentLimit => _studioRecentLimit;
  String get studioRecentFolder => _studioRecentFolder;

  void loadStudioRecentPrefs() {
    final stored = prefs?.getInt(k('image_studio_recent_limit'));
    _studioRecentLimit = kStudioRecentChoices.contains(stored)
        ? stored!
        : kStudioRecentDefault;
    _studioRecentFolder =
        prefs?.getString(k('image_studio_recent_folder')) ?? '';
  }

  /// Ignores a value the shelf does not offer, so a stale phone cannot store
  /// a limit the desktop has no word for.
  Future<bool> setStudioRecentLimit(int value) async {
    if (!kStudioRecentChoices.contains(value)) return false;
    _studioRecentLimit = value;
    await prefs?.setInt(k('image_studio_recent_limit'), value);
    notify();
    return true;
  }

  Future<void> setStudioRecentFolder(String value) async {
    _studioRecentFolder = value.trim();
    await prefs?.setString(
      k('image_studio_recent_folder'),
      _studioRecentFolder,
    );
    notify();
  }
}
