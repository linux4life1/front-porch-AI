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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A [TextField] for the common "value in, onChanged out, parent rebuilds"
/// form shape, with the controller OWNED here instead of built in the caller's
/// `build()`.
///
/// Why this exists: a `TextEditingController(text: value)` constructed inline
/// in `build()` is handed to the field fresh on every rebuild, and since the
/// parent rebuilds on every keystroke the caret is thrown away each frame —
/// mid-text editing types into the wrong place and IME composition can never
/// complete. That exact bug was user-reported once already in the Image Studio
/// prompt box; this widget is the fixed pattern, packaged so form sections stop
/// re-deriving it.
///
/// [value] is only pushed into the field when it differs from what the field
/// already holds — i.e. an external rewrite (a preset applied, a value clamped
/// by the caller), never the user's own typing.
class SyncedTextField extends StatefulWidget {
  const SyncedTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.style,
    this.decoration,
    this.keyboardType,
    this.inputFormatters,
    this.readOnly = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final TextStyle? style;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  /// Shown but not editable (a value something else is about to rewrite).
  final bool readOnly;

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync ONLY a genuinely external change (reset button, engine update).
    // When the parent rebuild is just echoing our own keystroke back
    // (value == controller text), re-stamping would drag the caret to the
    // end on every character — the exact mid-word-editing bug this widget
    // exists to fix.
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      style: widget.style,
      decoration: widget.decoration,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      readOnly: widget.readOnly,
      onChanged: widget.onChanged,
    );
  }
}
