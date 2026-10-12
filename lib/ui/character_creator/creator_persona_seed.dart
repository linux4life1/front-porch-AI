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

import 'package:front_porch_ai/services/services.dart';

import 'creator_state.dart';

/// "Make a Character" → AI Assist: the persona becomes Quick mode's brief.
extension CreatorPersonaSeed on CreatorState {
  /// Starts from a blank form and stays off the saved draft: nothing from
  /// an unfinished character leaks in, and nothing here overwrites it.
  void applyPersonaSeed(PersonaCharacterSeed seed) {
    persistDraft = false;
    resetAllFields();
    creatorMode = CreatorMode.quick;
    nameController.text = seed.name;
    conceptController.text = seed.aiConcept;
    quickScenarioController.clear();
    // The persona dropdown is who the character will MEET; the persona this
    // character came from would have it meeting itself.
    selectedPersonaId = '';
    realismBirthday = seed.birthday;
    portraitSourcePath = seed.portraitPath;
    notify();
  }
}
