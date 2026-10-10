// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/rag_engine_card.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Shown under the group's memory switch when the memory model is missing
/// (or downloading): the switch alone would look like it works while every
/// search is skipped. Reuses the sidebar's engine card for the one-tap
/// download, its progress bar and Retry.
class GroupRagModelNote extends StatelessWidget {
  const GroupRagModelNote({super.key});

  @override
  Widget build(BuildContext context) {
    final emb = Provider.of<EmbeddingService>(context);
    if (emb.isAvailable) return const SizedBox.shrink();
    final missing = !emb.modelOnDisk;
    if (!missing && !emb.isSettingUp) return const SizedBox.shrink();
    final amber = AppColors.porchAmberOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (missing && !emb.isSettingUp)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 14, color: amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Memory search needs a memory model, and none is '
                      'installed, so this does nothing yet.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          RagEngineCard(accent: amber),
        ],
      ),
    );
  }
}
