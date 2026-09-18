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

part of 'group_member_card.dart';

/// Right-click "Edit Group" on the header. Secondary tap stays on the header
/// so expanded children (IconButton, TextButton) do not absorb it.
extension _GroupMemberCardMenu on _GroupMemberCardState {
  void _showEditGroupMenu(TapUpDetails details) {
    final active = widget.chatService.activeGroup;
    if (active == null) return;
    final position = details.globalPosition;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: AppColors.surfaceContainerOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(
              Icons.edit,
              color: AppColors.iconSecondary(context),
              size: 20,
            ),
            title: const Text('Edit Group'),
            dense: true,
          ),
        ),
      ],
    ).then((value) {
      if (value == 'edit' && mounted) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => EditGroupPage(group: active)));
      }
    });
  }
}
