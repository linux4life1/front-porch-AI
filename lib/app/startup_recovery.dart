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
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/database/data_migration_service.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart' show BackupListing;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Post-first-frame database recovery for MyApp: the full health check, the
/// corrupt-DB backup restore, the beta-first-launch stable-DB import, and the
/// one-time legacy-JSON → Drift migration. Owns the state its two overlays
/// ([DbCorruptionOverlay], [MigrationOverlay]) render; every change goes
/// through [_rebuild] (the host State's setState), and only while the
/// host's context is still mounted.
class StartupRecovery {
  StartupRecovery(this._rebuild);

  final void Function(VoidCallback fn) _rebuild;

  /// Startup only reaches MyApp after the cheap open-probe passed, so the
  /// database starts out presumed healthy until [checkDbHealth] says not.
  bool _dbHealthy = true;

  bool isMigrating = false;
  bool isDbCorrupt = false;
  List<BackupListing> availableBackups = [];
  String migrationStep = '';
  int migrationCurrent = 0;
  int migrationTotal = 1;

  void continueWithoutRestoring(BuildContext context) {
    if (context.mounted) _rebuild(() => isDbCorrupt = false);
  }

  Future<void> checkDbHealth(BuildContext context) async {
    // The full quick_check runs HERE, after first paint (see main() — only a
    // cheap open-probe runs before the window shows). A corrupt DB now
    // surfaces its restore overlay a moment after launch instead of holding
    // the whole window hostage while the file is validated.
    if (_dbHealthy) {
      try {
        final db = await AppDatabase.instance();
        _dbHealthy = await db.integrityCheck();
      } catch (_) {
        _dbHealthy = false;
      }
    }
    if (_dbHealthy) return;

    // DB is corrupt — load available backups and show overlay. Stat them
    // here, not in the overlay's build (no sync I/O on the frame path).
    final backups = <BackupListing>[
      for (final file in await BackupService.listBackups())
        (file: file, stat: await file.stat()),
    ];
    if (context.mounted) {
      _rebuild(() {
        isDbCorrupt = true;
        availableBackups = backups;
      });
    }
  }

  Future<void> restoreBackup(BuildContext context, File backup) async {
    if (context.mounted) {
      _rebuild(() {
        isDbCorrupt = false;
        isMigrating = true;
        migrationStep = 'Restoring backup...';
        migrationCurrent = 1;
        migrationTotal = 2;
      });
    }

    try {
      await BackupService.restoreBackup(backup.path);

      if (context.mounted) {
        _rebuild(() {
          migrationStep = 'Reopening database...';
          migrationCurrent = 2;
        });
      }

      // Re-open AND rebind: restoreBackup closed the old AppDatabase, but every
      // repository/service captured that instance at startup. Without the same
      // rebind+reload the import flow uses, the app dismisses this overlay and
      // then throws "database was closed" on every action until a restart.
      // No image cleanup here — this snapshot predates any character added
      // since it was taken, and their portraits are not junk.
      final rebound = await _rebindAfterDatabaseSwap(context);

      if (context.mounted) {
        if (rebound) {
          _rebuild(() => isMigrating = false);
        } else {
          // The backup IS safely on disk — only the live rewiring failed.
          // Never dismiss as success: every DB action would fail confusingly.
          _rebuild(() {
            migrationStep =
                'Backup restored. Please close and reopen Front Porch AI '
                'to finish.';
          });
        }
      }

      debugPrint('[DB] Backup restored successfully from: ${backup.path}');
    } catch (e) {
      debugPrint('[DB] Backup restore failed: $e');
      // The old DB may already be closed — dismissing the overlay would leave
      // a half-dead app that looks fine. Keep it up with an honest message.
      if (context.mounted) {
        _rebuild(() {
          migrationStep =
              'Restore failed. Please close and reopen Front Porch AI, '
              'then try another backup.';
        });
      }
    }
  }

  /// Rebinds every DB-holding service to a fresh AppDatabase instance, reloads
  /// them, and re-checks the file's health. Returns false when the rebind could
  /// not run/complete — callers that just closed the old instance (import,
  /// restore) must treat false as "the app needs a restart", not as success.
  ///
  /// [cleanOrphanedImages] must stay false for restores: an older snapshot
  /// legitimately lacks characters created since it was taken, and the cleanup
  /// would delete their portraits for good. See [reopenAndRebindDatabase].
  Future<bool> _rebindAfterDatabaseSwap(
    BuildContext context, {
    bool cleanOrphanedImages = false,
  }) async {
    if (!context.mounted) return false;

    final newDb = await reopenAndRebindDatabase(
      context,
      cleanOrphanedImages: cleanOrphanedImages,
    );
    if (newDb == null) return false;

    try {
      _dbHealthy = await newDb.integrityCheck();
    } catch (e) {
      debugPrint('[DB] Integrity check after database swap failed: $e');
      return false;
    }
    return true;
  }

  /// Show the stable DB import dialog on first beta launch.
  ///
  /// Offered when a stable DB exists and this beta install's library is still
  /// EMPTY. It deliberately does NOT use `StableDbImportDialog.shouldShow()`,
  /// which asks whether the beta `.db` file is absent: `main()` opens — and so
  /// creates — the beta database before the first frame (`openDatabaseGuarded`
  /// even runs a `SELECT 1` probe to force it open), so by the time this
  /// post-first-frame callback runs the file ALWAYS exists and the offer could
  /// never be made. Emptiness is the honest question, and it additionally
  /// refuses to overwrite a beta library the user has already built up.
  ///
  /// If the user chooses Import, the stable DB replaces the freshly-created
  /// beta DB and all repositories are reloaded with the new data.
  Future<void> showStableDbImportIfNeeded(BuildContext context) async {
    if (!isPreRelease) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('beta_stable_import_shown') ?? false) return;

    final stablePath = await StableDbImportDialog.stableDbPath();
    if (stablePath == null) return;

    // The dialog's path helpers assume the default documents-dir layout, so
    // the source it hands us is only ever the default stable location. Refuse
    // to act if startup actually opened the beta DB somewhere else (a moved
    // beta storage root): copying onto the default path would leave a stray
    // file the rebind never opens, and the user would be told nothing.
    final betaDbPath = p.join(
      (await getApplicationDocumentsDirectory()).path,
      'FrontPorchAI-Beta',
      'KoboldManager',
      'front_porch_beta.db',
    );
    final db = AppDatabase.current;
    if (db == null || AppDatabase.dbFilePath != betaDbPath) return;
    if (!await db.hasNoUserContent()) return;
    if (!context.mounted) return;

    // Show the dialog — it's modal and blocks further initialization
    await StableDbImportDialog.show(context);

    // Import unless the user chose Skip (the dialog writes both prefs).
    if (prefs.getBool('beta_stable_import_skipped') ?? false) return;

    try {
      // Same order the backup restore uses: close the live handle first, then
      // replace the file, then clear the stale WAL/SHM sidecars that belong to
      // the database we just replaced.
      await AppDatabase.closeAndReset();
      await File(stablePath).copy(betaDbPath);
      for (final sidecar in ['$betaDbPath-wal', '$betaDbPath-shm']) {
        try {
          await File(sidecar).delete();
        } catch (_) {}
      }
      debugPrint('[DB] Pre-release build — imported stable DB to beta DB');
    } catch (e) {
      // The copy failed; the beta DB is still whatever was there. Fall through
      // to the rebind so the app reopens a database instead of running on the
      // closed handle.
      debugPrint('[DB] Stable DB import failed (non-fatal): $e');
    }

    // Reinitialize the database and reload all repositories. The imported DB
    // is the new source of truth, so unreferenced portraits really are junk.
    await _rebindAfterDatabaseSwap(context, cleanOrphanedImages: true);
  }

  Future<void> runMigrationIfNeeded(BuildContext context) async {
    final needsMigration = Provider.of<bool>(context, listen: false);
    if (!needsMigration) return;

    _rebuild(() => isMigrating = true);

    final db = liveDatabase(context);
    final migration = DataMigrationService(db);
    try {
      await migration.migrate(
        onProgress: (step, current, total) {
          if (context.mounted) {
            _rebuild(() {
              migrationStep = step;
              migrationCurrent = current;
              migrationTotal = total;
            });
          }
          debugPrint('DB Migration [$current/$total]: $step');
        },
      );
    } catch (e) {
      // A migration throw must NOT leave isMigrating true forever (a
      // full-screen overlay = unusable app) and must NOT re-run every launch
      // (each retry re-imports characters, worsening the very duplicate-path
      // condition that can cause the throw). Log, drop the overlay, and let
      // the app open on whatever migrated so far — the legacy JSON is left in
      // place, so a fixed future build can retry.
      debugPrint('[DB Migration] Failed — continuing without it: $e');
    }

    if (context.mounted) {
      _rebuild(() => isMigrating = false);
    }
  }
}
