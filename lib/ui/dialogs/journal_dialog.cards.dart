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

part of 'journal_dialog.dart';

extension _JournalDialogCards on _JournalDialogState {
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
            DropdownMenuItem(value: p.id, child: Text("${p.name}'s Journal")),
        ],
        onChanged: (id) {
          if (id == null) return;
          rebuildState(() {
            _ownerId = id;
            _ownerName = owners.firstWhere((p) => p.id == id).name;
            _loading = true;
          });
          _load();
        },
      ),
    );
  }

  int get _belongingsCount => _cards.where((c) => c.category == 'item').length;

  List<JournalMemoryData> get _diaryCards =>
      _cards.where((c) => c.category != 'item').toList();

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

  Widget _emptyBelongings(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No belongings notes yet.\n\nWhen $_ownerName sets something down, '
          'hands it over, or changes outfits, a short placement memory lands '
          'here — so "where are my keys?" has an answer without scrolling the '
          'whole diary.',
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

  /// [categories] — diary uses [kJournalCategories] (no item); Belongings
  /// uses `const ['item']`. Section headers omit when a single category is
  /// already named by the tab.
  Widget _cardList(
    BuildContext context,
    String userName, {
    required List<String> categories,
  }) {
    final sections = <Widget>[];
    final showHeaders = categories.length > 1;
    for (final category in categories) {
      final cards = _cards.where((c) => c.category == category).toList();
      if (cards.isEmpty) continue;
      if (showHeaders) {
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
      }
      sections.addAll([
        for (final card in cards)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: JournalCardTile(
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
}
