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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/database/data_migration_service.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/atomic_prefs_store.dart';
import 'package:front_porch_ai/services/file_consolidation_service.dart';
import 'package:front_porch_ai/services/prefs_recovery.dart';
import 'package:front_porch_ai/ui/widgets/db_init_error_app.dart';
import 'package:front_porch_ai/utils/native_exit.dart';
import 'package:front_porch_ai/utils/utils.dart' show StartupTrace;
import 'package:window_manager/window_manager.dart';

// Pre-`runApp` startup phases. `main()` calls them in a fixed order and owns
// that sequence — see the phase-order comment there.

/// Sets SIGPIPE to SIG_IGN via libc so a write to a closed socket/pipe fails
/// with a normal, catchable `SocketException` instead of silently killing the
/// whole process (SIGPIPE's default disposition). No-op on Windows (no SIGPIPE)
/// and best-effort everywhere else — a lookup failure just leaves the default.
void ignoreSigpipe() {
  if (Platform.isWindows) return;
  try {
    // int signal(int signum, sighandler_t handler); SIG_IGN == (void*)1,
    // SIGPIPE == 13 on both macOS (Darwin) and Linux.
    final signal = DynamicLibrary.process()
        .lookupFunction<
          Pointer<Void> Function(Int32, Pointer<Void>),
          Pointer<Void> Function(int, Pointer<Void>)
        >('signal');
    signal(13, Pointer<Void>.fromAddress(1));
  } catch (e) {
    debugPrint('Could not set SIG_IGN for SIGPIPE: $e');
  }
}

void installSignalHandlers() {
  // Intercept SIGINT (Ctrl+C) and SIGTERM on Linux/macOS to prevent
  // the Flutter engine from doing an unclean teardown that triggers:
  //   "FlutterEngineRemoveView returned kInvalidArguments"
  //   "Segmentation fault (core dumped)"
  // On macOS the exit must also skip C++ finalizers (see
  // exitWithoutNativeFinalizers) or the abort-in-destructor crash fires here
  // too and the signal-quit gets logged as "Abort trap: 6".
  if (!Platform.isWindows) {
    ProcessSignal.sigint.watch().listen((_) {
      debugPrint('Caught SIGINT — exiting immediately.');
      Platform.isMacOS ? exitWithoutNativeFinalizers(0) : exit(0);
    });
    ProcessSignal.sigterm.watch().listen((_) {
      debugPrint('Caught SIGTERM — exiting immediately.');
      Platform.isMacOS ? exitWithoutNativeFinalizers(0) : exit(0);
    });
  }
  // Ignore SIGPIPE at the C level. A write to a socket/pipe whose peer has
  // already closed (a dropped web-server connection, the mDNSResponder/Tailscale
  // sockets used when serving over the LAN or a tailnet, a subprocess stdio pipe)
  // raises SIGPIPE, whose default disposition SILENTLY terminates the whole
  // process with no crash report — the "app just vanishes from the dock when I
  // toggle the web server on" bug in the signed/notarized build. The standalone
  // Dart VM sets SIG_IGN for us (so `flutter run` never showed it), but the
  // Flutter embedder leaves the default in place. dart:io deliberately REFUSES
  // to watch SIGPIPE, so we set the disposition directly via libc.
  ignoreSigpipe();
}

Future<void> healPrefsAndConsolidateFiles() async {
  // Self-heal a corrupt shared_preferences.json BEFORE anything reads it.
  // On Windows/Linux a crash or power loss mid-write can leave the settings
  // file full of NUL bytes; the first getInstance() then throws a
  // FormatException inside the database-open guard below and the app died on
  // a misleading "couldn't open its database" screen. Moving the broken file
  // aside here lets the app boot with default settings instead; the
  // post-first-frame notice (see the update-check block) tells the user.
  // The atomic store goes in first so no prefs read or write ever goes
  // through the stock truncate-then-write store.
  AtomicPrefsStore.install();
  await PrefsRecovery.moveLegacyWindowsFolder(nightly: isPreRelease);
  await PrefsRecovery.healIfCorrupt();
  StartupTrace.mark('PrefsRecovery.healIfCorrupt');

  // Consolidate files BEFORE loading database or any configs.
  try {
    await FileConsolidationService.consolidate();
  } catch (e) {
    debugPrint('Fatal error during file consolidation: $e');
  }
  StartupTrace.mark('FileConsolidationService.consolidate');
}

Future<({AppDatabase db, bool needsMigration})?> openDatabaseGuarded() async {
  // Initialize database. This is the last thing that can die BEFORE any window
  // exists — a disk-full/permissions failure, or a second copy of the app
  // holding the file (the documented dual-run case), would otherwise exit the
  // process silently ("app won't launch, no message"). Guard it and, on a
  // hard failure, show a minimal error window instead of nothing.
  // (NativeDatabase.createInBackground opens lazily, so a bad/locked file
  // surfaces at the first query — integrityCheck — not at instance().)
  final AppDatabase db;
  final bool needsMigration;
  try {
    db = await AppDatabase.instance();
    StartupTrace.mark('AppDatabase.instance (incl. schema migration)');
    needsMigration = !await DataMigrationService.isMigrated();
    StartupTrace.mark('DataMigrationService.isMigrated');
    // Cheap first-query probe: forces the lazily-opened file to actually
    // open, so a locked/unreadable DB still fails fast into
    // DbInitErrorApp. The EXPENSIVE health check (PRAGMA quick_check reads
    // and validates the whole file — seconds on a big chat DB) used to run
    // right here, before the window even existed, and was the single
    // largest fixed startup cost; it now runs post-first-frame in
    // StartupRecovery.checkDbHealth, which owns the corrupt-DB restore overlay anyway.
    await db.customSelect('SELECT 1').get();
    StartupTrace.mark('first DB query (SELECT 1)');
  } catch (e, st) {
    debugPrint('[DB] FATAL: could not open the database: $e\n$st');
    // A FormatException here is the settings file failing to parse (the
    // first prefs read lives inside this guard), not the database — and it
    // means PrefsRecovery couldn't heal it. Show the accurate variant.
    runApp(
      DbInitErrorApp(
        details: e.toString(),
        settingsFileCorrupt: e is FormatException,
      ),
    );
    if (Platform.isWindows || Platform.isMacOS) {
      // The Windows and macOS runners keep the window hidden until Dart
      // shows it (see showMainWindow); the error window has no bounds to
      // restore.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await windowManager.show();
        await windowManager.focus();
      });
    }
    return null;
  }
  // Soft-delete purge + legacy JSON cleanup are idempotent maintenance —
  // they moved to the post-first-frame block in MyApp's initState so
  // launch doesn't wait on them (they used to run before the window showed).
  return (db: db, needsMigration: needsMigration);
}
