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

/// The library grid's keys (#347): Ctrl+A (Cmd+A on a Mac) selects all,
/// Esc clears the selection. They work only while the grid has the
/// keyboard, so Ctrl+A in the search box still selects its text. A click
/// anywhere in the grid gives it the keyboard, and so does starting a
/// selection.
class LibraryGridKeys extends StatefulWidget {
  const LibraryGridKeys({
    super.key,
    required this.child,
    this.selecting = false,
    this.onSelectAll,
    this.onEscape,
  });

  final Widget child;

  /// True while picking cards; turning it on takes the keyboard.
  final bool selecting;
  final VoidCallback? onSelectAll;

  /// Null leaves Esc to whatever else listens for it.
  final VoidCallback? onEscape;

  @override
  State<LibraryGridKeys> createState() => _LibraryGridKeysState();
}

class _LibraryGridKeysState extends State<LibraryGridKeys> {
  final _focus = FocusNode(debugLabel: 'Library grid');

  @override
  void didUpdateWidget(LibraryGridKeys old) {
    super.didUpdateWidget(old);
    if (widget.selecting && !old.selecting) _focus.requestFocus();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectAll = widget.onSelectAll;
    return CallbackShortcuts(
      bindings: {
        if (selectAll != null) ...{
          const SingleActivator(LogicalKeyboardKey.keyA, control: true):
              selectAll,
          const SingleActivator(LogicalKeyboardKey.keyA, meta: true): selectAll,
        },
        const SingleActivator(LogicalKeyboardKey.escape): ?widget.onEscape,
      },
      child: Focus(
        focusNode: _focus,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _focus.requestFocus(),
          child: widget.child,
        ),
      ),
    );
  }
}
