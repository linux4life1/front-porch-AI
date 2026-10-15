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

import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/ui/character_creator/creator_interview.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/creator_dashed_outline.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/interview_question_row.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The Interview card (docs/design/creator-ui-spec.md, "Interview card"):
/// the questions the character is asked before the profile is written, in
/// the voice the Narrative voice selector above it sets. Every mode's
/// Configure step shows it directly after the card holding that selector.
class InterviewQuestionsCard extends StatefulWidget {
  const InterviewQuestionsCard({super.key, required this.state});

  final CreatorState state;

  @override
  State<InterviewQuestionsCard> createState() => _InterviewQuestionsCardState();
}

class _InterviewQuestionsCardState extends State<InterviewQuestionsCard> {
  /// The row just added, which takes the focus when it first builds.
  int? _addedId;

  CreatorState get _state => widget.state;
  CreatorInterview get _interview => _state.interview;

  NarrativeVoice get _voice => NarrativeVoice.parse(
    perspective: _state.narrativePerspective,
    tense: _state.narrativeTense,
  );

  NarrativePronouns get _pronouns =>
      resolveNarrativePronouns(_state.sexController.text);

  @override
  void initState() {
    super.initState();
    _interview.applyVoice(_voice, _pronouns);
  }

  /// The page rebuilds the step on every change, so a new voice or Sex
  /// arrives here.
  @override
  void didUpdateWidget(InterviewQuestionsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _interview.applyVoice(_voice, _pronouns);
  }

  /// Typing goes through the one save queue after a pause, like every box.
  void _edited(int i, String text) {
    _interview.edit(i, text);
    _state.scheduleSave();
    _state.notify();
  }

  void _changed() {
    _state.saveState();
    _state.notify();
  }

  void _add() {
    if (!_interview.add()) return;
    _addedId = _interview.rows.last.id;
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _interview.rows;
    return Container(
      key: const ValueKey('interview-card'),
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: StudioColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StudioColors.lineOf(context)),
      ),
      // The sketch's text: no tracking and the browser's normal line height,
      // where the app's text theme would add both.
      child: DefaultTextStyle.merge(
        style: const TextStyle(letterSpacing: 0, height: 1.2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            _header(context),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              proxyDecorator: (child, _, _) =>
                  Material(type: MaterialType.transparency, child: child),
              itemCount: rows.length,
              onReorderItem: (from, to) {
                _interview.move(from, to);
                _changed();
              },
              itemBuilder: (context, i) => _item(i, rows[i]),
            ),
            _footer(context, rows.length),
          ],
        ),
      ),
    );
  }

  /// Row [i]. Its callbacks find the row by id, not by [i]: two key presses
  /// can land before the list is rebuilt.
  Widget _item(int i, InterviewRow row) {
    int at() => _interview.rows.indexWhere((r) => r.id == row.id);
    return Padding(
      key: ValueKey('interview-row-${row.id}'),
      padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
      child: InterviewQuestionRow(
        index: i,
        question: row.q,
        controller: row.c,
        autofocus: row.id == _addedId,
        onChanged: (text) {
          final i = at();
          if (i >= 0) _edited(i, text);
        },
        onRemove: () {
          final i = at();
          if (i >= 0 && _interview.remove(i)) _changed();
        },
        onMoveBy: (by) {
          final from = at();
          final to = from + by;
          if (from < 0 || to < 0 || to >= _interview.rows.length) return;
          _interview.move(from, to);
          _changed();
        },
      ),
    );
  }

  Widget _header(BuildContext context) {
    final voice = _voice;
    final p = _pronouns;
    final amber = StudioColors.amberOf(context);
    final person = voice.isFirst ? 'first' : 'third';
    final tense = voice.isPast ? 'past' : 'present';
    final whose =
        '${p.possessive[0].toUpperCase()}${p.possessive.substring(1)}';
    final speaks = p.subject == 'they' ? 'speak' : 'speaks';
    final caption = voice.isFirst
        ? 'Follows Narrative voice above.'
        : 'Follows Narrative voice above. $whose own words are quoted when '
              '${p.subject} $speaks.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Text(
                'Interview',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: StudioColors.inkOf(context),
                ),
              ),
              Text(
                'The character is interviewed before the profile is written. Every answer reaches every later step. Edit any question, drag to reorder, or add your own. Each one is a model call, so fewer is faster on a local model. Voice first and appearance last works best.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: StudioColors.mutedOf(context),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  spacing: 8,
                  children: [
                    Container(
                      key: const ValueKey('interview-voice-pill'),
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Text(
                        'Answered in $person person, $tense',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: amber,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        caption,
                        key: const ValueKey('interview-voice-caption'),
                        style: TextStyle(
                          fontSize: 12,
                          color: StudioColors.faintOf(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 36,
          child: TextButton(
            key: const ValueKey('interview-reset'),
            onPressed: () {
              _interview.reset();
              _changed();
            },
            style: TextButton.styleFrom(
              foregroundColor: amber,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Reset to the standard questions',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _footer(BuildContext context, int count) {
    final amber = StudioColors.amberOf(context);
    final canAdd = !_interview.atCap;
    return Row(
      spacing: 12,
      children: [
        Opacity(
          opacity: canAdd ? 1 : 0.45,
          child: CustomPaint(
            foregroundPainter: CreatorDashedOutline(
              color: amber,
              radius: 10,
              width: 1,
              dash: 3,
              gap: 3,
            ),
            child: SizedBox(
              height: 40,
              child: TextButton.icon(
                key: const ValueKey('interview-add'),
                onPressed: canAdd ? _add : null,
                icon: const Icon(Icons.add, size: 16),
                label: const Text(
                  'Add a question',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: amber,
                  disabledForegroundColor: amber,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Text(
            '$count of $kInterviewQuestionCap · remove them all and the profile comes straight from your settings, no interview',
            key: const ValueKey('interview-count'),
            style: TextStyle(
              fontSize: 12,
              color: StudioColors.mutedOf(context),
            ),
          ),
        ),
      ],
    );
  }
}
