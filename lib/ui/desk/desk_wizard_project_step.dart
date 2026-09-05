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

/// In-app disk walker. Not the OS folder picker.
class DeskWizardProjectStep extends StatelessWidget {
  const DeskWizardProjectStep({
    super.key,
    required this.listing,
    required this.loading,
    required this.folderConfirmed,
    required this.onOpen,
    required this.onUseThisFolder,
  });

  final DeskFolderListing? listing;
  final bool loading;
  final bool folderConfirmed;
  final ValueChanged<String> onOpen;
  final VoidCallback onUseThisFolder;

  @override
  Widget build(BuildContext context) {
    final listing = this.listing;
    final amber = AppColors.porchAmberOf(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Project folder',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            listing?.path ?? '…',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          if (listing != null && listing.projectHints.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Looks like a project: ${listing.projectHints.join(', ')}',
              style: TextStyle(color: amber, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (listing == null)
            Text(
              'Could not list this folder.',
              style: TextStyle(color: AppColors.textSecondary(context)),
            )
          else
            Expanded(
              child: ListView(
                children: [
                  if (listing.parentPath != null)
                    ListTile(
                      leading: Icon(
                        Icons.arrow_upward,
                        color: AppColors.iconSecondary(context),
                      ),
                      title: const Text('..'),
                      onTap: () => onOpen(listing.parentPath!),
                    ),
                  for (final dir in listing.directories)
                    ListTile(
                      leading: Icon(Icons.folder, color: amber),
                      title: Text(dir.name),
                      onTap: () => onOpen(dir.path),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            key: const Key('desk-use-folder'),
            onPressed: listing == null ? null : onUseThisFolder,
            icon: Icon(
              folderConfirmed ? Icons.check : Icons.folder_open,
              size: 18,
            ),
            label: Text(
              folderConfirmed ? 'Using this folder' : 'Use this folder',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: amber,
              foregroundColor: AppColors.onChaosAccent,
            ),
          ),
        ],
      ),
    );
  }
}
