// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Lets a widget inside the transcript put text in the chat's message box
/// (a suggested action the user can edit before sending), or send it at
/// once, without owning the box. The chat page provides it around the
/// message list.
class ComposerDraftScope extends InheritedWidget {
  const ComposerDraftScope({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required super.child,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// The chat's send for text that does not come from the box.
  final void Function(String text) onSend;

  static ComposerDraftScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ComposerDraftScope>();

  /// Adds [text] to the message box (after anything already typed, so a
  /// half-written draft is never lost), cursor at the end, box focused.
  /// A second tap on the same suggestion does not add it again.
  void put(String text) {
    final draft = controller.text.trimRight();
    final idea = text.trim();
    final already = draft == idea || draft.endsWith(' $idea');
    final next = already ? draft : (draft.isEmpty ? idea : '$draft $idea');
    _setBox(next);
    focusNode.requestFocus();
  }

  /// Sends [text] at once. A copy an earlier tap left in the box is taken
  /// back out, so the next Send cannot send it a second time; anything else
  /// the user typed stays.
  void send(String text) {
    final draft = controller.text.trimRight();
    final idea = text.trim();
    if (draft == idea) {
      _setBox('');
    } else if (draft.endsWith(' $idea')) {
      _setBox(draft.substring(0, draft.length - idea.length).trimRight());
    }
    onSend(text);
  }

  void _setBox(String text) {
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  bool updateShouldNotify(ComposerDraftScope oldWidget) =>
      controller != oldWidget.controller ||
      focusNode != oldWidget.focusNode ||
      onSend != oldWidget.onSend;
}
