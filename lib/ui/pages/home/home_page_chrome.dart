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

import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/ui/pages/character_creator_page.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Home's three views (chats, stories, Waifu Coder) all sit inside the
/// model-load status bar.
class HomeStatusFrame extends StatelessWidget {
  const HomeStatusFrame({super.key, required this.content});

  final Widget content;

  @override
  Widget build(BuildContext context) => KoboldHomeStatus(child: content);
}

/// Toggle row that shrinks instead of overflowing when the window is
/// squeezed. Used on the empty-library and Stories chrome.
class HomeModeToggleBar extends StatelessWidget {
  const HomeModeToggleBar({super.key, required this.toggle});

  final Widget toggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
      child: Row(
        children: [
          Flexible(
            child: Align(alignment: Alignment.centerLeft, child: toggle),
          ),
        ],
      ),
    );
  }
}

/// The "create your first character" panel of an empty library. The import
/// callbacks run on the library view's context, which outlives this panel
/// once the first import lands.
class HomeEmptyLibrary extends StatelessWidget {
  const HomeEmptyLibrary({
    super.key,
    required this.onImportCards,
    required this.onBulkImport,
    required this.onImportByaf,
  });

  final VoidCallback onImportCards;
  final VoidCallback onBulkImport;
  final VoidCallback onImportByaf;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Get started by creating a new character!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(
                  context,
                ).textTheme.titleLarge?.color?.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: () =>
                      Provider.of<AppState>(context, listen: false).setIndex(1),
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Create New'),
                  style: _buttonStyle(context),
                ),
                ElevatedButton.icon(
                  onPressed: onImportCards,
                  icon: const Icon(Icons.download),
                  label: const Text('Import Card'),
                  style: _buttonStyle(context),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CharacterCreatorPage(),
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('AI Create'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.porchAmberOf(context),
                    foregroundColor: AppColors.onChaosAccent,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: onBulkImport,
                  icon: const Icon(Icons.library_add),
                  label: const Text('Bulk Import'),
                  style: _buttonStyle(context),
                ),
                ElevatedButton.icon(
                  onPressed: onImportByaf,
                  icon: const Icon(Icons.archive_outlined),
                  label: const Text('Import BYAF'),
                  style: _buttonStyle(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _buttonStyle(BuildContext context) {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.resolve(
        context,
        Colors.white.withValues(alpha: 0.1),
        Colors.black.withValues(alpha: 0.05),
      ),
      foregroundColor: AppColors.textPrimary(context),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppColors.resolve(context, Colors.white24, Colors.black26),
        ),
      ),
    );
  }
}
