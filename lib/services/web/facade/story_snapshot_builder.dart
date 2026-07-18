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

import 'package:front_porch_ai/models/story_project.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';

/// Reconstructs `character_card_snapshots` on the server from authoritative
/// character-card text + a role map, mirroring the desktop setup wizard
/// (`story_setup_page.dart`). The web client has no card text, so it sends only
/// character ids + roles; the card body is read here from [CharacterRepository]
/// so a hostile client can never inject arbitrary character definitions.
///
/// The snapshot map keys match exactly what `StoryPipelineService` consumes
/// (`name`, `description`, `personality`, `scenario`, `first_message`,
/// `system_prompt`, `role`, and `self_insert`) plus an extra `id` (character
/// dbId) the desktop ignores but the web setup uses to restore role pickers.
class StorySnapshotBuilder {
  StorySnapshotBuilder(this._charRepo, this._personaService);

  final CharacterRepository _charRepo;
  final UserPersonaService? _personaService;

  /// Rebuild snapshots for [project] using [requestRoles] (charDbId → role) sent
  /// by the client, falling back to roles from [previous]'s snapshots (so saves
  /// that don't carry a role map — e.g. dashboard act edits — never lose them),
  /// then to defaults (first selected character → Protagonist, rest Supporting).
  List<Map<String, String>> build(
    StoryProject project, {
    Map<String, String> requestRoles = const {},
    StoryProject? previous,
  }) {
    final snapshots = <Map<String, String>>[];

    if (project.useChatHistory && project.chatHistoryCharacterIds.isNotEmpty) {
      final selected = project.chatHistoryCharacterIds.toSet();
      final priorRoles = _rolesFromPrevious(previous);
      var assignedProtagonist =
          requestRoles.values.contains('Protagonist') ||
          priorRoles.values.contains('Protagonist');

      // Iterate repository order so snapshot numbering is stable across saves.
      for (final card in _charRepo.characters) {
        final id = card.dbId;
        if (id == null || !selected.contains(id)) continue;

        var role = requestRoles[id] ?? priorRoles[card.name];
        if (role == null || role.isEmpty) {
          if (!assignedProtagonist) {
            role = 'Protagonist';
            assignedProtagonist = true;
          } else {
            role = 'Supporting';
          }
        }

        snapshots.add({
          'id': id,
          'name': card.name,
          'description': card.description,
          'personality': card.personality,
          'scenario': card.scenario,
          'first_message': card.firstMessage,
          'system_prompt': card.systemPrompt,
          'role': role,
        });
      }
    }

    if (project.includeUserPersona) {
      final persona = _personaService?.persona;
      if (persona != null) {
        snapshots.add({
          'name': persona.name,
          'personality': persona.persona,
          'scenario': '',
          'first_message': '',
          'system_prompt': '',
          'role': project.userPersonaRole.isEmpty
              ? 'Protagonist'
              : project.userPersonaRole,
          'self_insert': 'true',
        });
      }
    }

    return snapshots;
  }

  /// Map of characterName → role from a previously-saved project's snapshots, so
  /// a save without an explicit role map preserves prior assignments.
  Map<String, String> _rolesFromPrevious(StoryProject? previous) {
    final roles = <String, String>{};
    if (previous == null) return roles;
    for (final snap in previous.characterCardSnapshots) {
      if (snap['self_insert'] == 'true') continue;
      final name = snap['name'];
      final role = snap['role'];
      if (name != null && name.isNotEmpty && role != null && role.isNotEmpty) {
        roles[name] = role;
      }
    }
    return roles;
  }
}
