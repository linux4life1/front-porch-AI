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

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';

/// The library card's "Use as Persona": confirm, then save a persona copy of
/// [character]. The character itself is untouched.
Future<void> convertHomeCharacterToPersona(
  BuildContext context,
  CharacterCard character,
) async {
  final personas = Provider.of<UserPersonaService>(context, listen: false);
  final root = Provider.of<StorageService>(context, listen: false).rootPath;
  final messenger = ScaffoldMessenger.of(context);
  final swap = await showCharacterToPersonaDialog(
    context,
    characterName: character.name,
    hasMacros: PersonaConversion.characterHasMacros(character),
  );
  if (swap == null) return;
  try {
    final persona = await PersonaConversion.createPersonaFromCharacter(
      character,
      personas: personas,
      swapMacros: swap,
      avatarDir: root == null ? null : p.join(root, 'persona_avatars'),
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '"${persona.name}" is now a persona. Pick it in Personas to play as it.',
        ),
      ),
    );
  } catch (e) {
    debugPrint('[UseAsPersona] Failed: $e');
    messenger.showSnackBar(
      SnackBar(content: Text('Could not create the persona: $e')),
    );
  }
}
