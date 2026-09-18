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

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/growth_review_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import '../sidebar_tokens.dart';

part 'growth_panel.card.dart';
part 'growth_panel.actions.dart';
part 'growth_panel.editor.dart';

/// Growth Rings sidebar panel (docs/design/growth-rings.md; replaced the
/// Character Evolution panel) — the focused character's growth timeline for
/// this chat: rings grouped by tier (Established / Developing / Emerging),
/// a collapsible Past growth section, receipt pills that jump to the message
/// that earned the ring, the cadence slider, the opt-in review toggle
/// (default OFF — autonomous growth), and Check now / Plant a ring / Reset.
/// Follows the focused participant like JournalPanel — every group member
/// (and scene guest) grows their own rings.
class GrowthPanel extends StatelessWidget {
  final ChatService chatService;
  final String characterId;
  final String characterName;

  /// Receipts tap-to-jump (null in tests or hosts without a chat behind).
  final ValueChanged<int>? onJumpToMessage;

  const GrowthPanel({
    super.key,
    required this.chatService,
    required this.characterId,
    required this.characterName,
    this.onJumpToMessage,
  });

  /// Friendly label + accent for a ring category chip.
  static String categoryLabel(String category) => switch (category) {
    'stance' => 'stance',
    'habit' => 'habit',
    'skill' => 'skill',
    'scar' => 'scar',
    GrowthPhysics.kArchiveCategory => 'archive',
    _ => 'trait',
  };

  static Color categoryAccent(BuildContext context, String category) =>
      switch (category) {
        'stance' => AppColors.porchTerracottaOf(context),
        'habit' => AppColors.trustHighOf(context),
        'skill' => AppColors.porchAmberOf(context),
        'scar' => AppColors.fixationAccentOf(context),
        GrowthPhysics.kArchiveCategory => AppColors.textTertiary(context),
        _ => AppColors.porchHoneyOf(context),
      };

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    final enabled = storage.memorySettings.characterEvolutionEnabled;
    final accent = AppColors.porchHoneyOf(context);

    // Rings come from the session-scoped sync cache; ListenableBuilder keeps
    // the timeline current after passes/edits (they all notifyListeners).
    return ListenableBuilder(
      listenable: chatService,
      builder: (context, _) {
        final rings = chatService.growthRingsForOwner(characterId);
        final active = rings.where((r) => !r.retired).toList();
        final past = rings.where((r) => r.retired).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SidebarSubHeader(
              icon: Icons.donut_large,
              label: 'Growth · $characterName',
              accent: accent,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (enabled)
                    IconButton(
                      icon: Icon(
                        Icons.settings,
                        size: 14,
                        color: AppColors.iconSecondary(context),
                      ),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Growth settings',
                      onPressed: () => _showSettings(context, storage),
                    ),
                  SizedBox(
                    height: 28,
                    child: FittedBox(
                      child: Switch(
                        value: enabled,
                        onChanged: (v) => storage.memorySettings
                            .setCharacterEvolutionEnabled(v),
                        activeTrackColor: accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!enabled)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 20),
                child: Text(
                  'Characters grow small, evidence-backed "rings" as you '
                  'chat — the original card is always preserved.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              ),
            if (enabled) ...[
              const SizedBox(height: 4),
              if (chatService.growthReview.hasPendingFor(
                chatService.currentSessionId,
              ))
                _reviewBanner(context),
              _cadenceSlider(context, storage, accent),
              if (chatService.hasLegacyGrowthBlobFor(characterId))
                Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 4),
                  child: Text(
                    'Growth recorded under the old system still applies — '
                    'it converts to rings at the next check.',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ),
              if (active.isEmpty &&
                  past.isEmpty &&
                  !chatService.hasLegacyGrowthBlobFor(characterId))
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 2),
                  child: Text(
                    '$characterName hasn\'t grown yet — rings appear as the '
                    'story changes them.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary(context),
                    ),
                  ),
                ),
              for (final tier in const [
                'established',
                'developing',
                'emerging',
              ])
                ..._tierSection(context, tier, active),
              if (past.isNotEmpty) _pastSection(context, past),
              const SizedBox(height: 6),
              _actionsRow(context, accent),
            ],
          ],
        );
      },
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────

  List<Widget> _tierSection(
    BuildContext context,
    String tier,
    List<GrowthRingData> active,
  ) {
    final rings = active.where((r) => GrowthPhysics.tierOf(r) == tier).toList();
    if (rings.isEmpty) return const [];
    final dot = switch (tier) {
      'established' => AppColors.porchHoneyOf(context),
      'developing' => AppColors.porchTerracottaOf(context),
      _ => AppColors.textTertiary(context),
    };
    return [
      Padding(
        padding: const EdgeInsets.only(left: 20, top: 8, bottom: 4),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              tier.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: AppColors.textTertiary(context),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Divider(
                height: 1,
                color: AppColors.borderOf(context).withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
      for (final ring in rings)
        Padding(
          padding: const EdgeInsets.only(left: 20, bottom: 6),
          child: _ringCard(context, ring),
        ),
    ];
  }

  Widget _reviewBanner(BuildContext context) {
    final honey = AppColors.porchHoneyOf(context);
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
        onTap: () => GrowthReviewDialog.show(context, chatService.growthReview),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: honey.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
            border: Border.all(color: honey.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Text('🌱', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$characterName has grown — '
                  '${chatService.growthReview.pending!.totalProposals} '
                  'proposal(s) waiting. Tap to review.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: honey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cadenceSlider(
    BuildContext context,
    StorageService storage,
    Color accent,
  ) {
    final value = storage.memorySettings.growthInterval.toDouble();
    return Padding(
      padding: const EdgeInsets.only(left: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Check for growth every',
                style: TextStyle(
                  color: AppColors.textSecondary(context),
                  fontSize: 10,
                ),
              ),
              const Spacer(),
              Text(
                '${storage.memorySettings.growthInterval} messages',
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(
            height: 26,
            child: Slider(
              value: value.clamp(2, 20),
              min: 2,
              max: 20,
              divisions: 18,
              activeColor: accent,
              onChanged: (v) =>
                  storage.memorySettings.setGrowthInterval(v.round()),
            ),
          ),
        ],
      ),
    );
  }
}
