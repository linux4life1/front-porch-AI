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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import '../sidebar_tokens.dart';

/// Trigger-state dot color: gray = enabled but idle (or an inclusion-group
/// loser this turn — idle is calm, not an error), blue = constant (always
/// injected), green = keyword-triggered. [injected] is the post-group-filter
/// truth from ChatService.currentlyActiveLoreEntries().
Color _loreDotColor(BuildContext context, LorebookEntry entry, bool injected) {
  if (!injected) return AppColors.textTertiary(context).withValues(alpha: 0.5);
  if (entry.constant) return AppColors.bondMidOf(context);
  return AppColors.bondHighOf(context);
}

/// Sticky/cooldown countdown pill for a row, or null when no timer runs.
Widget? loreTimerPill(BuildContext context, ChatService chat, LorebookEntry e) {
  final len = chat.messages.length;
  final sticky = chat.loreTimedEffects.stickyRemaining(e, len);
  if (sticky > 0) {
    return _pill(
      context,
      'sticky $sticky',
      AppColors.bondHighOf(context),
    );
  }
  final cooldown = chat.loreTimedEffects.cooldownRemaining(e, len);
  if (cooldown > 0) {
    return _pill(
      context,
      'cooldown $cooldown',
      AppColors.porchHoneyOf(context),
    );
  }
  return null;
}

Widget _pill(BuildContext context, String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color),
    ),
  );
}

/// One lorebook entry row (dot + name + optional timer pill) — shared by the
/// 1:1, group, and chat-book panels.
class LoreEntryRow extends StatelessWidget {
  final LorebookEntry entry;
  final String label;
  final double verticalPadding;
  final bool injected;
  final Widget? pill;
  final VoidCallback? onTap;
  final Widget? trailing;

  const LoreEntryRow({
    super.key,
    required this.entry,
    required this.label,
    required this.verticalPadding,
    required this.injected,
    this.pill,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _loreDotColor(context, entry, injected),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: injected
                    ? AppColors.textPrimary(context)
                    : AppColors.textSecondary(context),
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (pill != null) ...[const SizedBox(width: 6), pill!],
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// Lore token meter: how much of the lore budget the last generation used.
/// Warning tint when entries were dropped for space.
class LoreTokenMeter extends StatelessWidget {
  final ChatService chat;
  const LoreTokenMeter({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    final used = chat.lastLoreTokens;
    final budget = chat.lastLoreBudget;
    if (budget <= 0) return const SizedBox.shrink();
    final overflowed = chat.lastLoreOverflow.isNotEmpty;
    final color = overflowed
        ? AppColors.porchAmberOf(context)
        : AppColors.porchHoneyOf(context);
    final frac = (used / budget).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 4,
              backgroundColor:
                  AppColors.borderOf(context).withValues(alpha: 0.25),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            overflowed
                ? 'lore in prompt: $used / $budget tokens — '
                    '${chat.lastLoreOverflow.length} dropped'
                : 'lore in prompt: $used / $budget tokens',
            style: TextStyle(
              fontSize: 10,
              color: overflowed ? color : AppColors.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live "would trigger next" strip — watches the composer draft and shows
/// which idle entries the current text would wake up. Pure dry-run.
class WouldTriggerStrip extends StatelessWidget {
  final ChatService chat;
  final ValueListenable<TextEditingValue> draft;
  const WouldTriggerStrip({super.key, required this.chat, required this.draft});

  @override
  Widget build(BuildContext context) {
    final honey = AppColors.porchHoneyOf(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: draft,
      builder: (context, value, _) {
        final hits = chat.previewLoreTriggers(value.text);
        if (hits.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: honey.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WOULD TRIGGER NEXT',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: honey,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final e in hits.take(6))
                    _pill(context, e.displayName, honey),
                  if (hits.length > 6)
                    _pill(context, '+${hits.length - 6} more', honey),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Lorebook triggers panel for 1:1 chats — lives inside the Story Tools
/// accordion, entries list always visible. [chatService]/[draft] are optional
/// so lightweight hosts (tests) can render the plain list.
class LorebookSection extends StatelessWidget {
  final CharacterCard character;

  /// Post-group-filter injected set (ChatService.currentlyActiveLoreEntries).
  final Set<LorebookEntry> activeLore;

  final ChatService? chatService;
  final ValueListenable<TextEditingValue>? draft;

  const LorebookSection({
    super.key,
    required this.character,
    required this.activeLore,
    this.chatService,
    this.draft,
  });

  @override
  Widget build(BuildContext context) {
    final entries =
        character.lorebook != null && character.lorebook!.entries.isNotEmpty
        ? character.lorebook!.entries.where((e) => e.enabled).toList()
        : <LorebookEntry>[];
    final hasLorebook =
        character.lorebook != null && character.lorebook!.entries.isNotEmpty;
    final chat = chatService;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SidebarSubHeader(
          icon: Icons.menu_book,
          label: 'Lorebook',
          accent: AppColors.porchHoneyOf(context),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (chat != null) LoreTokenMeter(chat: chat),
              if (!hasLorebook)
                Text(
                  'No lorebook entries.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                )
              else if (entries.isEmpty)
                Text(
                  'No enabled entries.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in entries)
                      LoreEntryRow(
                        entry: entry,
                        label: entry.key.isEmpty && entry.constant
                            ? 'Always Active'
                            : entry.displayName,
                        verticalPadding: 4,
                        injected: activeLore.contains(entry),
                        pill: chat == null
                            ? null
                            : loreTimerPill(context, chat, entry),
                      ),
                  ],
                ),
              if (chat != null && draft != null)
                WouldTriggerStrip(chat: chat, draft: draft!),
            ],
          ),
        ),
      ],
    );
  }
}

/// Group-aware lorebook triggers panel for the group chat sidebar — active
/// entry count badge in the header, entries list always visible.
class GroupLorebookSection extends StatelessWidget {
  final ChatService chatService;
  final ValueListenable<TextEditingValue>? draft;
  const GroupLorebookSection({
    super.key,
    required this.chatService,
    this.draft,
  });

  @override
  Widget build(BuildContext context) {
    final activeEntries = chatService.getActiveGroupLoreEntries();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SidebarSubHeader(
          icon: Icons.menu_book,
          label: 'Lorebook',
          accent: AppColors.porchHoneyOf(context),
          trailing: activeEntries.isNotEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bondHighOf(
                      context,
                    ).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${activeEntries.length}',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.bondHighOf(context),
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LoreTokenMeter(chat: chatService),
              if (activeEntries.isEmpty)
                Text(
                  'No active lorebook entries.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in activeEntries)
                      LoreEntryRow(
                        entry: entry,
                        label: entry.displayName,
                        verticalPadding: 3,
                        injected: true,
                        pill: loreTimerPill(context, chatService, entry),
                      ),
                  ],
                ),
              if (draft != null)
                WouldTriggerStrip(chat: chatService, draft: draft!),
            ],
          ),
        ),
      ],
    );
  }
}
