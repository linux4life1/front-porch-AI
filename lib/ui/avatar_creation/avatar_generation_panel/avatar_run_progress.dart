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

import '../avatar_creation_controller.dart';

/// Live progress of a creator run: one line per stage, the pack's count and
/// bar, and the terminal done/failed note with Cancel while running.
class AvatarRunProgress extends StatelessWidget {
  const AvatarRunProgress({super.key, required this.controller});

  final AvatarCreationController controller;

  AvatarCreationController get _c => controller;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (_c.stage == AvatarRunStage.failed) {
      rows.add(
        Text(
          _c.statusDetail,
          style: const TextStyle(color: AppColors.logError, fontSize: 12.5),
        ),
      );
      rows.add(const SizedBox(height: 4));
      rows.add(
        Text(
          'Your character is saved — nothing was lost. Fix the engine and '
          'try again, or add images from the Avatar Gallery later.',
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 11,
          ),
        ),
      );
    } else {
      if (_c.source == PortraitSource.generate) {
        rows.add(
          _stageRow(
            context,
            at: AvatarRunStage.portrait,
            label: 'Portrait — saved & set as card image (create model)',
            activeLabel: 'Generating portrait…',
          ),
        );
      }
      if (_c.packEnabled && _c.packPossible) {
        if (_c.packEditModeNow) {
          rows.add(
            _stageRow(
              context,
              at: AvatarRunStage.switching,
              label: 'Switched to edit model',
              activeLabel:
                  'Switching to edit model (first use can take a minute)…',
            ),
          );
        }
        rows.add(_packRow(context));
        if (_c.qcEnabled) {
          rows.add(
            _stageRow(
              context,
              at: AvatarRunStage.qc,
              label: _c.flaggedExcluded > 0
                  ? 'Vision QC — ${_c.flaggedExcluded} flagged, held back'
                  : 'Vision QC',
              activeLabel: 'Vision QC — checking each face…',
            ),
          );
        }
      }
      if (_c.stage == AvatarRunStage.done) {
        rows.add(const SizedBox(height: 4));
        rows.add(
          Text(
            _c.importedCount > 0
                ? 'Done — ${_c.importedCount} expression'
                      '${_c.importedCount == 1 ? '' : 's'} in the gallery.'
                : 'Done.',
            style: const TextStyle(
              color: AppColors.logReady,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      if (_c.running) {
        rows.add(const SizedBox(height: 8));
        rows.add(
          Row(
            children: [
              Expanded(
                child: Text(
                  'Cancel keeps everything already finished. '
                  '${_c.card?.name ?? 'Your character'} exists either way.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                  ),
                ),
              ),
              TextButton(
                onPressed: _c.cancel,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary(context),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        );
      }
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  /// One progress line for [at]: pending (dim), active (amber + spinner-ish),
  /// or done (green check) based on the controller's current stage order.
  Widget _stageRow(
    BuildContext context, {
    required AvatarRunStage at,
    required String label,
    required String activeLabel,
  }) {
    final done = _c.stage.index > at.index && _c.stage != AvatarRunStage.failed;
    final active = _c.stage == at;
    final color = done
        ? AppColors.logReady
        : active
        ? AppColors.formMasterAccent
        : AppColors.textTertiary(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle
                : active
                ? Icons.autorenew
                : Icons.circle_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              active ? activeLabel : label,
              style: TextStyle(color: color, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _packRow(BuildContext context) {
    final s = _c.session;
    final total = s?.slots.length ?? _c.missingEmotions.length;
    final done = s?.doneCount ?? 0;
    String current = '';
    if (s != null) {
      for (final slot in s.slots) {
        if (slot.state == ExpressionSlotState.generating) {
          current = ' — "${slot.emotion}"';
          break;
        }
      }
    }
    final active = _c.stage == AvatarRunStage.pack;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _stageRow(
          context,
          at: AvatarRunStage.pack,
          label:
              'Expression pack $done / $total (identity pinned to the '
              'portrait)',
          activeLabel: 'Expression pack $done / $total$current',
        ),
        if (_c.packBaseConverted)
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 2, bottom: 2),
            child: Text(
              kPackConvertedNote,
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
              ),
            ),
          ),
        if (active && total > 0)
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 2, bottom: 2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: done / total,
                minHeight: 5,
                color: AppColors.formMasterAccent,
                backgroundColor: AppColors.surfaceContainerOf(context),
              ),
            ),
          ),
      ],
    );
  }
}
