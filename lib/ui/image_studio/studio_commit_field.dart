// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// A field that writes its text when the user submits it or leaves it.
class StudioCommitField extends StatefulWidget {
  const StudioCommitField({
    super.key,
    required this.value,
    required this.label,
    required this.onSubmit,
    this.hint,
    this.maxLines = 1,
  });

  final String value;
  final String label;
  final ValueChanged<String> onSubmit;
  final String? hint;
  final int maxLines;

  @override
  State<StudioCommitField> createState() => _StudioCommitFieldState();
}

class _StudioCommitFieldState extends State<StudioCommitField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);
  String _committed = '';

  @override
  void initState() {
    super.initState();
    _committed = widget.value;
  }

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    if (_controller.text == _committed) return;
    _committed = _controller.text;
    widget.onSubmit(_controller.text);
  }

  @override
  void didUpdateWidget(StudioCommitField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text && widget.value != oldWidget.value) {
      _controller.text = widget.value;
      _committed = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      maxLines: widget.maxLines,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
      ),
      onSubmitted: (_) => _commit(),
    );
  }
}
