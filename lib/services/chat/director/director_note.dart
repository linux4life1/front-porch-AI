// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/models/models.dart';

/// The speaker id a director's note carries. History builders render it as
/// `[Director: …]`, and Journal, Growth and stats skip it.
const String kDirectorCharacterId = '__director__';

/// The session-blob key that keeps Director Mode per chat. Additive: old
/// app versions ignore it and open the chat with the group's default.
const String kDirectingSessionKey = 'directing';

/// A director's note as it lands in the transcript. It counts as a user
/// line for turn order (the cast answers it) but is not in-story dialogue.
ChatMessage directorNoteMessage(String text) => ChatMessage(
  text: text,
  sender: 'Director',
  isUser: true,
  characterId: kDirectorCharacterId,
);

/// Director Mode as this chat last saved it, or null when the chat never
/// saved one (a new chat, or one saved by an older app) and the group's
/// default applies.
bool? directingFromSessionBlob(String? json) {
  if (json == null || json.isEmpty || json == '{}') return null;
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map) return null;
    final v = decoded[kDirectingSessionKey];
    return v is bool ? v : null;
  } catch (e) {
    debugPrint('[Director] unreadable session blob: $e');
    return null;
  }
}
