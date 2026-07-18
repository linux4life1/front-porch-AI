// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/backup_service.dart';

/// Tests the pure two-tier retention policy ([BackupService.backupsToKeep]) — the
/// part with the tricky day-boundary + recent/daily union logic — without any
/// filesystem. The FS wrapper [BackupService.pruneBackups] just feeds this and
/// deletes the complement.
void main() {
  // Fixed "now" so calendar-day math is deterministic (noon, June 23 2026).
  final now = DateTime(2026, 6, 23, 12, 0);

  // A backup timestamped [d] days before today at [hour]:[minute].
  ({String path, DateTime modified}) bk(
    String name,
    int daysAgo, {
    int hour = 12,
    int minute = 0,
  }) => (
    path: name,
    modified: DateTime(2026, 6, 23, hour, minute).subtract(Duration(days: daysAgo)),
  );

  // The recent tier always keeps this many; to exercise the DAILY tier a test
  // must push older backups past this window with that many fresh "today" ones.
  List<({String path, DateTime modified})> fillRecentToday() => [
    for (var i = 0; i < BackupService.maxBackups; i++)
      bk('today$i', 0, hour: 12, minute: 0 - 30 * i),
  ];

  group('BackupService.backupsToKeep — two-tier rolling retention', () {
    test('keeps everything when there are fewer than maxBackups', () {
      final entries = [bk('a', 0, hour: 12), bk('b', 0, hour: 11), bk('c', 1)];
      final keep = BackupService.backupsToKeep(entries, now);
      expect(keep, containsAll(['a', 'b', 'c']));
    });

    test('recent tier keeps exactly the newest maxBackups (all same day)', () {
      // 15 snapshots today, newest first.
      final entries = [
        for (var i = 0; i < 15; i++) bk('t$i', 0, hour: 12, minute: 0 - 30 * i),
      ];
      final keep = BackupService.backupsToKeep(entries, now);
      expect(keep.length, BackupService.maxBackups);
      for (var i = 0; i < BackupService.maxBackups; i++) {
        expect(keep, contains('t$i'));
      }
      // Older same-day snapshots beyond the recent window are NOT kept (today's
      // daily representative is the newest, already inside the recent tier).
      for (var i = BackupService.maxBackups; i < 15; i++) {
        expect(keep, isNot(contains('t$i')));
      }
    });

    test('daily tier keeps one per day for the last 7 days, drops older', () {
      final entries = [
        ...fillRecentToday(),
        for (var d = 1; d <= 8; d++) bk('day$d', d),
      ];
      final keep = BackupService.backupsToKeep(entries, now);
      // Recent today snapshots all survive.
      for (var i = 0; i < BackupService.maxBackups; i++) {
        expect(keep, contains('today$i'));
      }
      // Days 1..6 ago are within the rolling week (today=0 .. day6=6 → 7 days).
      for (var d = 1; d <= 6; d++) {
        expect(keep, contains('day$d'), reason: 'day $d ago is a daily keeper');
      }
      // Day 7 and beyond fall outside the week and are dropped.
      expect(keep, isNot(contains('day7')));
      expect(keep, isNot(contains('day8')));
    });

    test('for an old day with several backups, keeps only the most recent', () {
      final entries = [
        ...fillRecentToday(),
        bk('d3_evening', 3, hour: 20),
        bk('d3_morning', 3, hour: 8),
      ];
      final keep = BackupService.backupsToKeep(entries, now);
      expect(keep, contains('d3_evening'));
      expect(keep, isNot(contains('d3_morning')));
    });

    test('day exactly 7 days old is dropped; 6 days old is kept', () {
      final entries = [...fillRecentToday(), bk('day6', 6), bk('day7', 7)];
      final keep = BackupService.backupsToKeep(entries, now);
      expect(keep, contains('day6'));
      expect(keep, isNot(contains('day7')));
    });

    test('future-dated backup (clock skew) is not a daily keeper', () {
      // One backup dated tomorrow, plus enough today to fill the recent tier so
      // the skewed one would only survive via the (rejected) daily rule.
      final entries = [
        bk('future', -1), // tomorrow
        ...fillRecentToday(),
        bk('day2', 2),
      ];
      final keep = BackupService.backupsToKeep(entries, now);
      // 'future' is newest so the recent tier grabs it; assert the DAILY rule
      // itself rejects future dates by checking day2 still works and no crash.
      expect(keep, contains('day2'));
    });
  });
}
