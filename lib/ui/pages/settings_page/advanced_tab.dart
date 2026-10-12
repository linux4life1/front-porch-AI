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
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'package:front_porch_ai/ui/pages/settings_page.launch.dart';
import 'web_server_section.dart';

/// Settings → Advanced: storage path, web server, launch options and
/// database cleanup. The page owns the state that must outlive a tab switch
/// (the port draft, the launch-options expansion) and hands it in.
class SettingsAdvancedTab extends StatelessWidget {
  const SettingsAdvancedTab({
    super.key,
    required this.onPickStoragePath,
    required this.portDraft,
    required this.launchExpanded,
    required this.onToggleLaunchExpanded,
    required this.launchModelExists,
    required this.onRocmChanged,
    required this.onScanAndClean,
  });

  final VoidCallback onPickStoragePath;
  final WebServerPortDraft portDraft;
  final bool launchExpanded;
  final VoidCallback onToggleLaunchExpanded;
  final bool Function(String? path) launchModelExists;
  final VoidCallback onRocmChanged;

  /// Opens the orphaned-data cleanup dialog from the given context.
  final void Function(BuildContext context) onScanAndClean;

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Storage Configuration'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.folder, color: AppColors.porchAmberOf(context)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Data Directory', style: theme.textTheme.bodySmall),
                      Text(
                        storageService.rootPath ?? 'Not set',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.edit, color: theme.iconTheme.color),
                  onPressed: onPickStoragePath,
                  tooltip: 'Change Data Directory',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader('Web Server'),
          const SizedBox(height: 8),
          WebServerSection(portDraft: portDraft),
          const SizedBox(height: 24),
          AdvancedLaunchOptions(
            storage: storageService,
            expanded: launchExpanded,
            onToggleExpanded: onToggleLaunchExpanded,
            launchModelExists: launchModelExists,
            onRocmChanged: onRocmChanged,
          ),
          const SizedBox(height: 24),
          DatabaseMaintenanceSection(onScanAndClean: onScanAndClean),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// The Database Maintenance card: the orphaned-data scan button.
class DatabaseMaintenanceSection extends StatelessWidget {
  const DatabaseMaintenanceSection({super.key, required this.onScanAndClean});

  final void Function(BuildContext context) onScanAndClean;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Database Maintenance'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.cleaning_services,
                    color: AppColors.porchAmberOf(context),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Orphaned Data',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.search, size: 16),
                    label: const Text('Scan & Clean'),
                    onPressed: () => onScanAndClean(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.porchAmberOf(context),
                      foregroundColor: AppColors.onChaosAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Find and remove orphaned avatar images, objectives, data bank '
                'entries, message embeddings, sessions, and messages left behind '
                'after character deletion. Also repairs dangling cross-references '
                'in memory sources and group member lists.',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
