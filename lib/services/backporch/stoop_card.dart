// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:front_porch_ai/models/models.dart';

import 'backporch_user.dart';

/// Worlds on The Stoop — client readiness flag.
///
/// Portable places (.fpworld packages) ride the SAME card endpoints as a third
/// `type: 'WORLD'` whose `card` payload is the .fpworld envelope
/// (`encodeFpWorld` / `decodeFpWorld` in `models/fp_world_package.dart`), with
/// the place's cover image attached as the card avatar — so worlds get browse,
/// search, votes, downloads, creator pages, AND the exact moderation pipeline
/// characters already go through (PENDING → mod review → APPROVED before
/// anyone can see them). This keeps the backend change purely additive (one
/// new enum value; no new endpoints), per the mixed-fleet API contract.
///
/// The backend does not accept `WORLD` yet. The Dart client is fully wired —
/// upload, browse, download + auto-import — behind this flag; flip it to true
/// when the backend ships. While false, the UI shows Worlds as "coming soon".
const bool kStoopWorldsLive = true;

/// The mixed-view opt-in the API expects when a caller understands worlds.
/// Sent on list endpoints only; `type=all` deliberately still means
/// solo+group server-side so already-shipped apps never receive a WORLD item.
const String kStoopWorldTypes = 'solo,group,world';

/// Climate/weather flag on a WORLD .fpworld envelope.
///
/// Reads `climate_enabled` / `climateEnabled` (bool or 0/1). Missing key
/// means climate ON — old packages always shipped biome. Callers pass the
/// payload already on the card; this does not hit the network.
bool stoopWorldClimateEnabled(Map<String, dynamic> envelope) =>
    readWorldClimateEnabled(envelope) ?? true;

/// A creator reference as it appears on a card (`@handle`).
class StoopCreatorRef {
  final String id;
  final String displayName;

  /// Hub verification badge: `gold`, `blue`, or null (none / older server).
  final String? verification;
  const StoopCreatorRef({
    required this.id,
    required this.displayName,
    this.verification,
  });

  factory StoopCreatorRef.fromJson(Map<String, dynamic> j) => StoopCreatorRef(
    id: j['id'] as String? ?? '',
    displayName: j['displayName'] as String? ?? '',
    verification: stoopVerificationOf(j['verification']),
  );
}

/// A card as it appears in browse grids, carousels, and creator profiles.
class StoopCard {
  final String id;
  final String name;
  final String summary;

  /// `SOLO`, `GROUP`, or `WORLD` (a .fpworld place package).
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

  /// WORLD listing payload: the .fpworld envelope when the list includes
  /// `card`. Empty on SOLO/GROUP and on list rows that omit the envelope.
  final Map<String, dynamic> card;

  /// WORLD list DTO climate flag when [card] is omitted.
  ///
  /// Null on older servers and non-WORLD rows. Both `climateEnabled` and
  /// `climate_enabled` are accepted at the wire boundary.
  final bool? climateEnabled;

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
    this.card = const {},
    this.climateEnabled,
  });

  bool get isGroup => type == 'GROUP';
  bool get isWorld => type == 'WORLD';

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
        card: card,
        climateEnabled: climateEnabled,
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
    originalCreator:
        (j['originalCreator'] as String?)?.trim().isNotEmpty == true
        ? (j['originalCreator'] as String).trim()
        : null,
    primaryAssetId: j['primaryAssetId'] as String?,
    tokenCount: (j['tokenCount'] as num?)?.toInt(),
    card: j['card'] is Map
        ? Map<String, dynamic>.from(j['card'] as Map)
        : const {},
    climateEnabled: readWorldClimateEnabled(j),
  );
}

/// Climate/lore decision for a WORLD list row.
///
/// A flag inside a full envelope is authoritative. Otherwise the additive
/// list DTO flag fills the gap left by bandwidth-trimmed rows. A genuinely
/// old envelope remains climate-on through [stoopWorldClimateEnabled], while
/// an omitted/empty envelope no longer invents climate.
bool stoopCardClimateEnabled(StoopCard card) {
  final envelopeFlag = readWorldClimateEnabled(card.card);
  if (envelopeFlag != null) return envelopeFlag;
  return card.climateEnabled ?? card.card.isNotEmpty;
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

  /// The card payload: V2/V2.5 character JSON for `SOLO`, a group card for
  /// `GROUP`, or the .fpworld envelope (lore + climate + traits + cover) for
  /// `WORLD`.
  final Map<String, dynamic> card;
  final List<String> tags;
  final String? primaryAssetId;

  /// The caller's current vote: 1, -1, or 0.
  final int myVote;

  /// Per-card Discussion opt-in. Default OFF. Omitted / missing => false.
  final bool commentsEnabled;

  /// Live kill switch. True hides Discussion without wiping comments.
  /// Omitted / missing => false (unlocked).
  final bool commentsLocked;

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
    this.commentsEnabled = false,
    this.commentsLocked = false,
  });

  bool get isGroup => type == 'GROUP';
  bool get isWorld => type == 'WORLD';

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
    originalCreator:
        (j['originalCreator'] as String?)?.trim().isNotEmpty == true
        ? (j['originalCreator'] as String).trim()
        : null,
    card: (j['card'] as Map<String, dynamic>?) ?? const {},
    tags: ((j['tags'] as List?) ?? const []).map((e) => e.toString()).toList(),
    primaryAssetId: j['primaryAssetId'] as String?,
    myVote: (j['myVote'] as num?)?.toInt() ?? 0,
    commentsEnabled: j['commentsEnabled'] == true,
    commentsLocked: j['commentsLocked'] == true,
  );
}
