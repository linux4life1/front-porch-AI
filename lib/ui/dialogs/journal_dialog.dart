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

import 'package:front_porch_ai/utils/utils.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'journal_card_editor.dart';
import 'journal_card_tile.dart';
import 'journal_promises_tab.dart';
import 'journal_timeline_tab.dart';

part 'journal_dialog.cards.dart';
part 'journal_dialog.actions.dart';

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

  /// Class door for the cards/actions part extensions — [setState] is
  /// @protected and cannot be called from an extension.
  void rebuildState(VoidCallback fn) => setState(fn);

  /// One reader for the receipt column. The source-scan in
  /// receipt_ids_test pins this library file (not the actions part).
  List<int> _decodeReceipts(String? raw) => decodeReceiptIds(raw);

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
            // Diary | Promises | Belongings | Our Story — Belongings used to
            // bury at the bottom of a long Diary list (156+ cards); its own
            // tab is the same pattern Promises got for the same reason.
            Expanded(
              child: DefaultTabController(
                length: 4,
                child: Column(
                  children: [
                    TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: accent,
                      unselectedLabelColor: AppColors.textTertiary(context),
                      indicatorColor: accent,
                      labelStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      tabs: [
                        const Tab(height: 34, text: 'Diary'),
                        const Tab(height: 34, text: 'Promises'),
                        Tab(
                          height: 34,
                          text: _belongingsCount == 0
                              ? 'Belongings'
                              : 'Belongings ($_belongingsCount)',
                        ),
                        const Tab(height: 34, text: 'Our Story'),
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
                              : _diaryCards.isEmpty
                              ? _emptyState(context)
                              : _cardList(
                                  context,
                                  userName,
                                  // Emotional diary only — item cards live
                                  // on the Belongings tab (not buried at
                                  // the bottom of this list).
                                  categories: kJournalDisplayCategories
                                      .where((c) => c != 'item')
                                      .toList(),
                                ),
                          JournalPromisesTab(
                            chat: _chat,
                            ownerId: _ownerId,
                            ownerName: widget.ownerName,
                          ),
                          _loading
                              ? Center(
                                  child: CircularProgressIndicator(
                                    color: accent,
                                  ),
                                )
                              : _belongingsCount == 0
                              ? _emptyBelongings(context)
                              : _cardList(
                                  context,
                                  userName,
                                  categories: const ['item'],
                                ),
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
}
