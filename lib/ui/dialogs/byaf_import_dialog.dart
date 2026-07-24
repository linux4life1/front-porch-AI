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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/byaf_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Result from the BYAF import dialog.
class ByafImportResult {
  final bool confirmed;
  final bool importChatHistory;
  final bool applySettings;
  ByafImportResult({
    required this.confirmed,
    required this.importChatHistory,
    this.applySettings = false,
  });
}

/// Dialog to preview and confirm import of a .byaf character file.
class ByafImportDialog extends StatefulWidget {
  final ByafImportPreview preview;

  const ByafImportDialog({super.key, required this.preview});

  @override
  State<ByafImportDialog> createState() => _ByafImportDialogState();
}

class _ByafImportDialogState extends State<ByafImportDialog> {
  bool _importChat = true;
  bool _applySettings = true;

  ByafImportResult get _cancelResult =>
      ByafImportResult(confirmed: false, importChatHistory: false);

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;

    return Dialog(
      backgroundColor: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  Icons.archive_outlined,
                  color: AppColors.formMasterAccent,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Import Backyard AI Character',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: AppColors.iconSecondary(context),
                  ),
                  onPressed: () => Navigator.pop(context, _cancelResult),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: AppColors.borderOf(context), height: 1),
            const SizedBox(height: 16),

            // Content - scrollable
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Character info row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Avatar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 100,
                            height: 100,
                            color: AppColors.surfaceContainerOf(context),
                            child: preview.extractedImagePath != null
                                ? Image.file(
                                    File(preview.extractedImagePath!),
                                    fit: BoxFit.cover,
                                    alignment: Alignment.topCenter,
                                    errorBuilder: (_, _, _) => Icon(
                                      Icons.person,
                                      color: AppColors.iconSecondary(context),
                                      size: 48,
                                    ),
                                  )
                                : Icon(
                                    Icons.person,
                                    color: AppColors.iconSecondary(context),
                                    size: 48,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Name + stats
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                preview.name,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary(context),
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildInfoChip(
                                Icons.auto_stories,
                                '${preview.persona.length} chars persona',
                              ),
                              if (preview.loreItems.isNotEmpty)
                                _buildInfoChip(
                                  Icons.book,
                                  '${preview.loreItems.length} lore items',
                                ),
                              if (preview.exampleMessages.isNotEmpty)
                                _buildInfoChip(
                                  Icons.format_quote,
                                  '${preview.exampleMessages.length} example '
                                  'dialogue entries',
                                ),
                              if (preview.messages.isNotEmpty)
                                _buildInfoChip(
                                  Icons.chat,
                                  '${preview.messages.length} chat messages',
                                ),
                              if (preview.firstMessage != null &&
                                  preview.firstMessage!.isNotEmpty)
                                _buildInfoChip(
                                  Icons.chat_bubble_outline,
                                  'Has greeting',
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Persona preview
                    if (preview.persona.isNotEmpty) ...[
                      const Text(
                        'Persona',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.formMasterAccent,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildTextPreview(
                        preview.persona.length > 400
                            ? '${preview.persona.substring(0, 400)}…'
                            : preview.persona,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // First message preview
                    if (preview.firstMessage != null &&
                        preview.firstMessage!.isNotEmpty) ...[
                      const Text(
                        'First Message',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.formMasterAccent,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _buildTextPreview(
                        preview.firstMessage!.length > 300
                            ? '${preview.firstMessage!.substring(0, 300)}…'
                            : preview.firstMessage!,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Backyard model settings + apply toggle
                    if (preview.modelSettings.isNotEmpty) ...[
                      _buildToggleTile(
                        value: _applySettings,
                        onChanged: (v) =>
                            setState(() => _applySettings = v ?? true),
                        title: 'Apply Backyard settings',
                        subtitle:
                            'Uses these sampler values for the imported chat '
                            'so responses feel like they did in Backyard AI',
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: preview.modelSettings.entries
                            .map(
                              (e) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerOf(context),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${e.key}: ${e.value.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: AppColors.textTertiary(context),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Chat history import toggle
                    if (preview.messages.isNotEmpty)
                      _buildToggleTile(
                        value: _importChat,
                        onChanged: (v) =>
                            setState(() => _importChat = v ?? true),
                        title:
                            'Import chat history '
                            '(${preview.messages.length} messages)',
                        subtitle:
                            'Creates a chat session with the imported messages',
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, _cancelResult),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textTertiary(context)),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    ByafImportResult(
                      confirmed: true,
                      importChatHistory: _importChat,
                      applySettings: _applySettings,
                    ),
                  ),
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Import Character'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.formMasterAccent,
                    foregroundColor: AppColors.onChaosAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.iconSecondary(context)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextPreview(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundOf(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 12,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildToggleTile({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.formMasterAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.formMasterAccent.withValues(alpha: 0.3),
        ),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged,
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.formMasterAccent,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
          ),
        ),
        activeColor: AppColors.formMasterAccent,
        checkColor: AppColors.onChaosAccent,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        dense: true,
      ),
    );
  }
}
