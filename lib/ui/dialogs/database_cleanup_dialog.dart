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
import 'package:front_porch_ai/database/database_cleanup.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class DatabaseCleanupDialog extends StatefulWidget {
  const DatabaseCleanupDialog({super.key});

  @override
  State<DatabaseCleanupDialog> createState() => _DatabaseCleanupDialogState();
}

class _DatabaseCleanupDialogState extends State<DatabaseCleanupDialog> {
  OrphanReport? _report;
  bool _scanning = true;
  bool _cleaning = false;

  @override
  void initState() {
    super.initState();
    _runScan();
  }

  Future<void> _runScan() async {
    setState(() {
      _scanning = true;
      _report = null;
    });
    try {
      final db = liveDatabase(context);
      final report = await DatabaseCleanup.checkOrphans(db);
      if (!mounted) return;
      setState(() {
        _report = report;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
    }
  }

  Future<void> _runCleanAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundOf(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Cleanup'),
        content: const Text(
          'This will permanently delete orphaned records and fix broken '
          'cross-references. This action cannot be undone.\n\n'
          'Proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Clean Up',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cleaning = true);
    try {
      final db = liveDatabase(context);
      await DatabaseCleanup.cleanOrphans(db);
      if (!mounted) return;
      setState(() => _cleaning = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cleanup complete')));
      await _runScan();
    } catch (e) {
      if (!mounted) return;
      setState(() => _cleaning = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cleanup failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: AppColors.backgroundOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [_buildHeader(theme), _buildBody(theme)],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cleaning_services,
            color: AppColors.formAccentOf(context),
            size: 22,
          ),
          const SizedBox(width: 10),
          Text(
            'Database Cleanup',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          if (_cleaning) ...[
            const SizedBox(width: 12),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
          const Spacer(),
          IconButton(
            icon: Icon(
              Icons.close,
              color: AppColors.iconSecondary(context),
              size: 20,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_scanning) {
      return Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Scanning for orphaned data...',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ],
        ),
      );
    }

    final report = _report;
    if (report == null) {
      return Padding(
        padding: const EdgeInsets.all(48),
        child: Text(
          'Scan failed. Close and try again.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }

    final total = report.totalOrphans + report.totalBrokenRefs;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary line
          Text(
            total > 0
                ? 'Found $total item${total == 1 ? '' : 's'} needing attention:'
                : 'Database is clean — no orphaned records found.',
            style: TextStyle(
              color: total > 0 ? Colors.orangeAccent : Colors.greenAccent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          // Orphan rows section
          ..._buildOrphanCategoryList(theme, report),
          Divider(color: AppColors.borderOf(context), height: 16),
          // Broken refs section
          ..._buildBrokenRefCategoryList(theme, report),
          const SizedBox(height: 16),
          // Clean All button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: Text('Clean All ($total item${total == 1 ? '' : 's'})'),
              onPressed: (!_cleaning && total > 0) ? _runCleanAll : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.formAccentOf(context),
                foregroundColor: AppColors.onAccentOf(context),
                disabledBackgroundColor: AppColors.surfaceContainerOf(context),
                disabledForegroundColor: AppColors.textTertiary(context),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Bottom actions
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Re-scan'),
                onPressed: _scanning || _cleaning ? null : _runScan,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _orphanCategories = [
    _Category('avatar_images', 'Orphaned avatar images', Icons.image),
    _Category('objectives', 'Orphaned objectives', Icons.flag),
    _Category('data_bank_entries', 'Orphaned data bank entries', Icons.storage),
    _Category(
      'message_embeddings',
      'Orphaned message embeddings',
      Icons.memory,
    ),
    _Category('sessions', 'Orphaned sessions', Icons.chat),
    _Category(
      'group_orphan_sessions',
      'Orphaned group sessions',
      Icons.group_work,
    ),
    _Category('messages', 'Orphaned messages', Icons.message),
  ];

  static const _refCategories = [
    _Category('memory_sources', 'Broken memory source refs', Icons.link_off),
    _Category(
      'group_character_ids',
      'Broken group character refs',
      Icons.group,
    ),
    _Category('group_world_refs', 'Broken group world refs', Icons.public),
  ];

  List<Widget> _buildOrphanCategoryList(ThemeData theme, OrphanReport report) {
    final items = <Widget>[];
    for (final cat in _orphanCategories) {
      final count = report.orphanCounts[cat.key] ?? 0;
      items.add(_buildCategoryRow(theme, cat, count));
    }
    return items;
  }

  List<Widget> _buildBrokenRefCategoryList(
    ThemeData theme,
    OrphanReport report,
  ) {
    final items = <Widget>[];
    for (final cat in _refCategories) {
      final count = report.brokenRefCounts[cat.key] ?? 0;
      items.add(_buildCategoryRow(theme, cat, count));
    }
    return items;
  }

  Widget _buildCategoryRow(ThemeData theme, _Category cat, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(cat.icon, size: 18, color: AppColors.iconSecondary(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              cat.label,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary(context),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: count > 0
                  ? Colors.orangeAccent.withValues(alpha: 0.15)
                  : AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: count > 0
                    ? Colors.orangeAccent
                    : AppColors.textTertiary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Category {
  final String key;
  final String label;
  final IconData icon;
  const _Category(this.key, this.label, this.icon);
}
