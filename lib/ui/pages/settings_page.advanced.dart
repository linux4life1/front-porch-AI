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

/// Advanced tab shell (storage, web server, database maintenance) for
/// [_SettingsPageState]. The Hardware/GPU and Advanced-Launch blocks live in
/// their own `part of` files. Extracted from the inline _buildAdvancedTab;
/// direct state access preserves behavior. AppColors + warm-porch accents.
extension _SettingsAdvancedTab on _SettingsPageState {
  Widget _buildAdvancedTab(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final hardwareService = Provider.of<HardwareService>(context);
    final llmProvider = Provider.of<LLMProvider>(context);
    final theme = Theme.of(context);
    final isPresetActive =
        storageService.activeKcppsPath != null &&
        storageService.activeKcppsPath!.isNotEmpty;

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

  Widget _buildWebServerSection(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer2<StorageService, WebServerHost>(
      builder: (context, storage, webServer, _) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        webServer.isRunning
                            ? Icons.wifi_tethering
                            : Icons.wifi_tethering_off,
                        color: webServer.isRunning
                            ? AppColors.bondHighOf(context)
                            : AppColors.textTertiary(context),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Enable Web Server',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Switch(
                    value: storage.webServerEnabled,
                    activeTrackColor: AppColors.porchAmberOf(context),
                    onChanged: (val) async {
                      await storage.setWebServerEnabled(val);
                      if (val) {
                        // startSafely reverts + disables on failure so a
                        // bad start can never leave the app in a launch
                        // crash loop.
                        final ok = await webServer.startSafely(
                          storage.webServerPort,
                        );
                        if (!context.mounted) return;
                        if (ok) {
                          // Guide the user through how they'll reach it.
                          await WebAccessSetupDialog.show(context);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Web server failed to start and was '
                                'turned off.',
                              ),
                            ),
                          );
                        }
                      } else {
                        await webServer.stop();
                      }
                    },
                  ),
                ],
              ),
              if (storage.webServerEnabled) ...[
                Divider(color: AppColors.borderOf(context)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Port', style: theme.textTheme.bodySmall),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 120,
                            child: TextFormField(
                              initialValue: storage.webServerPort.toString(),
                              keyboardType: TextInputType.number,
                              style: TextStyle(
                                color: AppColors.textPrimary(context),
                                fontSize: 13,
                              ),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: theme.scaffoldBackgroundColor,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              onFieldSubmitted: (val) async {
                                final port = int.tryParse(val) ?? 8085;
                                await storage.setWebServerPort(port);
                                if (webServer.isRunning) {
                                  await webServer.stop();
                                  await webServer.start(port);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Login', style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                if (webServer.auth case final auth?)
                  WebLoginSection(
                    // Rebuild after a reset from the web side too.
                    key: ValueKey(webServer.isRunning),
                    auth: auth,
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Status', style: theme.textTheme.bodySmall),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: webServer.isRunning
                                      ? AppColors.bondHighOf(context)
                                      : AppColors.negativeAccentOf(context),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                webServer.isRunning ? 'Running' : 'Stopped',
                                style: TextStyle(
                                  color: webServer.isRunning
                                      ? AppColors.bondHighOf(context)
                                      : AppColors.negativeAccentOf(context),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (webServer.lanIp != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.porchAmberOf(
                        context,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.porchAmberOf(
                          context,
                        ).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.language,
                          color: AppColors.porchAmberOf(context),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            'http://${webServer.lanIp}:${storage.webServerPort}',
                            style: TextStyle(
                              color: AppColors.porchAmberOf(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (webServer.hasActiveClient) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.porchHoneyOf(
                        context,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.porchHoneyOf(
                          context,
                        ).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.devices,
                          color: AppColors.porchHoneyOf(context),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Client connected: ${webServer.connectedClientIp ?? "Unknown"}',
                            style: TextStyle(
                              color: AppColors.porchHoneyOf(context),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
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
