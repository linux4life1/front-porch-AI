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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/pages/character_creator_page.dart';
import 'package:front_porch_ai/ui/pages/create_character_page.dart';

/// "Make a Character" from a persona: ask Manual or AI Assist, then open
/// that wizard pre-filled. Nothing is saved until the wizard saves.
Future<void> makeCharacterFromPersona(
  BuildContext context,
  UserPersona persona,
) async {
  final navigator = Navigator.of(context);
  final choice = await showPersonaToCharacterDialog(
    context,
    personaName: persona.name,
    hasMacros: PersonaConversion.hasCharUserMacros(persona.persona),
  );
  if (choice == null) return;
  final seed = PersonaConversion.characterSeedFromPersona(
    persona,
    swapMacros: choice.swapMacros,
  );
  await navigator.push(
    MaterialPageRoute(
      builder: (_) => switch (choice.mode) {
        PersonaToCharacterMode.manual => CreateCharacterPage(seed: seed),
        PersonaToCharacterMode.aiAssist => CharacterCreatorPage(seed: seed),
      },
    ),
  );
}
