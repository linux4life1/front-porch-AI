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

import 'package:front_porch_ai/services/backup/restore_applier.dart';

/// Which automatic snapshots BackupService.pruneBackups keeps. Pure: no
/// filesystem, so the policy is tested on its own.
class BackupRetention {
  BackupRetention._();

  /// Recent rolling tier: the newest this-many snapshots are always kept.
  static const int maxBackups = 10;

  /// Daily tier: additionally keep ONE backup per calendar day for the last
  /// this-many days (a rolling week of dailies on top of the recent snapshots).
  static const int dailyRetentionDays = 7;

  /// How many restore safety copies are kept, newest first.
  static const int maxSafetyCopies = 3;

  /// The backups to delete, given them NEWEST-FIRST. Safety copies (the
  /// undo for a restore) are kept apart from the automatic snapshots: they
  /// never count toward [toKeep], and the newest [maxSafetyCopies] stay.
  static Set<String> toDrop(
    List<({String path, DateTime modified})> backupsNewestFirst,
    DateTime now,
  ) {
    final safety = [
      for (final b in backupsNewestFirst)
        if (RestoreApplier.isSafetyCopy(b.path)) b.path,
    ];
    final snapshots = [
      for (final b in backupsNewestFirst)
        if (!RestoreApplier.isSafetyCopy(b.path)) b,
    ];
    final keep = snapshots.length <= maxBackups
        ? {for (final b in snapshots) b.path}
        : toKeep(snapshots, now);
    return {
      for (final b in snapshots)
        if (!keep.contains(b.path)) b.path,
      ...safety.skip(maxSafetyCopies),
    };
  }

  /// Given backups as (path, modified) ordered NEWEST-FIRST and the current
  /// time [now], returns the paths to KEEP under the recent + daily rules.
  /// Order matters: the first entry seen for a day is treated as that day's
  /// most-recent snapshot.
  static Set<String> toKeep(
    List<({String path, DateTime modified})> backupsNewestFirst,
    DateTime now,
  ) {
    final keep = <String>{};

    // Recent tier — the newest maxBackups snapshots.
    for (var i = 0; i < backupsNewestFirst.length && i < maxBackups; i++) {
      keep.add(backupsNewestFirst[i].path);
    }

    // Daily tier — one per calendar day for the last dailyRetentionDays days.
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final seenDays = <String>{};
    for (final b in backupsNewestFirst) {
      final mod = b.modified;
      final day = DateTime(mod.year, mod.month, mod.day);
      final ageDays = todayMidnight.difference(day).inDays;
      if (ageDays < 0 || ageDays >= dailyRetentionDays) {
        continue; // future-dated (clock skew) or older than the rolling week
      }
      if (seenDays.add('${day.year}-${day.month}-${day.day}')) {
        keep.add(b.path); // most-recent backup of this day
      }
    }

    return keep;
  }
}
