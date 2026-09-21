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
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The Notifications tab of the Stoop inbox: automated decision notices
/// (card approved / needs changes), newest first — kept separate from the
/// human moderator conversation, mirroring the web hub.
class StoopNotificationsTab extends StatelessWidget {
  /// SYSTEM-kind messages only, oldest first (as the API returns them).
  final List<StoopMessage> notices;
  const StoopNotificationsTab({super.key, required this.notices});

  @override
  Widget build(BuildContext context) {
    if (notices.isEmpty) {
      return stoopEmpty(
        context,
        glyph: '📣',
        title: 'No notifications yet',
        body:
            'Approvals and review notes for your shared characters land '
            'here automatically.',
      );
    }
    final newestFirst = notices.reversed.toList();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: newestFirst.length,
      itemBuilder: (_, i) => _NoticeCard(notice: newestFirst[i]),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final StoopMessage notice;
  const _NoticeCard({required this.notice});

  @override
  Widget build(BuildContext context) {
    // The server writes fixed templates for decisions; classify for the icon
    // and accent only — unknown phrasing just renders neutral.
    final body = notice.body;
    final approved =
        body.contains('approved and') || body.contains('is approved');
    final rejected =
        body.contains('wasn’t approved') || body.contains("wasn't approved");
    final accent = approved
        ? stoopTealText(context)
        : rejected
        ? stoopEmberText(context)
        : stoopDusk(context);
    final edge = approved
        ? AppColors.stoopTeal
        : rejected
        ? AppColors.stoopEmber
        : stoopDusk(context);
    // Flutter will not paint a rounded BoxDecoration whose BorderSide
    // colors differ (left accent vs hairline). The card laid out and
    // then failed in paint(), which is the empty-bar screenshot.
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: stoopCard(context),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: stoopBorder(context)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: edge),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        approved
                            ? Icons.check_circle_outline
                            : rejected
                            ? Icons.edit_note
                            : Icons.campaign_outlined,
                        size: 20,
                        color: accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              body,
                              style: TextStyle(
                                color: stoopCream2(context),
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (notice.character != null) ...[
                                  Flexible(
                                    child: Text(
                                      're: ${notice.character!.name}',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: accent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Text(
                                  _timeAgo(notice.createdAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: stoopFaint(context),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
