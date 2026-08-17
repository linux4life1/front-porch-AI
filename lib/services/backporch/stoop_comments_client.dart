// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Injected comments client. This pass is MOCK-only — the in-memory fake is
// what the detail panel and tests use. Do not point this at prod.

import 'package:front_porch_ai/services/backporch/backporch_api.dart';
import 'package:front_porch_ai/services/backporch/backporch_user.dart';
import 'package:front_porch_ai/services/backporch/stoop_comment.dart';
import 'package:front_porch_ai/services/backporch/stoop_comment_gate.dart';
import 'package:front_porch_ai/services/backporch/stoop_comments_opt_in.dart';

/// List / create / delete / report comments on a character card.
abstract class StoopCommentsClient {
  Future<List<StoopComment>> list(String cardId);

  Future<StoopComment> create({
    required String cardId,
    required String body,
    required BackporchUser author,
  });

  Future<StoopComment> delete({
    required String cardId,
    required String commentId,
    required BackporchUser actor,
    String? cardOwnerId,
    bool canModerate = false,
  });

  Future<void> report({
    required String cardId,
    required String commentId,
    required BackporchUser actor,
    required String category,
    required String reason,
  });

  Future<StoopComment> createReply({
    required String cardId,
    required String commentId,
    required String body,
    required BackporchUser author,
    String? cardOwnerId,
  });

  Future<StoopComment> deleteReply({
    required String cardId,
    required String commentId,
    required BackporchUser actor,
    String? cardOwnerId,
    bool canModerate = false,
  });

  Future<void> reportReply({
    required String cardId,
    required String commentId,
    required BackporchUser actor,
    required String category,
    required String reason,
  });
}

/// In-memory fake. Fail-closed on unverified write/report and on reporting
/// your own comment (403), even if the UI hid the control.
class MemoryStoopCommentsClient implements StoopCommentsClient {
  MemoryStoopCommentsClient({
    List<StoopComment>? seed,
    this.duplicateWindow = const Duration(seconds: 30),
    DateTime Function()? now,
    StoopCommentsOptIn? optIn,
    Map<String, bool>? commentsEnabled,
  }) : _now = now ?? DateTime.now,
       _optIn = optIn,
       _enforceCardMap = commentsEnabled != null {
    if (seed != null) _items.addAll(seed);
    if (commentsEnabled != null) {
      _cardCommentsEnabled.addAll(commentsEnabled);
    }
  }

  final Duration duplicateWindow;
  final DateTime Function() _now;
  final StoopCommentsOptIn? _optIn;
  final bool _enforceCardMap;
  final Map<String, bool> _cardCommentsEnabled = {};
  final List<StoopComment> _items = [];
  int _seq = 0;

  /// If set, the next [create] throws this (409 / 429 / 403 tests).
  Object? nextCreateError;

  /// If set, the next [createReply] throws this (409 / 429 / 403 tests).
  Object? nextReplyError;

  /// Last top-level create args as they would go on the wire. Never includes
  /// asOwner / role / isCreator / parentId — those are not part of create.
  Map<String, dynamic>? lastCreatePayload;

  /// Last [createReply] args. Separate call; never a create() with parentId.
  Map<String, dynamic>? lastCreateReplyPayload;

  List<StoopComment> get items => List.unmodifiable(_items);

  int _indexOf(String cardId, String commentId) =>
      _items.indexWhere((c) => c.id == commentId && c.cardId == cardId);

  void _requireVerified(BackporchUser user) {
    if (!stoopCanComment(user)) {
      throw const BackporchApiException(403, 'email_not_verified');
    }
  }

  /// Record the card JSON `commentsEnabled` field for [cardId].
  void setCardCommentsEnabled(String cardId, bool value) {
    _cardCommentsEnabled[cardId] = value;
  }

  /// Live discussion for [cardId]. Kill-switch / omitted opt-in is fail-closed
  /// when a store or per-card map is wired. Bare UI-test fakes (neither
  /// passed) stay on — those tests mount [StoopCardComments] only after the
  /// host already opted in.
  bool discussionLive(String cardId) {
    final fromCard = _cardCommentsEnabled[cardId] ?? false;
    if (_optIn != null) {
      return _optIn.live(cardId, fromCard: fromCard);
    }
    if (_enforceCardMap) return fromCard;
    return true;
  }

  void _requireCommentsEnabled(String cardId) {
    if (!discussionLive(cardId)) {
      throw const BackporchApiException(403, 'comments_disabled');
    }
  }

  void _validateBody(String trimmed) {
    if (trimmed.isEmpty) {
      throw const BackporchApiException(400, 'blank_comment');
    }
    if (trimmed.length > kStoopCommentMaxLength) {
      throw const BackporchApiException(400, 'too_long');
    }
    if (stoopCommentBodyHasLink(trimmed)) {
      throw const BackporchApiException(400, 'no_links');
    }
  }

  @override
  Future<List<StoopComment>> list(String cardId) async {
    final out = _items.where((c) => c.cardId == cardId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  @override
  Future<StoopComment> create({
    required String cardId,
    required String body,
    required BackporchUser author,
  }) async {
    lastCreatePayload = {
      'cardId': cardId,
      'body': body,
      'authorId': author.id,
      'displayName': author.displayName,
    };
    _requireVerified(author);
    _requireCommentsEnabled(cardId);
    final trimmed = body.trim();
    _validateBody(trimmed);
    if (nextCreateError != null) {
      throw nextCreateError!;
    }
    final now = _now();
    final dup = _items.any(
      (c) =>
          !c.deleted &&
          c.cardId == cardId &&
          c.authorId == author.id &&
          c.body == trimmed &&
          now.difference(c.createdAt).abs() <= duplicateWindow,
    );
    if (dup) {
      throw const BackporchApiException(409, 'duplicate_comment');
    }
    _seq += 1;
    final comment = StoopComment(
      id: 'c$_seq',
      cardId: cardId,
      authorId: author.id,
      displayName: author.displayName,
      authorAvatarAssetId: author.avatarAssetId,
      createdAt: now,
      body: trimmed,
    );
    _items.add(comment);
    return comment;
  }

  @override
  Future<StoopComment> delete({
    required String cardId,
    required String commentId,
    required BackporchUser actor,
    String? cardOwnerId,
    bool canModerate = false,
  }) async {
    final i = _indexOf(cardId, commentId);
    if (i < 0) {
      throw const BackporchApiException(404, 'not_found');
    }
    final existing = _items[i];
    if (!stoopCanDeleteComment(
      comment: existing,
      user: actor,
      cardOwnerId: cardOwnerId,
      canModerate: canModerate,
    )) {
      throw const BackporchApiException(403, 'forbidden');
    }
    final tombstone = existing.copyWith(deleted: true, body: '');
    _items[i] = tombstone;
    return tombstone;
  }

  @override
  Future<void> report({
    required String cardId,
    required String commentId,
    required BackporchUser actor,
    required String category,
    required String reason,
  }) async {
    _requireVerified(actor);
    final i = _indexOf(cardId, commentId);
    if (i < 0) {
      throw const BackporchApiException(404, 'not_found');
    }
    final existing = _items[i];
    if (existing.authorId == actor.id) {
      throw const BackporchApiException(403, 'cannot_report_own');
    }
    if (reason.trim().isEmpty) {
      throw const BackporchApiException(400, 'reason_required');
    }
    // Accepted — mock does not persist reports.
  }

  @override
  Future<StoopComment> createReply({
    required String cardId,
    required String commentId,
    required String body,
    required BackporchUser author,
    String? cardOwnerId,
  }) async {
    lastCreateReplyPayload = {
      'cardId': cardId,
      'commentId': commentId,
      'body': body,
      'authorId': author.id,
      'displayName': author.displayName,
    };
    _requireVerified(author);
    _requireCommentsEnabled(cardId);
    if (cardOwnerId == null || author.id != cardOwnerId) {
      throw const BackporchApiException(403, 'not_card_owner');
    }
    final i = _indexOf(cardId, commentId);
    if (i < 0) {
      throw const BackporchApiException(404, 'not_found');
    }
    final existing = _items[i];
    // Hidden UI is not the gate — a deleted (or hidden) parent must 403
    // here so a live reply cannot be glued onto a tombstone.
    if (existing.deleted) {
      throw const BackporchApiException(403, 'comment_deleted');
    }
    if (existing.authorId == author.id) {
      throw const BackporchApiException(403, 'forbidden');
    }
    if (existing.reply != null && !existing.reply!.deleted) {
      throw const BackporchApiException(409, 'reply_exists');
    }
    final trimmed = body.trim();
    _validateBody(trimmed);
    if (nextReplyError != null) {
      throw nextReplyError!;
    }
    final now = _now();
    final dup = _items.any((c) {
      final r = c.reply;
      if (r == null || r.deleted) return false;
      if (c.cardId != cardId) return false;
      if (r.authorId != author.id || r.body != trimmed) return false;
      return now.difference(r.createdAt).abs() <= duplicateWindow;
    });
    if (dup) {
      throw const BackporchApiException(409, 'duplicate_comment');
    }
    final reply = StoopCommentReply(
      authorId: author.id,
      displayName: author.displayName,
      authorAvatarAssetId: author.avatarAssetId,
      createdAt: now,
      body: trimmed,
    );
    final updated = existing.copyWith(reply: reply);
    _items[i] = updated;
    return updated;
  }

  @override
  Future<StoopComment> deleteReply({
    required String cardId,
    required String commentId,
    required BackporchUser actor,
    String? cardOwnerId,
    bool canModerate = false,
  }) async {
    final i = _indexOf(cardId, commentId);
    if (i < 0) {
      throw const BackporchApiException(404, 'not_found');
    }
    final existing = _items[i];
    final reply = existing.reply;
    if (reply == null) {
      throw const BackporchApiException(404, 'not_found');
    }
    if (!stoopCanDeleteReply(
      reply: reply,
      user: actor,
      cardOwnerId: cardOwnerId,
      canModerate: canModerate,
    )) {
      throw const BackporchApiException(403, 'forbidden');
    }
    final tombstone = existing.copyWith(
      reply: reply.copyWith(deleted: true, body: ''),
    );
    _items[i] = tombstone;
    return tombstone;
  }

  @override
  Future<void> reportReply({
    required String cardId,
    required String commentId,
    required BackporchUser actor,
    required String category,
    required String reason,
  }) async {
    _requireVerified(actor);
    final i = _indexOf(cardId, commentId);
    if (i < 0) {
      throw const BackporchApiException(404, 'not_found');
    }
    final reply = _items[i].reply;
    if (reply == null) {
      throw const BackporchApiException(404, 'not_found');
    }
    if (reply.authorId == actor.id) {
      throw const BackporchApiException(403, 'cannot_report_own');
    }
    if (reason.trim().isEmpty) {
      throw const BackporchApiException(400, 'reason_required');
    }
  }
}
