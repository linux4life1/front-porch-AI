// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// First paint of a chat: last [kSessionOpenWindow] rows, then older
/// rows page in on the UI isolate in [kSessionOlderPage] chunks with a
/// yield between pages so the chat screen stays live.
const kSessionOpenWindow = 24;
const kSessionOlderPage = 200;

/// In-memory suffix of a session while older rows are still loading.
///
/// Persist MUST write [basePosition] + index, never the raw index: a
/// 24-row snapshot saved as positions 0–23 would overwrite the start of
/// a long chat. [upsertMessagesPreservingTail] only protects positions
/// *past* the snapshot, not under it.
class SessionHistoryWindow {
  int basePosition = 0;
  int epoch = 0;
  Future<void>? backfill;

  /// Session the in-flight [backfill] belongs to. A second open of that
  /// same session must not restart the archive load.
  String? backfillSessionId;
  bool hasMore = false;

  bool get isBackfilling => backfill != null;

  void reset() {
    epoch++;
    backfill = null;
    backfillSessionId = null;
    basePosition = 0;
    hasMore = false;
  }
}

/// DB `position` for in-memory index [index] of a (possibly windowed) list.
int persistMessagePosition({required int base, required int index}) =>
    base + index;

/// Receipts for the live tip. [length] is `_messages.length`.
///
/// A tail window (last ~24 lines of a long chat) must cite [base]+last, not
/// the on-screen index 0..23.
List<int> persistTipCite({required int base, required int length}) =>
    length <= 0
    ? const []
    : [persistMessagePosition(base: base, index: length - 1)];
