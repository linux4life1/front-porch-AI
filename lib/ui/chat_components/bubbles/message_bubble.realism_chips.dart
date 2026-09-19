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

part of 'message_bubble.dart';

/// Event / receipt chips appended after the classic bond/mood/lust/trust
/// chips in `_buildRealismIndicator`.
extension _BubbleRealismChips on _MessageBubbleState {
  void _appendEventAndReceiptChips({
    required List<Widget> chips,
    required Widget Function(Widget child, String tip) maybeTooltip,
    required bool timeReversal,
    required String timeSkipTo,
    required String searchQuery,
    required bool searchOk,
    required String toolName,
    required bool toolOk,
    required String chanceTimeEvent,
    required String verifStatus,
    required int verifPasses,
    required String verifReason,
    required List<String> pocketReceipts,
  }) {
    // Time reversal chip
    if (timeReversal) {
      chips.add(
        Tooltip(
          message: 'Time is going backwards?!',
          preferBelow: false,
          textStyle: const TextStyle(fontSize: 12, color: Colors.white),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '😵‍💫',
                style: TextStyle(fontSize: 11),
              ), // Dizzy face with spirals
              const SizedBox(width: 4),
              const Text(
                'Time Reversal',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.cyanAccent,
                ),
              ),
            ],
          ),
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
          textStyle: const TextStyle(fontSize: 12, color: Colors.white),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎰', style: TextStyle(fontSize: 11)),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  'Chance Time: ${chanceTimeEvent.length > 30 ? chanceTimeEvent.substring(0, 30) + '…' : chanceTimeEvent}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFFD166),
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
          ? AppColors.resolve(context, Colors.greenAccent, Colors.green)
          : AppColors.resolve(context, Colors.orangeAccent, Colors.deepOrange);
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
              Text(
                text,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.porchAmberOf(context),
                ),
              ),
            ],
          ),
          'Pockets & Wardrobe',
        ),
      );
    }
  }
}
