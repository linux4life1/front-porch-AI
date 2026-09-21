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

import 'transcript_auto_scroll.dart';

/// Reverse-list controller that keeps the visible rows still when the
/// newest (offset-0) end grows — streaming tokens, a newly completed
/// bubble, or any other height change at that end.
///
/// A plain [ScrollController] on `reverse: true` preserves pixels-from-the
/// newest edge, so growth yanks the viewport toward the new bottom. That
/// is the token auto-scroll the 2026-09-18 lock forbids, including when
/// the user is already at offset 0 watching generation.
class TranscriptScrollController extends ScrollController {
  TranscriptScrollController({super.initialScrollOffset, super.debugLabel});

  /// Next extent change is a new baseline (chat switch, journal jump).
  void resetHold() {
    if (!hasClients) return;
    final pos = position;
    if (pos is TranscriptScrollPosition) pos.resetHold();
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return TranscriptScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class TranscriptScrollPosition extends ScrollPositionWithSingleContext {
  TranscriptScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    ScrollPosition? oldPosition,
    super.debugLabel,
  }) : super(oldPosition: oldPosition) {
    if (oldPosition is TranscriptScrollPosition) {
      _heldMax = oldPosition._heldMax;
    } else if (oldPosition != null && oldPosition.hasContentDimensions) {
      _heldMax = oldPosition.maxScrollExtent;
    }
  }

  double? _heldMax;

  void resetHold() {
    _heldMax = null;
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final prior = hasContentDimensions ? this.maxScrollExtent : _heldMax;
    final priorPixels = hasPixels ? pixels : null;
    final result = super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent,
    );
    if (prior != null && priorPixels != null && prior != maxScrollExtent) {
      final next = heldTranscriptOffset(
        offset: priorPixels,
        previousMax: prior,
        newMax: maxScrollExtent,
        minExtent: minScrollExtent,
      );
      if (next != pixels) correctPixels(next);
    }
    _heldMax = maxScrollExtent;
    return result;
  }
}
