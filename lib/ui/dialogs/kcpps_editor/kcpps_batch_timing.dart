// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'kcpps_editor_controller.dart';
import 'kcpps_editor_style.dart';

/// Under the batch field: whether the batch was measured on this card, and
/// "Time batch sizes", which tries the sizes that fit and keeps the fastest
/// in the preset being edited.
class KcppsBatchTiming extends StatelessWidget {
  const KcppsBatchTiming({super.key, required this.c});

  final KcppsEditorController c;

  @override
  Widget build(BuildContext context) {
    final faint = AppColors.slateFaintOf(context);
    final busy = c.batchTiming || c.mmqTiming;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          koboldMeasuredWords(
            c.config,
            card: c.hardware.hardwareInfo?.gpuName ?? '',
            backend: c.backendChoice.label,
          ),
          key: const ValueKey('kcpps-batch-measured'),
          style: keText(context, size: 12, color: faint),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            KeButton(
              c.batchTiming ? 'Timing…' : 'Time batch sizes',
              key: const ValueKey('kcpps-time-batch'),
              kind: KeButtonKind.amberOutline,
              height: 36,
              padding: 12,
              fontSize: 13,
              onPressed:
                  busy || c.draft.modelPath.isEmpty || !c.canWrite || !c.hasCard
                  ? null
                  : c.timeBatch,
            ),
            if (c.batchStatus case final status?)
              Text(status, style: keText(context, size: 12, color: faint)),
          ],
        ),
      ],
    );
  }
}
