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

import 'package:front_porch_ai/ui/theme/theme.dart';

/// Sidebar body text: a fixed line-clamp, then tap-to-expand.
///
/// The old 1-line [TextOverflow.ellipsis] in a [Row]/[Expanded] budgeted
/// trailing margin it did not need, so a wide panel still truncated. A
/// fixed 3–4 line clamp uses the width it actually has; tap reveals the
/// rest (and tap again collapses). Short text is never tappable.
class ExpandableSidebarText extends StatefulWidget {
  final String text;
  final int maxLines;
  final TextStyle? style;

  const ExpandableSidebarText({
    super.key,
    required this.text,
    this.maxLines = 4,
    this.style,
  });

  @override
  State<ExpandableSidebarText> createState() => _ExpandableSidebarTextState();
}

class _ExpandableSidebarTextState extends State<ExpandableSidebarText> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant ExpandableSidebarText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final style =
        widget.style ??
        TextStyle(
          fontSize: kSidebarHelpFontSize,
          color: AppColors.textPrimary(context),
          height: 1.35,
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: widget.maxLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        final body = Text(
          widget.text,
          maxLines: _expanded ? null : widget.maxLines,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: style,
        );
        if (!overflows && !_expanded) return body;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: body,
        );
      },
    );
  }
}
