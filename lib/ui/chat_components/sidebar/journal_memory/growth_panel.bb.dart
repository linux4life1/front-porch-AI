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

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/chat_colors.dart';

import '../sidebar_tokens.dart';
import 'growth_panel.actions.dart';

/// One Boons or Bogies section in the Growth panel — a header naming the
/// focused member (group parity with the Chaos card) and a row per ring.
/// Boons show strength; bogies show roll pressure and cooldown
/// (docs/design/boons-and-bogies.md §7 mockup 2).
class BoonBogeySection extends StatelessWidget {
  final String title;
  final String? trailing;
  final List<GrowthRingData> rings;
  final ChatService chatService;
  final String characterId;
  final ValueChanged<int>? onJumpToMessage;

  const BoonBogeySection({
    super.key,
    required this.title,
    required this.rings,
    required this.chatService,
    required this.characterId,
    this.trailing,
    this.onJumpToMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (rings.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: AppColors.textTertiary(context),
                ),
              ),
              const Spacer(),
              if (trailing != null)
                Text(
                  trailing!,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: AppColors.textTertiary(context),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (final ring in rings)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: BoonBogeyCard(
                ring: ring,
                chatService: chatService,
                characterId: characterId,
                onJumpToMessage: onJumpToMessage,
              ),
            ),
        ],
      ),
    );
  }
}

/// One boon or bogey row: kind tag, tier, meter (strength or roll pressure),
/// kit/pin/cooldown meta, receipts, the Undo affordance for the stored
/// one-step snapshot, and the pin / edit / retire menu.
class BoonBogeyCard extends StatelessWidget {
  final GrowthRingData ring;
  final ChatService chatService;
  final String characterId;
  final ValueChanged<int>? onJumpToMessage;

  const BoonBogeyCard({
    super.key,
    required this.ring,
    required this.chatService,
    required this.characterId,
    this.onJumpToMessage,
  });

  @override
  Widget build(BuildContext context) {
    final bogey = BoonsBogies.isBogey(ring);
    final color = bogey
        ? ChatColors.bogeyOf(context)
        : AppColors.porchHoneyOf(context);
    final tier = BoonsBogies.tierOf(ring);
    final undo = BoonsBogies.undoOf(ring);
    final seeded = BoonsBogies.bbOf(ring)[BoonsBogies.kSeededKey] == true;
    final receipts = GrowthStore.receiptsOf(ring);
    final onCooldown = bogey && ring.bogeyCooldown > 0;

    final meta = <String>[
      if (tier.isNotEmpty) _tierLabel(tier),
      if (seeded) 'kit',
      if (bogey && onCooldown) 'cooldown ${ring.bogeyCooldown}',
      if (bogey && !onCooldown) '${ring.bogeyPressure}%',
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.deepWellOf(context),
        borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  bogey ? 'BOGEY' : 'BOON',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              if (meta.isNotEmpty)
                Expanded(
                  child: Text(
                    meta.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                )
              else
                const Spacer(),
              if (undo != null)
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _undo(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Undo',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                  ),
                ),
              if (ring.pinned) Icon(Icons.push_pin, size: 11, color: color),
              _menu(context),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            ring.content,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.3,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: bogey
                        ? (ring.bogeyPressure / 100).clamp(0.0, 1.0)
                        : ring.strength.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: AppColors.borderOf(
                      context,
                    ).withValues(alpha: 0.4),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ),
              if (receipts.isNotEmpty) const SizedBox(width: 8),
              for (final pos in receipts.take(3))
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: onJumpToMessage == null
                        ? null
                        : () => onJumpToMessage!(pos),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '#${pos + 1}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ),
                ),
              if (receipts.length > 3)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Text(
                    '+${receipts.length - 3}',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _tierLabel(String tier) => switch (tier) {
    'master' => 'Master',
    'skilled' => 'Skilled',
    _ => 'Novice',
  };

  Future<void> _undo(BuildContext context) async {
    final sessionId = chatService.currentSessionId;
    if (sessionId == null) return;
    await chatService.growthReview.undoBoonBogey(
      sessionId,
      characterId,
      ring.id,
    );
  }

  Widget _menu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_horiz,
        size: 14,
        color: AppColors.iconSecondary(context),
      ),
      padding: EdgeInsets.zero,
      iconSize: 14,
      color: AppColors.surfaceContainerOf(context),
      onSelected: (action) async {
        switch (action) {
          case 'pin':
            await chatService.setGrowthRingPinned(ring.id, !ring.pinned);
            break;
          case 'edit':
            await editGrowthRing(context, chatService, ring);
            break;
          case 'retire':
            await chatService.retireGrowthRing(ring.id);
            break;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'pin',
          child: Text(ring.pinned ? 'Unpin' : 'Pin (never fades)'),
        ),
        const PopupMenuItem(value: 'edit', child: Text('Edit wording')),
        const PopupMenuItem(value: 'retire', child: Text('Retire to past')),
      ],
    );
  }
}
