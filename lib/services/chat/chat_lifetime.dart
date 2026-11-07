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

import 'package:front_porch_ai/services/kobold_service.dart';

/// Whether the chat service is still alive, and whether a desktop chat page
/// shows the open chat. KoboldCpp's saved cache follows the chat the user
/// is in: [chatOpened] tells it, and the session state calls it on every
/// switch.
///
/// Every door that must stop after dispose, or that asks the user
/// something only an open chat page can answer, takes this leaf.
class ChatLifetime {
  ChatLifetime(this._kobold);

  final KoboldService _kobold;

  bool _disposed = false;

  /// Chat screens open on the desktop ([screenOpened]); a "Did time pass?"
  /// question needs one (or a web client) to be asked.
  int _chatScreens = 0;

  /// The service was disposed: async work started before it stops.
  bool get disposed => _disposed;

  /// Marks the service gone. One way: nothing brings it back.
  void dispose() => _disposed = true;

  /// A desktop chat page is open, so a "Did time pass?" question has
  /// someone to answer it.
  bool get chatScreenOpen => _chatScreens != 0;

  /// The desktop's chat page opened: [openChat], the chat it shows, is the
  /// open one.
  void screenOpened(String? openChat) {
    if (_chatScreens++ == 0) chatOpened(openChat);
  }

  /// The desktop's chat page closed. With none left the user went back to
  /// the library: no chat is open, and KoboldCpp's saved cache can go.
  void screenClosed() {
    if (_chatScreens > 0 && --_chatScreens == 0) chatOpened(null);
  }

  /// Tells KoboldCpp which chat is open ([chat]), or that none is.
  void chatOpened(String? chat) {
    try {
      _kobold.openChat(chat);
    } on Object catch (e) {
      debugPrint('[Chat] KoboldCpp could not be told which chat is open: $e');
    }
  }
}
