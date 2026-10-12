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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

/// Platform-appropriate label for the regenerate shortcut (#86), surfaced in
/// the Generate-reply button tooltip so keyboard users can discover it.
String get chatRegenShortcutLabel => Platform.isMacOS ? '⌘R' : 'Ctrl+R';

/// ⌘R (macOS) / Ctrl+R: (re)generate the last AI reply. If the reply was
/// deleted, regenerateLastMessage() writes a fresh one from the trailing user
/// prompt instead. Mirrors the Generate-reply toolbar button / bubble regen.
///
/// Read at the keyboard, not on the message box's focus node: a click on a
/// bubble, the sidebar or a button moves focus out of the box, and the
/// shortcut used to go dead (macOS played its error sound). [host] is the
/// chat page that registered the handler; returns whether the key was used.
bool handleChatRegenShortcut(KeyEvent event, State host) {
  if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyR) {
    return false;
  }
  final keys = HardwareKeyboard.instance;
  if (!(Platform.isMacOS ? keys.isMetaPressed : keys.isControlPressed)) {
    return false;
  }
  // Only while the chat is the screen in front. A dialog over it (the
  // Regenerate dialog takes a second press itself) or a page pushed on top
  // keeps the key.
  if (!host.mounted || !(ModalRoute.of(host.context)?.isCurrent ?? false)) {
    return false;
  }
  final context = host.context;
  final chatService = Provider.of<ChatService>(context, listen: false);
  if (chatService.isGenerating || chatService.isGuestBusy) return true;
  final messages = chatService.messages;
  final last = messages.isEmpty ? null : messages.last;
  if (last != null && !last.isUser && last != messages.first) {
    unawaited(
      promptLookupRegen(
        context,
        chatService,
        chatService.regenerateLastMessage,
      ),
    );
  } else {
    chatService.regenerateLastMessage();
  }
  return true;
}
