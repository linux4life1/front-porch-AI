// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'studio_widgets.dart';

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
  bool _pending = false;

  @override
  void initState() {
    super.initState();
    _committed = widget.value;
  }

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    if (studioSettingsLocked(context)) {
      if (_controller.text != _committed) setState(() => _pending = true);
      return;
    }
    if (_controller.text == _committed) return;
    _committed = _controller.text;
    setState(() => _pending = false);
    widget.onSubmit(_controller.text);
  }

  @override
  void didUpdateWidget(StudioCommitField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text == _committed && widget.value != oldWidget.value) {
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
        helperText: _pending
            ? 'Draft kept. Apply after generation finishes.'
            : null,
        suffixIcon: _pending
            ? TextButton(onPressed: _commit, child: const Text('Apply'))
            : null,
      ),
      onSubmitted: (_) => _commit(),
    );
  }
}
