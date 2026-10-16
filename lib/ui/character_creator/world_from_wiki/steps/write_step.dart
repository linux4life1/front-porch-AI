// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

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
                CircularProgressIndicator(color: StudioColors.amberOf(context)),
              const SizedBox(height: 24),
              Text(
                state.status.isEmpty ? 'Writing lorebook cards…' : state.status,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: StudioColors.inkOf(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$done of $n cards. Nothing is saved until Preview.',
                textAlign: TextAlign.center,
                style: TextStyle(color: StudioColors.proseOf(context)),
              ),
              if (state.error != null) ...[
                const SizedBox(height: 16),
                Text(
                  state.error!,
                  style: TextStyle(color: StudioColors.honeyOf(context)),
                ),
              ],
              if (state.writing || state.engine?.aborted == true) ...[
                const SizedBox(height: 24),
                // Stop: the outlined action's shape in `bad`.
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    key: const Key('world-from-wiki-stop'),
                    onPressed: state.writing ? state.abortWrite : null,
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text(
                      'Stop',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: StudioColors.badOf(context),
                      side: BorderSide(
                        color: StudioColors.badOf(context),
                        width: 1.5,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
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
