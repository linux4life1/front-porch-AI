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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// What every story screen shows while the pipeline runs: the stage, its
/// message, the token count, and a Stop that ends the run at the next safe
/// point with everything written so far kept.
class StudioRunningOverlay extends StatelessWidget {
  final StoryPipelineService pipeline;

  const StudioRunningOverlay(this.pipeline, {super.key});

  @override
  Widget build(BuildContext context) {
    final stopping = pipeline.stopRequested;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.porchHoneyOf(context),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              pipeline.currentStep,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              pipeline.statusMessage,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            if (pipeline.tokenCount > 0) ...[
              const SizedBox(height: 16),
              Text(
                '${pipeline.tokenCount} tokens generated',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 28),
            OutlinedButton.icon(
              key: const ValueKey('story-stop'),
              onPressed: stopping ? null : pipeline.requestStop,
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: Text(stopping ? 'Stopping…' : 'Stop'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary(context),
                side: BorderSide(color: AppColors.borderOf(context)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Stop finishes the current step and keeps everything written '
              'so far.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
