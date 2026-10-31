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
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// One of the group's own switches in a member's editor, read-only:
/// "Realism Engine · On in this chat", and a link to where the group sets
/// it. A group has one of each; the member never gets a second switch.
class GroupWideLine extends StatelessWidget {
  const GroupWideLine({
    super.key,
    required this.icon,
    required this.text,
    this.linkLabel,
    this.onOpen,
    this.where,
  });

  final IconData icon;
  final String text;

  /// The link's words ("Group Settings"); no link without [onOpen].
  final String? linkLabel;
  final VoidCallback? onOpen;

  /// Where the group sets it, said in words when there is no link to it.
  final String? where;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.iconSecondary(context)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          if ((onOpen == null || linkLabel == null) && where != null)
            Text(
              where!,
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
              ),
            ),
          if (onOpen != null && linkLabel != null)
            TextButton(
              onPressed: onOpen,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.formAccentOf(context),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              child: Text('$linkLabel ›'),
            ),
        ],
      ),
    );
  }
}

/// A short note in a member's editor (why a section is hidden, or what the
/// group does with a tab's settings).
class MemberEditorNote extends StatelessWidget {
  const MemberEditorNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.formAccentOf(context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.formAccentOf(context).withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(color: AppColors.textSecondary(context), fontSize: 12),
      ),
    );
  }
}

/// The group's lines a member's Realism form shows in place of the switches
/// a 1:1 card has: [header] where the master switch and Time & Day are,
/// [chaos] and [afterglow] in Optional Features, and [startNote] under the
/// Relationship heading.
class MemberGroupRows {
  const MemberGroupRows({
    required this.header,
    required this.chaos,
    this.afterglow,
    required this.startNote,
    this.noStartNote,
  });

  final Widget header;
  final Widget chaos;

  /// Null while Porch Life does not allow Afterglow.
  final Widget? afterglow;
  final String startNote;

  /// Shown in the start's place when there is none to set.
  final String? noStartNote;
}
