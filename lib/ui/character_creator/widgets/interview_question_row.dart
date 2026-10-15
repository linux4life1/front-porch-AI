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
import 'package:flutter/services.dart';

import 'package:front_porch_ai/services/chargen/chargen.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/creator_dashed_outline.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// One row of the Interview card (docs/design/creator-ui-spec.md): the drag
/// handle, the number, the question's box (grows with its text) and ×. A
/// conditional row cannot be removed, so it has a spacer where × would be,
/// a dashed border and a pill that says when it is asked; an edited
/// standard row has an amber border and the "kept as written" pill. The
/// handle drags the row, or moves it with ArrowUp / ArrowDown once focused.
class InterviewQuestionRow extends StatefulWidget {
  const InterviewQuestionRow({
    super.key,
    required this.index,
    required this.question,
    required this.controller,
    required this.onChanged,
    required this.onRemove,
    required this.onMoveBy,
    this.autofocus = false,
  });

  /// Position in the list (the drag listener's index); shown as index + 1.
  final int index;
  final InterviewQuestion question;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onRemove;

  /// -1 moves the row up one place, 1 down one.
  final ValueChanged<int> onMoveBy;
  final bool autofocus;

  @override
  State<InterviewQuestionRow> createState() => _InterviewQuestionRowState();
}

class _InterviewQuestionRowState extends State<InterviewQuestionRow> {
  /// The dashed border goes amber while the box has focus, like the others;
  /// the handle's dots go amber while it has focus.
  final _focus = FocusNode();
  final _handle = FocusNode(debugLabel: 'interview handle');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    _handle.addListener(_onFocus);
  }

  void _onFocus() => setState(() {});

  KeyEventResult _onHandleKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final by = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      _ => 0,
    };
    if (by == 0) return KeyEventResult.ignored;
    widget.onMoveBy(by);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _handle
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final n = widget.index + 1;
    final amber = StudioColors.amberOf(context);
    final muted = StudioColors.mutedOf(context);
    final pills = [
      if (q.condition == InterviewCondition.relationship)
        _pill('Asked only when a relationship is set', amber, amber, 0.5),
      if (q.condition == InterviewCondition.nsfw)
        _pill('Asked only when 18+ is on', amber, amber, 0.5),
      if (q.isEdited)
        _pill('Edited · kept as written', muted, StudioColors.lineOf(context)),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        ReorderableDragStartListener(
          index: widget.index,
          child: Focus(
            focusNode: _handle,
            onKeyEvent: _onHandleKey,
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Semantics(
                label: 'Move question $n',
                hint: 'Drag, or use the up and down arrow keys',
                child: SizedBox(
                  width: 24,
                  height: 44,
                  child: Center(
                    child: CustomPaint(
                      size: const Size.square(18),
                      painter: _SixDots(
                        _handle.hasFocus
                            ? amber
                            : StudioColors.faintOf(context),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 22,
          height: 44,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$n',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              _box(context, n),
              if (pills.isNotEmpty)
                Wrap(spacing: 6, runSpacing: 6, children: pills),
            ],
          ),
        ),
        if (q.isConditional)
          const SizedBox(width: 40)
        else
          SizedBox(
            width: 40,
            height: 44,
            child: IconButton(
              onPressed: widget.onRemove,
              tooltip: 'Remove question $n',
              padding: EdgeInsets.zero,
              // The sketch draws × in `muted`; the web card does too.
              icon: Icon(Icons.close, size: 18, color: muted),
            ),
          ),
      ],
    );
  }

  /// The question's box. Its padding includes the border, as the sketch's
  /// border-box text areas do.
  Widget _box(BuildContext context, int n) {
    final q = widget.question;
    final amber = StudioColors.amberOf(context);
    final dashed = q.isConditional && !q.isEdited;
    final width = q.isEdited ? 1.5 : 1.0;
    // No gapPadding: it adds 4px beside the text (it is for a label gap).
    OutlineInputBorder outline(Color c) => OutlineInputBorder(
      gapPadding: 0,
      borderRadius: BorderRadius.circular(12),
      borderSide: dashed ? BorderSide.none : BorderSide(color: c, width: width),
    );
    final rest = outline(q.isEdited ? amber : StudioColors.lineOf(context));
    final field = TextField(
      controller: widget.controller,
      focusNode: _focus,
      autofocus: widget.autofocus,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      onChanged: widget.onChanged,
      style: TextStyle(
        fontSize: 14,
        height: 1.45,
        letterSpacing: 0,
        color: q.isConditional
            ? StudioColors.proseOf(context)
            : StudioColors.inkOf(context),
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: StudioColors.bgOf(context),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14 + width,
          vertical: 10 + width,
        ),
        // One line is as tall as the handle and the number beside it.
        constraints: const BoxConstraints(minHeight: 44),
        border: rest,
        enabledBorder: rest,
        focusedBorder: outline(amber),
      ),
    );
    final label = switch (q.condition) {
      InterviewCondition.relationship => 'Relationship question',
      InterviewCondition.nsfw => '18+ question',
      null => 'Question $n',
    };
    return Semantics(
      label: label,
      child: dashed
          ? CustomPaint(
              foregroundPainter: CreatorDashedOutline(
                color: _focus.hasFocus
                    ? amber
                    : StudioColors.lineStrongOf(context),
                radius: 12,
                width: 1,
                dash: 3,
                gap: 3,
              ),
              child: field,
            )
          : field,
    );
  }

  Widget _pill(String text, Color fg, Color border, [double alpha = 1]) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border.withValues(alpha: alpha)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      );
}

/// The sketch's handle: six 1.6-unit dots on a 24-unit grid, drawn at 18px.
class _SixDots extends CustomPainter {
  const _SixDots(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final paint = Paint()..color = color;
    for (final y in const [6.0, 12.0, 18.0]) {
      for (final x in const [9.0, 15.0]) {
        canvas.drawCircle(Offset(x, y) * scale, 1.6 * scale, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SixDots old) => old.color != color;
}
