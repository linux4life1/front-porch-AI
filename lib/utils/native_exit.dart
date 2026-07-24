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

import 'dart:ffi';

/// Terminate the process WITHOUT running C++ static destructors (libc _exit).
///
/// On macOS every normal quit route ends in libc exit(), whose
/// __cxa_finalize pass runs the bundled native libraries' global
/// destructors — and onnxruntime's teardown (the in-process expression/
/// embedding engines keep ~16 parked worker threads alive) aborts there via
/// std::terminate. Result: EVERY clean quit was logged as "Abort trap: 6"
/// in ~/Library/Logs/DiagnosticReports and macOS flagged the app as
/// crashed. libc _exit ends the process without finalizers.
///
/// Callers must finish all real cleanup first (prefs writes, chat-save
/// flush, KoboldCpp stop, web-server stop); SQLite's committed WAL data is
/// crash-safe by design, so skipping the destructors loses nothing. Used by
/// every macOS exit path: window close, Cmd+Q/Dock quit, SIGINT/SIGTERM,
/// and the updater's install-and-relaunch.
Never exitWithoutNativeFinalizers(int code) {
  final libcExit = DynamicLibrary.process()
      .lookupFunction<Void Function(Int32), void Function(int)>('_exit');
  libcExit(code);
  throw StateError('unreachable — _exit terminated the process');
}
