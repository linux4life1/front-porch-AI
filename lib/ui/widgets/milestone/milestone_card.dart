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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/chat_service.dart' show MilestoneView;
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/milestone_palette.dart';

/// The milestone card (docs/design/boons-and-bogies.md §7), transcribed from
/// the approved mockup (docs/design/mockups/boons-and-bogies-milestones.html):
/// "✦ Milestone", the kind line (naming the member in a group), the ring box
/// with its pill, tier line, sentence and meter, the receipt line, the ask,
/// and Reject / Accept on one row at phone width. The web card
/// (MilestoneModal.tsx) is the same component.
///
/// Chrome follows the app theme; the accents are the fixed milestone
/// palette. [badge] (0..1) drives the Master badge's stamp — 1 at once under
/// reduce motion.
class MilestoneCard extends StatelessWidget {
  const MilestoneCard({
    super.key,
    required this.view,
    required this.onAccept,
    required this.onReject,
    required this.onClose,
    this.replaying = false,
    this.busy = false,
    this.notice,
    this.badge = 1,
  });

  final MilestoneView view;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onClose;
  final bool replaying;
  final bool busy;

  /// A line under the ask (the bogey cap is full).
  final String? notice;
  final double badge;

  Color get _accent => switch (view.kind) {
    'overcome' => MilestonePalette.overcome,
    _ when view.isBogey => MilestonePalette.violet,
    _ => MilestonePalette.gold,
  };

  bool get _master => view.kind.startsWith('master_');

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    final secondary = AppColors.textSecondary(context);
    final primary = AppColors.textPrimary(context);
    return Semantics(
      container: true,
      label: 'Milestone: ${view.title}',
      child: Container(
        width: 340,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: AppColors.cardOf(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderOf(context)),
          boxShadow: const [
            BoxShadow(
              color: MilestonePalette.shadow,
              blurRadius: 50,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The ✦ is the star icon on desktop (the app font has no ✦ glyph),
            // as the Boons & Bogies line pairs ✨ on web with auto_awesome here.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 15,
                  color: MilestonePalette.gold,
                  shadows: [
                    Shadow(
                      color: MilestonePalette.gold.withValues(alpha: 0.6),
                      blurRadius: 10,
                    ),
                  ],
                ),
                const SizedBox(width: 5),
                Text(
                  'Milestone',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(
                text: view.title,
                children: [
                  if (view.inGroup && view.ownerName.isNotEmpty) ...[
                    const TextSpan(text: ' · '),
                    TextSpan(
                      text: view.ownerName,
                      style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: secondary),
            ),
            const SizedBox(height: 14),
            _ringBox(context, accent),
            const SizedBox(height: 10),
            if (view.receipt.isNotEmpty)
              Text(
                view.receipt,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: secondary),
              ),
            if (view.ask.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                view.ask,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
              ),
            ],
            if (notice != null) ...[
              const SizedBox(height: 8),
              Text(
                notice!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: secondary),
              ),
            ],
            const SizedBox(height: 14),
            _buttons(context),
          ],
        ),
      ),
    );
  }

  Widget _ringBox(BuildContext context, Color accent) {
    final card = AppColors.cardOf(context);
    // Bright gold on a light card is unreadable: a light theme darkens the
    // pill's word toward the text colour (web: milestone.css .ms-pill).
    final pillInk = Theme.of(context).brightness == Brightness.light
        ? Color.lerp(accent, AppColors.textPrimary(context), 0.7)!
        : accent;
    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: 0.10), card),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  view.pill,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: pillInk,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  view.tierLine,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            view.text,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: LinearProgressIndicator(
                value: view.meter.clamp(0.0, 1.0),
                backgroundColor: AppColors.textSecondary(
                  context,
                ).withValues(alpha: 0.25),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ),
        ],
      ),
    );
    if (!_master) return box;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        box,
        Positioned(
          right: 12,
          top: -12,
          child: Opacity(
            opacity: badge.clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: 8 * math.pi / 180,
              child: Transform.scale(
                scale: 1 + 1.2 * (1 - badge.clamp(0.0, 1.0)),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: const [
                      BoxShadow(color: MilestonePalette.shadow, blurRadius: 14),
                    ],
                  ),
                  child: Text(
                    'MASTER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.3,
                      color: view.isBogey
                          ? MilestonePalette.white
                          : MilestonePalette.onGold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buttons(BuildContext context) {
    final shape = WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
    const minSize = WidgetStatePropertyAll(Size(0, 44));
    final reject = OutlinedButton(
      onPressed: busy ? null : (replaying ? onClose : onReject),
      style: ButtonStyle(
        shape: shape,
        minimumSize: minSize,
        side: WidgetStatePropertyAll(
          BorderSide(color: AppColors.borderOf(context), width: 1.5),
        ),
        foregroundColor: WidgetStatePropertyAll(AppColors.textPrimary(context)),
      ),
      child: Text(
        replaying ? 'Close' : 'Reject',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
    if (replaying) return SizedBox(width: double.infinity, child: reject);
    return Row(
      children: [
        Expanded(child: reject),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: busy ? null : onAccept,
            style: ButtonStyle(
              shape: shape,
              minimumSize: minSize,
              backgroundColor: const WidgetStatePropertyAll(
                MilestonePalette.gold,
              ),
              foregroundColor: const WidgetStatePropertyAll(
                MilestonePalette.onGold,
              ),
            ),
            child: const Text(
              'Accept',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}
