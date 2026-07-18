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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/journal_card_editor.dart';
import 'package:front_porch_ai/ui/dialogs/journal_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/journal_review_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import '../sidebar_tokens.dart';

/// "The Journal" sidebar panel — a compact peek at the focused character's
/// diary for this chat (docs/design/journal-memory.md §8 phase 3): the three
/// freshest memories with their emotion chips, plus "Open" (the full
/// [JournalDialog]) and "Plant a memory." In a group this follows the focused
/// member — every member keeps their own diary.
///
/// Hidden while the Journal is disabled (the toggle + explainer live in
/// SummarySection directly above). Reloads itself when the session switches
/// or a maintenance pass finishes; its own mutations reload inline.
class JournalPanel extends StatefulWidget {
  final ChatService chatService;
  final String characterId;
  final String characterName;

  /// Receipts tap-to-jump, forwarded into the diary dialog (null in tests
  /// or hosts without a scrollable chat behind the panel).
  final ValueChanged<int>? onJumpToMessage;

  const JournalPanel({
    super.key,
    required this.chatService,
    required this.characterId,
    required this.characterName,
    this.onJumpToMessage,
  });

  @override
  State<JournalPanel> createState() => _JournalPanelState();
}

class _JournalPanelState extends State<JournalPanel> {
  List<JournalMemoryData> _cards = const [];
  String? _loadedSessionId;
  bool _passWasRunning = false;

  @override
  void initState() {
    super.initState();
    widget.chatService.addListener(_onChatChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant JournalPanel old) {
    super.didUpdateWidget(old);
    if (old.characterId != widget.characterId) _load();
  }

  @override
  void dispose() {
    widget.chatService.removeListener(_onChatChanged);
    super.dispose();
  }

  /// ChatService notifies constantly (streaming); only reload the DB when a
  /// maintenance pass just finished writing cards or the chat switched.
  void _onChatChanged() {
    final running = widget.chatService.isSummaryGenerating;
    final passJustFinished = _passWasRunning && !running;
    _passWasRunning = running;
    if (passJustFinished ||
        widget.chatService.currentSessionId != _loadedSessionId) {
      _load();
    }
  }

  Future<void> _load() async {
    final sessionId = widget.chatService.currentSessionId;
    final cards = sessionId == null
        ? const <JournalMemoryData>[]
        : await widget.chatService.journalStore.cardsFor(
            sessionId,
            widget.characterId,
          );
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _loadedSessionId = sessionId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    if (!storage.journalEnabled) return const SizedBox.shrink();
    final accent = AppColors.journalAccentOf(context);

    // Preview: pinned first (store order), then the freshest unpinned.
    final pinned = _cards.where((c) => c.pinned);
    final unpinned = _cards.where((c) => !c.pinned).toList().reversed;
    final preview = [...pinned, ...unpinned].take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SidebarSubHeader(
          icon: Icons.menu_book,
          label: 'The Journal',
          accent: accent,
          trailing: Text(
            '${_cards.length}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary(context),
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Review-first mode: proposals parked by the last maintenance pass.
        if (widget.chatService.journalReview.hasPendingFor(
          widget.chatService.currentSessionId,
        ))
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
              onTap: _openReview,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.porchHoneyOf(
                    context,
                  ).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
                  border: Border.all(
                    color: AppColors.porchHoneyOf(
                      context,
                    ).withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.rate_review_outlined,
                      size: 14,
                      color: AppColors.porchHoneyOf(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${widget.chatService.journalReview.pending!.totalProposals} '
                        'proposed update(s) — tap to review',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.porchHoneyOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (preview.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(
              '${widget.characterName} has no memories of this chat yet — '
              'entries appear as you talk.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary(context),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Column(
              children: [
                for (final card in preview)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Text(
                          journalCardEmoji(card),
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            card.content,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                        ),
                        if (card.pinned)
                          Icon(
                            Icons.push_pin,
                            size: 11,
                            color: AppColors.porchHoneyOf(context),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Row(
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: _openJournal,
                icon: Icon(Icons.auto_stories, size: 13, color: accent),
                label: Text(
                  'Open',
                  style: TextStyle(fontSize: 11, color: accent),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: _plantMemory,
                icon: Icon(
                  Icons.spa,
                  size: 13,
                  color: AppColors.iconSecondary(context),
                ),
                label: Text(
                  'Plant a memory',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openReview() async {
    await JournalReviewDialog.show(context, widget.chatService.journalReview);
    // Applied cards / cleared banner — refresh either way.
    await _load();
  }

  Future<void> _openJournal() async {
    await JournalDialog.show(
      context,
      chatService: widget.chatService,
      ownerId: widget.characterId,
      ownerName: widget.characterName,
      onJumpToMessage: widget.onJumpToMessage,
    );
    // Pick up whatever was pinned/edited/planted/retired in the dialog.
    await _load();
  }

  Future<void> _plantMemory() async {
    final userName = Provider.of<UserPersonaService>(
      context,
      listen: false,
    ).persona.name;
    final draft = await JournalCardEditorDialog.show(
      context,
      title: 'Plant a memory in ${widget.characterName}\'s journal',
      userName: userName,
    );
    if (draft == null || !mounted) return;
    final sessionId = widget.chatService.currentSessionId;
    if (sessionId == null) return;
    final storage = Provider.of<StorageService>(context, listen: false);
    await widget.chatService.journalStore.addCard(
      sessionId: sessionId,
      characterId: widget.characterId,
      content: draft.content,
      category: draft.category,
      emotionLabel: draft.feeling,
      maxCards: storage.journalMaxCards,
    );
    await _load();
  }
}
