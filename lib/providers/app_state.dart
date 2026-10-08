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

import 'package:flutter/material.dart';

class AppState extends ChangeNotifier {
  // Transient UI state only. Theme/dark mode lives in StorageService (single source of truth,
  // persisted, drives root MaterialApp rebuild via Consumer2). Removing the old duplication
  // also removes the source of prior "setState during build" and init-race bugs.
  int _selectedIndex = 0;
  int get selectedIndex => _selectedIndex;

  /// Bumped when the sidebar's Home entry is tapped while Home is already the
  /// selected page. Re-tapping Home used to be a silent no-op; the home grid
  /// listens for this and returns to the library's top level (folder = null).
  int _homeResetTick = 0;
  int get homeResetTick => _homeResetTick;

  /// The sidebar belongs to the main screen only. Home's sub-apps (Porch
  /// Stories, Waifu Coder) take the whole window; the mode toggle above
  /// them is the way back.
  bool _sidebarHidden = false;
  bool get sidebarHidden => _sidebarHidden && _selectedIndex == 0;

  /// [notify] false is for dispose, where listeners must not be rebuilt.
  void setSidebarHidden(bool hidden, {bool notify = true}) {
    if (_sidebarHidden == hidden) return;
    _sidebarHidden = hidden;
    if (notify) notifyListeners();
  }

  void setIndex(int index) {
    if (index == 0 && _selectedIndex == 0) _homeResetTick++;
    _selectedIndex = index;
    notifyListeners();
  }
}
