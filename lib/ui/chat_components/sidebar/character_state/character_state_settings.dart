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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import '../sidebar_tokens.dart';

/// The Character State gear flyout — an inline inset panel (not a popup menu,
/// which would dismiss on every toggle tap) collecting the simulation
/// switches that used to be scattered through realism_section and the inline
/// group NSFW toggle: Needs Simulation, Automatic Passage of Time, One-Shot
/// Eval, and NSFW Enhancements (the arousal system — its settings home after
/// the Lust bar moved in among the bond bars). Manual time nudging lives
/// ONLY on the TimeStrip's chevrons (a duplicate row here was removed —
/// user feedback 2026-07-03).
///
/// NSFW visibility split-brain (documented at chat_service_group_settings):
/// group READ uses the stable per-member flag [ChatService.isGroupNsfwEnabled]
/// (the live nsfwService scalar is per-speaker-volatile in groups); 1:1 READ
/// uses the scalar; WRITE is always [ChatService.setNsfwCooldownEnabled],
/// which propagates to every member in a group.
class CharacterStateSettings extends StatelessWidget {
  final ChatService chat;
  final bool isGroup;

  const CharacterStateSettings({
    super.key,
    required this.chat,
    required this.isGroup,
  });

  @override
  Widget build(BuildContext context) {
    // Listening on purpose: one-shot eval lives on StorageService.
    final storage = Provider.of<StorageService>(context);
    final nsfwOn = isGroup
        ? chat.isGroupNsfwEnabled
        : chat.nsfwService.nsfwCooldownEnabled;

    return Container(
      padding: SidebarTokens.wellPadding,
      decoration: BoxDecoration(
        color: AppColors.sunkenSurfaceOf(context),
        borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _toggleRow(
            context,
            icon: Icons.battery_std,
            label: 'Needs Simulation',
            caption:
                'Tracks satisfaction levels (hunger, bladder, energy, social, '
                'fun, hygiene, comfort). Higher = more sated / less urgent '
                '(100 = full, 0 = critical). Affects prompts & behavior when '
                'low.',
            value: chat.needsSimEnabled,
            accent: AppColors.porchTerracottaOf(context),
            onChanged: chat.isGenerating
                ? null
                : (val) => chat.setNeedsSimEnabled(val),
          ),
          const SizedBox(height: 10),
          _toggleRow(
            context,
            icon: Icons.access_time,
            label: 'Automatic Passage of Time',
            caption:
                'Time advances automatically as you chat. Manual controls '
                'remain available.',
            value: chat.timeService.passageOfTimeEnabled,
            accent: AppColors.timeDayAccentOf(context),
            // Must go through the ChatService wrapper — the raw TimeService
            // setter is deliberately side-effect-free (no save, no notify),
            // which is why this toggle looked dead / possessed before.
            onChanged: chat.isGenerating
                ? null
                : (val) => chat.setPassageOfTimeEnabled(val),
          ),
          const SizedBox(height: 10),
          _toggleRow(
            context,
            icon: Icons.speed,
            label: 'One-Shot Eval (Experimental)',
            caption:
                'Fuses relationship + scene evals into a single LLM call to '
                'double the processing speed. May be less accurate on < 8B '
                'param models.',
            value: storage.realismOneShotEval,
            accent: AppColors.journalAccentOf(context),
            onChanged: chat.isGenerating
                ? null
                : (val) => storage.setRealismOneShotEval(val),
          ),
          const SizedBox(height: 10),
          _toggleRow(
            context,
            icon: Icons.local_fire_department,
            label: 'NSFW Enhancements',
            caption:
                'Tracks arousal (the Lust bar above) with post-climax '
                'refractory cooldowns.'
                '${isGroup ? ' Applies to every group member.' : ''}',
            value: nsfwOn,
            accent: AppColors.lustAccentOf(context),
            onChanged: chat.isGenerating
                ? null
                : (val) => chat.setNsfwCooldownEnabled(val),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String caption,
    required bool value,
    required Color accent,
    required ValueChanged<bool>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppColors.iconSecondary(context)),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(
              height: 24,
              child: FittedBox(
                child: Switch(
                  value: value,
                  activeThumbColor: accent,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
