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

import 'package:front_porch_ai/models/models.dart';

/// Below this many messages a chat is flagged as short in the "Start from a
/// chat" picker: it can still be picked, but there is little for a story to
/// be built on.
const int kShortChatMessages = 20;

/// How many chats the picker lists at once; search narrows the rest.
const int kChatSourcePageSize = 50;

/// Roughly how many chat messages each length needs before a faithful
/// retelling stops being mostly invented. Estimates, not measurements: the
/// shortest length is still a 30,000-word novella.
const Map<String, int> kChatMessagesForLength = {
  'Short': 60,
  'Standard': 150,
  'Epic': 400,
};

/// The length a faithful retelling of a chat with [messages] starts on.
String suggestedLengthForChat(int messages) =>
    messages < kChatMessagesForLength['Standard']! ? 'Short' : 'Standard';

/// Plain words for a chat too small for the chosen [length], or null when
/// it fits. [messages] 0 means the size is not known.
String? chatLengthWarning(int messages, String length) {
  final needed = kChatMessagesForLength[length];
  if (messages <= 0 || needed == null || messages >= needed) return null;
  final count = '$messages message${messages == 1 ? '' : 's'}';
  return length == 'Short'
      ? 'This chat has $count. Even the shortest length is a 30,000-word '
            'novella, so most of the story will be invented around the chat.'
      : 'This chat has $count. A story this long will be mostly invented. '
            'A shorter length stays closer to the chat.';
}

/// One member of the group a story starts from: the card the story
/// snapshots, keyed by the member id the chat's messages carry as their
/// speaker (docs/design/stories-from-group-chats.md §1).
class StoryChatMember {
  const StoryChatMember({
    required this.id,
    required this.name,
    this.description = '',
    this.personality = '',
    this.scenario = '',
    this.firstMessage = '',
    this.systemPrompt = '',
    this.imagePath = '',
  });

  factory StoryChatMember.fromGroupMember(
    GroupMember m, {
    String imagePath = '',
  }) => StoryChatMember(
    id: m.id,
    name: m.name,
    description: m.description,
    personality: m.personality,
    scenario: m.scenario,
    firstMessage: m.firstMessage,
    systemPrompt: m.systemPrompt,
    imagePath: imagePath,
  );

  final String id;
  final String name;
  final String description;
  final String personality;
  final String scenario;
  final String firstMessage;
  final String systemPrompt;

  /// The member's avatar file in the group's private folder; '' when the
  /// row came over the wire or the member has none.
  final String imagePath;

  /// The snapshot the pipeline reads, in the shape of a library card's.
  Map<String, String> snapshot(String role) => {
    'id': id,
    'name': name,
    'description': description,
    'personality': personality,
    'scenario': scenario,
    'first_message': firstMessage,
    'system_prompt': systemPrompt,
    'role': role,
  };

  /// The wire row: who, not the card text (the relay snapshots that).
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// "Mira", "Mira & Dov", "Mira, Dov & Ash".
String joinCastNames(Iterable<String> names) {
  final list = names.toList();
  if (list.isEmpty) return '';
  if (list.length == 1) return list.single;
  return '${list.sublist(0, list.length - 1).join(', ')} & ${list.last}';
}

/// One chat a story can start from: a 1:1 chat, or a group chat with its
/// roster (then [characterName] is the group's name and [characterId] its
/// first member's id, the default lead).
class StoryChatSourceRow {
  const StoryChatSourceRow({
    required this.characterId,
    required this.characterName,
    required this.sessionId,
    required this.sessionName,
    required this.summary,
    required this.createdAt,
    required this.messageCount,
    this.groupId,
    this.members = const [],
  });

  final String characterId;
  final String characterName;
  final String sessionId;
  final String sessionName;
  final String summary;
  final DateTime createdAt;
  final int messageCount;

  /// The group a group chat belongs to; null for a 1:1 chat.
  final String? groupId;

  /// The group's roster, names only; empty for a 1:1 chat.
  final List<StoryChatMember> members;

  bool get isGroup => groupId != null;
  bool get isShort => messageCount < kShortChatMessages;

  /// The roster as one line, for the row under the group's name.
  String get memberLine => joinCastNames(members.map((m) => m.name));

  Map<String, dynamic> toJson() => {
    'character_id': characterId,
    'character_name': characterName,
    'session_id': sessionId,
    'session_name': sessionName,
    'date': createdAt.toIso8601String(),
    'message_count': messageCount,
    'short': isShort,
    if (groupId != null) 'group_id': groupId,
    if (groupId != null) 'group_name': characterName,
    if (groupId != null) 'members': [for (final m in members) m.toJson()],
  };
}

/// [rows] whose character, group, member or chat name contains every word
/// of [query].
List<StoryChatSourceRow> filterChatSources(
  List<StoryChatSourceRow> rows,
  String query,
) {
  final words = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return rows;
  return rows.where((r) {
    final hay = '${r.characterName} ${r.sessionName} ${r.memberLine}'
        .toLowerCase();
    return words.every(hay.contains);
  }).toList();
}

/// A roster member as the chat service holds it (a [CharacterCard] whose
/// `dbId` is the group member id) as story cast. The card's image path is
/// the member's avatar file.
StoryChatMember storyMemberFromCard(CharacterCard card) => StoryChatMember(
  id: card.dbId ?? card.name,
  name: card.name,
  description: card.description,
  personality: card.personality,
  scenario: card.scenario,
  firstMessage: card.firstMessage,
  systemPrompt: card.systemPrompt,
  imagePath: card.imagePath ?? '',
);
