// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/persona/persona_ids.dart';

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
      id: json['id'] ?? newPersonaId(),
      title: json['title'] ?? '',
      name: json['name'] ?? 'User',
      persona: personaText,
      avatarPath: json['avatar_path'],
      birthday: json['birthday'] as String? ?? '',
    );
  }
}
