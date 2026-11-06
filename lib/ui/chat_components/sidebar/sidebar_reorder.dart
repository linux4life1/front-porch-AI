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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// True while the sidebar layout is locked. [SidebarReorderHandle] reads it and
/// turns every grip — top-level section or nested accordion leaf — into a
/// dimmed lock icon that starts no drag, so the arrangement cannot move by
/// accident. One switch for the whole body; the pill that flips it lives in
/// the pinned chrome above.
class SidebarReorderLock extends InheritedWidget {
  final bool locked;

  const SidebarReorderLock({
    super.key,
    required this.locked,
    required super.child,
  });

  /// The lock state above [context], false outside the sidebar body (the
  /// standalone tests and any other host).
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SidebarReorderLock>()
          ?.locked ??
      false;

  @override
  bool updateShouldNotify(SidebarReorderLock oldWidget) =>
      oldWidget.locked != locked;
}

/// THE drag grip of the reorderable chat sidebar: a small handle that starts a
/// drag on its own list item and never toggles the thing it sits on.
///
/// It must live inside a [ReorderableListView] item (the listener reads that
/// list's state from its context). The caller wraps it opaque so a tap on the
/// grip does not reach the header's InkWell — the same trick the accordion's
/// trailing switch/gear uses. Error Book P44: a drag must not act until the
/// movement is unmistakable; below it, the press is still the click it was.
///
/// Under a locked [SidebarReorderLock] it renders an inert lock icon instead:
/// the list keeps its item keys and order, only the drag start disappears.
class SidebarReorderHandle extends StatelessWidget {
  /// The item's index in its own reorderable list.
  final int index;

  /// The tooltip words ("Drag to reorder").
  final String label;

  const SidebarReorderHandle({
    super.key,
    required this.index,
    this.label = 'Drag to reorder',
  });

  @override
  Widget build(BuildContext context) {
    if (SidebarReorderLock.of(context)) {
      return Tooltip(
        message: 'Sidebar layout locked',
        child: Icon(
          Icons.lock_outline,
          size: 16,
          color: AppColors.textTertiary(context),
        ),
      );
    }
    return ReorderableDragStartListener(
      index: index,
      child: Tooltip(
        message: label,
        child: Icon(
          Icons.drag_handle,
          size: 16,
          color: AppColors.textTertiary(context),
        ),
      ),
    );
  }
}

/// Wraps a grip opaque so a tap on it never reaches the thing it sits on —
/// the same trick the accordion's header uses (Error Book P44). The leaf
/// widgets and the Character State leaf builder call this on the grip they
/// are handed.
Widget opaqueReorderHandle(Widget handle) => GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: () {},
  child: handle,
);

/// The sidebar's mouse-wheel pump while a tab is picked up.
///
/// A reorderable list freezes its own scroll for the duration of an item
/// drag, which leaves mouse users stuck: the wheel does nothing while a grip
/// is held, so a tab at the bottom cannot travel to the top of a long
/// sidebar. The freeze happens because the list's own Scrollable claims the
/// wheel signal first (signals dispatch deepest-first) and then no-ops it.
/// So the pump claims deeper: every reorderable item wraps itself in a
/// [WheelPump] listener that participates ONLY while a drag is active —
/// including while the item is lifted in the drag feedback, whose path runs
/// through the same wrapper. Outside a drag nothing changes: the wrapper
/// never registers, and the list scrolls the wheel the normal way.
///
/// Nested lists — the Character State, Journal & Memory and Story Tools
/// leaves — report their drags up through this pump and wrap their leaves in
/// the same listener, so a leaf in hand pumps the body's scroll.
class ReorderScrollPump extends InheritedWidget {
  /// True while any grip in the body is held. Owned by the sidebar body's
  /// State; [reportDrag] flips it.
  final ValueNotifier<bool> dragging;

  /// The wheel handler: scrolls the body's list by hand while [dragging].
  final void Function(PointerSignalEvent event) onWheel;

  const ReorderScrollPump({
    super.key,
    required this.dragging,
    required this.onWheel,
    required super.child,
  });

  /// The pump above [context], or null outside the sidebar body. Read
  /// without registering a dependency.
  static ReorderScrollPump? maybeOf(BuildContext context) =>
      context
              .getElementForInheritedWidgetOfExactType<ReorderScrollPump>()
              ?.widget
          as ReorderScrollPump?;

  /// Said by a list's onReorderStart/onReorderEnd while a tab is held.
  void reportDrag(bool active) => dragging.value = active;

  @override
  bool updateShouldNotify(ReorderScrollPump oldWidget) => false;
}

/// One reorderable item, pumping the wheel while a drag is in hand. The
/// [Listener] is only wired (non-null) while a drag runs, so it never joins
/// the signal race when nothing is being dragged.
class WheelPump extends StatelessWidget {
  final ReorderScrollPump? pump;
  final Widget child;

  const WheelPump({super.key, required this.pump, required this.child});

  @override
  Widget build(BuildContext context) {
    final pump = this.pump;
    if (pump == null) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: pump.dragging,
      builder: (context, dragging, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: dragging ? pump.onWheel : null,
        child: child,
      ),
      child: child,
    );
  }
}
