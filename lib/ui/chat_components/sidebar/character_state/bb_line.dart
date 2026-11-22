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

import 'package:front_porch_ai/database/database.dart' show GrowthRingData;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/growth_boons_bogies.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/chat_colors.dart';
import 'package:front_porch_ai/ui/widgets/porch_life_needs_gate.dart';

/// This chat's own Boons & Bogies switch for one character, on the line it
/// controls (spec ruling 18, the third layer): the 1:1 chat's, or the
/// focused group member's, for this chat only. While Porch Life's Boons &
/// Bogies (or Growth) is off it greys out and says where to look; the chat's
/// own choice is kept for when Porch Life turns it back on.
///
/// Off freezes that member's rings — they stay visible and readable, but no
/// fade, advance, roll or proposal runs, and nothing is deleted.
class BbLine extends StatelessWidget {
  const BbLine({super.key, required this.chat, this.member});

  final ChatService chat;

  /// The focused group member whose switch this is; null for the 1:1 host.
  final CharacterCard? member;

  @override
  Widget build(BuildContext context) {
    final allowed = porchLifeAllowsBbOf(context);
    final member = this.member;
    // '' for the 1:1 host, whose switch is the chat's.
    final memberId = member == null ? '' : chat.characterIdFor(member);
    final on = chat.bbSwitchFor(memberId);
    final accent = AppColors.porchHoneyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 14,
              color: allowed ? accent : AppColors.textTertiary(context),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Boons & Bogies',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: allowed
                      ? AppColors.textPrimary(context)
                      : AppColors.textTertiary(context),
                ),
              ),
            ),
            SizedBox(
              height: 24,
              child: FittedBox(
                child: Switch(
                  value: on,
                  activeThumbColor: accent,
                  onChanged: !allowed || chat.isGenerating
                      ? null
                      : (on) => chat.setMemberBbEnabled(memberId, on),
                ),
              ),
            ),
          ],
        ),
        if (!allowed)
          Text(
            'Off in Porch Life — this chat keeps its choice for when it '
            'returns.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary(context),
            ),
          )
        else if (on)
          _traits(context, accent),
      ],
    );
  }

  /// The rings this line governs, under it like Needs' bars: boons first,
  /// then bogies, each with its tier. The card's kit is what fills this on
  /// a new chat's first growth pass — an empty list says so rather than
  /// leaving the author wondering where the traits went.
  Widget _traits(BuildContext context, Color accent) {
    final member = this.member;
    final ownerId = member == null
        ? (chat.activeCharacter == null
              ? ''
              : chat.characterIdFor(chat.activeCharacter!))
        : chat.characterIdFor(member);
    final rings = ownerId.isEmpty
        ? const <GrowthRingData>[]
        : chat
              .growthRingsForOwner(ownerId)
              .where((r) => BoonsBogies.isBoonOrBogey(r) && !r.retired)
              .toList()
        ..sort((a, b) {
          final kind = (BoonsBogies.isBogey(a) ? 1 : 0).compareTo(
            BoonsBogies.isBogey(b) ? 1 : 0,
          );
          return kind != 0 ? kind : b.strength.compareTo(a.strength);
        });
    if (rings.isEmpty) {
      return Text(
        'Nothing yet — a new chat seeds the card\'s kit on its first '
        'growth pass.',
        style: TextStyle(
          fontSize: 11,
          color: AppColors.textTertiary(context),
        ),
      );
    }
    final bogey = ChatColors.bogeyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rings.take(6))
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  BoonsBogies.isBogey(r)
                      ? Icons.blur_on_outlined
                      : Icons.auto_awesome,
                  size: 12,
                  color: BoonsBogies.isBogey(r) ? bogey : accent,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    r.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _tierLabel(BoonsBogies.tierOf(r)),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ],
            ),
          ),
        if (rings.length > 6)
          Text(
            '+${rings.length - 6} more in Journal & Memory → Growth',
            style: TextStyle(
              fontSize: 10.5,
              color: AppColors.textTertiary(context),
            ),
          ),
      ],
    );
  }

  static String _tierLabel(String tier) => switch (tier) {
    'master' => 'Master',
    'skilled' => 'Skilled',
    _ => 'Novice',
  };
}
