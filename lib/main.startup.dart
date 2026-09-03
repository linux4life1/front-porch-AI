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

/// Pre-`runApp` startup phases, called from `main()` in this exact order —
/// see the phase-order comment there. Split out verbatim from the original
/// inline `main()` body (god-file elimination, Tranche C); no behavior
/// change, just named boundaries around what used to be positional.

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
Future<bool> _windowBoundsVisible(Rect bounds) async {
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

/// Sets SIGPIPE to SIG_IGN via libc so a write to a closed socket/pipe fails
/// with a normal, catchable `SocketException` instead of silently killing the
/// whole process (SIGPIPE's default disposition). No-op on Windows (no SIGPIPE)
/// and best-effort everywhere else — a lookup failure just leaves the default.
void _ignoreSigpipe() {
  if (Platform.isWindows) return;
  try {
    // int signal(int signum, sighandler_t handler); SIG_IGN == (void*)1,
    // SIGPIPE == 13 on both macOS (Darwin) and Linux.
    final signal = DynamicLibrary.process().lookupFunction<
        Pointer<Void> Function(Int32, Pointer<Void>),
        Pointer<Void> Function(int, Pointer<Void>)>('signal');
    signal(13, Pointer<Void>.fromAddress(1));
  } catch (e) {
    debugPrint('Could not set SIG_IGN for SIGPIPE: $e');
  }
}

void _installSignalHandlers() {
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
  _ignoreSigpipe();
}

Future<void> _healPrefsAndConsolidateFiles() async {
  // Self-heal a corrupt shared_preferences.json BEFORE anything reads it.
  // On Windows/Linux a crash or power loss mid-write can leave the settings
  // file full of NUL bytes; the first getInstance() then throws a
  // FormatException inside the database-open guard below and the app died on
  // a misleading "couldn't open its database" screen. Moving the broken file
  // aside here lets the app boot with default settings instead; the
  // post-first-frame notice (see the update-check block) tells the user.
  await PrefsRecovery.healIfCorrupt();
  _mark('PrefsRecovery.healIfCorrupt');

  // Consolidate files BEFORE loading database or any configs.
  try {
    await FileConsolidationService.consolidate();
  } catch (e) {
    debugPrint('Fatal error during file consolidation: $e');
  }
  _mark('FileConsolidationService.consolidate');
}

Future<({AppDatabase db, bool needsMigration})?> _openDatabaseGuarded() async {
  // Initialize database. This is the last thing that can die BEFORE any window
  // exists — a disk-full/permissions failure, or a second copy of the app
  // holding the file (the documented dual-run case), would otherwise exit the
  // process silently ("app won't launch, no message"). Guard it and, on a
  // hard failure, show a minimal error window instead of nothing.
  // (NativeDatabase.createInBackground opens lazily, so a bad/locked file
  // surfaces at the first query — integrityCheck — not at instance().)
  final AppDatabase db;
  final bool needsMigration;
  final bool dbHealthy;
  try {
    db = await AppDatabase.instance();
    _mark('AppDatabase.instance (incl. schema migration)');
    needsMigration = !await DataMigrationService.isMigrated();
    _mark('DataMigrationService.isMigrated');
    // Cheap first-query probe: forces the lazily-opened file to actually
    // open, so a locked/unreadable DB still fails fast into
    // _DbInitErrorApp. The EXPENSIVE health check (PRAGMA quick_check reads
    // and validates the whole file — seconds on a big chat DB) used to run
    // right here, before the window even existed, and was the single
    // largest fixed startup cost; it now runs post-first-frame in
    // _checkDbHealth, which owns the corrupt-DB restore overlay anyway.
    await db.customSelect('SELECT 1').get();
    _mark('first DB query (SELECT 1)');
    dbHealthy = true;
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
    return null;
  }
  _dbHealthy = dbHealthy;

  // Soft-delete purge + legacy JSON cleanup are idempotent maintenance —
  // they moved to the post-first-frame block in _MyAppState.initState so
  // launch doesn't wait on them (they used to run before the window showed).

  // TODO: Enable after verifying DatabaseCleanup behaves correctly in production
  // try {
  //   final report = await DatabaseCleanup.checkOrphans(db);
  //   if (report.totalOrphans > 0 || report.totalBrokenRefs > 0) {
  //     debugPrint('[DB] Found ${report.totalOrphans + report.totalBrokenRefs}'
  //         ' orphaned records — running cleanup');
  //     await DatabaseCleanup.cleanOrphans(db);
  //   }
  // } catch (e) {
  //   debugPrint('[DB] Orphan cleanup failed: $e (non-fatal)');
  // }
  return (db: db, needsMigration: needsMigration);
}

Future<void> _showMainWindow() async {
  final forcedSize = WindowSizeEnv.sizeFromEnvironment();
  final windowOptions = WindowOptions(
    size: forcedSize ?? const Size(1280, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: 'Front Porch AI',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    if (forcedSize != null) {
      // Launch hook: skip saved-bounds restore so --dart-define sizes
      // actually show. Missing axis is 1280 or 720.
      await windowManager.setSize(forcedSize);
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final windowWidth = prefs.getDouble(_k('window_width'));
        final windowHeight = prefs.getDouble(_k('window_height'));
        final windowX = prefs.getDouble(_k('window_x'));
        final windowY = prefs.getDouble(_k('window_y'));
        final windowMaximized = prefs.getBool(_k('window_maximized')) ?? false;

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
        // before applying it (issue #78 — see _windowBoundsVisible). If it
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
          if (await _windowBoundsVisible(candidate)) {
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

    await windowManager.show();
    await windowManager.focus();
    await windowManager.setPreventClose(true);
  });
  _mark('window shown (waitUntilReadyToShow)');
}
