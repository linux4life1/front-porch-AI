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

import 'package:front_porch_ai/services/chargen/chargen.dart' show isHandEdited;
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/character_creator/creator_profile.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state_engine.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/creator_text_card.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/review_rewrite_card.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The Review step's Lorebook card (docs/design/creator-ui-spec.md, "Review
/// step"): up to three entry rows and "and {n} more"; "Open the lorebook
/// editor" lists every entry with its keep checkbox (an unchecked entry is
/// left out of the saved character) and opens any of them for editing; an
/// entry edited by hand says so and survives "Rewrite the lorebook".
class ReviewLorebookSection extends StatefulWidget {
  const ReviewLorebookSection({super.key, required this.state});

  final CreatorState state;

  @override
  State<ReviewLorebookSection> createState() => _ReviewLorebookSectionState();
}

class _ReviewLorebookSectionState extends State<ReviewLorebookSection> {
  bool _editorOpen = false;

  CreatorState get _s => widget.state;

  Future<void> _edit(int i) async {
    final book = _s.generatedCard?.lorebook;
    if (book == null || i >= book.entries.length) return;
    final edited = await showLorebookEntryDialog(
      context: context,
      existing: book.entries[i],
    );
    if (edited == null || !mounted) return;
    book.entries[i] = edited;
    _s.notify();
  }

  @override
  Widget build(BuildContext context) {
    final lorebook = _s.generatedCard?.lorebook;
    if (lorebook == null || lorebook.entries.isEmpty) {
      return const SizedBox.shrink();
    }
    const kind = ReviewRewrite.lorebook;
    final r = _s.review;
    final writing = r.writing(kind);
    final entries = lorebook.entries;
    final shown = _editorOpen ? entries.length : entries.length.clamp(0, 3);
    final more = entries.length - shown;
    final amber = StudioColors.amberOf(context);
    LLMProvider llm() => Provider.of<LLMProvider>(context, listen: false);

    return CreatorCardShell(
      key: const ValueKey('review-lorebook'),
      title: 'Lorebook',
      subtitle: '${entries.length} entries',
      writing: writing,
      trailing: SizedBox(
        height: 36,
        child: TextButton(
          key: const ValueKey('review-lorebook-editor'),
          onPressed: writing
              ? null
              : () => setState(() => _editorOpen = !_editorOpen),
          style: TextButton.styleFrom(
            foregroundColor: amber,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            'Open the lorebook editor',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      children: [
        Opacity(
          opacity: writing ? 0.45 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              for (var i = 0; i < shown; i++)
                ReviewLoreRow(
                  key: ValueKey('review-lore-$i'),
                  entry: entries[i],
                  editedByHand: isHandEdited(entries[i]),
                  onEdit: () => _edit(i),
                  kept: _editorOpen
                      ? (_s.lorebookEntryEnabled[i] ?? true)
                      : null,
                  onToggle: _editorOpen
                      ? (v) {
                          _s.lorebookEntryEnabled[i] = v;
                          _s.notify();
                        }
                      : null,
                ),
              if (more > 0)
                Text(
                  'and $more more',
                  style: TextStyle(
                    fontSize: 12,
                    color: StudioColors.faintOf(context),
                  ),
                ),
            ],
          ),
        ),
        ReviewRewriteRow(
          id: 'review-lorebook',
          steer: r.loreSteer,
          hint:
              'Steer it (optional), e.g. more about the town, less about '
              'the sea',
          action: 'Rewrite the lorebook',
          writing: writing,
          onRun: () => _s.rewriteLorebook(llmProvider: llm()),
          onStop: () => _s.stopReviewRewrite(kind),
          caption:
              'Rewrites the entries from the profile and your direction. An '
              'entry you edited by hand is kept.',
          error: r.errorOf(kind),
        ),
      ],
    );
  }
}
