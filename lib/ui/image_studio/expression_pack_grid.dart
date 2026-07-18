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

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/expression_pack_qc.dart';
import 'package:front_porch_ai/services/expression_pack_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'expression_pack_prompt_editor.dart';
import 'expression_pack_qc_ui.dart';

/// Step 2 of the Expression-pack dialog: the live generation grid. One cell
/// per emotion, generated sequentially by the [ExpressionPackSession]; this
/// widget just listens and renders (progress header, per-cell keep/re-roll/
/// retry, QC badges, and the cancel/resume/vision-check/import footer
/// supplied by the dialog).
class ExpressionPackGrid extends StatelessWidget {
  const ExpressionPackGrid({
    super.key,
    required this.session,
    required this.imageGen,
    required this.cancelRequested,
    required this.importing,
    required this.qc,
    required this.resolvingVision,
    required this.onVisionCheck,
    required this.onCancel,
    required this.onResume,
    required this.onImport,
  });

  final ExpressionPackSession session;
  final ImageGenService imageGen;
  final bool cancelRequested;
  final bool importing;

  /// The dialog-owned Vision QC controller (null until the first check).
  final ExpressionPackQc? qc;
  final bool resolvingVision;
  final VoidCallback onVisionCheck;
  final VoidCallback onCancel;
  final VoidCallback onResume;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final qc = this.qc;
    return ListenableBuilder(
      // QC verdicts land on the slots via the controller's own notifications,
      // so the grid re-renders on either source.
      listenable: qc == null ? session : Listenable.merge([session, qc]),
      builder: (context, _) {
        final total = session.slots.length;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : session.doneCount / total,
                        minHeight: 6,
                        color: AppColors.formMasterAccent,
                        backgroundColor: AppColors.surfaceContainerOf(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${session.doneCount} / $total',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.74,
                ),
                itemCount: total,
                itemBuilder: (context, i) =>
                    _PackCell(session: session, index: i, imageGen: imageGen),
              ),
            ),
            _footer(context),
          ],
        );
      },
    );
  }

  Widget _footer(BuildContext context) {
    final buttons = <Widget>[];
    if (session.isRunning) {
      buttons.add(
        OutlinedButton.icon(
          onPressed: cancelRequested ? null : onCancel,
          icon: Icon(
            Icons.stop_circle_outlined,
            size: 16,
            color: AppColors.iconSecondary(context),
          ),
          label: Text(
            cancelRequested ? 'Stopping after current…' : 'Cancel',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppColors.borderOf(context)),
          ),
        ),
      );
    } else {
      // Vision QC (advisory): only offered once there are images to check and
      // no import is writing them out.
      if (session.doneCount > 0 && !importing) {
        buttons.add(
          PackQcFooterControls(
            session: session,
            qc: qc,
            resolvingVision: resolvingVision,
            onVisionCheck: onVisionCheck,
          ),
        );
      }
      if (session.pendingCount > 0) {
        if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 10));
        buttons.add(
          OutlinedButton.icon(
            onPressed: onResume,
            icon: Icon(
              Icons.play_arrow,
              size: 16,
              color: AppColors.iconSecondary(context),
            ),
            label: Text(
              'Generate remaining (${session.pendingCount})',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.borderOf(context)),
            ),
          ),
        );
      }
      if (session.doneCount > 0) {
        if (buttons.isNotEmpty) buttons.add(const SizedBox(width: 10));
        buttons.add(
          ElevatedButton.icon(
            onPressed: (session.keptCount == 0 || importing) ? null : onImport,
            icon: importing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_done, size: 16),
            label: Text('Import ${session.keptCount} expressions'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.formMasterAccent,
              foregroundColor: AppColors.onChaosAccent,
            ),
          ),
        );
      }
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons),
    );
  }
}

/// One emotion cell: emoji + label header, then the slot's body — dimmed
/// placeholder (pending), spinner or the backend's live preview (generating),
/// the image with keep-checkbox + re-roll (done), or error + retry (failed).
class _PackCell extends StatelessWidget {
  const _PackCell({
    required this.session,
    required this.index,
    required this.imageGen,
  });

  final ExpressionPackSession session;
  final int index;
  final ImageGenService imageGen;

  @override
  Widget build(BuildContext context) {
    final slot = session.slots[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              EmotionLabels.emoji[slot.emotion] ?? '🎭',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                slot.emotion,
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 10.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.borderOf(context).withValues(alpha: 0.6),
                ),
              ),
              child: _body(context, slot),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, ExpressionSlot slot) {
    switch (slot.state) {
      case ExpressionSlotState.pending:
        return Center(
          child: Icon(
            Icons.hourglass_empty,
            size: 18,
            color: AppColors.iconSecondary(context).withValues(alpha: 0.5),
          ),
        );
      case ExpressionSlotState.generating:
        // The backend's in-progress preview when available (A1111/ComfyUI
        // stream frames); otherwise a plain spinner.
        return ListenableBuilder(
          listenable: imageGen,
          builder: (context, _) {
            final preview = imageGen.genPreview;
            if (preview != null) {
              return Image.memory(
                preview,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              );
            }
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.formMasterAccent,
                ),
              ),
            );
          },
        );
      case ExpressionSlotState.done:
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(slot.bytes!, fit: BoxFit.cover),
            // Vision QC verdict (advisory) — top-left, clear of the keep
            // checkbox (bottom-left) and re-roll (bottom-right). Re-rolling
            // resets slot.qc, so stale badges vanish on their own.
            if (slot.qc != null)
              Positioned(
                left: 2,
                top: 2,
                child: PackQcBadge(verdict: slot.qc!, emotion: slot.emotion),
              ),
            Positioned(
              left: 2,
              right: 2,
              bottom: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  packOverlayChip(
                    context,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: slot.keep,
                        activeColor: AppColors.formMasterAccent,
                        onChanged: (v) =>
                            session.setKeep(index, v ?? false),
                      ),
                    ),
                  ),
                  packOverlayChip(
                    context,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      iconSize: 14,
                      tooltip: 'Re-roll (edit prompt, strength, seed)',
                      icon: Icon(
                        Icons.casino_outlined,
                        color: AppColors.iconPrimary(context),
                      ),
                      // Same seed + same settings = the same image, so a
                      // re-roll is ALWAYS the editor: tweak prompt/strength
                      // (pack-consistent seed) or opt into fresh noise.
                      onPressed: session.isRunning
                          ? null
                          : () => unawaited(
                              showPackRerollEditor(context, session, index),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      case ExpressionSlotState.failed:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: slot.error ?? 'Generation failed',
                child: Icon(
                  Icons.error_outline,
                  size: 18,
                  color: AppColors.negativeAccentOf(context),
                ),
              ),
              const SizedBox(height: 4),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                iconSize: 16,
                // A failed slot produced NO image, so a same-settings retry
                // is meaningful (errors are usually transient).
                tooltip: 'Retry',
                icon: Icon(
                  Icons.refresh,
                  color: AppColors.iconSecondary(context),
                ),
                onPressed: session.isRunning
                    ? null
                    : () => unawaited(session.reroll(index)),
              ),
            ],
          ),
        );
    }
  }
}
