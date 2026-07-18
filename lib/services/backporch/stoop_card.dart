// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

/// A creator reference as it appears on a card (`@handle`).
class StoopCreatorRef {
  final String id;
  final String displayName;
  const StoopCreatorRef({required this.id, required this.displayName});

  factory StoopCreatorRef.fromJson(Map<String, dynamic> j) => StoopCreatorRef(
    id: j['id'] as String? ?? '',
    displayName: j['displayName'] as String? ?? '',
  );
}

/// A card as it appears in browse grids, carousels, and creator profiles.
class StoopCard {
  final String id;
  final String name;
  final String summary;

  /// `SOLO` or `GROUP`.
  final String type;
  final bool nsfw;

  /// Net vote score (up minus down).
  final int score;
  final int downloadCount;
  final bool modPick;
  final StoopCreatorRef? creator;

  /// Attribution: who originally made this character, when the uploader isn't
  /// the author (free text — the creator needn't have a Stoop account).
  /// Null/empty = the uploader's own work.
  final String? originalCreator;
  final String? primaryAssetId;

  /// Approximate Llama token count of the card's content (server-computed), so
  /// the browser can show "how big is this" before download. Null on older
  /// records not yet backfilled.
  final int? tokenCount;

  const StoopCard({
    required this.id,
    required this.name,
    required this.summary,
    required this.type,
    required this.nsfw,
    required this.score,
    required this.downloadCount,
    required this.modPick,
    required this.creator,
    this.originalCreator,
    required this.primaryAssetId,
    this.tokenCount,
  });

  bool get isGroup => type == 'GROUP';

  /// This card with fresh live counters (from a [StoopCardStats] push).
  StoopCard withStats({required int score, required int downloadCount}) =>
      StoopCard(
        id: id,
        name: name,
        summary: summary,
        type: type,
        nsfw: nsfw,
        score: score,
        downloadCount: downloadCount,
        modPick: modPick,
        creator: creator,
        originalCreator: originalCreator,
        primaryAssetId: primaryAssetId,
        tokenCount: tokenCount,
      );

  factory StoopCard.fromJson(Map<String, dynamic> j) => StoopCard(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    summary: j['summary'] as String? ?? '',
    type: j['type'] as String? ?? 'SOLO',
    nsfw: j['nsfw'] as bool? ?? false,
    score: (j['score'] as num?)?.toInt() ?? 0,
    downloadCount: (j['downloadCount'] as num?)?.toInt() ?? 0,
    modPick: j['modPick'] as bool? ?? false,
    creator: j['creator'] is Map<String, dynamic>
        ? StoopCreatorRef.fromJson(j['creator'] as Map<String, dynamic>)
        : null,
    originalCreator: (j['originalCreator'] as String?)?.trim().isNotEmpty ==
            true
        ? (j['originalCreator'] as String).trim()
        : null,
    primaryAssetId: j['primaryAssetId'] as String?,
    tokenCount: (j['tokenCount'] as num?)?.toInt(),
  );
}

/// A live counter update for one card, pushed over the Stoop socket whenever
/// anyone votes on or first-downloads it — so counts tick up in real time
/// while the user is browsing.
class StoopCardStats {
  final String cardId;
  final int score;
  final int downloadCount;
  const StoopCardStats({
    required this.cardId,
    required this.score,
    required this.downloadCount,
  });

  factory StoopCardStats.fromJson(Map<String, dynamic> j) => StoopCardStats(
    cardId: j['cardId'] as String? ?? '',
    score: (j['score'] as num?)?.toInt() ?? 0,
    downloadCount: (j['downloadCount'] as num?)?.toInt() ?? 0,
  );

  /// Patch [cards] in place wherever the id matches; true if any tile changed.
  bool applyTo(List<StoopCard> cards) {
    var hit = false;
    for (var i = 0; i < cards.length; i++) {
      if (cards[i].id == cardId) {
        cards[i] = cards[i].withStats(
          score: score,
          downloadCount: downloadCount,
        );
        hit = true;
      }
    }
    return hit;
  }
}

/// A page of browse results.
class StoopBrowsePage {
  final int total;
  final int page;
  final List<StoopCard> items;
  const StoopBrowsePage({
    required this.total,
    required this.page,
    required this.items,
  });

  factory StoopBrowsePage.fromJson(Map<String, dynamic> j) => StoopBrowsePage(
    total: (j['total'] as num?)?.toInt() ?? 0,
    page: (j['page'] as num?)?.toInt() ?? 0,
    items: ((j['items'] as List?) ?? const [])
        .map((e) => StoopCard.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

/// The full card detail — everything the card ships with, for the detail page.
class StoopCardDetail {
  final String id;
  final String name;
  final String summary;
  final String type;
  final bool nsfw;
  final int score;
  final int downloadCount;
  final int version;

  /// Approximate Llama token count of the card's content (server-computed).
  /// Null on older records not yet backfilled.
  final int? tokenCount;
  final StoopCreatorRef? creator;

  /// Attribution: who originally made this character, when the uploader isn't
  /// the author. Null = the uploader's own work.
  final String? originalCreator;

  /// The V2/V2.5 card payload (description, personality, scenario, first_mes,
  /// alternate_greetings, mes_example, character_book, etc.).
  final Map<String, dynamic> card;
  final List<String> tags;
  final String? primaryAssetId;

  /// The caller's current vote: 1, -1, or 0.
  final int myVote;

  const StoopCardDetail({
    required this.id,
    required this.name,
    required this.summary,
    required this.type,
    required this.nsfw,
    required this.score,
    required this.downloadCount,
    required this.version,
    this.tokenCount,
    required this.creator,
    this.originalCreator,
    required this.card,
    required this.tags,
    required this.primaryAssetId,
    required this.myVote,
  });

  bool get isGroup => type == 'GROUP';

  factory StoopCardDetail.fromJson(Map<String, dynamic> j) => StoopCardDetail(
    id: j['id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    summary: j['summary'] as String? ?? '',
    type: j['type'] as String? ?? 'SOLO',
    nsfw: j['nsfw'] as bool? ?? false,
    score: (j['score'] as num?)?.toInt() ?? 0,
    downloadCount: (j['downloadCount'] as num?)?.toInt() ?? 0,
    version: (j['version'] as num?)?.toInt() ?? 1,
    tokenCount: (j['tokenCount'] as num?)?.toInt(),
    creator: j['creator'] is Map<String, dynamic>
        ? StoopCreatorRef.fromJson(j['creator'] as Map<String, dynamic>)
        : null,
    originalCreator: (j['originalCreator'] as String?)?.trim().isNotEmpty ==
            true
        ? (j['originalCreator'] as String).trim()
        : null,
    card: (j['card'] as Map<String, dynamic>?) ?? const {},
    tags: ((j['tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
    primaryAssetId: j['primaryAssetId'] as String?,
    myVote: (j['myVote'] as num?)?.toInt() ?? 0,
  );
}
