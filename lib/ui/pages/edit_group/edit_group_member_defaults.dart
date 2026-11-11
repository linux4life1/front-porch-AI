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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/identity_chip_lists.dart'
    show afterglowEnabledOf, pocketsEnabledOf;
import 'package:front_porch_ai/ui/widgets/realism_form_section/realism_form_section.dart';

/// One member's defaults for the group's NEW chats, under their line in the
/// Realism & Dynamics tab: Afterglow (with its Recovery block while it is
/// on) and Pockets & Wardrobe. They are flags on the member's own copy and
/// reach nothing that is live: a chat that is open keeps its own switch for
/// the member (docs/design/one-chat-ux.md, ruling 5). Their start, Needs
/// bars and pace are in their editor (Edit).
///
/// A member whose stored extensions could not be read has none here, and
/// writing defaults over them would erase what is stored, so the row only
/// points at Edit.
class EditGroupMemberDefaults extends StatelessWidget {
  const EditGroupMemberDefaults({
    super.key,
    required this.member,
    required this.onChanged,
  });

  final CharacterCard member;
  final ValueChanged<FrontPorchExtensions> onChanged;

  @override
  Widget build(BuildContext context) {
    final ext = member.frontPorchExtensions;
    final hint = TextStyle(
      fontSize: 11,
      color: AppColors.textSecondary(context),
    );
    if (ext == null || member.isLite) return const SizedBox.shrink();
    final afterglowShown = afterglowEnabledOf(context);
    final pocketsAllowed = pocketsEnabledOf(context);
    return Column(
      key: ValueKey('member-defaults-${member.dbId}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (afterglowShown) ...[
          _row(
            context,
            'Afterglow · new chats',
            ext.afterglowEnabled,
            AppColors.lustAccentOf(context),
            (v) => onChanged(ext.copyWith(afterglowEnabled: v)),
          ),
          if (ext.afterglowEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: RecoveryBlock(
                recovery: ext.recovery,
                sex: ext.sex,
                intimateInto: ext.intimateInto,
                intimateNotInto: ext.intimateNotInto,
                onChanged: (r) => onChanged(ext.copyWith(recovery: r)),
              ),
            ),
        ],
        if (pocketsAllowed)
          _row(
            context,
            'Pockets · new chats',
            ext.pocketsEnabled,
            AppColors.porchTerracottaOf(context),
            (v) => onChanged(ext.copyWith(pocketsEnabled: v)),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Pockets & Wardrobe is off in Porch Life; this default waits for it.',
              style: hint,
            ),
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    bool value,
    Color accent,
    ValueChanged<bool> onToggle,
  ) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary(context),
          ),
        ),
      ),
      Switch(
        value: value,
        activeThumbColor: accent,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: onToggle,
      ),
    ],
  );
}
