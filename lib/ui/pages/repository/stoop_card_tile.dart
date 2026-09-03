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
import 'package:front_porch_ai/ui/pages/repository/stoop_verified_badge.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The hub card tile (hub.frontporchai.app .hub-tile): square art on top
/// with badge pills, then a body — name, @creator, two-line summary, and a
/// stats foot (▲ score, ⬇ downloads, token count). Lifts with an amber
/// border + warm glow on hover. [compact] is the Mod's-Picks-row variant
/// (.hub-picktile): art + name only.
class StoopCardTile extends StatefulWidget {
  final StoopCard card;
  final VoidCallback onTap;
  final bool compact;
  const StoopCardTile({
    super.key,
    required this.card,
    required this.onTap,
    this.compact = false,
  });

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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          decoration: BoxDecoration(
            gradient: stoopCardGradient(context),
            borderRadius: BorderRadius.circular(widget.compact ? 9 : 14),
            border: Border.all(
              color: _hover ? AppColors.stoopAmberDeep : stoopBorder(context),
            ),
            boxShadow: _hover
                ? [
                    const BoxShadow(
                      color: Color(0x59000000),
                      blurRadius: 34,
                      offset: Offset(0, 12),
                    ),
                    BoxShadow(
                      color: AppColors.stoopAmber.withValues(alpha: 0.07),
                      blurRadius: 26,
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _art(card),
              if (widget.compact) _compactName(card) else _body(card),
            ],
          ),
        ),
      ),
    );
  }

  // Square art with the badge pills floated top-left (lantern placeholder
  // shows through when a card has no avatar asset).
  Widget _art(StoopCard card) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: stoopBg1(context),
            child: StoopAvatar(assetId: card.primaryAssetId),
          ),
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (card.modPick) const StoopBadge(StoopBadgeKind.pick),
                if (card.isGroup) const StoopBadge(StoopBadgeKind.group),
                if (card.isWorld)
                  ...stoopWorldKindBadges(
                    climateEnabled: stoopCardClimateEnabled(card),
                  ),
                if (card.nsfw) const StoopBadge(StoopBadgeKind.nsfw),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactName(StoopCard card) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        card.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: stoopCream(context),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _body(StoopCard card) {
    final faint = TextStyle(color: stoopFaint(context), fontSize: 11.5);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: stoopDisplay(context, size: 15.5),
            ),
            if (card.creator != null || card.originalCreator != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  if (card.creator != null) ...[
                    Flexible(
                      child: Text(
                        '@${card.creator!.displayName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: faint,
                      ),
                    ),
                    StoopVerifiedBadge(
                      verification: card.creator!.verification,
                      size: 12,
                    ),
                  ],
                  if (card.originalCreator != null)
                    Flexible(
                      child: Text(
                        '${card.creator != null ? ' · ' : ''}✎ ${card.originalCreator}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: faint,
                      ),
                    ),
                ],
              ),
            ],
            if (card.summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  stoopResolveMacros(card.summary, card.name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: stoopMute(context),
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ),
            ] else
              const Spacer(),
            const SizedBox(height: 8),
            _statsFoot(card),
          ],
        ),
      ),
    );
  }

  // "▲ 12  ⬇ 340" with amber numbers; token count sits faint on the right.
  Widget _statsFoot(StoopCard card) {
    final numberStyle = TextStyle(
      color: stoopAmberText(context),
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
    );
    final labelStyle = TextStyle(color: stoopCream2(context), fontSize: 12.5);
    return Row(
      children: [
        Text('▲ ', style: labelStyle),
        Text('${card.score}', style: numberStyle),
        const SizedBox(width: 12),
        Text('⬇ ', style: labelStyle),
        Text('${card.downloadCount}', style: numberStyle),
        const Spacer(),
        if (stoopTokenLabel(card.tokenCount) case final tl?)
          Text(
            '$tl tok',
            style: TextStyle(color: stoopFaint(context), fontSize: 11),
          ),
      ],
    );
  }
}
