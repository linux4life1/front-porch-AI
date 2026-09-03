// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/models/models.dart';

/// Compile-time launch hook (`--dart-define=OPEN_CHAT=Flora`).
///
/// Empty (the product default) is a no-op. A non-empty value is matched
/// against 1:1 [CharacterCard.name] exactly (case-sensitive) — never a
/// group, so `Flora` does not open `Misty Flora`.
class OpenChatEnv {
  OpenChatEnv._();

  static const String name = String.fromEnvironment('OPEN_CHAT');

  static bool get enabled => name.isNotEmpty;

  /// First 1:1 library card whose [CharacterCard.name] equals [name].
  /// Groups are not in [cards]; substring / case-folded names do not match.
  static CharacterCard? findOneToOneCard(
    Iterable<CharacterCard> cards, {
    required String name,
  }) {
    if (name.isEmpty) return null;
    for (final c in cards) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// [getSessionsForId] already sorts newest-first. Skip the picker and
  /// load this id; never `__new__`.
  static String? mostRecentSessionId(List<Map<String, dynamic>> sessions) {
    if (sessions.isEmpty) return null;
    final id = sessions.first['id'];
    return id is String && id.isNotEmpty && id != '__new__' ? id : null;
  }
}
