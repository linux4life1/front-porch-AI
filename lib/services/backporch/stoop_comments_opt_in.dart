// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-card Discussion opt-in. The hub/API field is not deployed yet — this
// is the client-side store the detail page, upload draft, and mock client
// read. Default is OFF (omitted / missing => false).
//
// Field name (sketch for a future hub column, same shape as `nsfw`):
//   commentsEnabled: bool  // default false
//
// Sent on upload/update as payload['commentsEnabled']. Parsed on
// StoopCardDetail / StoopCharacter when/if the API echoes it. Live owner
// kill-switch writes [_live] only — comment rows stay in the mock DB.

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Client overlay for per-card `commentsEnabled`.
///
/// - [published] is what the author opted in at upload/update (or what the
///   card JSON said).
/// - [live] is the owner kill-switch. Turning it off hides Discussion
///   without wiping comments.
class StoopCommentsOptIn {
  StoopCommentsOptIn();

  /// Process-wide store so upload → detail works in one app session.
  static final StoopCommentsOptIn instance = StoopCommentsOptIn();

  final Map<String, bool> _published = {};
  final Map<String, bool> _live = {};

  /// Author opt-in for [cardId]. Falls back to [fromCard] (the model field),
  /// then false.
  bool published(String cardId, {bool fromCard = false}) =>
      _published[cardId] ?? fromCard;

  /// Live visibility. Kill-switch override wins; else [published].
  bool live(String cardId, {bool fromCard = false}) =>
      _live[cardId] ?? published(cardId, fromCard: fromCard);

  /// Record the upload/update choice. Also resets the live override to match.
  void setPublished(String cardId, bool value) {
    if (cardId.isEmpty) return;
    _published[cardId] = value;
    _live[cardId] = value;
  }

  /// Owner kill-switch. Does not change [published] and does not touch
  /// comment rows.
  void setLive(String cardId, bool value) {
    if (cardId.isEmpty) return;
    _live[cardId] = value;
  }

  @visibleForTesting
  void reset() {
    _published.clear();
    _live.clear();
  }
}
