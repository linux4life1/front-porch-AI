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

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

final _macroPattern = RegExp(r'\{\{(char|user)\}\}', caseSensitive: false);

/// Character card ↔ user persona conversion (SillyTavern's "Convert to
/// Persona", plus the reverse it lacks). A persona only holds a name, a
/// description, a birthday and a picture, so that is all that moves; the
/// original is never touched.
class PersonaConversion {
  const PersonaConversion._();

  static bool hasCharUserMacros(String text) => _macroPattern.hasMatch(text);

  /// Swaps `{{char}}` and `{{user}}`, so "{{char}} is {{user}}'s neighbour"
  /// still reads right once the speaker changes sides.
  static String swapCharUserMacros(String text) => text.replaceAllMapped(
    _macroPattern,
    (m) => m[1]!.toLowerCase() == 'char' ? '{{user}}' : '{{char}}',
  );

  /// The persona text for [card]: its description, with the personality
  /// folded in under a heading when the card has one.
  static String personaTextFromCharacter(
    CharacterCard card, {
    required bool swapMacros,
  }) {
    final description = card.description.trim();
    final personality = card.personality.trim();
    final text = [
      if (description.isNotEmpty) description,
      if (personality.isNotEmpty) 'Personality: $personality',
    ].join('\n\n');
    return swapMacros ? swapCharUserMacros(text) : text;
  }

  static bool characterHasMacros(CharacterCard card) =>
      hasCharUserMacros(card.description) ||
      hasCharUserMacros(card.personality);

  /// Saves [card] as a new persona. It only joins the list: the default and
  /// the persona you are right now stay as they were. The portrait is
  /// re-encoded into [avatarDir] so the persona keeps its picture even if the
  /// character is deleted later.
  static Future<UserPersona> createPersonaFromCharacter(
    CharacterCard card, {
    required UserPersonaService personas,
    required bool swapMacros,
    String? avatarDir,
  }) async {
    final name = card.name.trim().isEmpty ? 'Persona' : card.name.trim();
    final clash = personas.personas.any((x) => x.name == name);
    final avatarPath = avatarDir == null
        ? null
        : await _copyPortrait(card.imagePath, name, avatarDir);
    final id = await personas.createPersona(
      clash ? '$name (from character)' : '',
      name,
      personaTextFromCharacter(card, swapMacros: swapMacros),
      avatarPath,
      birthday: card.frontPorchExtensions?.birthday ?? '',
      activate: false,
    );
    return personas.personas.firstWhere((x) => x.id == id);
  }

  /// What a new character starts from when it is made from [persona].
  static PersonaCharacterSeed characterSeedFromPersona(
    UserPersona persona, {
    required bool swapMacros,
  }) {
    final text = persona.persona.trim();
    final avatar = persona.avatarPath;
    return PersonaCharacterSeed(
      name: persona.name.trim(),
      description: swapMacros ? swapCharUserMacros(text) : text,
      birthday: persona.birthday,
      portraitPath: avatar != null && avatar.isNotEmpty ? avatar : null,
    );
  }

  static Future<String?> _copyPortrait(
    String? source,
    String name,
    String avatarDir,
  ) async {
    if (source == null || source.isEmpty) return null;
    try {
      final file = File(source);
      if (!await file.exists()) return null;
      // Re-encoded rather than copied: the card PNG carries the whole card
      // as metadata, which has no business inside a persona picture.
      final decoded = img.decodeImage(await file.readAsBytes());
      if (decoded == null) return null;
      await Directory(avatarDir).create(recursive: true);
      final safeName = name.replaceAll(RegExp(r'[^\w]'), '_');
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final out = p.join(avatarDir, 'persona_${safeName}_$stamp.png');
      await File(out).writeAsBytes(img.encodePng(decoded));
      return out;
    } catch (e) {
      debugPrint('[PersonaConversion] Portrait copy failed: $e');
      return null;
    }
  }
}

/// A new character's starting fields when it is made from a persona.
class PersonaCharacterSeed {
  const PersonaCharacterSeed({
    required this.name,
    required this.description,
    this.birthday = '',
    this.portraitPath,
  });

  final String name;
  final String description;
  final String birthday;

  /// The persona's picture, used as the new card's portrait.
  final String? portraitPath;

  /// The AI creator's concept: the persona is the brief, the model fills in
  /// everything a persona does not carry.
  String get aiConcept => [
    'Build a full roleplay character from this existing person. Keep their '
        'name, identity and every stated detail; invent only what is missing '
        '(personality, scenario, greetings).',
    if (description.isNotEmpty) description,
    if (birthday.isNotEmpty) 'Birthday: $birthday',
  ].join('\n\n');
}
