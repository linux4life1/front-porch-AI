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

import 'package:front_porch_ai/services/chat/ambition_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Sidebar Ambitions rows (Living Time §6) — 🧭 text, stage word, and a thin
/// stage bar per ambition, visible from the FIRST frame of a fresh chat so
/// the system is never invisible (smoke-test feedback 2026-07-21: lazily
/// created progress cards meant zero UI until the first tick). Purely
/// presentational — values arrive from ChatService.ambitionsFor via the
/// parent (the plain-values bridge every Character State widget uses);
/// meters are fine in UI, the words-only rule is for prompts.
class AmbitionsRow extends StatelessWidget {
  final List<({String text, int progress})> ambitions;

  const AmbitionsRow({super.key, required this.ambitions});

  @override
  Widget build(BuildContext context) {
    if (ambitions.isEmpty) return const SizedBox.shrink();
    final amber = AppColors.porchAmberOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ambitions',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 4),
        for (final a in ambitions)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Tooltip(
              message:
                  '${a.text} — ${AmbitionService.stageWord(a.progress)}.\n'
                  'Progress moves when quests that serve it complete.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('🧭', style: TextStyle(fontSize: 11)),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          a.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        AmbitionService.stageWord(a.progress),
                        style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: a.progress >= 100
                              ? amber
                              : AppColors.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: a.progress.clamp(0, 100) / 100,
                      minHeight: 3,
                      backgroundColor: AppColors.borderOf(
                        context,
                      ).withValues(alpha: 0.25),
                      valueColor: AlwaysStoppedAnimation<Color>(amber),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
