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

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';

/// The phone's "Use as Persona" and "Make a Character": the same
/// [PersonaConversion] the desktop library and Persona page call.
class PersonaConversionFacade {
  PersonaConversionFacade(this._repo, this._personas, this._storage);

  final CharacterRepository _repo;
  final UserPersonaService _personas;
  final StorageService _storage;

  /// What the confirm dialog needs before converting a character.
  Future<Map<String, dynamic>?> characterPreview(String characterId) async {
    final card = await _repo.getCharacterCardById(characterId);
    if (card == null) return null;
    return {
      'name': card.name,
      'hasMacros': PersonaConversion.characterHasMacros(card),
    };
  }

  /// Saves the character as a persona; null when the character is unknown.
  Future<Map<String, dynamic>?> characterToPersona(
    String characterId, {
    required bool swapMacros,
  }) async {
    final card = await _repo.getCharacterCardById(characterId);
    if (card == null) return null;
    final root = _storage.rootPath;
    final persona = await PersonaConversion.createPersonaFromCharacter(
      card,
      personas: _personas,
      swapMacros: swapMacros,
      avatarDir: root == null ? null : p.join(root, 'persona_avatars'),
    );
    return {'id': persona.id, 'name': persona.name};
  }

  /// The wizards' starting fields for a character made from [personaId].
  Map<String, dynamic>? characterSeed(
    String personaId, {
    required bool swapMacros,
  }) {
    final persona = _find(personaId);
    if (persona == null) return null;
    final seed = PersonaConversion.characterSeedFromPersona(
      persona,
      swapMacros: swapMacros,
    );
    return {
      'personaId': persona.id,
      'name': seed.name,
      'description': seed.description,
      'personality': seed.personality,
      'birthday': seed.birthday,
      'aiConcept': seed.aiConcept,
      'hasPortrait': seed.portraitPath != null,
      'hasMacros': PersonaConversion.hasCharUserMacros(persona.persona),
    };
  }

  /// The persona's picture, for a character created from it.
  String? portraitPathFor(String personaId) => _find(personaId)?.avatarPath;

  /// The persona's picture as served to the phone's wizards; null when it
  /// has none or the file is gone.
  Future<({List<int> bytes, String contentType})?> portrait(
    String personaId,
  ) async {
    final path = portraitPathFor(personaId);
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final ext = p.extension(path).toLowerCase();
    final type = switch (ext) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.webp' => 'image/webp',
      '.gif' => 'image/gif',
      _ => 'image/png',
    };
    return (bytes: await file.readAsBytes(), contentType: type);
  }

  UserPersona? _find(String id) {
    for (final persona in _personas.personas) {
      if (persona.id == id) return persona;
    }
    return null;
  }
}
