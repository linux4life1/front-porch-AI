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

/// In-app disk walker. Not the OS folder picker. Hidden folders stay
/// off the list until the user asks — `$HOME` is full of them.
class DeskWizardProjectStep extends StatefulWidget {
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
  State<DeskWizardProjectStep> createState() => _DeskWizardProjectStepState();
}

class _DeskWizardProjectStepState extends State<DeskWizardProjectStep> {
  var _showHidden = false;

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    final amber = AppColors.porchAmberOf(context);
    final honey = AppColors.porchHoneyOf(context);
    final visible = listing?.visible(includeHidden: _showHidden) ?? const [];
    final hiddenCount =
        listing?.directories.where((d) => d.isHidden).length ?? 0;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Project folder',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.textPrimary(context),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'First the folder. Then you pick who sits with you.',
            style: TextStyle(color: honey, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            listing?.path ?? '…',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          if (listing != null && listing.projectHints.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Looks like a project: ${listing.projectHints.join(', ')}',
              style: TextStyle(
                color: amber,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (widget.loading)
            Center(child: CircularProgressIndicator(color: amber))
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
                    _folderTile(
                      context,
                      icon: Icons.arrow_upward,
                      label: '..',
                      onTap: () => widget.onOpen(listing.parentPath!),
                      leadingColor: AppColors.iconSecondary(context),
                    ),
                  for (final dir in visible)
                    _folderTile(
                      context,
                      icon: Icons.folder,
                      label: dir.name,
                      onTap: () => widget.onOpen(dir.path),
                      leadingColor: amber,
                    ),
                ],
              ),
            ),
          if (hiddenCount > 0)
            SwitchListTile(
              key: const Key('desk-show-hidden'),
              value: _showHidden,
              onChanged: (v) => setState(() => _showHidden = v),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                _showHidden
                    ? 'Hide hidden folders'
                    : 'Show $hiddenCount hidden folder${hiddenCount == 1 ? '' : 's'}',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              key: const Key('desk-use-folder'),
              onPressed: listing == null ? null : widget.onUseThisFolder,
              icon: Icon(
                widget.folderConfirmed ? Icons.check : Icons.folder_open,
                size: 18,
              ),
              label: Text(
                widget.folderConfirmed
                    ? 'Using this folder'
                    : 'Use this folder',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.folderConfirmed ? honey : amber,
                foregroundColor: AppColors.onChaosAccent,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _folderTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color leadingColor,
  }) {
    final amber = AppColors.porchAmberOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          onTap: onTap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: amber.withValues(alpha: 0.35)),
          ),
          leading: Icon(icon, color: leadingColor, size: 30),
          title: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: AppColors.porchHoneyOf(context),
          ),
        ),
      ),
    );
  }
}
