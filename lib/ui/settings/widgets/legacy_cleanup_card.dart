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

import 'package:front_porch_ai/services/legacy_model_cleanup.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/settings/widgets/section_header.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';

/// One-time cleanup offer for model files only the retired Python engines
/// could read (old Whisper CT2 exports, the legacy Kokoro pair, rhasspy
/// Piper .onnx voices). Renders NOTHING when there is nothing to reclaim,
/// so fresh installs never see it — per the sidecar-retirement playbook,
/// user downloads are never deleted silently, only offered with sizes.
class LegacyCleanupCard extends StatefulWidget {
  const LegacyCleanupCard({super.key});

  @override
  State<LegacyCleanupCard> createState() => _LegacyCleanupCardState();
}

class _LegacyCleanupCardState extends State<LegacyCleanupCard> {
  List<LegacyModelGroup>? _groups;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    Future(_scan);
  }

  Future<void> _scan() async {
    final root = context.read<StorageService>().rootPath;
    if (root == null) return;
    final groups = await LegacyModelCleanup.scan(root);
    if (mounted) setState(() => _groups = groups);
  }

  Future<void> _confirmAndReclaim() async {
    final groups = _groups;
    final root = context.read<StorageService>().rootPath;
    if (groups == null || groups.isEmpty || root == null) return;
    final total = groups.fold(0, (sum, g) => sum + g.bytes);

    final confirmed = await showWarmDialog<bool>(
      context,
      title: 'Reclaim disk space?',
      icon: Icons.cleaning_services_outlined,
      destructive: true,
      content: Text(
        'This permanently deletes '
        '${LegacyModelCleanup.formatBytes(total)} of model files that '
        'only the old speech engines could use. Your voices and settings '
        'are unaffected — the new engines have their own models.',
        style: TextStyle(
          color: AppColors.textSecondary(context),
          fontSize: 13,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.formMasterAccent,
            foregroundColor: AppColors.onChaosAccent,
          ),
          child: const Text('Delete old models'),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    setState(() => _working = true);
    final freed = await LegacyModelCleanup.reclaim(root);
    if (!mounted) return;
    setState(() => _working = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Freed ${LegacyModelCleanup.formatBytes(freed)} of disk space',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
    await _scan();
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    if (groups == null || groups.isEmpty) return const SizedBox.shrink();
    final total = groups.fold(0, (sum, g) => sum + g.bytes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const SectionHeader('Reclaim Disk Space'),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The new built-in speech engines use their own models. '
                'These files from the old engines are no longer used:',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              for (final g in groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${g.label} — '
                    '${LegacyModelCleanup.formatBytes(g.bytes)}',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 13,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: _working ? null : _confirmAndReclaim,
                  icon: _working
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onChaosAccent,
                          ),
                        )
                      : const Icon(Icons.cleaning_services_outlined, size: 16),
                  label: Text(
                    'Reclaim ${LegacyModelCleanup.formatBytes(total)}',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.formMasterAccent,
                    foregroundColor: AppColors.onChaosAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
