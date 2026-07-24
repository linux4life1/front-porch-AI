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
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:front_porch_ai/services/chat/milestone_providers.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// "Our Story" — the milestones timeline tab inside the Journal dialog
/// (Living Time §7 v1). Riverpod-native: watches the memoizing
/// [milestoneFeedProvider] family and renders through AsyncValue, grouped by
/// story day where known. Entries with a message receipt tap-to-jump via the
/// dialog's existing onJumpToMessage contract (dialog closes, chat scrolls).
class JournalTimelineTab extends ConsumerWidget {
  final ChatService chat;
  final String ownerId;
  final ValueChanged<int>? onJumpToMessage;

  const JournalTimelineTab({
    super.key,
    required this.chat,
    required this.ownerId,
    this.onJumpToMessage,
  });

  static const _kindIcons = {
    'ring': '🌱',
    'chance': '⚡',
    'objective': '🎯',
    'memory': '📔',
    'dream': '🌙',
    'ambition': '🧭',
    'milestone': '🏆',
    'promise': '🤝',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionId = chat.currentSessionId;
    if (sessionId == null) return const SizedBox.shrink();
    final entriesAsync = ref.watch(
      milestoneTimelineProvider(
        feed: chat.milestoneFeed,
        sessionId: sessionId,
        characterId: ownerId,
        revision: chat.messages.length,
        messages: chat.messages,
      ),
    );
    final accent = AppColors.porchAmberOf(context);

    return entriesAsync.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: accent)),
      error: (e, _) => Center(
        child: Text(
          'Could not load the timeline: $e',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary(context),
          ),
        ),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Nothing on the timeline yet — strong memories, growth, '
                'Chance Time strikes, achieved objectives, and dreams will '
                'gather here as your story unfolds.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
          );
        }
        // Group consecutive runs by known story day; day-less entries ride
        // with their neighbors (position-sorted upstream).
        final children = <Widget>[];
        int? lastDay;
        for (final e in entries) {
          if (e.storyDay != null && e.storyDay != lastDay) {
            lastDay = e.storyDay;
            children.add(
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Text(
                  'Day $lastDay',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            );
          }
          final canJump = e.position != null && onJumpToMessage != null;
          children.add(
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: canJump
                  ? () {
                      Navigator.of(context).pop();
                      onJumpToMessage!(e.position!);
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _kindIcons[e.kind] ?? '•',
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.text,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                    ),
                    if (e.emotion != null && e.emotion!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        e.emotion!,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ],
                    if (canJump)
                      Icon(
                        Icons.arrow_outward,
                        size: 12,
                        color: AppColors.iconSecondary(context),
                      ),
                  ],
                ),
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(top: 4),
          children: children,
        );
      },
    );
  }
}
