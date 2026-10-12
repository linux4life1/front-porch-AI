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

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/ui/dialogs/journal_card_editor.dart';
import 'package:front_porch_ai/ui/dialogs/journal_card_tile.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Centered explanatory note for an empty Journal tab.
class JournalEmptyNote extends StatelessWidget {
  final String message;

  const JournalEmptyNote({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
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
}

/// The memory cards of [categories], in that order, as one scrolling list.
/// The Diary passes every display category but `item`; Belongings passes
/// `const ['item']`. Section headers are omitted when a single category is
/// already named by the tab.
class JournalCardList extends StatelessWidget {
  final List<JournalMemoryData> cards;
  final List<String> categories;
  final String userName;
  final DateTime storyStartDate;
  final ValueChanged<JournalMemoryData> onPinToggle;
  final ValueChanged<JournalMemoryData> onEdit;
  final ValueChanged<JournalMemoryData> onDelete;
  final ValueChanged<JournalMemoryData> onShowReceipts;

  const JournalCardList({
    super.key,
    required this.cards,
    required this.categories,
    required this.userName,
    required this.storyStartDate,
    required this.onPinToggle,
    required this.onEdit,
    required this.onDelete,
    required this.onShowReceipts,
  });

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[];
    final showHeaders = categories.length > 1;
    for (final category in categories) {
      final inCategory = cards.where((c) => c.category == category).toList();
      if (inCategory.isEmpty) continue;
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
        for (final card in inCategory)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: JournalCardTile(
              card: card,
              when: journalWhenLine(card, storyStartDate),
              onPinToggle: () => onPinToggle(card),
              onEdit: () => onEdit(card),
              onDelete: () => onDelete(card),
              onShowReceipts: () => onShowReceipts(card),
            ),
          ),
      ]);
    }
    return ListView(children: sections);
  }
}
