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

/// Hub `.hub-detail-top`: square art beside name, creator, and the **full**
/// listing summary — not a 260px banner with the blurb painted onto the image.
class StoopDetailTop extends StatelessWidget {
  const StoopDetailTop({
    super.key,
    required this.detail,
    required this.downloadCount,
    required this.onClose,
    this.onCreatorTap,
  });

  final StoopCardDetail detail;
  final int downloadCount;
  final VoidCallback onClose;
  final VoidCallback? onCreatorTap;

  static const _sideBySideMin = 560.0;
  static const _artMax = 280.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerRight, child: _close(context)),
          LayoutBuilder(
            builder: (context, constraints) {
              final side = constraints.maxWidth >= _sideBySideMin;
              final art = _art(context);
              final info = _info(context);
              if (!side) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: _artMax),
                      child: art,
                    ),
                    const SizedBox(height: 16),
                    info,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: _artMax, child: art),
                  const SizedBox(width: 22),
                  Expanded(child: info),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _close(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: stoopBg1(context),
        shape: BoxShape.circle,
        border: Border.all(color: stoopBorderHi(context)),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onClose,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(Icons.close, size: 18, color: stoopCream2(context)),
        ),
      ),
    );
  }

  Widget _art(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: stoopBorderHi(context)),
        ),
        child: AspectRatio(
          aspectRatio: 1,
          child: StoopAvatar(assetId: detail.primaryAssetId),
        ),
      ),
    );
  }

  Widget _info(BuildContext context) {
    final d = detail;
    final summary = stoopResolveMacros(d.summary, d.name).trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            if (d.isWorld)
              ...stoopWorldKindBadges(
                climateEnabled: stoopWorldClimateEnabled(d.card),
              ),
            if (d.isGroup) const StoopBadge(StoopBadgeKind.group),
            if (d.nsfw) const StoopBadge(StoopBadgeKind.nsfw),
          ],
        ),
        if (d.isWorld || d.isGroup || d.nsfw) const SizedBox(height: 8),
        Text(d.name, style: stoopDisplay(context, size: 26)),
        if (d.creator != null) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onCreatorTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'by ${d.creator!.displayName}',
                  style: TextStyle(
                    color: stoopTealText(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                StoopVerifiedBadge(verification: d.creator!.verification),
              ],
            ),
          ),
        ],
        if (d.originalCreator != null) ...[
          const SizedBox(height: 2),
          Text(
            'created by ${d.originalCreator}',
            style: TextStyle(
              color: stoopFaint(context),
              fontStyle: FontStyle.italic,
              fontSize: 13,
            ),
          ),
        ],
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            summary,
            key: const Key('stoop-detail-summary'),
            style: TextStyle(color: stoopCream2(context), height: 1.45),
          ),
        ],
        if (d.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final t in d.tags)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: stoopTealSoft(context),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.stoopTeal.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    '#$t',
                    style: TextStyle(
                      color: stoopTealText(context),
                      fontSize: 12.5,
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '⬇ $downloadCount',
              style: TextStyle(color: stoopMute(context)),
            ),
            if (d.version >= 2)
              Text(
                'v${d.version}',
                style: TextStyle(color: stoopMute(context)),
              ),
            if (stoopTokenLabel(d.tokenCount) case final tl?)
              Text('~$tl tokens', style: TextStyle(color: stoopMute(context))),
          ],
        ),
      ],
    );
  }
}
