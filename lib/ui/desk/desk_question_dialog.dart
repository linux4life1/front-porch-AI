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

import 'package:front_porch_ai/services/desk/desk.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class DeskQuestionDialog extends StatelessWidget {
  const DeskQuestionDialog({super.key, required this.request});

  final DeskQuestionRequest request;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return AlertDialog(
      backgroundColor: AppColors.cardOf(context),
      title: Text(
        request.prompt,
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final choice in request.choices)
            ListTile(
              key: Key('desk-question-$choice'),
              title: Text(choice),
              onTap: () => Navigator.pop(context, choice),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: Text(
            'Skip',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        if (request.choices.isEmpty)
          TextButton(
            onPressed: () => Navigator.pop(context, 'ok'),
            child: Text('OK', style: TextStyle(color: amber)),
          ),
      ],
    );
  }
}
