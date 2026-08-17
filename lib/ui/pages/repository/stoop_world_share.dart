// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sharing Places (worlds) to The Stoop — the upload wizard's Places section
// and the publish call. Worlds ride the same card endpoints as `type: 'WORLD'`
// (payload = the .fpworld envelope, cover image attached as the card avatar)
// and go through the SAME moderation pipeline as characters. Gated behind
// [kStoopWorldsLive] until the backend accepts the new type.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/world_cover.dart';

/// Publish [world] to The Stoop as a `WORLD` card: the .fpworld envelope as
/// the card payload, the place's cover image as the card avatar (required —
/// it's what moderators review and what tiles display). Lands in the same
/// PENDING moderation queue as characters. Returns a user-facing validation
/// message when the world can't be shared, null on success; server failures
/// propagate as [BackporchApiException] for the wizard's shared error mapping.
Future<String?> publishStoopWorld({
  required BackporchApi api,
  required WorldRepository repo,
  required String accessToken,
  required World world,
  required String name,
  required String summary,
  required bool nsfw,
  required List<String> tags,
  required String originalCreator,
  bool commentsEnabled = false,
}) async {
  final cover = decodeWorldCoverBytes(world.coverImage);
  if (cover == null) {
    return 'This place needs a cover image before it can be shared.';
  }
  final isPng = (world.coverImage ?? '').startsWith('data:image/png');

  // Stable identity for re-shares. The server treats (owner + card's source
  // id) as "the same post" and turns a repeat upload into a new version
  // instead of a second pending row — but `encodeFpWorld` only stamps
  // `meta.sourceId` on worlds that were themselves imported. Without this, a
  // place you authored here has none, and every re-share would pile up another
  // duplicate in the moderation queue.
  final card = repo.fpWorldJson(world);
  final rawMeta = card['meta'];
  final meta = <String, dynamic>{
    if (rawMeta is Map)
      for (final e in rawMeta.entries) e.key.toString(): e.value,
  };
  meta['sourceId'] = world.sourceId ?? world.id;
  card['meta'] = meta;

  final completeness = StoopCardCompleteness.assess(card, 'WORLD');
  if (completeness.incomplete) {
    return completeness.message;
  }

  final result = await api.uploadCharacter(
    accessToken: accessToken,
    payload: {
      'name': name,
      'summary': summary,
      'type': 'WORLD',
      'nsfw': nsfw,
      'commentsEnabled': commentsEnabled,
      'tags': tags,
      // Full place package — lore, resolved climate, traits, and the cover
      // (as a data URL) so a download restores the world exactly.
      'card': card,
      'changelog': 'Initial upload',
      'originalCreator': originalCreator,
    },
    avatarBytes: cover,
    avatarFilename: isPng ? 'cover.png' : 'cover.jpg',
  );
  StoopCommentsOptIn.instance.setPublished(result.id, commentsEnabled);
  return null;
}

/// A place's cover image at [size], or an amber landscape glyph when the
/// world has none / [coverBytes] wasn't resolvable. Shared by the pick tiles
/// and the wizard's review preview.
Widget stoopWorldCoverPreview(
  BuildContext context, {
  required Uint8List? coverBytes,
  double size = 96,
}) {
  if (coverBytes != null) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        coverBytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: stoopAmberSoft(context),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(
      Icons.landscape_rounded,
      // The tile passes an unbounded size to fill its slot; keep the glyph sane.
      size: size.isFinite ? size * 0.45 : 44,
      color: stoopAmberText(context),
    ),
  );
}

/// The upload wizard's Places section. While [kStoopWorldsLive] is false it
/// renders a "coming soon" banner; once live it lists the user's shareable
/// places (those with a cover image) for selection.
class StoopWorldsPickSection extends StatefulWidget {
  final String query;
  final String? selectedWorldId;
  final ValueChanged<World> onSelect;
  const StoopWorldsPickSection({
    super.key,
    required this.query,
    required this.selectedWorldId,
    required this.onSelect,
  });

  @override
  State<StoopWorldsPickSection> createState() => _StoopWorldsPickSectionState();
}

class _StoopWorldsPickSectionState extends State<StoopWorldsPickSection> {
  // Covers are ≤350 KB base64 data URLs; decode once per world, not on every
  // rebuild of the wizard (each keystroke in the search field rebuilds us).
  final Map<String, Uint8List?> _coverCache = {};

  Uint8List? _coverFor(World w) =>
      _coverCache.putIfAbsent(w.id, () => decodeWorldCoverBytes(w.coverImage));

  @override
  Widget build(BuildContext context) {
    if (!kStoopWorldsLive) {
      // Tagged, not hidden: the section announces itself so users know world
      // sharing is on the way. No tiles until the backend accepts WORLD cards.
      if (widget.query.isNotEmpty) return const SizedBox.shrink();
      return _noticeBanner(
        context,
        badge: 'COMING SOON',
        body:
            'Soon you’ll be able to share your worlds here — portable '
            '.fpworld places with their lore, climate, traits, and cover '
            'art. Shared places go through the same moderator review as '
            'characters before anyone sees them.',
      );
    }
    final places = context.read<WorldRepository>().placeWorlds;
    // A place can only be shared with cover art — it's what moderators review
    // and what every Stoop tile displays.
    final worlds = places
        .where((w) => w.coverImage != null && w.coverImage!.isNotEmpty)
        .where(
          (w) =>
              widget.query.isEmpty ||
              w.name.toLowerCase().contains(widget.query),
        )
        .toList();
    if (worlds.isEmpty) {
      // Searching: stay quiet, the field filters characters too.
      if (widget.query.isNotEmpty) return const SizedBox.shrink();
      // Silently rendering nothing here reads as "world sharing doesn't
      // exist" — say why instead, since the fix is one step away.
      if (places.isNotEmpty) {
        return _noticeBanner(
          context,
          badge: 'NEEDS COVER ART',
          body:
              'Your places need a cover image before they can be shared — '
              'it’s what moderators review and what every tile shows. Open '
              'Worlds, edit a place, add its art, and it’ll appear here.',
        );
      }
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            'Places',
            style: TextStyle(
              color: stoopCream2(context),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            childAspectRatio: 0.78,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: worlds.length,
          itemBuilder: (context, i) => _worldTile(worlds[i]),
        ),
      ],
    );
  }

  Widget _noticeBanner(
    BuildContext context, {
    required String badge,
    required String body,
  }) {
    final amber = stoopAmberText(context);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: stoopCardGradient(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.stoopAmber.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.landscape_rounded, color: amber, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Places',
                      style: TextStyle(
                        color: stoopCream(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        gradient: stoopAmberGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: AppColors.stoopAmberInk,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: stoopMute(context),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _worldTile(World world) {
    final selected = widget.selectedWorldId == world.id;
    final accent = AppColors.stoopAmberDeep;
    return GestureDetector(
      onTap: () => widget.onSelect(world),
      child: Container(
        decoration: BoxDecoration(
          gradient: stoopCardGradient(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : stoopBorder(context),
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _coverFor(world) == null
                  ? stoopWorldCoverPreview(
                      context,
                      coverBytes: null,
                      size: double.infinity,
                    )
                  : Image.memory(
                      _coverFor(world)!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                world.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: stoopCream(context),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
