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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Where the library grid puts card [index], worked out from the grid's own
/// delegate and padding — so a box can reach cards that are scrolled out of
/// view and were never built.
class LibraryGridGeometry {
  const LibraryGridGeometry({required this.delegate, required this.padding});

  final SliverGridDelegate delegate;
  final EdgeInsets padding;

  /// Every card's rect in content coordinates (scroll offset 0), for a grid
  /// [width] wide.
  List<Rect> rects(int count, double width) {
    final layout = delegate.getLayout(
      SliverConstraints(
        axisDirection: AxisDirection.down,
        growthDirection: GrowthDirection.forward,
        userScrollDirection: ScrollDirection.idle,
        scrollOffset: 0,
        precedingScrollExtent: 0,
        overlap: 0,
        remainingPaintExtent: 0,
        crossAxisExtent: width - padding.horizontal,
        crossAxisDirection: AxisDirection.right,
        viewportMainAxisExtent: 0,
        remainingCacheExtent: 0,
        cacheOrigin: 0,
      ),
    );
    return [
      for (var i = 0; i < count; i++)
        () {
          final g = layout.getGeometryForChildIndex(i);
          return Rect.fromLTWH(
            padding.left + g.crossAxisOffset,
            padding.top + g.scrollOffset,
            g.crossAxisExtent,
            g.mainAxisExtent,
          );
        }(),
    ];
  }
}

/// A quick mouse drag on the library grid draws a box and picks every
/// character and group card it touches (library phase 2). It starts on empty
/// space or on a card — holding still first starts a card drag instead —
/// and Ctrl/Cmd held at the start adds to the picks rather than replacing
/// them. Near the top or bottom edge the grid scrolls. Mouse only: touch and
/// trackpad gestures keep scrolling, and the scrollbar keeps its thumb.
class LibraryBoxSelect extends StatefulWidget {
  const LibraryBoxSelect({
    super.key,
    required this.child,
    required this.scrollController,
    required this.geometry,
    required this.keys,
    required this.groupKeys,
    required this.pickedCharacters,
    required this.pickedGroups,
    required this.onBox,
  });

  final Widget child;
  final ScrollController scrollController;
  final LibraryGridGeometry geometry;

  /// The selection key of each grid cell, in grid order; null for folder
  /// tiles, which a box never picks.
  final List<String?> keys;

  /// Which of [keys] are group chats.
  final Set<String> groupKeys;
  final Set<String> pickedCharacters;
  final Set<String> pickedGroups;

  /// The picks while the box moves: what it touches, plus what was picked
  /// before when Ctrl/Cmd was held.
  final void Function(Set<String> characters, Set<String> groups) onBox;

  @override
  State<LibraryBoxSelect> createState() => _LibraryBoxSelectState();
}

class _LibraryBoxSelectState extends State<LibraryBoxSelect> {
  static const _edge = 40.0;
  static const _scrollbarGutter = 16.0;

  Offset? _start; // content coordinates
  Offset _pointer = Offset.zero; // viewport coordinates
  Set<String> _baseChars = const {};
  Set<String> _baseGroups = const {};
  Set<String> _lastTouched = const {};
  Timer? _autoScroll;

  double get _offset =>
      widget.scrollController.hasClients ? widget.scrollController.offset : 0;

  bool get _active => _start != null;

  Rect get _box => Rect.fromPoints(_start!, _pointer + Offset(0, _offset));

  void _begin(DragStartDetails details) {
    final keys = HardwareKeyboard.instance;
    final add = keys.isControlPressed || keys.isMetaPressed;
    _baseChars = add ? {...widget.pickedCharacters} : const {};
    _baseGroups = add ? {...widget.pickedGroups} : const {};
    _lastTouched = const {};
    _pointer = details.localPosition;
    setState(() => _start = details.localPosition + Offset(0, _offset));
    _report();
  }

  void _move(DragUpdateDetails details) {
    if (!_active) return;
    setState(() => _pointer = details.localPosition);
    _report();
    _autoScroll ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _scrollTick(),
    );
  }

  void _end(DragEndDetails _) => _finish();

  void _finish() {
    _autoScroll?.cancel();
    _autoScroll = null;
    if (mounted) setState(() => _start = null);
  }

  void _scrollTick() {
    final c = widget.scrollController;
    final height = context.size?.height ?? 0;
    if (!_active || !c.hasClients || height == 0) return;
    final depth = _pointer.dy < _edge
        ? _pointer.dy - _edge
        : _pointer.dy > height - _edge
        ? _pointer.dy - (height - _edge)
        : 0.0;
    if (depth == 0) return;
    final p = c.position;
    final next = (p.pixels + depth.clamp(-_edge, _edge) / 2).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    if (next == p.pixels) return;
    c.jumpTo(next);
    setState(() {});
    _report();
  }

  void _report() {
    final width = context.size?.width ?? 0;
    final box = _box;
    final rects = widget.geometry.rects(widget.keys.length, width);
    final touched = <String>{
      for (var i = 0; i < rects.length; i++)
        if (widget.keys[i] != null && rects[i].overlaps(box)) widget.keys[i]!,
    };
    if (setEquals(touched, _lastTouched)) return;
    _lastTouched = touched;
    widget.onBox(
      {..._baseChars, ...touched.where((k) => !widget.groupKeys.contains(k))},
      {..._baseGroups, ...touched.where(widget.groupKeys.contains)},
    );
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchTerracottaOf(context);
    return RawGestureDetector(
      gestures: {
        _BoxDragRecognizer:
            GestureRecognizerFactoryWithHandlers<_BoxDragRecognizer>(
              () => _BoxDragRecognizer(
                gutter: _scrollbarGutter,
                width: () => context.size?.width ?? 0,
              ),
              (r) => r
                ..dragStartBehavior = DragStartBehavior.down
                ..onStart = _begin
                ..onUpdate = _move
                ..onEnd = _end
                ..onCancel = _finish,
            ),
      },
      child: MouseRegion(
        cursor: _active ? SystemMouseCursors.precise : MouseCursor.defer,
        child: Stack(
          children: [
            widget.child,
            if (_active)
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRect(
                    child: CustomSingleChildLayout(
                      delegate: _BoxPlacement(_box.shift(Offset(0, -_offset))),
                      child: DecoratedBox(
                        key: const Key('library-select-box'),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          border: Border.all(color: accent, width: 1.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Primary-button mouse drags only, and not on the scrollbar's strip at
/// the right edge.
class _BoxDragRecognizer extends PanGestureRecognizer {
  _BoxDragRecognizer({required this.gutter, required this.width})
    : super(
        supportedDevices: const {PointerDeviceKind.mouse},
        allowedButtonsFilter: (buttons) => buttons == kPrimaryButton,
      );

  final double gutter;
  final double Function() width;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      event.localPosition.dx < width() - gutter &&
      super.isPointerAllowed(event);
}

class _BoxPlacement extends SingleChildLayoutDelegate {
  _BoxPlacement(this.rect);

  final Rect rect;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tight(rect.size);

  @override
  Offset getPositionForChild(Size size, Size childSize) => rect.topLeft;

  @override
  bool shouldRelayout(_BoxPlacement oldDelegate) => oldDelegate.rect != rect;
}
