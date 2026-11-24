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
import 'package:front_porch_ai/ui/chat_components/sidebar/journal_memory/growth_panel.bb.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/milestone/milestone.dart';
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
    final ownerId = _ownerId();
    // Moments (phase 5, §7) show under the same gate as the traits they
    // are about: Porch Life allows the feature and this member's switch is
    // on. One read feeds the header dot and the section.
    return MomentsLoader(
      chat: chat,
      ownerId: allowed && on ? ownerId : '',
      builder: (context, moments) => _line(
        context,
        allowed: allowed,
        on: on,
        accent: accent,
        memberId: memberId,
        ownerId: ownerId,
        moments: moments,
      ),
    );
  }

  String _ownerId() {
    final member = this.member;
    if (member != null) return chat.characterIdFor(member);
    final host = chat.activeCharacter;
    return host == null ? '' : chat.characterIdFor(host);
  }

  Widget _line(
    BuildContext context, {
    required bool allowed,
    required bool on,
    required Color accent,
    required String memberId,
    required String ownerId,
    required List<MilestoneView> moments,
  }) {
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
            MomentsUnreadDot(moments: moments),
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
        else if (on) ...[
          _traits(context, ownerId),
          MomentsSection(chat: chat, moments: moments),
        ],
      ],
    );
  }

  /// The rings this line governs, mounted as the SAME cards the Growth
  /// panel renders (BoonBogeyCard: kind, tier, meter, pin/cooldown meta,
  /// receipts, undo, menu) — the sidebar must not invent a blander second
  /// language for the same data (maintainer, 2026-11-22). The panel keeps
  /// the full list and the jump-to-message taps; this is the same rows,
  /// one owner, boons then bogies.
  Widget _traits(BuildContext context, String ownerId) {
    final rings = ownerId.isEmpty
        ? const <GrowthRingData>[]
        : chat
              .growthRingsForOwner(ownerId)
              .where((r) => BoonsBogies.isBoonOrBogey(r) && !r.retired)
              .toList();
    if (rings.isEmpty) {
      return Text(
        'No boons or bogies yet — a card kit seeds when a chat opens.',
        style: TextStyle(fontSize: 11, color: AppColors.textTertiary(context)),
      );
    }
    final boons = rings.where(BoonsBogies.isBoon).toList();
    final bogies = rings.where(BoonsBogies.isBogey).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BoonBogeySection(
          title: 'Boons',
          rings: boons,
          chatService: chat,
          characterId: ownerId,
        ),
        BoonBogeySection(
          title: 'Bogies',
          trailing: '${bogies.length} of ${BoonsBogies.kMaxActiveBogies}',
          rings: bogies,
          chatService: chat,
          characterId: ownerId,
        ),
      ],
    );
  }
}
