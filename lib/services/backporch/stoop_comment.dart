// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A character-card comment. Payload NEVER includes email — only public
// identity (handle, avatar, optional gold/blue verification) + body + tombstone.

import 'package:front_porch_ai/services/backporch/backporch_user.dart';

/// One-level owner reply glued under a [StoopComment].
class StoopCommentReply {
  final String authorId;

  /// Public handle / display name. Shown as `@handle`.
  final String displayName;
  final String? verification;
  final String? authorAvatarAssetId;
  final DateTime createdAt;

  /// Plain-text body. Empty when [deleted] (tombstone keeps the row).
  final String body;
  final bool deleted;

  const StoopCommentReply({
    required this.authorId,
    required this.displayName,
    this.verification,
    this.authorAvatarAssetId,
    required this.createdAt,
    required this.body,
    this.deleted = false,
  });

  StoopCommentReply copyWith({String? body, bool? deleted}) =>
      StoopCommentReply(
        authorId: authorId,
        displayName: displayName,
        verification: verification,
        authorAvatarAssetId: authorAvatarAssetId,
        createdAt: createdAt,
        body: body ?? this.body,
        deleted: deleted ?? this.deleted,
      );

  factory StoopCommentReply.fromJson(Map<String, dynamic> j) =>
      StoopCommentReply(
        authorId: (j['authorId'] as String?) ?? '',
        displayName:
            (j['displayName'] as String?) ??
            (j['authorHandle'] as String?) ??
            '',
        verification: stoopVerificationOf(j['verification']),
        authorAvatarAssetId: j['authorAvatarAssetId'] as String?,
        createdAt: j['createdAt'] is String
            ? DateTime.tryParse(j['createdAt'] as String) ??
                  DateTime.fromMillisecondsSinceEpoch(0)
            : DateTime.fromMillisecondsSinceEpoch(0),
        body: (j['body'] as String?) ?? '',
        deleted: j['deleted'] == true,
      );

  /// Wire shape. Deliberately omits email.
  Map<String, dynamic> toJson() => {
    'authorId': authorId,
    'displayName': displayName,
    if (verification != null) 'verification': verification,
    if (authorAvatarAssetId != null) 'authorAvatarAssetId': authorAvatarAssetId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'body': deleted ? '' : body,
    'deleted': deleted,
  };
}

/// One comment on a Stoop character card.
class StoopComment {
  final String id;
  final String cardId;
  final String authorId;

  /// Public handle / display name. Shown as `@handle`.
  final String displayName;
  final String? verification;
  final String? authorAvatarAssetId;
  final DateTime createdAt;

  /// Plain-text body. Empty when [deleted] (tombstone keeps the row).
  final String body;
  final bool deleted;

  /// At most one owner reply. Null when nobody has replied yet.
  final StoopCommentReply? reply;

  const StoopComment({
    required this.id,
    required this.cardId,
    required this.authorId,
    required this.displayName,
    this.verification,
    this.authorAvatarAssetId,
    required this.createdAt,
    required this.body,
    this.deleted = false,
    this.reply,
  });

  StoopComment copyWith({
    String? body,
    bool? deleted,
    StoopCommentReply? reply,
  }) => StoopComment(
    id: id,
    cardId: cardId,
    authorId: authorId,
    displayName: displayName,
    verification: verification,
    authorAvatarAssetId: authorAvatarAssetId,
    createdAt: createdAt,
    body: body ?? this.body,
    deleted: deleted ?? this.deleted,
    reply: reply ?? this.reply,
  );

  factory StoopComment.fromJson(Map<String, dynamic> j) => StoopComment(
    id: (j['id'] as String?) ?? '',
    cardId: (j['cardId'] as String?) ?? '',
    authorId: (j['authorId'] as String?) ?? '',
    displayName:
        (j['displayName'] as String?) ?? (j['authorHandle'] as String?) ?? '',
    verification: stoopVerificationOf(j['verification']),
    authorAvatarAssetId: j['authorAvatarAssetId'] as String?,
    createdAt: j['createdAt'] is String
        ? DateTime.tryParse(j['createdAt'] as String) ??
              DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch(0),
    body: (j['body'] as String?) ?? '',
    deleted: j['deleted'] == true,
    reply: j['reply'] is Map
        ? StoopCommentReply.fromJson(
            Map<String, dynamic>.from(j['reply'] as Map),
          )
        : null,
  );

  /// Wire shape. Deliberately omits email.
  Map<String, dynamic> toJson() => {
    'id': id,
    'cardId': cardId,
    'authorId': authorId,
    'displayName': displayName,
    if (verification != null) 'verification': verification,
    if (authorAvatarAssetId != null) 'authorAvatarAssetId': authorAvatarAssetId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'body': deleted ? '' : body,
    'deleted': deleted,
    if (reply != null) 'reply': reply!.toJson(),
  };
}
