// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';

/// Dispose [chat], let its fire-and-forget DB writes land, then close [db].
///
/// ChatService issues un-awaited writes (patchSession → bumpSyncVersion,
/// persist retries, ring / embedding invalidation). `AppDatabase.forTesting`
/// runs drift in a background isolate; `db.close()` tears the channel down
/// and every request still in flight completes with "Channel was closed
/// before receiving a response". Nobody awaits those futures, so the error
/// is reported against whichever test is running — a teardown race that
/// only shows under `--concurrency=4` load.
///
/// Drift answers requests on one connection in order, so a `SELECT 1`
/// round trip returns only after every earlier request finished. Chained
/// writes issue their next step after the previous one resolves, hence a
/// few rounds of (yield to the event loop, then barrier).
Future<void> disposeChatThenCloseDb(
  ChatService? chat,
  AppDatabase? db, {
  int rounds = 5,
}) async {
  chat?.dispose();
  if (db == null) return;
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
    try {
      await db.customSelect('SELECT 1').get();
    } catch (_) {
      break;
    }
  }
  await db.close();
}
