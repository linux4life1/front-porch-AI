// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

/// Lets a widget inside the transcript put text in the chat's message box
/// (a suggested action the user can edit before sending) without owning the
/// box. The chat page provides it around the message list.
class ComposerDraftScope extends InheritedWidget {
  const ComposerDraftScope({
    super.key,
    required this.controller,
    required this.focusNode,
    required super.child,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  static ComposerDraftScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ComposerDraftScope>();

  /// Adds [text] to the message box (after anything already typed, so a
  /// half-written draft is never lost), cursor at the end, box focused.
  void put(String text) {
    final draft = controller.text.trimRight();
    final next = draft.isEmpty ? text : '$draft $text';
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    focusNode.requestFocus();
  }

  @override
  bool updateShouldNotify(ComposerDraftScope oldWidget) =>
      controller != oldWidget.controller || focusNode != oldWidget.focusNode;
}
