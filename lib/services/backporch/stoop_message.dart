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
  bool get isSystem => kind == 'SYSTEM';

  factory StoopMessage.fromJson(Map<String, dynamic> j) => StoopMessage(
    id: (j['id'] ?? '') as String,
    fromMod: j['fromMod'] == true,
    kind: (j['kind'] as String?) ?? 'CHAT',
    body: (j['body'] ?? '') as String,
    character: j['character'] is Map<String, dynamic>
        ? StoopMessageCard.fromJson(j['character'] as Map<String, dynamic>)
        : null,
    createdAt:
        DateTime.tryParse((j['createdAt'] ?? '') as String)?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );
}
