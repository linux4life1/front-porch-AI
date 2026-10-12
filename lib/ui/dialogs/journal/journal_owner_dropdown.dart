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

/// Header dropdown that switches the Journal between group members' diaries.
/// Reports the picked member's id through [onChanged].
class JournalOwnerDropdown extends StatelessWidget {
  final List<ChatParticipant> owners;
  final String ownerId;
  final ValueChanged<String> onChanged;

  const JournalOwnerDropdown({
    super.key,
    required this.owners,
    required this.ownerId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // The focused member may not be in the cast anymore (removed mid-dialog);
    // fall back to the first owner so the dropdown always has a valid value.
    final value = owners.any((p) => p.id == ownerId)
        ? ownerId
        : owners.first.id;
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isDense: true,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary(context),
        ),
        dropdownColor: AppColors.surfaceContainerOf(context),
        items: [
          for (final p in owners)
            DropdownMenuItem(value: p.id, child: Text("${p.name}'s Journal")),
        ],
        onChanged: (id) {
          if (id == null) return;
          onChanged(id);
        },
      ),
    );
  }
}
