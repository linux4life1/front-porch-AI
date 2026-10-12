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

/// "Memories:" dropdown choosing whose journal marks the calendar.
class CalendarOwnerPicker extends StatelessWidget {
  final List<ChatParticipant> owners;
  final String? ownerId;
  final ValueChanged<String> onChanged;

  const CalendarOwnerPicker({
    super.key,
    required this.owners,
    required this.ownerId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Memories: ',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: owners.any((p) => p.id == ownerId)
                ? ownerId
                : owners.first.id,
            isDense: true,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary(context),
            ),
            dropdownColor: AppColors.surfaceContainerOf(context),
            items: [
              for (final p in owners)
                DropdownMenuItem<String>(value: p.id, child: Text(p.name)),
            ],
            onChanged: (id) {
              if (id == null) return;
              onChanged(id);
            },
          ),
        ),
      ],
    );
  }
}
