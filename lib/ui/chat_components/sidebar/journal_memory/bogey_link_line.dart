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
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/warm_dialog.dart';

/// A bogey's boon link on its card (docs/design/boons-and-bogies.md phase
/// 7, maintainer rulings 2026-11-26): "Held back by Stealth (Skilled)" with
/// a Change tap, or "Not linked to a boon" with a Link tap when the owner
/// has boons to pick. The card editor or the Growth pass set the link; this
/// is where the user fixes a wrong one or removes it. The web twin is
/// `BogeyLinkLine` in `web_ui/src/components/GrowthPanel.tsx`.
class BogeyLinkLine extends StatelessWidget {
  const BogeyLinkLine({
    super.key,
    required this.ring,
    required this.chatService,
    required this.characterId,
  });

  final GrowthRingData ring;
  final ChatService chatService;
  final String characterId;

  @override
  Widget build(BuildContext context) {
    final owned = chatService.growthRingsForOwner(characterId);
    final boons = [
      for (final r in owned)
        if (!r.retired && BoonsBogies.isBoon(r)) r,
    ];
    final linked = BoonLink.linkedBoonOf(ring, owned);
    if (linked == null && boons.isEmpty) return const SizedBox.shrink();
    final honey = AppColors.porchHoneyOf(context);
    final label = linked == null
        ? 'Not linked to a boon'
        : 'Held back by ${linked.content} '
              '(${_tierName(BoonsBogies.tierOf(linked))})';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            linked == null ? Icons.link_off : Icons.shield_outlined,
            size: 11,
            color: linked == null ? AppColors.textTertiary(context) : honey,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: linked == null
                    ? AppColors.textTertiary(context)
                    : AppColors.textSecondary(context),
              ),
            ),
          ),
          if (boons.isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: chatService.isGenerating
                  ? null
                  : () => _pick(context, boons, linked),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  linked == null ? 'Link' : 'Change',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: honey,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _tierName(String tier) => switch (tier) {
    'master' => 'Master',
    'skilled' => 'Skilled',
    _ => 'Novice',
  };

  /// The picker: one row per boon plus "No boon". Cancel writes nothing.
  Future<void> _pick(
    BuildContext context,
    List<GrowthRingData> boons,
    GrowthRingData? linked,
  ) async {
    final picked = await showWarmDialog<_LinkPick>(
      context,
      title: 'Which boon holds this back?',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '"${ring.content}"',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(height: 8),
          for (final b in boons)
            _option(
              context,
              label: '${b.content} (${_tierName(BoonsBogies.tierOf(b))})',
              selected: linked?.id == b.id,
              pick: _LinkPick(b.id),
            ),
          _option(
            context,
            label: 'No boon',
            selected: linked == null,
            pick: const _LinkPick(null),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
    if (picked == null || picked.boonId == linked?.id) return;
    await setBogeyLink(chatService, characterId, ring.id, picked.boonId);
  }

  Widget _option(
    BuildContext context, {
    required String label,
    required bool selected,
    required _LinkPick pick,
  }) {
    final honey = AppColors.porchHoneyOf(context);
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => Navigator.of(context).pop(pick),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 16,
              color: selected ? honey : AppColors.iconSecondary(context),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textPrimary(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One picker answer: a boon id, or null for "No boon" (distinct from a
/// cancelled dialog, which returns no pick at all).
class _LinkPick {
  const _LinkPick(this.boonId);
  final String? boonId;
}
