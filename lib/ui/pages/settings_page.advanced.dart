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

part of 'settings_page.dart';

/// Advanced tab: storage path and database cleanup.
/// Web server start/port live in settings_page.advanced.web.dart.
extension _SettingsAdvancedTab on _SettingsPageState {
  Widget _buildAdvancedTab(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final hardwareService = Provider.of<HardwareService>(context);
    final llmProvider = Provider.of<LLMProvider>(context);
    final theme = Theme.of(context);
    final isPresetActive =
        storageService.backendSettings.activeKcppsPath != null &&
        storageService.backendSettings.activeKcppsPath!.isNotEmpty;

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
                  onPressed: _pickStoragePath,
                  tooltip: 'Change Data Directory',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader('Web Server'),
          const SizedBox(height: 8),
          _buildWebServerSection(context),
          const SizedBox(height: 24),
          _buildHardwareGpuSection(
            context,
            storageService,
            hardwareService,
            llmProvider,
            isPresetActive,
          ),
          const SizedBox(height: 24),
          _buildAdvancedLaunchOptions(context, storageService),
          const SizedBox(height: 24),
          _buildDatabaseMaintenanceSection(context, storageService),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDatabaseMaintenanceSection(
    BuildContext context,
    StorageService storageService,
  ) {
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
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => const DatabaseCleanupDialog(),
                      );
                    },
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

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required BuildContext context,
    bool isNumber = false,
  }) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: theme.textTheme.bodySmall?.color),
        filled: true,
        fillColor: AppColors.cardOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
