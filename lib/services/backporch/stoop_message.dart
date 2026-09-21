// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

/// The card a message is about, if any (shown as a `re: <name>` line).
class StoopMessageCard {
  final String id;
  final String name;
  const StoopMessageCard({required this.id, required this.name});

  factory StoopMessageCard.fromJson(Map<String, dynamic> j) => StoopMessageCard(
    id: (j['id'] ?? '') as String,
    name: (j['name'] ?? '') as String,
  );
}

/// One message in the user's single thread with the moderation team.
/// [fromMod] true = a moderator sent it; false = the user did.
class StoopMessage {
  final String id;
  final bool fromMod;

  /// 'SYSTEM' = an automated decision notice (card approved/denied); 'CHAT' =
  /// typed by a human. Older servers omit the field — treated as chat.
  final String kind;
  final String body;
  final StoopMessageCard? character;
  final DateTime createdAt;

  const StoopMessage({
    required this.id,
    required this.fromMod,
    this.kind = 'CHAT',
    required this.body,
    required this.character,
    required this.createdAt,
  });

  /// True for automated decision notices — shown under Notifications, not chat.
  bool get isSystem {
    final k = kind.trim().toUpperCase();
    return k == 'SYSTEM' ||
        k == 'NOTICE' ||
        k == 'NOTIFICATION' ||
        k == 'DECISION';
  }

  factory StoopMessage.fromJson(Map<String, dynamic> j) {
    final characterRaw = j['character'];
    return StoopMessage(
      id: _stoopString(j['id']),
      fromMod: j['fromMod'] == true || j['from_mod'] == true,
      kind: _stoopKind(j),
      body: _stoopBody(j),
      character: characterRaw is Map
          ? StoopMessageCard.fromJson(Map<String, dynamic>.from(characterRaw))
          : null,
      createdAt:
          DateTime.tryParse(
            _stoopString(j['createdAt']).isNotEmpty
                ? _stoopString(j['createdAt'])
                : _stoopString(j['created_at']),
          )?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

String _stoopString(dynamic v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is num || v is bool) return v.toString();
  return '';
}

String _stoopKind(Map<String, dynamic> j) {
  if (j['isSystem'] == true || j['is_system'] == true) return 'SYSTEM';
  for (final key in const ['kind', 'type']) {
    final s = _stoopString(j[key]).trim();
    if (s.isNotEmpty) return s;
  }
  return 'CHAT';
}

String _stoopBody(Map<String, dynamic> j) {
  for (final key in const ['body', 'text', 'message', 'content']) {
    final s = _stoopString(j[key]).trim();
    if (s.isNotEmpty) return s;
  }
  return '';
}
