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
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:front_porch_ai/services/backporch/backporch.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_avatar.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_verified_badge.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The ONE creator identity header, used by both the signed-in profile tab and
/// other creators' pages (per the approved profile mockup): avatar (or amber
/// monogram), display name, "On the porch since …", the lifetime stat line,
/// bio, and teal link chips — with the caller's action buttons on the right.
class StoopProfileHeader extends StatelessWidget {
  final StoopCreator creator;

  /// Live follower count (the creator page updates it optimistically on
  /// follow/unfollow; defaults to the profile's own number).
  final int? followers;

  /// Action buttons rendered top-right (Edit profile + Share for your own
  /// profile; Follow + Share on someone else's).
  final List<Widget> actions;

  const StoopProfileHeader({
    super.key,
    required this.creator,
    this.followers,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = creator;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: stoopPanel(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StoopCreatorAvatar(
                assetId: c.avatarAssetId,
                name: c.displayName,
                size: 64,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          c.displayName,
                          style: stoopDisplay(context, size: 23),
                        ),
                        StoopVerifiedBadge(
                          verification: c.verification,
                          size: 22,
                        ),
                      ],
                    ),
                    if (c.createdAt != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        'On the porch since ${_monthYear(c.createdAt!)}',
                        style: TextStyle(
                          color: stoopFaint(context),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _statLine(context),
                  ],
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: 12),
                Wrap(spacing: 10, runSpacing: 8, children: actions),
              ],
            ],
          ),
          if (c.bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              c.bio,
              style: TextStyle(
                color: stoopCream2(context),
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ],
          if (c.links.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final url in c.links) _linkChip(context, url)],
            ),
          ],
        ],
      ),
    );
  }

  // "12 followers · 8 cards · 1,240 downloads · ▲ 312 net votes" — the same
  // lifetime line the hub shows (server totals, not the visible slice).
  Widget _statLine(BuildContext context) {
    final s = creator.stats;
    final f = followers ?? creator.followers;
    final parts = [
      '$f ${f == 1 ? 'follower' : 'followers'}',
      '${s.cards} ${s.cards == 1 ? 'card' : 'cards'}',
      '${s.downloads} downloads',
      '▲ ${s.score} net votes',
    ];
    return Text(
      parts.join(' · '),
      style: TextStyle(color: stoopCream2(context), fontSize: 13.5),
    );
  }

  Widget _linkChip(BuildContext context, String url) {
    var label = url.replaceFirst(RegExp(r'^https?://'), '');
    if (label.endsWith('/')) label = label.substring(0, label.length - 1);
    if (label.length > 42) label = '${label.substring(0, 40)}…';
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
        decoration: BoxDecoration(
          color: stoopTealSoft(context),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppColors.stoopTeal.withValues(alpha: 0.35),
          ),
        ),
        child: Text(
          '🔗 $label',
          style: TextStyle(color: stoopTealText(context), fontSize: 12.5),
        ),
      ),
    );
  }

  static String _monthYear(DateTime d) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }
}

/// A round, amber-ringed creator avatar: the profile picture when one is set,
/// the serif monogram otherwise. Shared by the profile header, the Following
/// chips, and the account sheet.
class StoopCreatorAvatar extends StatelessWidget {
  final String? assetId;
  final String name;
  final double size;
  const StoopCreatorAvatar({
    super.key,
    required this.assetId,
    required this.name,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    final id = assetId;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: stoopBg1(context),
        border: Border.all(
          color: AppColors.stoopAmber.withValues(alpha: 0.45),
          width: size >= 48 ? 2 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: id != null && id.isNotEmpty
          ? StoopAvatar(assetId: id, width: size, height: size)
          : Text(
              name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
              style: stoopDisplay(
                context,
                size: size * 0.4,
                color: stoopAmberText(context),
              ),
            ),
    );
  }
}

/// Copy the creator's public hub page link (hub.frontporchai.app/creator/…) —
/// vanity display name when it's route-safe, the immutable id otherwise. Same
/// rule as the hub's own Share button.
void stoopCopyCreatorLink(
  BuildContext context, {
  required String id,
  required String displayName,
}) {
  final ref = RegExp(r'^[\w-]{2,40}$').hasMatch(displayName) ? displayName : id;
  Clipboard.setData(
    ClipboardData(text: 'https://hub.frontporchai.app/creator/$ref'),
  );
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Link copied — paste it anywhere.')),
  );
}
