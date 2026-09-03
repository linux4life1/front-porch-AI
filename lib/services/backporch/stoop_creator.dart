// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'backporch_user.dart';
import 'stoop_card.dart';

/// Lifetime totals over every approved card (server-computed, so they don't
/// shrink for viewers with 18+ hidden).
class StoopCreatorStats {
  final int cards;
  final int downloads;
  final int score;
  const StoopCreatorStats({this.cards = 0, this.downloads = 0, this.score = 0});

  factory StoopCreatorStats.fromJson(Map<String, dynamic>? j) =>
      StoopCreatorStats(
        cards: ((j ?? const {})['cards'] as num?)?.toInt() ?? 0,
        downloads: ((j ?? const {})['downloads'] as num?)?.toInt() ?? 0,
        score: ((j ?? const {})['score'] as num?)?.toInt() ?? 0,
      );
}

/// A creator's public profile plus their approved cards.
class StoopCreator {
  final String id;
  final String displayName;

  /// Hub verification badge: `gold`, `blue`, or null (none / older server).
  final String? verification;
  final int followers;

  /// Whether the signed-in user follows this creator.
  final bool following;

  /// Whether this profile is the signed-in user's own.
  final bool isMe;
  final List<StoopCard> cards;

  /// Public profile extras (all additive; empty/null on older servers).
  final String bio;
  final List<String> links;
  final String? avatarAssetId;
  final DateTime? createdAt;
  final StoopCreatorStats stats;

  const StoopCreator({
    required this.id,
    required this.displayName,
    this.verification,
    required this.followers,
    required this.following,
    required this.isMe,
    required this.cards,
    this.bio = '',
    this.links = const [],
    this.avatarAssetId,
    this.createdAt,
    this.stats = const StoopCreatorStats(),
  });

  factory StoopCreator.fromJson(Map<String, dynamic> j) => StoopCreator(
    id: j['id'] as String? ?? '',
    displayName: j['displayName'] as String? ?? '',
    verification: stoopVerificationOf(j['verification']),
    followers: (j['followers'] as num?)?.toInt() ?? 0,
    following: j['following'] as bool? ?? false,
    isMe: j['isMe'] as bool? ?? false,
    cards: ((j['cards'] as List?) ?? const [])
        .map((e) => StoopCard.fromJson(e as Map<String, dynamic>))
        .toList(),
    bio: (j['bio'] as String? ?? '').trim(),
    // The server sends both `links` and `profileLinks` (same array) — read
    // either defensively.
    links: ((j['links'] ?? j['profileLinks']) as List? ?? const [])
        .whereType<String>()
        .toList(),
    avatarAssetId: j['avatarAssetId'] as String?,
    // `is String` (not a cast): a malformed field must cost one line on the
    // profile, never the whole creator-page parse.
    createdAt: j['createdAt'] is String
        ? DateTime.tryParse(j['createdAt'] as String)
        : null,
    stats: StoopCreatorStats.fromJson(j['stats'] as Map<String, dynamic>?),
  );
}

/// A creator the signed-in user follows (for the "Following" list/row).
class StoopFollowedCreator {
  final String id;
  final String displayName;

  /// Hub verification badge: `gold`, `blue`, or null (none / older server).
  final String? verification;
  final int followers;
  final String? avatarAssetId;
  const StoopFollowedCreator({
    required this.id,
    required this.displayName,
    this.verification,
    required this.followers,
    this.avatarAssetId,
  });

  factory StoopFollowedCreator.fromJson(Map<String, dynamic> j) =>
      StoopFollowedCreator(
        id: j['id'] as String? ?? '',
        displayName: j['displayName'] as String? ?? '',
        verification: stoopVerificationOf(j['verification']),
        followers: (j['followers'] as num?)?.toInt() ?? 0,
        avatarAssetId: j['avatarAssetId'] as String?,
      );
}
