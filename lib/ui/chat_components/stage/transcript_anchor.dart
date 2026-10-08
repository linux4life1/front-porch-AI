// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'package:front_porch_ai/models/models.dart';

/// Keeps the row the reader is looking at still when older rows mount
/// above it. A lazy list's max extent is an estimate, so holding by the
/// change in max lands the reader rows away from where they were; this
/// measures the row itself once it is laid out again.
class TranscriptAnchors {
  final Map<ChatMessage, BuildContext> _rows = Map.identity();
  ChatMessage? _message;
  double _into = 0;
  int _tries = 0;

  bool get pending => _message != null;

  /// The anchor row has a box in the current layout.
  bool get rowLaidOut {
    final row = _message == null ? null : _rows[_message];
    return row != null && _scrollTopOf(row) != null;
  }

  /// Remember the row at the viewport top and how far into it the
  /// reader is. Call before the prepend lays out.
  void capture(ScrollController c) {
    _message = null;
    _tries = 0;
    if (!c.hasClients) return;
    // Last row starting at or above the viewport top; at the very top
    // (list padding) the first row below it.
    double? best;
    for (final row in _rows.entries) {
      final top = _scrollTopOf(row.value);
      if (top == null) continue;
      final above = top <= c.offset;
      final better =
          best == null ||
          (above
              ? (best > c.offset || top > best)
              : (best > c.offset && top < best));
      if (better) {
        best = top;
        _message = row.key;
      }
    }
    if (best != null) _into = c.offset - best;
  }

  void cancel() => _message = null;

  /// Put the anchor row back where it was. False once settled, given up,
  /// or the row is gone; true when another frame should try again.
  bool restore(ScrollController c, void Function(double to) jump) {
    final message = _message;
    if (message == null || !c.hasClients) return false;
    final row = _rows[message];
    final top = row == null ? null : _scrollTopOf(row);
    if (top != null) {
      final p = c.position;
      final to = (top + _into).clamp(p.minScrollExtent, p.maxScrollExtent);
      if ((to - c.offset).abs() <= 0.5) {
        _message = null;
        return false;
      }
      jump(to);
    }
    if (++_tries >= 6) {
      _message = null;
      return false;
    }
    return true;
  }

  static double? _scrollTopOf(BuildContext row) {
    if (!row.mounted) return null;
    final box = row.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    return viewport?.getOffsetToReveal(box, 0).offset;
  }
}

/// Registers one transcript row with [TranscriptAnchors].
class TranscriptAnchorRow extends StatefulWidget {
  const TranscriptAnchorRow({
    super.key,
    required this.anchors,
    required this.message,
    required this.child,
  });

  final TranscriptAnchors anchors;
  final ChatMessage message;
  final Widget child;

  @override
  State<TranscriptAnchorRow> createState() => _TranscriptAnchorRowState();
}

class _TranscriptAnchorRowState extends State<TranscriptAnchorRow> {
  @override
  void initState() {
    super.initState();
    widget.anchors._rows[widget.message] = context;
  }

  @override
  void didUpdateWidget(TranscriptAnchorRow old) {
    super.didUpdateWidget(old);
    _forget(old);
    widget.anchors._rows[widget.message] = context;
  }

  @override
  void dispose() {
    _forget(widget);
    super.dispose();
  }

  void _forget(TranscriptAnchorRow w) {
    if (identical(w.anchors._rows[w.message], context)) {
      w.anchors._rows.remove(w.message);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
