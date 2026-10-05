// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The home screen's line about the local engine: [status] is its status
/// line (what a load is doing, a note, or why it stopped on its own). The
/// bar under the words moves only while something starts or loads, so a
/// stopped engine's reason never looks like a load still going.
class KoboldStatusBar extends StatelessWidget {
  const KoboldStatusBar({super.key, required this.status, required this.phase});

  final String status;
  final KoboldPhase phase;

  @override
  Widget build(BuildContext context) {
    final loading =
        phase == KoboldPhase.starting || phase == KoboldPhase.loading;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        border: Border(top: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
          if (loading) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 4,
                backgroundColor: AppColors.surfaceContainerOf(context),
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppColors.porchHoneyOf(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
