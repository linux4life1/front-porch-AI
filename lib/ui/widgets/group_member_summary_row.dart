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
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/group_member_start.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart';

/// "Close / Trusting · Afterglow on", after a member's name: their start in
/// new chats of the group ([start], null when they start without Realism)
/// and their own Afterglow ([afterglow], null when Porch Life does not allow
/// it).
String groupMemberSummaryDetail({
  GroupMemberStart? start,
  bool? afterglow,
  bool lite = false,
}) => [
  if (lite)
    'Realism starts when promoted'
  else if (start != null)
    '${startLongTermTierName(start.longTerm)} / '
        '${startTrustTierName(start.trust)}',
  if (!lite && afterglow != null) 'Afterglow ${afterglow ? 'on' : 'off'}',
].join(' · ');

/// One member's line where a group lists its members' Realism, with an Edit
/// that opens the member's editor (where every setting of theirs is).
class GroupMemberSummaryRow extends StatelessWidget {
  const GroupMemberSummaryRow({
    super.key,
    required this.name,
    required this.detail,
    this.leading,
    this.onEdit,
    this.below,
  });

  final String name;

  /// [groupMemberSummaryDetail]; empty shows the name alone.
  final String detail;
  final Widget? leading;

  /// Opens the member editor; no button without it.
  final VoidCallback? onEdit;

  /// Live controls that stay on the row (the open chat's own switches).
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Expanded(
                child: Wrap(
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: AppColors.textPrimary(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        ' · $detail',
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              if (onEdit != null)
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('Edit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary(context),
                    side: BorderSide(color: AppColors.borderOf(context)),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
            ],
          ),
          ?below,
        ],
      ),
    );
  }
}
