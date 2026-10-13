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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/ui/window_size_env.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'main_window.dart';

/// The main window's last NORMAL (non-maximized, non-minimized) bounds,
/// tracked live from window_manager events so [save] never persists a
/// full-screen rect or the Win32 minimized sentinel (PR #53, issue #78).
class WindowBoundsTracker {
  double _normalWidth = 1280;
  double _normalHeight = 720;
  double? _normalX;
  double? _normalY;

  /// Post-first-frame capture after restore, so tracking is correct even if
  /// the user maximizes without any interactive resize this session.
  Future<void> captureInitial() async {
    try {
      if (!await windowManager.isMaximized()) {
        final size = await windowManager.getSize();
        final position = await windowManager.getPosition();
        _normalWidth = size.width;
        _normalHeight = size.height;
        _normalX = position.dx;
        _normalY = position.dy;
      }
    } catch (e) {
      debugPrint('Failed to capture initial window bounds: $e');
    }
  }

  Future<void> onResized() async {
    try {
      if (!await windowManager.isMaximized()) {
        final size = await windowManager.getSize();
        _normalWidth = size.width;
        _normalHeight = size.height;
      }
    } catch (e) {
      debugPrint('Failed to capture window size: $e');
    }
  }

  Future<void> onMoved() async {
    try {
      if (!await windowManager.isMaximized()) {
        final pos = await windowManager.getPosition();
        _normalX = pos.dx;
        _normalY = pos.dy;
      }
    } catch (e) {
      debugPrint('Failed to capture window position: $e');
    }
  }

  Future<void> onUnmaximized() async {
    try {
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      _normalWidth = size.width;
      _normalHeight = size.height;
      _normalX = pos.dx;
      _normalY = pos.dy;
    } catch (e) {
      debugPrint('Failed to capture window bounds after unmaximize: $e');
    }
  }

  /// Persists size, position and maximized state. Call while the window is
  /// still alive and queryable. Never throws.
  Future<void> save() async {
    // Save window state (size, position, maximized) before cleanup.
    // Must happen early while the window is still alive and queryable.
    try {
      final isMax = await windowManager.isMaximized();
      // A window closed while MINIMIZED reports the Win32 minimized sentinel
      // (~ -32000, -32000) from getPosition(). Saving that poisons the restore
      // and strands the window off-screen next launch (issue #78). Treat
      // minimized exactly like maximized: persist the tracked non-minimized
      // _normal* bounds instead of the live (bogus) rect.
      final isMin = await windowManager.isMinimized();
      final prefs = await SharedPreferences.getInstance();
      // WINDOW_WIDTH/HEIGHT launch hook: do not poison the user's saved
      // window with the dart-define size.
      final persistSize = !WindowSizeEnv.active;

      if (isMax || isMin) {
        // Save tracked normal (non-maximized, non-minimized) bounds so the
        // restore code never sets the window to full-screen size in the
        // non-maximized state and never writes the minimized sentinel.
        // This eliminates the ghost frame root cause on Windows and the
        // off-screen-taskbar-icon bug from issue #78.
        //
        // NOTE: _normal* fields are populated ONLY from live windowManager
        // queries during this session (post-frame capture, resize/move
        // listeners, unmaximize). They are NOT seeded from the persisted
        // window_* prefs on launch. Consequence: if the user launches
        // maximized, never unmaximizes or resizes, and closes while still
        // maximized, stale defaults are saved here (1280x720 / 0) rather
        // than their actual normal geometry. This works across
        // Windows/macOS/Linux because each OS internally preserves the
        // pre-maximize "restore down" rect and applies it when the window
        // is unmaximized after next launch — the stale prefs are simply
        // overwritten. If a platform ever drops this behavior, the fix is
        // to unconditionally seed _normal* from persisted prefs in the
        // post-frame callback ([captureInitial]), before or instead of the
        // live capture. See PR #53 for the full ghost-frame analysis.
        if (persistSize) {
          await prefs.setDouble(windowPrefKey('window_width'), _normalWidth);
          await prefs.setDouble(windowPrefKey('window_height'), _normalHeight);
        }
        await prefs.setDouble(windowPrefKey('window_x'), _normalX ?? 0.0);
        await prefs.setDouble(windowPrefKey('window_y'), _normalY ?? 0.0);
      } else {
        final size = await windowManager.getSize();
        final position = await windowManager.getPosition();
        _normalWidth = size.width;
        _normalHeight = size.height;
        _normalX = position.dx;
        _normalY = position.dy;
        if (persistSize) {
          await prefs.setDouble(windowPrefKey('window_width'), size.width);
          await prefs.setDouble(windowPrefKey('window_height'), size.height);
        }
        await prefs.setDouble(windowPrefKey('window_x'), position.dx);
        await prefs.setDouble(windowPrefKey('window_y'), position.dy);
      }
      await prefs.setBool(windowPrefKey('window_maximized'), isMax);
    } catch (e) {
      debugPrint('Failed to save window state: $e');
    }
  }
}
