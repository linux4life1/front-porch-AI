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

/// The in-call realism window: their current emotion plus the bond/trust
/// movement of the last scored exchange (read straight off the last
/// reply's chip metadata — the same numbers the bubbles show after the
/// call). Renders nothing with the engine off or before the first eval.
class CallRealismStrip extends StatelessWidget {
  const CallRealismStrip({super.key, required this.chat});

  final ChatService chat;

  @override
  Widget build(BuildContext context) {
    if (!chat.realismEnabled) return const SizedBox(height: 22);
    final chips = <Widget>[];
    final emotion = chat.characterEmotion;
    if (emotion.isNotEmpty) {
      chips.add(
        _stripChip(
          context,
          Icons.mood,
          emotion[0].toUpperCase() + emotion.substring(1),
          AppColors.porchHoneyOf(context),
        ),
      );
    }
    final messages = chat.messages;
    final last = messages.isNotEmpty ? messages.last : null;
    final meta = (last != null && !last.isUser) ? last.activeMetadata : null;
    final bond = meta?['bond_delta'] as int? ?? 0;
    final trust = meta?['trust_delta'] as int? ?? 0;
    if (bond != 0) {
      chips.add(
        _stripChip(
          context,
          Icons.favorite,
          bond > 0 ? '+$bond' : '$bond',
          bond > 0
              ? AppColors.bondHighOf(context)
              : AppColors.bondNegOf(context),
        ),
      );
    }
    if (trust != 0) {
      chips.add(
        _stripChip(
          context,
          Icons.handshake,
          trust > 0 ? '+$trust' : '$trust',
          trust > 0
              ? AppColors.trustHighOf(context)
              : AppColors.bondNegOf(context),
        ),
      );
    }
    if (chips.isEmpty) return const SizedBox(height: 22);
    return Wrap(spacing: 8, runSpacing: 4, children: chips);
  }

  Widget _stripChip(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
