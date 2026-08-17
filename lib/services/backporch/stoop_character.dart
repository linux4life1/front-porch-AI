// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

/// One of the signed-in user's own uploads on The Stoop, as returned by
/// `GET /me/characters` — used by the "my uploads / pending review" view.
class StoopCharacter {
  final String id;
  final String name;

  /// `SOLO` or `GROUP`.
  final String type;
  final bool nsfw;

  /// `PENDING`, `APPROVED`, `REJECTED`, or `TAKEN_DOWN`.
  final String status;

  /// The moderator's note when [status] is `REJECTED`/`TAKEN_DOWN`.
  final String? rejectionNote;
  final String summary;

  /// Attribution: who originally made this character, when the uploader isn't
  /// the author. Null = the uploader's own work. Prefilled into the update
  /// flow so re-publishing never silently drops the credit.
  final String? originalCreator;
  final int version;
  final int downloadCount;
  final String? primaryAssetId;

  /// The card's permanent stable id (if it carried one), used to find the local
  /// library character this post came from when publishing an in-place update.
  final String? originStableId;

  /// Per-card Discussion opt-in. Default OFF. See StoopCardDetail.commentsEnabled.
  final bool commentsEnabled;

  const StoopCharacter({
    required this.id,
    required this.name,
    required this.type,
    required this.nsfw,
    required this.status,
    required this.rejectionNote,
    required this.summary,
    this.originalCreator,
    required this.version,
    required this.downloadCount,
    required this.primaryAssetId,
    this.originStableId,
    this.commentsEnabled = false,
  });

  bool get isPending => status == 'PENDING';
  bool get isApproved => status == 'APPROVED';
  bool get isRejected => status == 'REJECTED' || status == 'TAKEN_DOWN';

  factory StoopCharacter.fromJson(Map<String, dynamic> json) => StoopCharacter(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    type: json['type'] as String? ?? 'SOLO',
    nsfw: json['nsfw'] as bool? ?? false,
    status: json['status'] as String? ?? 'PENDING',
    rejectionNote: json['rejectionNote'] as String?,
    summary: json['summary'] as String? ?? '',
    originalCreator:
        (json['originalCreator'] as String?)?.trim().isNotEmpty == true
        ? (json['originalCreator'] as String).trim()
        : null,
    version: (json['version'] as num?)?.toInt() ?? 1,
    downloadCount: (json['downloadCount'] as num?)?.toInt() ?? 0,
    primaryAssetId: json['primaryAssetId'] as String?,
    originStableId: json['originStableId'] as String?,
    commentsEnabled: json['commentsEnabled'] == true,
  );
}
