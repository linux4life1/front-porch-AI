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

// A dropdown picked on a Settings tab keeps keyboard focus, and its grey
// focus box is ink on the nearest Material. That Material only clips ink to
// its own bounds. When it was the page Scaffold, scrolling the dropdown up
// left the box painted over the (transparent) tab bar.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/settings_page_harness.dart';

void main() {
  testWidgets('a picked dropdown scrolled up keeps its focus box inside the '
      'tab body, off the tab bar', (tester) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    await mountSettings(
      tester,
      lastUsedIsB: false,
      before: (rig) => rig.store.expressionSettings.setExpressionEnabled(true),
    );
    // A window short enough that the tab scrolls.
    await tester.binding.setSurfaceSize(const Size(1400, 700));
    await tester.pump();
    await openTab(tester, 'Voice & Media');

    // The expression classification picker. (It was the Advanced tab's KV
    // cache picker, which is now only in the preset editor and the dialog.)
    final picker = find.byWidgetPredicate(
      (w) =>
          w is DropdownButton<String> &&
          (w.items?.any((i) => i.value == 'onnx') ?? false),
    );
    await pickFromDropdown(tester, picker, 'Manual Only');

    final ink = find.descendant(of: picker, matching: find.byType(InkWell));
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(
      find.ancestor(
        of: find.byElementPredicate((e) => identical(e, focused)),
        matching: picker,
      ),
      findsOneWidget,
      reason: 'the dropdown no longer holds keyboard focus after a pick',
    );

    // Scroll the dropdown up until its top half sits above the tab body,
    // where the tab bar is (a dense dropdown is shorter than 30 px).
    final tabBar = tester.getRect(find.byType(TabBar));
    final position = Scrollable.of(tester.element(picker)).position;
    final half = tester.getRect(ink).height / 2;
    final dy = tester.getRect(ink).top - (tabBar.bottom - half);
    position.jumpTo(position.pixels + dy);
    await tester.pump();
    expect(
      tester.getRect(ink).overlaps(tabBar),
      isTrue,
      reason: 'the setup did not move the dropdown under the tab bar',
    );

    // Paint the Material the dropdown's ink lives on and keep what of the
    // focus box survives the clips around it (ink paints before children,
    // under translates and clips only).
    final controller = Material.of(tester.element(ink)) as RenderBox;
    final focusColor = tester.widget<InkWell>(ink).focusColor!;
    final drawn = paintedFocusBoxes(controller, focusColor);
    expect(drawn, isNotEmpty, reason: 'the focus box is not painted at all');
    for (final box in drawn) {
      expect(
        box.overlaps(tabBar),
        isFalse,
        reason: 'the focus box is painted over the tab bar: $box vs $tabBar',
      );
    }
  });
}

/// The global rects, after clipping, where [box] paints a [color] rect.
List<Rect> paintedFocusBoxes(RenderBox box, Color color) {
  final origin = box.localToGlobal(Offset.zero);
  final stack = <(Offset, Rect)>[];
  var offset = Offset.zero;
  var clip = Rect.largest;
  final out = <Rect>[];
  expect(
    box,
    paints..everything((method, args) {
      switch (method) {
        case #save || #saveLayer:
          stack.add((offset, clip));
        case #restore:
          (offset, clip) = stack.removeLast();
        case #translate:
          offset += Offset(args[0] as double, args[1] as double);
        case #clipRect:
          clip = clip.intersect((args[0] as Rect).shift(offset));
        case #drawRect
            when (args[1] as Paint).color.toARGB32() == color.toARGB32():
          final shown = (args[0] as Rect).shift(offset).intersect(clip);
          if (!shown.isEmpty) out.add(shown.shift(origin));
      }
      return true;
    }),
  );
  return out;
}
