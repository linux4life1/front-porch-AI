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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

import 'message_bubble.realism_chips.dart';
import 'message_bubble.realism_layout.dart';

/// Parses a message's realism/needs metadata into the chip widgets shown
/// under the bubble (bond / trust / mood / lust / time-skip / time-reversal /
/// Chance Time / Director-verifier chips, plus the per-need delta chips),
/// then hands the two chip lists to [MessageRealismChipLayout]
/// (`message_bubble.realism_layout.dart`) for final layout.
class MessageRealismIndicator extends StatelessWidget {
  const MessageRealismIndicator({
    super.key,
    required this.metadata,
    required this.message,
    required this.index,
    required this.chatService,
    required this.onReprocess,
  });

  /// The shown swipe's metadata.
  final Map<String, dynamic> metadata;
  final ChatMessage message;
  final int index;
  final ChatService? chatService;

  /// Opens Manual Reprocess for this message.
  final VoidCallback onReprocess;

  @override
  Widget build(BuildContext context) {
    // A present key means the relationship judge ran, even when it
    // returned 0. A missing key is an older turn or a skipped judge.
    final bondRecorded = metadata.containsKey('bond_delta');
    final trustRecorded = metadata.containsKey('trust_delta');
    final bondDelta = metadata['bond_delta'] as int? ?? 0;
    final emotionLabel = metadata['emotion_label'] as String? ?? '';
    final arousalDelta = metadata['arousal_delta'] as int? ?? 0;
    final trustDelta = metadata['trust_delta'] as int? ?? 0;
    final bondReason = metadata['bond_reason'] as String? ?? '';
    final trustReason = metadata['trust_reason'] as String? ?? '';
    final arousalReason = metadata['arousal_reason'] as String? ?? '';
    final emotionCause = metadata['emotion_cause'] as String? ?? '';
    final timeSkipTo = metadata['time_skip_to'] as String? ?? '';
    final timePassed = metadata['time_passed'] as String? ?? '';
    final chanceTimeEvent = metadata['chance_time_event'] as String? ?? '';
    final timeReversal = metadata['time_reversal'] as bool? ?? false;
    final searchReceipt = metadata['search_receipt'] as Map<String, dynamic>?;
    final searchQuery = (searchReceipt?['query'] as String?)?.trim() ?? '';
    final searchOk = searchReceipt?['ok'] == true;
    final wikiReceipt = metadata['wiki_receipt'] as Map<String, dynamic>?;
    final wikiQueryRaw = (wikiReceipt?['query'] as String?)?.trim() ?? '';
    final wikiQuery = wikiQueryRaw == searchQuery ? '' : wikiQueryRaw;
    final wikiOk = wikiReceipt?['ok'] == true;
    final toolReceipt = metadata['tool_receipt'] as Map<String, dynamic>?;
    final toolName = (toolReceipt?['tool'] as String?)?.trim() ?? '';
    final toolOk = toolReceipt?['ok'] == true;
    final needsDeltas = metadata['needs_deltas'] as Map<String, dynamic>?;
    final needsUnaffected = metadata[kNeedsUnaffectedMeta] == true;
    // The judge ran and its answer could not be read. One plain chip says so
    // instead of "unchanged", which would claim a score nobody gave.
    final feelingsUnscored =
        metadata[kFeelingsUnscoredMeta] == true &&
        !bondRecorded &&
        !trustRecorded;

    // Pockets & Wardrobe receipts, read BEFORE the early return below: Pockets
    // answers to its own switch and runs with the Realism Engine off, so a
    // message can legitimately carry receipts and no realism/needs keys at all.
    // Bailing out on the realism keys alone dropped the chip entirely for
    // exactly those users.
    final rawPocketChanges = metadata['pocket_changes'];
    final pocketReceipts = rawPocketChanges is List
        ? rawPocketChanges
              .map((raw) => raw is String ? raw.trim() : '')
              .where((text) => text.isNotEmpty)
              .toList()
        : const <String>[];

    // Verifier result (attached by realism_verification leaf when feature active for the turn).
    // status: 'accepted' | 'corrected'; passes: reprocess count; reason optional for tooltip.
    final verifData =
        metadata[RealismVerification.kMetaKey] as Map<String, dynamic>?;
    final verifStatus = (verifData?['status'] as String? ?? '').trim();
    final verifPasses = (verifData?['passes'] as num?)?.toInt() ?? 0;
    final verifReason = (verifData?['reason'] as String? ?? '').trim();
    // Mood, needs, or the verifier mean the engine scored this reply. A
    // missing bond/trust key on that reply is a dropped zero, not a
    // skipped judge. Say so, the same way Needs says nothing moved. The
    // clock is not on that list: Passage of Time runs without the engine
    // (2026-08-06), so a time chip alone proves nothing about the judge,
    // and counting it put "Bond unchanged" on every reply of a chat with
    // Realism off (a user's report on v1.5.0).
    final realismTouched =
        emotionLabel.isNotEmpty ||
        needsUnaffected ||
        (needsDeltas != null && needsDeltas.isNotEmpty) ||
        verifStatus.isNotEmpty ||
        bondRecorded ||
        trustRecorded;
    final showBond = !feelingsUnscored && (bondRecorded || realismTouched);
    final showTrust = !feelingsUnscored && (trustRecorded || realismTouched);
    final bondUnchanged = !bondRecorded || bondDelta == 0;
    final trustUnchanged = !trustRecorded || trustDelta == 0;

    if ((needsDeltas == null || needsDeltas.isEmpty) &&
        !needsUnaffected &&
        !feelingsUnscored &&
        !showBond &&
        emotionLabel.isEmpty &&
        arousalDelta == 0 &&
        !showTrust &&
        timeSkipTo.isEmpty &&
        timePassed.isEmpty &&
        chanceTimeEvent.isEmpty &&
        !timeReversal &&
        verifStatus.isEmpty &&
        pocketReceipts.isEmpty &&
        searchQuery.isEmpty &&
        wikiQuery.isEmpty &&
        toolName.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget maybeTooltip(Widget child, String tip) {
      if (tip.isEmpty) return child;
      return Tooltip(
        message: tip,
        preferBelow: false,
        textStyle: RealismColors.tooltipText(context),
        decoration: RealismColors.tooltipDecoration(context),
        child: child,
      );
    }

    final chips = <Widget>[];

    // ── Needs Simulation Chips (deltas + reasons) — built into a separate list
    // so we can render them on their own row underneath the classic realism chips.
    final List<Widget> needsChipList = [];

    if (needsDeltas != null && needsDeltas.isNotEmpty) {
      needsDeltas.forEach((need, data) {
        final delta = (data is Map) ? (data['delta'] as int? ?? 0) : 0;
        if (delta == 0) {
          return; // only show needs that actually changed this turn (avoids "Bladder 0" clutter; mirrors bond/trust/lust skipping 0s)
        }
        final reason = (data is Map) ? (data['reason'] as String? ?? '') : '';

        IconData icon;
        Color color;
        String label = need[0].toUpperCase() + need.substring(1);

        switch (need) {
          case 'hunger':
            icon = Icons.restaurant;
            color = RealismColors.hungerOf(context);
            break;
          case 'bladder':
            icon = Icons.water_drop;
            color = RealismColors.bladderOf(context);
            break;
          case 'energy':
            icon = Icons.bolt;
            color = RealismColors.energyOf(context);
            break;
          case 'social':
            icon = Icons.people;
            color = RealismColors.socialOf(context);
            break;
          case 'fun':
            icon = Icons.celebration;
            color = RealismColors.funOf(context);
            break;
          case 'hygiene':
            icon = Icons.shower;
            color = RealismColors.hygieneOf(context);
            break;
          case 'comfort':
            icon = Icons.chair;
            color = RealismColors.comfortOf(context);
            break;
          default:
            icon = Icons.circle;
            color = RealismColors.otherNeedOf(context);
        }

        final chip = realismDeltaChip(
          context,
          icon: icon,
          label: '$label ${delta > 0 ? '+$delta' : '$delta'}',
          color: color,
          hasReason: reason.isNotEmpty,
        );

        needsChipList.add(maybeTooltip(chip, reason));
      });
    }

    if (needsUnaffected && needsChipList.isEmpty) {
      final amber = AppColors.porchAmberOf(context);
      needsChipList.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 11, color: amber),
            const SizedBox(width: 4),
            Text(
              kNeedsUnaffectedLabel,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: amber,
              ),
            ),
          ],
        ),
      );
    }

    if (feelingsUnscored) {
      final amber = AppColors.porchAmberOf(context);
      chips.add(
        maybeTooltip(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.help_outline, size: 11, color: amber),
              const SizedBox(width: 4),
              Text(
                kFeelingsUnscoredLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: amber,
                ),
              ),
            ],
          ),
          kFeelingsUnscoredTip,
        ),
      );
    }

    if (showBond) {
      final bondColor = bondUnchanged
          ? AppColors.textSecondary(context)
          : bondDelta > 0
          ? RealismColors.bondUpOf(context)
          : RealismColors.bondDownOf(context);
      final chip = realismDeltaChip(
        context,
        icon: bondUnchanged
            ? Icons.favorite_border
            : bondDelta > 0
            ? Icons.favorite
            : Icons.heart_broken,
        label: bondUnchanged
            ? 'Bond unchanged'
            : 'Bond: ${bondDelta > 0 ? '+$bondDelta' : '$bondDelta'}',
        color: bondColor,
        hasReason: bondReason.isNotEmpty,
      );
      chips.add(maybeTooltip(chip, bondReason));
    }

    if (emotionLabel.isNotEmpty) {
      // Why they feel this (the judge's cause, filed with this reply), then
      // what they walked in carrying (Standing Mood). The sidebar no longer
      // prints the cause, so this hover is where it lives.
      final standing =
          MoodBaseline.fromJson(metadata['mood_context'])?.summary ?? '';
      final moodTip = [
        if (emotionCause.isNotEmpty) 'Because $emotionCause',
        if (standing.isNotEmpty) 'Came in $standing',
      ].join('\n');
      chips.add(
        maybeTooltip(
          realismDeltaChip(
            context,
            icon: Icons.psychology,
            label: 'Mood: $emotionLabel',
            color: AppColors.emotionAccentOf(context),
            hasReason: moodTip.isNotEmpty,
          ),
          moodTip,
        ),
      );
    }

    if (arousalDelta != 0) {
      chips.add(
        maybeTooltip(
          realismDeltaChip(
            context,
            icon: arousalDelta > 0
                ? Icons.local_fire_department
                : Icons.ac_unit,
            label:
                'Lust: ${arousalDelta > 0 ? '+$arousalDelta' : '$arousalDelta'}',
            color: arousalDelta > 0
                ? RealismColors.lustUpOf(context)
                : RealismColors.lustDownOf(context),
            hasReason: arousalReason.isNotEmpty,
          ),
          arousalReason,
        ),
      );
    }

    if (showTrust) {
      final trustColor = trustUnchanged
          ? AppColors.textSecondary(context)
          : trustDelta > 0
          ? RealismColors.trustUpOf(context)
          : RealismColors.trustDownOf(context);
      final chip = realismDeltaChip(
        context,
        icon: trustUnchanged
            ? Icons.handshake_outlined
            : trustDelta > 0
            ? Icons.handshake
            : Icons.gavel,
        label: trustUnchanged
            ? 'Trust unchanged'
            : 'Trust: ${trustDelta > 0 ? '+$trustDelta' : '$trustDelta'}',
        color: trustColor,
        hasReason: trustReason.isNotEmpty,
      );
      chips.add(maybeTooltip(chip, trustReason));
    }

    chips.addAll(
      realismEventAndReceiptChips(
        context,
        maybeTooltip: maybeTooltip,
        timeReversal: timeReversal,
        timeSkipTo: timeSkipTo,
        timePassed: timePassed,
        searchQuery: searchQuery,
        searchOk: searchOk,
        wikiQuery: wikiQuery,
        wikiOk: wikiOk,
        toolName: toolName,
        toolOk: toolOk,
        chanceTimeEvent: chanceTimeEvent,
        verifStatus: verifStatus,
        verifPasses: verifPasses,
        verifReason: verifReason,
        pocketReceipts: pocketReceipts,
      ),
    );

    return MessageRealismChipLayout(
      chips: chips,
      needsChips: needsChipList,
      message: message,
      index: index,
      chatService: chatService,
      onReprocess: onReprocess,
    );
  }
}
