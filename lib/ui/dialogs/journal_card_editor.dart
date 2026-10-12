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
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Shared presentation vocabulary + the write-a-memory dialog for The Journal
/// UI (docs/design/journal-memory.md §8 phase 3). Used by both the sidebar
/// JournalPanel ("Plant a memory") and the full JournalDialog (plant + edit).

/// What the editor hands back: the memory text, its category, and the
/// (optional) feeling attached to it.
typedef JournalCardDraft = ({String content, String category, String? feeling});

/// Emoji chip for a card — the card's feeling mapped to its standard emotion
/// family (same table the expression sprites use), 📝 when it has none.
String journalCardEmoji(JournalMemoryData card) {
  final family = JournalPhysics.emotionFamily(card.emotionLabel);
  return EmotionLabels.emoji[family] ?? '📝';
}

/// Every category a stored card can actually CARRY, for display surfaces —
/// deliberately a superset of [kJournalCategories], which is the LLM pass's
/// authoring enum. 'item' lives only here: belongings cards are written
/// DETERMINISTICALLY from pocket events, never by the model and never by
/// hand, so offering the category to the pass (or the plant editor) would
/// break that guarantee — but a display list that omits it makes every
/// placement memory invisible in the diary, which is exactly the gap the
/// maintainer's "where is the UI for item memories?" question found
/// (2026-08-11).
const List<String> kJournalDisplayCategories = [...kJournalCategories, 'item'];

/// Friendly section name for a card category.
String journalCategoryLabel(String category, String userName) =>
    switch (category) {
      'about_user' => 'About $userName',
      'about_us' => 'About us',
      'promise' => 'Promises',
      'item' => 'Belongings',
      _ => 'Moments',
    };

/// "felt wistful (strongly)" / "once felt sad — now feels proud" — the card's
/// emotional imprint line, or null for an unstamped card.
String? journalFeelingLine(JournalMemoryData card) {
  final emotion = card.emotionLabel;
  if (emotion == null || emotion.isEmpty) return null;
  if (card.originalEmotionLabel != null &&
      card.originalEmotionLabel != emotion) {
    return 'once felt ${card.originalEmotionLabel} — now feels $emotion';
  }
  final intensity = switch (card.emotionIntensity) {
    'strong' => ' (strongly)',
    'mild' => ' (mildly)',
    _ => '',
  };
  return 'felt $emotion$intensity';
}

/// "Day 5 · Tue, Mar 3" — WHEN the memory happened (story-calendar §4), or
/// null for pre-calendar cards. The date re-derives live from the story's
/// Day 1 anchor, so a calendar re-anchor retro-dates every memory.
String? journalWhenLine(JournalMemoryData card, DateTime storyStartDate) {
  final (day, _) = JournalStore.stampOf(card);
  if (day == null) return null;
  final date = StoryClock.dateOnly(storyStartDate).add(Duration(days: day - 1));
  return 'Day $day · ${StoryClock.formatShortDate(date)}';
}

/// Modal editor for one memory card. Returns null on cancel, otherwise the
/// draft. [showCategory] is on for planting a new memory and off when editing
/// (a memory keeps the category it was filed under).
class JournalCardEditorDialog extends StatefulWidget {
  final String title;
  final String userName;
  final bool showCategory;
  final String initialContent;
  final String initialCategory;
  final String? initialFeeling;

  const JournalCardEditorDialog({
    super.key,
    required this.title,
    required this.userName,
    this.showCategory = true,
    this.initialContent = '',
    this.initialCategory = 'moment',
    this.initialFeeling,
  });

  static Future<JournalCardDraft?> show(
    BuildContext context, {
    required String title,
    required String userName,
    bool showCategory = true,
    String initialContent = '',
    String initialCategory = 'moment',
    String? initialFeeling,
  }) => showDialog<JournalCardDraft>(
    context: context,
    builder: (_) => JournalCardEditorDialog(
      title: title,
      userName: userName,
      showCategory: showCategory,
      initialContent: initialContent,
      initialCategory: initialCategory,
      initialFeeling: initialFeeling,
    ),
  );

  @override
  State<JournalCardEditorDialog> createState() =>
      _JournalCardEditorDialogState();
}

class _JournalCardEditorDialogState extends State<JournalCardEditorDialog> {
  late final TextEditingController _content = TextEditingController(
    text: widget.initialContent,
  );
  late String _category = widget.initialCategory;
  late String? _feeling = widget.initialFeeling;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  bool _isDirty() =>
      _content.text.trim() != widget.initialContent.trim() ||
      _category != widget.initialCategory ||
      _feeling != widget.initialFeeling;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.journalAccentOf(context);
    // Keep a nuanced stamped feeling ('wistful', …) selectable when editing —
    // the dropdown otherwise offers the standard labels.
    final feelings = <String?>[
      null,
      if (_feeling != null && !EmotionLabels.all.contains(_feeling)) _feeling,
      ...EmotionLabels.all,
    ];
    final labelStyle = TextStyle(
      fontSize: 11,
      color: AppColors.textSecondary(context),
      fontWeight: FontWeight.w500,
    );

    return UnsavedChangesGuard(
      isDirty: _isDirty,
      child: AlertDialog(
        backgroundColor: AppColors.cardOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          widget.title,
          style: TextStyle(fontSize: 16, color: AppColors.textPrimary(context)),
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: _content,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                maxLength: kJournalMemoryMaxChars,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary(context),
                ),
                decoration: InputDecoration(
                  hintText:
                      'One memory, in the character\'s own words — '
                      '"Sam works nights at the hospital."',
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary(context),
                  ),
                  filled: true,
                  fillColor: AppColors.surfaceContainerOf(context),
                  counterStyle: TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary(context),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.borderOf(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: AppColors.borderOf(context)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: accent),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              if (widget.showCategory) ...[
                Text('Filed under', style: labelStyle),
                const SizedBox(height: 4),
                _dropdown<String>(
                  context,
                  value: _category,
                  items: [
                    // The authorable set, plus 'item' ONLY when editing an
                    // existing belongings card — without it the dropdown's
                    // value is not among its items, which is a crash, not a
                    // fallback. Hand-planting INTO 'item' stays impossible:
                    // belongings cards are deterministic-only.
                    for (final c in {
                      ...kJournalCategories,
                      if (_category == 'item') 'item',
                    })
                      DropdownMenuItem(
                        value: c,
                        child: Text(journalCategoryLabel(c, widget.userName)),
                      ),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? 'moment'),
                ),
                const SizedBox(height: 10),
              ],
              Text('How it felt (optional)', style: labelStyle),
              const SizedBox(height: 4),
              _dropdown<String?>(
                context,
                value: _feeling,
                items: [
                  for (final f in feelings)
                    DropdownMenuItem(
                      value: f,
                      child: Text(
                        f == null
                            ? 'No particular feeling'
                            : '${EmotionLabels.emoji[JournalPhysics.emotionFamily(f)] ?? ''} $f',
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _feeling = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent),
            onPressed: _content.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop((
                    content: _content.text.trim(),
                    category: _category,
                    feeling: _feeling,
                  )),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>(
    BuildContext context, {
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          style: TextStyle(fontSize: 12, color: AppColors.textPrimary(context)),
          dropdownColor: AppColors.surfaceContainerOf(context),
          padding: const EdgeInsets.symmetric(vertical: 8),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
