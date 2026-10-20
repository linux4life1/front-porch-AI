// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_avatar.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_verified_badge.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// The Mod's-Pick hero (.hub-pickhero): a blurred, zoomed fill of the card
/// art behind a dusk scrim, with the SHARP portrait at true 3:4 on the left
/// so faces never stretch, and name/summary/CTA beside it.
class StoopBrowseHero extends StatelessWidget {
  final StoopCard card;
  final VoidCallback onOpen;

  const StoopBrowseHero({super.key, required this.card, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: GestureDetector(
        onTap: onOpen,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            height: 230,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.stoopAmber.withValues(alpha: 0.3),
              ),
              boxShadow: [
                const BoxShadow(
                  color: InkColors.shadow,
                  blurRadius: 30,
                  offset: Offset(0, 10),
                ),
                BoxShadow(
                  color: AppColors.stoopAmber.withValues(alpha: 0.06),
                  blurRadius: 44,
                ),
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Blur the image itself (not a backdrop) and oversize it so
                // the blur's transparent edge never shows.
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: Transform.scale(
                    scale: 1.18,
                    child: StoopAvatar(assetId: card.primaryAssetId),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      // theme-keep: scrim over the hero art, the same in every theme
                      colors: [Color(0x590A0805), Color(0xB80A0805)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: AppColors.stoopBorderHi),
                          boxShadow: const [
                            BoxShadow(
                              color: InkColors.shadowDeep,
                              blurRadius: 24,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: AspectRatio(
                          aspectRatio: 3 / 4,
                          child: StoopAvatar(assetId: card.primaryAssetId),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(child: _details(context)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Hero text column. The hero sits on a dark scrim in BOTH themes, so this
  // deliberately uses the dusk constants rather than theme-resolved tokens.
  Widget _details(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            const StoopBadge(StoopBadgeKind.featured),
            if (card.isGroup) const StoopBadge(StoopBadgeKind.group),
            if (card.isWorld)
              ...stoopWorldKindBadges(
                climateEnabled: stoopCardClimateEnabled(card),
              ),
            if (card.nsfw) const StoopBadge(StoopBadgeKind.nsfw),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          card.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: stoopDisplay(context, size: 26, color: AppColors.stoopCream),
        ),
        if (card.creator != null) ...[
          const SizedBox(height: 3),
          Row(
            children: [
              Flexible(
                child: Text(
                  '@${card.creator!.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.stoopCream2,
                    fontSize: 12.5,
                  ),
                ),
              ),
              StoopVerifiedBadge(
                verification: card.creator!.verification,
                size: 13,
              ),
            ],
          ),
        ],
        if (card.summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            stoopResolveMacros(card.summary, card.name),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.stoopCream2, height: 1.45),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            StoopAmberButton(
              label: 'View card',
              onPressed: onOpen,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            ),
            const SizedBox(width: 14),
            Text(
              '▲ ${card.score}   ⬇ ${card.downloadCount}',
              style: const TextStyle(
                color: AppColors.stoopCream2,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
