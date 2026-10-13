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

import 'package:flutter/widgets.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';
import 'package:front_porch_ai/utils/native_exit.dart';
import 'package:provider/provider.dart';

import 'window_bounds_tracker.dart';

/// The one quit path for the red button, Cmd+Q / Dock-quit and the window
/// close request. Saves window state, drains chat saves, stops child
/// processes and ends the process without the engine's buggy view teardown.
class AppShutdown {
  /// True once a shutdown path has started — makes close requests
  /// idempotent (red button + Cmd+Q can both fire in one quit).
  bool get started => _started;
  bool _started = false;

  /// [context] must sit below the app's provider graph. Never returns on a
  /// desktop platform: every branch ends the process.
  Future<void> run(BuildContext context, WindowBoundsTracker bounds) async {
    if (_started) return;
    _started = true;
    await bounds.save();

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
      if (koboldService.isRunning || koboldService.isStarting) {
        await koboldService.stopKobold();
      }
    } catch (e) {
      debugPrint('AG_DEBUG: Error stopping Kobold on window close: $e');
    }

    try {
      final oc = Provider.of<OpenCodeManager>(context, listen: false);
      if (oc.isRunning) await oc.stop();
    } catch (e) {
      debugPrint('AG_DEBUG: Error stopping OpenCode on window close: $e');
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
}
