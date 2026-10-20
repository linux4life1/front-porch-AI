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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/ui/window_chrome.dart';
import 'package:front_porch_ai/ui/window_size_env.dart';
import 'package:front_porch_ai/utils/utils.dart' show StartupTrace;
// screen_retriever is a transitive dep of window_manager (used here to validate
// that restored window bounds are actually visible on a connected display).
// ignore: depend_on_referenced_packages
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// Prefix SharedPreferences keys for beta builds so window state is
/// isolated from the stable installation.  Unchanged for stable builds.
String windowPrefKey(String key) => isPreRelease ? 'beta_$key' : key;

/// True when a meaningful chunk of the given window rect overlaps at least one
/// connected display's visible area — i.e. the window would actually be
/// reachable on screen if we restored it there.
///
/// This is the guard for GitHub issue #78: on Windows, closing the app while
/// the window is *minimized* makes `getPosition()` return the Win32 minimized
/// sentinel (~ -32000, -32000). Without this check that poisoned coordinate was
/// written to `window_x`/`window_y` and, on the next launch, `setBounds` placed
/// the window far off-screen — it appeared only as an unreachable taskbar icon
/// that WIN+arrow / ALT+Enter could not recover. Because SharedPreferences on
/// Windows lives outside the app's data folders, uninstalling did not clear it,
/// so the break survived a full reinstall. Rejecting off-screen bounds here
/// self-heals those already-affected installs (we fall back to the centered
/// default) as well as any window stranded by a since-disconnected monitor.
Future<bool> windowBoundsVisible(Rect bounds) async {
  // Cheap, dependency-free rejection of the Win32 minimized sentinel first —
  // this is also the fallback if display enumeration throws below.
  const double kOffscreenSentinel = -30000;
  if (bounds.left <= kOffscreenSentinel || bounds.top <= kOffscreenSentinel) {
    return false;
  }
  try {
    final displays = await screenRetriever.getAllDisplays();
    for (final d in displays) {
      final origin = d.visiblePosition ?? Offset.zero;
      final size = d.visibleSize ?? d.size;
      final screen = Rect.fromLTWH(
        origin.dx,
        origin.dy,
        size.width,
        size.height,
      );
      final overlap = bounds.intersect(screen);
      // Require a grabbable chunk (roughly the title bar + a corner) to be
      // visible, so a 1px sliver peeking onto a screen still counts as lost.
      if (overlap.width > 120 && overlap.height > 60) return true;
    }
    return false;
  } catch (e) {
    // Display enumeration failed (rare, pre-runApp). We already ruled out the
    // sentinel above, so trust the saved bounds rather than fighting the OS.
    debugPrint('Failed to enumerate displays for window restore: $e');
    return true;
  }
}

/// On Windows the window stays hidden until Dart shows it, and every size
/// change below happens with the engine already producing frames, so the
/// engine's resize handshake can complete instead of timing out with no
/// frame to wait for (flutter/flutter#192537: a timed-out handshake left
/// the window white until a real resize). On Windows [runApp] has already
/// been called; macOS and Linux still call this before it.
Future<void> showMainWindow({Color? background}) async {
  final forcedSize = WindowSizeEnv.sizeFromEnvironment();
  final windowOptions = mainWindowOptions(
    size: forcedSize,
    background: background,
  );

  if (Platform.isWindows) {
    // The first frame rasterized by the engine, at the window's creation
    // size, before any resize.
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
  }

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (forcedSize != null) {
      // Launch hook: skip saved-bounds restore so --dart-define sizes
      // actually show. Missing axis is 1280 or 720.
      await windowManager.setSize(forcedSize);
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final windowWidth = prefs.getDouble(windowPrefKey('window_width'));
        final windowHeight = prefs.getDouble(windowPrefKey('window_height'));
        final windowX = prefs.getDouble(windowPrefKey('window_x'));
        final windowY = prefs.getDouble(windowPrefKey('window_y'));
        final windowMaximized =
            prefs.getBool(windowPrefKey('window_maximized')) ?? false;

        // NOTE: Users upgrading from builds before PR #53 may have saved
        // full-screen rect values in window_* prefs (old code used
        // unconditional getSize() in onWindowClose regardless of maximize
        // state). setBounds(fullscreen) + maximize() could in theory
        // reproduce ghosting, but setBounds to the already-maximized size
        // is a no-op and the bug doesn't trigger. Even without this defense,
        // the stale values self-heal on the first non-maximized close (which
        // saves correct bounds).
        //
        // Validate the saved rect is actually visible on a connected display
        // before applying it (issue #78 — see windowBoundsVisible). If it
        // isn't (Win32 minimized sentinel, or a monitor that has since been
        // unplugged), we skip setBounds and fall through to the centered
        // default from WindowOptions instead of stranding the window off-screen.
        Rect? savedBounds;
        if (windowX != null &&
            windowY != null &&
            windowWidth != null &&
            windowHeight != null) {
          final candidate = Rect.fromLTWH(
            windowX,
            windowY,
            windowWidth,
            windowHeight,
          );
          if (await windowBoundsVisible(candidate)) {
            savedBounds = candidate;
          }
        }

        if (windowMaximized) {
          // Restore the non-maximized bounds first (so the OS remembers
          // the correct "restore down" size), then maximize. This never
          // puts the window at full-screen size in non-maximized state,
          // which was the root cause of the Windows ghost frame issue.
          if (savedBounds != null) {
            await windowManager.setBounds(savedBounds);
          }
          await windowManager.maximize();
        } else if (savedBounds != null) {
          // Restore saved position + size
          await windowManager.setBounds(savedBounds);
        }
      } catch (e) {
        debugPrint('Failed to restore window state: $e');
      }
    }

    if (Platform.isWindows) {
      // A frame at the restored size, so the window appears painted rather
      // than white or stretched from the creation size.
      await WidgetsBinding.instance.endOfFrame;
    }
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setPreventClose(true);
    // waitUntilReadyToShow applies titleBarStyle *before* backgroundColor.
    // Re-pin last so a later plugin cannot leave fullSizeContentView on.
    // TitleBarStyle.normal is a no-op-shaped decorated window on Win/Linux.
    await windowManager.setTitleBarStyle(
      TitleBarStyle.normal,
      windowButtonVisibility: true,
    );
  });
  StartupTrace.mark('window shown (waitUntilReadyToShow)');
}
