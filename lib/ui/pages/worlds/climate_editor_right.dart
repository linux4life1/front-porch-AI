// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/pages/worlds/climate_editor_widgets.dart';
import 'package:front_porch_ai/ui/pages/worlds/climate_preview_panel.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

class ClimateEditorRightColumn extends StatelessWidget {
  const ClimateEditorRightColumn({
    super.key,
    required this.preview,
    required this.biome,
    required this.fahrenheit,
    required this.errors,
    required this.onRefresh,
  });

  final BiomePreview? preview;
  final Biome biome;
  final bool fahrenheit;
  final List<String> errors;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    // The preview already lists its own errors; repeat only the rest (a
    // rename with no danger level, or numbers changed since the refresh).
    final listed = {
      for (final e in preview?.errors ?? const <String>[])
        displayUnitError(e, fahrenheit),
    };
    final unlisted = [
      for (final e in errors)
        if (!listed.contains(e)) e,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Runs the real weather engine over your numbers.',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.porchAmberOf(context),
                side: BorderSide(
                  color: AppColors.porchAmberOf(context).withValues(alpha: 0.6),
                ),
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: onRefresh,
              child: const Text('Refresh preview'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (preview != null)
          ClimatePreviewPanel(
            preview: preview!,
            biome: biome,
            fahrenheit: fahrenheit,
          ),
        if (unlisted.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final e in unlisted)
            Container(
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: kClimateDanger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '⛔ $e',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: StatusColors.noticeDangerOf(context),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
