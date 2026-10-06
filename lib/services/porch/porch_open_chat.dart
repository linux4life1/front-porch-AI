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

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';

import 'porch_format.dart';

/// Said when a reply is still being written: moving chats opens each one,
/// and that must never happen under a reply in progress.
const String kPorchBusyWords =
    'A reply is still being written. Wait for it to finish, then try again.';

/// Runs [body], then reopens the chat that was open before it. Moving a
/// character's chats opens each one in turn (the `.fpchat` exporter reads
/// the open chat), and the chat a person had open must not change under
/// them — on the desktop or on the phone, which share it.
Future<T> keepingOpenChat<T>(
  ChatService chat,
  Future<T> Function() body,
) async {
  if (chat.isGenerating || chat.isSettlingTurn || chat.isImporting) {
    throw const PorchRefused(kPorchBusyWords);
  }
  final character = chat.activeCharacter;
  final group = chat.activeGroup;
  final session = chat.currentSessionId;
  try {
    return await body();
  } on ChatImportBusy {
    throw const PorchRefused(kPorchBusyWords);
  } finally {
    final moved =
        chat.currentSessionId != session ||
        !identical(chat.activeCharacter, character) ||
        !identical(chat.activeGroup, group);
    // Nothing was open: leave it. Opening "no chat" still runs the chat-open
    // path, which can start the local backend.
    if (moved && (group != null || character != null)) {
      try {
        if (group != null) {
          await chat.setActiveGroup(group);
        } else {
          await chat.setActiveCharacter(character);
        }
        if (session != null && chat.currentSessionId != session) {
          await chat.loadSession(session);
        }
      } catch (e) {
        debugPrint('[porch] could not reopen the chat that was open: $e');
      }
    }
  }
}
