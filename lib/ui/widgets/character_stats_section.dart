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
import 'package:intl/intl.dart';

import 'package:front_porch_ai/services/character_stats.dart';
import 'package:front_porch_ai/services/database_rebind.dart' show liveDatabase;
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// "Your chats together": counts from a character's 1:1 chats.
///
/// Shows nothing for a character that has never been chatted with (or has
/// no library id yet). [wrap] puts the content in the host page's own card.
class CharacterStatsSection extends StatefulWidget {
  final String? characterId;
  final Widget Function(Widget content) wrap;
  final Future<CharacterStats> Function(String characterId)? load;

  const CharacterStatsSection({
    super.key,
    required this.characterId,
    required this.wrap,
    this.load,
  });

  @override
  State<CharacterStatsSection> createState() => _CharacterStatsSectionState();
}

class _CharacterStatsSectionState extends State<CharacterStatsSection> {
  Future<CharacterStats>? _stats;

  @override
  void initState() {
    super.initState();
    final id = widget.characterId;
    if (id == null || id.isEmpty) return;
    _stats = (widget.load ?? _loadFromLibrary)(id);
  }

  /// Reads the library the page already has ([liveDatabase]), never by
  /// opening the startup singleton, whose first open reads SharedPreferences
  /// and the documents folder on its own. A read that fails is logged and
  /// leaves the section empty, as for a character never chatted with.
  Future<CharacterStats> _loadFromLibrary(String id) async {
    try {
      return await loadCharacterStats(liveDatabase(context), id);
    } catch (e, st) {
      debugPrint('[character stats] load failed: $e\n$st');
      return const CharacterStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    final future = _stats;
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<CharacterStats>(
      future: future,
      builder: (context, snap) {
        final stats = snap.data;
        if (stats == null || stats.isEmpty) return const SizedBox.shrink();
        return widget.wrap(_StatsGrid(stats: stats));
      },
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final CharacterStats stats;

  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final n = NumberFormat.decimalPattern();
    final d = DateFormat.yMMMd();
    final tiles = <(String, String)>[
      ('Chats', n.format(stats.chats)),
      ('Their messages', n.format(stats.theirMessages)),
      ('Your messages', n.format(stats.yourMessages)),
      ('Their words', n.format(stats.theirWords)),
      ('Your words', n.format(stats.yourWords)),
      ('Longest chat', '${n.format(stats.longestChat)} messages'),
      if (stats.firstChat != null) ('First chat', d.format(stats.firstChat!)),
      if (stats.lastChat != null) ('Last chat', d.format(stats.lastChat!)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (label, value) in tiles)
              _StatTile(label: label, value: value),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'From your 1:1 chats. Group chats are not counted.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
