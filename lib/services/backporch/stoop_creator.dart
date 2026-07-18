// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'stoop_card.dart';

/// A creator's public profile plus their approved cards.
class StoopCreator {
  final String id;
  final String displayName;
  final int followers;

  /// Whether the signed-in user follows this creator.
  final bool following;

  /// Whether this profile is the signed-in user's own.
  final bool isMe;
  final List<StoopCard> cards;

  const StoopCreator({
    required this.id,
    required this.displayName,
    required this.followers,
    required this.following,
    required this.isMe,
    required this.cards,
  });

  factory StoopCreator.fromJson(Map<String, dynamic> j) => StoopCreator(
    id: j['id'] as String? ?? '',
    displayName: j['displayName'] as String? ?? '',
    followers: (j['followers'] as num?)?.toInt() ?? 0,
    following: j['following'] as bool? ?? false,
    isMe: j['isMe'] as bool? ?? false,
    cards: ((j['cards'] as List?) ?? const [])
        .map((e) => StoopCard.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// A creator the signed-in user follows (for the "Following" list/row).
class StoopFollowedCreator {
  final String id;
  final String displayName;
  final int followers;
  const StoopFollowedCreator({
    required this.id,
    required this.displayName,
    required this.followers,
  });

  factory StoopFollowedCreator.fromJson(Map<String, dynamic> j) =>
      StoopFollowedCreator(
        id: j['id'] as String? ?? '',
        displayName: j['displayName'] as String? ?? '',
        followers: (j['followers'] as num?)?.toInt() ?? 0,
      );
}
