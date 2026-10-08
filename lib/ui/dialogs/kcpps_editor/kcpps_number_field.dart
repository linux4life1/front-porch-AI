// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'kcpps_editor_style.dart';

/// A number box on the editor's form. It shows the form's [value]. What is
/// typed goes to [onValid] when [check] has no complaint; otherwise it stays
/// on screen, with the complaint, until the form's number moves by other
/// means (a tap on "use the largest that fits"). A preset put in the form
/// starts the box again: the form is keyed on it.
class KeNumberField extends StatefulWidget {
  const KeNumberField({
    super.key,
    required this.value,
    required this.keyName,
    required this.semanticLabel,
    required this.check,
    required this.onValid,
    required this.builder,
    this.width,
    this.error = false,
  });

  /// The form's number; null is an empty box.
  final int? value;
  final String keyName;
  final String semanticLabel;
  final double? width;

  /// Marks the box as wrong for a reason of the form's, beside a typed one.
  final bool error;

  /// What is wrong with [text], in plain words; null when it will do.
  final String? Function(String text) check;

  /// Takes [text], which [check] had nothing against.
  final ValueChanged<String> onValid;

  /// Lays the box out beside the complaint about it, if any.
  final Widget Function(BuildContext context, Widget box, String? problem)
  builder;

  @override
  State<KeNumberField> createState() => _KeNumberFieldState();
}

class _KeNumberFieldState extends State<KeNumberField> {
  late final TextEditingController _text = TextEditingController(
    text: _show(widget.value),
  );
  String? _problem;

  static String _show(int? value) => value == null ? '' : '$value';

  @override
  void didUpdateWidget(KeNumberField old) {
    super.didUpdateWidget(old);
    // What was just typed moves the form's number to itself: nothing to do.
    // Any other move leaves the box behind, and a wrong entry with it.
    if (widget.value != old.value &&
        int.tryParse(_text.text.trim()) != widget.value) {
      _text.text = _show(widget.value);
      _problem = null;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _typed(String text) {
    final problem = widget.check(text);
    setState(() => _problem = problem);
    if (problem == null) widget.onValid(text);
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    KeBox(
      controller: _text,
      keyName: widget.keyName,
      width: widget.width,
      number: true,
      error: _problem != null || widget.error,
      semanticLabel: widget.semanticLabel,
      onChanged: _typed,
    ),
    _problem,
  );
}
