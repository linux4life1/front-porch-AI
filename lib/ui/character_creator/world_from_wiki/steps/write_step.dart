// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class WorldFromWikiWriteStep extends StatelessWidget {
  const WorldFromWikiWriteStep({super.key, required this.state});

  final WorldFromWikiState state;

  @override
  Widget build(BuildContext context) {
    final n = state.signed.length;
    final done = state.entries.length;
    return Center(
      key: const ValueKey('world-write'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.writing)
                CircularProgressIndicator(
                  color: AppColors.porchAmberOf(context),
                ),
              const SizedBox(height: 24),
              Text(
                state.status.isEmpty ? 'Writing lorebook cards…' : state.status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$done of $n cards. Nothing is saved until Preview.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
              if (state.error != null) ...[
                const SizedBox(height: 16),
                Text(
                  state.error!,
                  style: TextStyle(color: AppColors.taskAccentOf(context)),
                ),
              ],
              if (state.writing || state.engine?.aborted == true) ...[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  key: const Key('world-from-wiki-stop'),
                  onPressed: state.writing ? state.abortWrite : null,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('Stop'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.porchAmberOf(context),
                    foregroundColor: AppColors.onChaosAccent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
