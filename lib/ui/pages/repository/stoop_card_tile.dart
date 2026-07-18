// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_avatar.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// A cinematic, glassmorphic card: full-bleed art with a bottom scrim carrying
/// the name + @creator + downloads, a glowing net-score badge, and neon NSFW /
/// GROUP pills. Lifts and glows on hover.
class StoopCardTile extends StatefulWidget {
  final StoopCard card;
  final VoidCallback onTap;
  const StoopCardTile({super.key, required this.card, required this.onTap});

  @override
  State<StoopCardTile> createState() => _StoopCardTileState();
}

class _StoopCardTileState extends State<StoopCardTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover ? 1.035 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hover
                    ? stoopAccent(context).withValues(alpha: 0.85)
                    : AppColors.borderOf(context),
                width: _hover ? 1.5 : 1,
              ),
              boxShadow: _hover
                  ? [
                      BoxShadow(
                        color: stoopAccent(context).withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: -4,
                      ),
                    ]
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                StoopAvatar(assetId: card.primaryAssetId),
                // Bottom scrim for legible title text over arbitrary art.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 24, 10, 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.82),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          card.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                // Uploader, plus the credited original author
                                // when the card is an attributed repost.
                                [
                                  if (card.creator != null)
                                    '@${card.creator!.displayName}',
                                  if (card.originalCreator != null)
                                    '✎ ${card.originalCreator}',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.download_rounded,
                              size: 12,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${card.downloadCount}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 11,
                              ),
                            ),
                            if (stoopTokenLabel(card.tokenCount) case final tl?) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.data_usage_rounded,
                                size: 11,
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                tl,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(top: 6, left: 6, child: _scoreBadge(context)),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (card.nsfw)
                        StoopPill(
                          tint: AppColors.resolve(
                            context,
                            Colors.pinkAccent,
                            Colors.pink,
                          ),
                          child: const Text(
                            '18+',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (card.isGroup) ...[
                        const SizedBox(height: 4),
                        StoopPill(
                          tint: stoopAccent2(context),
                          child: const Text(
                            'GROUP',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
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

  // Net score on a gradient-tinted glass pill with a glow.
  Widget _scoreBadge(BuildContext context) {
    return StoopPill(
      tint: stoopAccent(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.arrow_upward_rounded, size: 12, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            '${widget.card.score}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
