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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/chat_participant.dart';
import 'package:front_porch_ai/services/chat/journal_physics.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'journal_card_editor.dart';
import 'journal_timeline_tab.dart';

/// The Journal — the full diary reader (docs/design/journal-memory.md §8
/// phase 3). One character's memory cards for THIS chat, grouped by category,
/// with emotion chips, pin/edit/retire, "plant a memory," and source-line
/// receipts. In a group every member keeps their own diary — the header
/// dropdown switches between them (scene guests never journal, so they're
/// not offered).
///
/// Mutations go straight through [ChatService.journalStore]; the next
/// generation picks them up automatically (the injection builder re-reads the
/// DB every turn).
class JournalDialog extends StatefulWidget {
  final ChatService chatService;
  final String ownerId;
  final String ownerName;

  /// Receipts tap-to-jump: called with a message position AFTER this dialog
  /// has closed itself, so the chat behind it can scroll to the line. Null
  /// hides the affordance (hosts without a scrollable chat).
  final ValueChanged<int>? onJumpToMessage;

  const JournalDialog({
    super.key,
    required this.chatService,
    required this.ownerId,
    required this.ownerName,
    this.onJumpToMessage,
  });

  static Future<void> show(
    BuildContext context, {
    required ChatService chatService,
    required String ownerId,
    required String ownerName,
    ValueChanged<int>? onJumpToMessage,
  }) => showDialog(
    context: context,
    builder: (_) => JournalDialog(
      chatService: chatService,
      ownerId: ownerId,
      ownerName: ownerName,
      onJumpToMessage: onJumpToMessage,
    ),
  );

  @override
  State<JournalDialog> createState() => _JournalDialogState();
}

class _JournalDialogState extends State<JournalDialog> {
  late String _ownerId = widget.ownerId;
  late String _ownerName = widget.ownerName;
  List<JournalMemoryData> _cards = const [];
  bool _loading = true;

  ChatService get _chat => widget.chatService;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessionId = _chat.currentSessionId;
    final cards = sessionId == null
        ? const <JournalMemoryData>[]
        : await _chat.journalStore.cardsFor(sessionId, _ownerId);
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.journalAccentOf(context);
    final userName = Provider.of<UserPersonaService>(
      context,
      listen: false,
    ).persona.name;
    // Diary owners: every non-lite cast member (guests never journal).
    final owners = _chat.cast.where((p) => !p.isLite).toList();
    final pinnedCount = _cards.where((c) => c.pinned).length;

    return Dialog(
      backgroundColor: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 560,
        height: 620,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('📖', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: owners.length > 1
                      ? _ownerDropdown(context, owners)
                      : Text(
                          "$_ownerName's Journal",
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary(context),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
                TextButton.icon(
                  onPressed: () => _plantMemory(userName),
                  icon: Icon(Icons.spa, size: 15, color: accent),
                  label: Text(
                    'Plant a memory',
                    style: TextStyle(fontSize: 12, color: accent),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: AppColors.iconSecondary(context),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(
                '${_cards.length} '
                'memor${_cards.length == 1 ? 'y' : 'ies'} from this chat'
                '${pinnedCount > 0 ? ' · $pinnedCount pinned' : ''}'
                ' · memories stay inside this chat',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Diary | Our Story (Living Time §7) — the timeline tab lives in
            // its own file (journal_timeline_tab.dart); only the scaffolding
            // is here so this dialog doesn't regrow.
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      labelColor: accent,
                      unselectedLabelColor: AppColors.textTertiary(context),
                      indicatorColor: accent,
                      labelStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      tabs: const [
                        Tab(height: 34, text: 'Diary'),
                        Tab(height: 34, text: 'Our Story'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _loading
                              ? Center(
                                  child: CircularProgressIndicator(
                                    color: accent,
                                  ),
                                )
                              : _cards.isEmpty
                              ? _emptyState(context)
                              : _cardList(context, userName),
                          JournalTimelineTab(
                            chat: _chat,
                            ownerId: _ownerId,
                            onJumpToMessage: widget.onJumpToMessage,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ownerDropdown(BuildContext context, List<ChatParticipant> owners) {
    // The focused member may not be in the cast anymore (removed mid-dialog);
    // fall back to the first owner so the dropdown always has a valid value.
    final value = owners.any((p) => p.id == _ownerId)
        ? _ownerId
        : owners.first.id;
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isDense: true,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary(context),
        ),
        dropdownColor: AppColors.surfaceContainerOf(context),
        items: [
          for (final p in owners)
            DropdownMenuItem(
              value: p.id,
              child: Text("${p.name}'s Journal"),
            ),
        ],
        onChanged: (id) {
          if (id == null) return;
          setState(() {
            _ownerId = id;
            _ownerName = owners.firstWhere((p) => p.id == id).name;
            _loading = true;
          });
          _load();
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No memories yet.\n\n$_ownerName writes journal entries as you '
          'chat — moments that mattered, things learned about you, and '
          'promises made, each stamped with how it felt. You can also plant '
          'one yourself.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: AppColors.textTertiary(context),
          ),
        ),
      ),
    );
  }

  Widget _cardList(BuildContext context, String userName) {
    final sections = <Widget>[];
    for (final category in const [
      'about_user',
      'about_us',
      'moment',
      'promise',
    ]) {
      final cards = _cards.where((c) => c.category == category).toList();
      if (cards.isEmpty) continue;
      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Text(
            journalCategoryLabel(category, userName).toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: AppColors.journalAccentOf(context),
            ),
          ),
        ),
      );
      sections.addAll([
        for (final card in cards)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _JournalCardTile(
              card: card,
              when: journalWhenLine(card, _chat.timeService.startDate),
              onPinToggle: () async {
                await _chat.journalStore.setPinned(card.id, !card.pinned);
                await _load();
              },
              onEdit: () => _editCard(card, userName),
              onDelete: () => _deleteCard(card),
              onShowReceipts: () => _showReceipts(card),
            ),
          ),
      ]);
    }
    return ListView(children: sections);
  }

  Future<void> _plantMemory(String userName) async {
    final draft = await JournalCardEditorDialog.show(
      context,
      title: 'Plant a memory in $_ownerName\'s journal',
      userName: userName,
    );
    if (draft == null || !mounted) return;
    final sessionId = _chat.currentSessionId;
    if (sessionId == null) return;
    final storage = Provider.of<StorageService>(context, listen: false);
    await _chat.journalStore.addCard(
      sessionId: sessionId,
      characterId: _ownerId,
      content: draft.content,
      category: draft.category,
      emotionLabel: draft.feeling,
      storyDay: _chat.timeService.dayCount,
      storyClock: _chat.timeService.storyClockIso,
      maxCards: storage.journalMaxCards,
    );
    await _load();
  }

  Future<void> _editCard(JournalMemoryData card, String userName) async {
    final draft = await JournalCardEditorDialog.show(
      context,
      title: 'Edit memory',
      userName: userName,
      showCategory: false,
      initialContent: card.content,
      initialFeeling: card.emotionLabel,
    );
    if (draft == null || !mounted) return;
    await _chat.journalStore.reviseCard(
      card,
      content: draft.content,
      feeling: draft.feeling,
    );
    await _load();
  }

  Future<void> _deleteCard(JournalMemoryData card) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardOf(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Retire this memory?',
          style: TextStyle(fontSize: 15, color: AppColors.textPrimary(ctx)),
        ),
        content: Text(
          '"${card.content}"\n\nThe conversation itself is untouched — only '
          'the journal entry is removed.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Keep',
              style: TextStyle(color: AppColors.textSecondary(ctx)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.negativeAccentOf(ctx),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Retire'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _chat.journalStore.retireCard(card.id);
    await _load();
  }

  /// Receipts: the original chat lines this memory was written from
  /// (sourceMessageIds holds message positions — stable across saves, but a
  /// heavily edited/deleted history can outdate them, hence the guards).
  /// Tapping a line closes the receipts AND the journal, then asks the chat
  /// page to scroll to that message.
  Future<void> _showReceipts(JournalMemoryData card) async {
    final positions = _receiptPositions(card);
    final messages = _chat.messages;
    final entries = [
      for (final pos in positions)
        if (pos >= 0 && pos < messages.length)
          (
            pos: pos,
            line: '#$pos  ${messages[pos].sender}: '
                '${messages[pos].displayText}',
          ),
    ];
    final jump = widget.onJumpToMessage;
    final jumpTo = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardOf(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          'Where this memory came from',
          style: TextStyle(fontSize: 15, color: AppColors.textPrimary(ctx)),
        ),
        content: SizedBox(
          width: 420,
          child: entries.isEmpty
              ? Text(
                  'The cited messages are no longer in this chat.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary(ctx),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (jump != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Tap a line to go to it in the chat.',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textTertiary(ctx),
                            ),
                          ),
                        ),
                      for (final entry in entries)
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: jump == null
                              ? null
                              : () => Navigator.of(ctx).pop(entry.pos),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 4,
                            ),
                            child: Text(
                              entry.line,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: AppColors.textSecondary(ctx),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Close',
              style: TextStyle(color: AppColors.textSecondary(ctx)),
            ),
          ),
        ],
      ),
    );
    if (jumpTo == null || jump == null || !mounted) return;
    // Close the journal itself so the chat is visible, THEN scroll.
    Navigator.of(context).pop();
    jump(jumpTo);
  }

  List<int> _receiptPositions(JournalMemoryData card) {
    final raw = card.sourceMessageIds;
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).whereType<int>().toList();
    } catch (_) {
      return const [];
    }
  }
}

/// One memory card row: emotion chip, the memory in the character's words,
/// the feeling line (with the "once felt X — now feels Y" healed arc), and
/// pinned/faded state. Pin is one tap; edit/receipts/retire live in the menu.
class _JournalCardTile extends StatelessWidget {
  final JournalMemoryData card;

  /// "Day 5 · Tue, Mar 3" (story-calendar §4); null for pre-calendar cards.
  final String? when;
  final VoidCallback onPinToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onShowReceipts;

  const _JournalCardTile({
    required this.card,
    this.when,
    required this.onPinToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onShowReceipts,
  });

  @override
  Widget build(BuildContext context) {
    final faded = !JournalPhysics.isHot(card);
    final feelingLine = journalFeelingLine(card);
    final feeling = feelingLine == null
        ? when
        : when == null
        ? feelingLine
        : '$feelingLine · $when';
    final hasReceipts =
        card.sourceMessageIds != null && card.sourceMessageIds!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: card.pinned
              ? AppColors.porchHoneyOf(context).withValues(alpha: 0.5)
              : AppColors.borderOf(context).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Opacity(
              opacity: faded ? 0.45 : 1.0,
              child: Text(
                journalCardEmoji(card),
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.content,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: faded
                        ? AppColors.textTertiary(context)
                        : AppColors.textPrimary(context),
                  ),
                ),
                if (feeling != null || faded) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (feeling != null)
                        Flexible(
                          child: Text(
                            feeling,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontStyle: FontStyle.italic,
                              color: AppColors.textTertiary(context),
                            ),
                          ),
                        ),
                      if (faded) ...[
                        if (feeling != null) const SizedBox(width: 6),
                        Icon(
                          Icons.ac_unit,
                          size: 10,
                          color: AppColors.frostAccentOf(context),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          'faded',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.frostAccentOf(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 15,
            tooltip: card.pinned ? 'Unpin' : 'Pin (never fades)',
            icon: Icon(
              card.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              color: card.pinned
                  ? AppColors.porchHoneyOf(context)
                  : AppColors.iconSecondary(context),
            ),
            onPressed: onPinToggle,
          ),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            iconSize: 15,
            icon: Icon(
              Icons.more_vert,
              color: AppColors.iconSecondary(context),
            ),
            color: AppColors.surfaceContainerOf(context),
            onSelected: (action) {
              if (action == 'edit') {
                onEdit();
              } else if (action == 'receipts') {
                onShowReceipts();
              } else {
                onDelete();
              }
            },
            itemBuilder: (ctx) => [
              _menuItem(ctx, 'edit', Icons.edit_outlined, 'Edit'),
              if (hasReceipts)
                _menuItem(
                  ctx,
                  'receipts',
                  Icons.format_quote,
                  'Where this came from',
                ),
              _menuItem(ctx, 'retire', Icons.delete_outline, 'Retire'),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    BuildContext context,
    String value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem(
      value: value,
      height: 36,
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.iconSecondary(context)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}
