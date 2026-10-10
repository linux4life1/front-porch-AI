// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/rag_engine_card.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Shown under the group's memory switch whenever the memory engine is not
/// running (model missing, downloading, starting, or failed to start): the
/// switch alone would look like it works while every search is skipped.
/// Reuses the sidebar's engine card for the one-tap download, its progress
/// bar, and Retry.
class GroupRagModelNote extends StatefulWidget {
  const GroupRagModelNote({super.key});

  @override
  State<GroupRagModelNote> createState() => _GroupRagModelNoteState();
}

class _GroupRagModelNoteState extends State<GroupRagModelNote> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final emb = Provider.of<EmbeddingService>(context);
    // A group has no sidebar memory panel to load a model that is already
    // on disk, so start it here (else "Starting…" would never move). A
    // missing model is never downloaded without the Download tap.
    if (emb.isAvailable || !emb.modelOnDisk) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !emb.isAvailable && emb.modelOnDisk) emb.ensureReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    final emb = Provider.of<EmbeddingService>(context);
    if (emb.isAvailable) return const SizedBox.shrink();
    final missing = !emb.modelOnDisk;
    final failed = emb.setupError != null || emb.lastEngineError != null;
    final warning = emb.isSettingUp
        ? null
        : missing
        ? 'Memory search needs a memory model, and none is installed, so '
              'this does nothing yet.'
        : failed
        ? 'Memory search isn\'t running: the memory model is installed but '
              'didn\'t start, so this does nothing until it does.'
        : null;
    final amber = AppColors.porchAmberOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (warning != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 14, color: amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      warning,
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
