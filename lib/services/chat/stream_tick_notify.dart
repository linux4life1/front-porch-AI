// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Marks the ChatService notifies that only carry streamed reply text
/// (~30/s while a reply streams). Listeners run synchronously inside
/// `notifyListeners`, so chat chrome that shows no streamed text can read
/// [active] in its listener and skip the rebuild. A static flag, not a
/// ChatService member, so `implements ChatService` test doubles need nothing.
abstract final class StreamTickNotify {
  static bool active = false;

  /// Runs [notify] with [active] set.
  static void run(void Function() notify) {
    active = true;
    try {
      notify();
    } finally {
      active = false;
    }
  }
}
