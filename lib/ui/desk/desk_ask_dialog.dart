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

class DeskAskDialog extends StatelessWidget {
  const DeskAskDialog({super.key, required this.request});

  final DeskAskRequest request;

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return AlertDialog(
      backgroundColor: AppColors.cardOf(context),
      title: Text(
        request.doomLoop ? 'Same tool again' : 'Allow this change?',
        style: TextStyle(color: AppColors.textPrimary(context)),
      ),
      content: Text(
        '${request.toolName}: ${request.summary}',
        style: TextStyle(color: AppColors.textSecondary(context)),
      ),
      actions: [
        TextButton(
          key: const Key('desk-ask-deny'),
          onPressed: () => Navigator.pop(context, DeskAskDecision.deny),
          child: Text(
            'Deny',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        TextButton(
          key: const Key('desk-ask-once'),
          onPressed: () => Navigator.pop(context, DeskAskDecision.allowOnce),
          child: Text('Allow once', style: TextStyle(color: amber)),
        ),
        ElevatedButton(
          key: const Key('desk-ask-always'),
          onPressed: () => Navigator.pop(context, DeskAskDecision.allowAlways),
          style: ElevatedButton.styleFrom(
            backgroundColor: amber,
            foregroundColor: AppColors.onChaosAccent,
          ),
          child: const Text('Always this session'),
        ),
      ],
    );
  }
}
