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

import 'package:front_porch_ai/ui/theme/theme.dart';

/// One delta chip under a reply: icon, label, and an ⓘ when hovering it
/// shows a reason. Bond, trust, mood, lust and every need draw through it,
/// so a chip that has a reason always looks like one.
Widget realismDeltaChip(
  BuildContext context, {
  required IconData icon,
  required String label,
  required Color color,
  required bool hasReason,
}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 4),
      Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      if (hasReason) ...[
        const SizedBox(width: 4),
        Icon(
          Icons.info_outline,
          size: 10,
          color: AppColors.textTertiary(context),
        ),
      ],
    ],
  );
}

/// Event / receipt chips appended after the classic bond/mood/lust/trust
/// chips in `MessageRealismIndicator`, in display order. [maybeTooltip] is
/// the indicator's shared chip tooltip.
List<Widget> realismEventAndReceiptChips(
  BuildContext context, {
  required Widget Function(Widget child, String tip) maybeTooltip,
  required bool timeReversal,
  required String timeSkipTo,
  required String timePassed,
  required String searchQuery,
  required bool searchOk,
  String wikiQuery = '',
  bool wikiOk = false,
  required String toolName,
  required bool toolOk,
  required String chanceTimeEvent,
  required String verifStatus,
  required int verifPasses,
  required String verifReason,
  required List<String> pocketReceipts,
}) {
  final chips = <Widget>[];
  // Time reversal chip
  if (timeReversal) {
    chips.add(
      Tooltip(
        message: 'Time is going backwards?!',
        preferBelow: false,
        textStyle: RealismColors.tooltipText(context),
        decoration: RealismColors.tooltipDecoration(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '😵‍💫',
              style: TextStyle(fontSize: 11),
            ), // Dizzy face with spirals
            const SizedBox(width: 4),
            Text(
              'Time Reversal',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: RealismColors.timeOddOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  if (timePassed.isNotEmpty) {
    chips.add(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            size: 11,
            color: AppColors.porchAmberOf(context),
          ),
          const SizedBox(width: 4),
          Text(
            timePassed,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.porchAmberOf(context),
            ),
          ),
        ],
      ),
    );
  }

  if (timeSkipTo.isNotEmpty) {
    chips.add(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.fast_forward,
            size: 11,
            color: AppColors.porchAmberOf(context),
          ),
          const SizedBox(width: 4),
          Text(
            'Time skip: $timeSkipTo',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.porchAmberOf(context),
            ),
          ),
        ],
      ),
    );
  }

  if (searchQuery.isNotEmpty) {
    final amber = AppColors.porchAmberOf(context);
    chips.add(
      maybeTooltip(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.travel_explore, size: 11, color: amber),
            const SizedBox(width: 4),
            Text(
              searchOk ? 'Looked up' : 'Looked up — nothing',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: amber,
              ),
            ),
          ],
        ),
        searchOk
            ? 'Looked up: $searchQuery'
            : 'Looked up "$searchQuery" — nothing reliable',
      ),
    );
  }

  if (wikiQuery.isNotEmpty) {
    final amber = AppColors.porchAmberOf(context);
    chips.add(
      maybeTooltip(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book, size: 11, color: amber),
            const SizedBox(width: 4),
            Text(
              wikiOk ? 'Wiki' : 'Wiki — nothing',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: amber,
              ),
            ),
          ],
        ),
        wikiOk
            ? 'Looked up: $wikiQuery'
            : 'Looked up "$wikiQuery" — nothing reliable',
      ),
    );
  }

  if (toolName.isNotEmpty) {
    final amber = AppColors.porchAmberOf(context);
    final label = toolOk ? toolName : '$toolName — nothing';
    chips.add(
      maybeTooltip(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension, size: 11, color: amber),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: amber,
              ),
            ),
          ],
        ),
        toolOk ? 'Tool: $toolName' : '$toolName returned nothing useful',
      ),
    );
  }

  if (chanceTimeEvent.isNotEmpty) {
    chips.add(
      Tooltip(
        message: chanceTimeEvent,
        preferBelow: false,
        textStyle: RealismColors.tooltipText(context),
        decoration: RealismColors.tooltipDecoration(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎰', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                'Chance Time: ${chanceTimeEvent.length > 30 ? chanceTimeEvent.substring(0, 30) + '…' : chanceTimeEvent}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.chaosAccentOf(context),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Verifier (Director) status chip — only when present (feature was on for this speaker/turn).
  // Reuses the chip row style + maybeTooltip. Data from ChatMessage metadata set by god/leaf after verify.
  // Status + passes; reason in tooltip if provided. Uses AppColors for new/refactored parts.
  if (verifStatus.isNotEmpty) {
    final isAccepted = verifStatus == 'accepted';
    final label = isAccepted
        ? '✓ Director accepted'
        : '🕵️ Director corrected ($verifPasses reprocess${verifPasses == 1 ? '' : 'es'})';
    final icon = isAccepted ? Icons.verified : Icons.fact_check;
    final chipColor = isAccepted
        ? StatusColors.successOf(context)
        : StatusColors.warningOf(context);
    final chip = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: chipColor),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: chipColor,
          ),
        ),
      ],
    );
    chips.add(
      maybeTooltip(
        chip,
        verifReason.isNotEmpty ? verifReason : 'Realism Verification result',
      ),
    );
  }
  // Pockets & Wardrobe receipts. Written by the post-generation pass as
  // plain phrases ("picked up: car keys"), so nothing here parses or
  // re-derives anything — the applier already decided what changed, and this
  // shows exactly that. Absent on every turn nothing moved, which is most.
  for (final text in pocketReceipts) {
    chips.add(
      maybeTooltip(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.checkroom_outlined,
              size: 11,
              color: AppColors.porchAmberOf(context),
            ),
            const SizedBox(width: 4),
            // Bounded: receipts are free-form model phrases, and one longer
            // than the bubble overflowed it. The tooltip keeps the full text.
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.porchAmberOf(context),
                ),
              ),
            ),
          ],
        ),
        'Pockets & Wardrobe: $text',
      ),
    );
  }
  return chips;
}
