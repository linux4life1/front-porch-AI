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

part of 'user_persona_service.dart';

class UserPersona {
  final String id;
  final String title;
  final String name;
  final String persona;
  final String? avatarPath;

  /// Calendar birthday `YYYY-MM-DD`. Empty = unset. Feb 29 is rejected
  /// at parse. Story-clock age, not wall-clock.
  final String birthday;

  /// Returns title if set, otherwise name — used for display in persona list
  String get displayLabel => title.isNotEmpty ? title : name;

  UserPersona({
    required this.id,
    this.title = '',
    this.name = 'User',
    this.persona = '',
    this.avatarPath,
    this.birthday = '',
  });

  UserPersona copyWith({
    String? title,
    String? name,
    String? persona,
    String? avatarPath,
    String? birthday,
  }) {
    return UserPersona(
      id: this.id,
      title: title ?? this.title,
      name: name ?? this.name,
      persona: persona ?? this.persona,
      avatarPath: avatarPath ?? this.avatarPath,
      birthday: birthday ?? this.birthday,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'name': name,
      'persona': persona,
      'avatar_path': avatarPath,
      if (birthday.isNotEmpty) 'birthday': birthday,
    };
  }

  factory UserPersona.fromJson(Map<String, dynamic> json) {
    // Support legacy JSON that may have 'description' instead of 'persona'.
    // (Legacy 'learned_facts' entries are deliberately ignored — the old
    // auto-fact feature was replaced by the per-chat Journal, fresh start.)
    final personaText =
        (json['persona'] as String?) ?? (json['description'] as String?) ?? '';
    return UserPersona(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: json['title'] ?? '',
      name: json['name'] ?? 'User',
      persona: personaText,
      avatarPath: json['avatar_path'],
      birthday: json['birthday'] as String? ?? '',
    );
  }
}
