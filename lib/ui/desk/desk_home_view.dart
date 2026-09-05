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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/desk/desk_wizard_page.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Third home pane — sibling of Chats and Porch Stories. Sit down opens
/// the Project → Coworker → Sit down wizard. Separate pipeline from chat.
class DeskHomeView extends StatelessWidget {
  const DeskHomeView({super.key, this.onSitDown});

  /// Test seam. Production navigates to [DeskWizardPage].
  final VoidCallback? onSitDown;

  void _openWizard(BuildContext context) {
    var local = false;
    var label = '';
    try {
      final llm = Provider.of<LLMProvider>(context, listen: false);
      local = llm.isLocal;
      label = local ? 'local Kobold' : 'remote';
    } catch (_) {}
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            DeskWizardPage(isLocalBackend: local, backendLabel: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.porchAmberOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.desk, size: 72, color: amber.withValues(alpha: 0.4)),
            const SizedBox(height: 24),
            Text(
              'Desk',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pick a throwaway folder and a coworker. She codes in character.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              key: const Key('desk-sit-down'),
              onPressed: onSitDown ?? () => _openWizard(context),
              icon: const Icon(Icons.chair_alt, size: 20),
              label: const Text('Sit down'),
              style: ElevatedButton.styleFrom(
                backgroundColor: amber,
                foregroundColor: AppColors.onChaosAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
