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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/model_settings_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Surface a generation failure with a way out: red snackbar with the plain
/// message, plus a "Set Up AI" action into [ModelSettingsDialog] when the
/// failure is the AI backend being unavailable ([LlmUnavailableException]
/// already carries a user-facing message). Story pages call this from every
/// pipeline catch instead of hand-rolling `SnackBar(Text('Error: $e'))`.
void showAiErrorSnackBar(BuildContext context, Object error) {
  final isEngineDown = error is LlmUnavailableException;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(isEngineDown ? '$error' : 'Error: $error'),
      backgroundColor: AppColors.negativeAccentOf(context),
      duration: const Duration(seconds: 6),
      action: isEngineDown
          ? SnackBarAction(
              label: 'Set Up AI',
              textColor: AppColors.porchHoney,
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const ModelSettingsDialog(),
              ),
            )
          : null,
    ),
  );
}
