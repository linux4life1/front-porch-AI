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

part of 'main.dart';

/// Shutdown + post-first-frame chores, extracted verbatim from
/// `_MyAppState` (god-file elimination, Tranche C). `onWindowClose` /
/// `_onAppExitRequested` (shell) call `_saveStateAndShutdown()` unqualified;
/// `build`'s post-frame block calls `_checkForUpdates(context)` /
/// `_autoStartWebServer(context)` unqualified — unqualified class→extension
/// resolution is the same pattern proven at 0 warnings by
/// `settings_page.dart`'s `_buildAdvancedTab(context)`.
extension _MainLifecycle on _MyAppState {
  Future<void> _saveStateAndShutdown() async {
    if (_shutdownStarted) return;
    _shutdownStarted = true;
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
        // post-frame callback (around line 682), before or instead of the
        // live capture. See PR #53 for the full ghost-frame analysis.
        if (persistSize) {
          await prefs.setDouble(_k('window_width'), _normalWidth);
          await prefs.setDouble(_k('window_height'), _normalHeight);
        }
        await prefs.setDouble(_k('window_x'), _normalX ?? 0.0);
        await prefs.setDouble(_k('window_y'), _normalY ?? 0.0);
      } else {
        final size = await windowManager.getSize();
        final position = await windowManager.getPosition();
        _normalWidth = size.width;
        _normalHeight = size.height;
        _normalX = position.dx;
        _normalY = position.dy;
        if (persistSize) {
          await prefs.setDouble(_k('window_width'), size.width);
          await prefs.setDouble(_k('window_height'), size.height);
        }
        await prefs.setDouble(_k('window_x'), position.dx);
        await prefs.setDouble(_k('window_y'), position.dy);
      }
      await prefs.setBool(_k('window_maximized'), isMax);
    } catch (e) {
      debugPrint('Failed to save window state: $e');
    }

    // Flush any pending chat save BEFORE tearing anything down. The last turn's
    // post-generation Needs vector + Realism scalars are applied in memory and
    // reach the DB only through _saveChat(); some of those saves are
    // fire-and-forget, so one can still be queued or mid-commit at close time.
    // Awaiting the flush drains the save chain and writes the live state once
    // more, so exit(0)/destroy() below can't kill an in-flight write. This is
    // the fix for "the needs deltas from the last character message didn't
    // stick after closing and reopening the app."
    try {
      await Provider.of<ChatService>(
        context,
        listen: false,
      ).flushPendingSaves();
    } catch (e) {
      debugPrint('AG_DEBUG: Error flushing chat save on window close: $e');
    }

    // Stop the managed KoboldCPP backend BEFORE destroying the window. This
    // prevents an orphaned process when the app closes.
    try {
      final koboldService = Provider.of<KoboldService>(context, listen: false);
      if (koboldService.isRunning) {
        await koboldService.stopKobold();
      }
    } catch (e) {
      debugPrint('AG_DEBUG: Error stopping Kobold on window close: $e');
    }

    // Run pending installer if user deferred the update
    if (UpdateService.isSupported) {
      final updateService = Provider.of<UpdateService>(context, listen: false);
      if (updateService.hasPendingInstaller) {
        await updateService.installOnClose();
      }
    }

    // Stop web server
    try {
      final webServer = Provider.of<WebServerHost>(context, listen: false);
      if (webServer.isRunning) {
        await webServer.stop();
      }
    } catch (e) {
      debugPrint('AG_DEBUG: Error stopping web server on close: $e');
    }

    // On Linux and Windows, windowManager.destroy() can trigger a Flutter engine bug:
    //   "FlutterEngineRemoveView returned kInvalidArguments"
    //   "Segmentation fault (core dumped)" or a native crash popup on Windows 11.
    // Workaround: exit(0) after cleanup to bypass the buggy view teardown.
    if (Platform.isLinux || Platform.isWindows) {
      exit(0);
    } else {
      // macOS: end the process WITHOUT running C++ static destructors.
      // destroy() → [NSApp terminate:] → libc exit() → __cxa_finalize runs
      // the bundled native libraries' global destructors — and onnxruntime's
      // (in-process expression/embedding engines; its worker pool holds ~16
      // parked threads at quit) aborts there via std::terminate. Every
      // red-button close produced an "Abort trap: 6" crash report in
      // ~/Library/Logs/DiagnosticReports even though the quit was clean.
      // Dart's exit(0) would hit the same finalize pass, so end the process
      // with no finalizers instead. Safe: everything above was awaited
      // (prefs written, chat saves flushed, KoboldCpp stopped, web server
      // stopped), and SQLite's committed WAL data is crash-safe by design.
      exitWithoutNativeFinalizers(0);
    }
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    final updateService = Provider.of<UpdateService>(context, listen: false);
    await updateService.initialize();

    // Only check for updates on platforms that support self-update
    if (!UpdateService.isSupported) return;
    if (!updateService.autoCheckEnabled) return;

    final hasUpdate = await updateService.checkForUpdate();
    if (hasUpdate && context.mounted) {
      UpdateDialog.show(context);
    }
  }

  Future<void> _autoStartWebServer(BuildContext context) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    await storage.initialized;
    if (!storage.webServerSettings.webServerEnabled) return;

    final webServer = Provider.of<WebServerHost>(context, listen: false);
    // Crash-loop-safe: a hung or crashing start disables the server instead of
    // re-crashing on every launch and locking the user out (see startSafely).
    await webServer.startSafely(
      storage.webServerSettings.webServerPort,
      isAutoStart: true,
    );
  }
}
