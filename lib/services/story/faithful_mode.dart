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

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/story_project.dart';

/// Living Time §4 — "turn this chat into a story": the faithful-mode prompt
/// directives and the ONE pre-configured-project builder shared by the
/// desktop dialog and the web facade (so the two entry points cannot drift).
/// Lives outside story_pipeline_service.dart by design — that file is
/// already enormous (file-size rule).

/// Appended to the Story Architect prompt when [StoryProject.faithfulMode].
const String faithfulArchitectDirective =
    '\n\nFAITHFUL RETELLING MODE: This story is a NOVELIZATION of the canon '
    'event timeline above, not a story merely inspired by it. The story '
    'bible, acts, and threads MUST follow the timeline\'s events in their '
    'original order — do not reorder, replace, or invent major plot events. '
    'You may deepen interiority, sensory detail, and connective tissue '
    'between events, but every major beat must come from the timeline.';

/// Appended to the Scene Weaver prompt when [StoryProject.faithfulMode].
const String faithfulSceneDirective =
    '\n\nFAITHFUL RETELLING MODE: Scenes must dramatize the canon timeline '
    'events assigned to this act, in order, without inventing major new '
    'events. Expand moments, do not replace them.';

/// Build the pre-configured project for "Turn this chat into a story…".
/// The caller saves it and (on desktop) navigates to the Story dashboard,
/// whose existing auto-run already goes distiller → architect.
StoryProject buildChatStoryProject({
  required String sessionId,
  required CharacterCard character,
  required String characterId,
  required String userName,
  required String recap,
  required bool faithful,
  required String length, // 'Short story' | 'Novella'
  required String pov,
}) {
  final charName = character.name;
  final isShort = length == 'Short story';
  return StoryProject(
    title: faithful
        ? 'The Story of $charName & $userName'
        : 'Inspired by $charName & $userName',
    concept: (faithful
            ? 'A faithful novelization of the roleplay between $charName '
                'and $userName — the real events of their chat, retold as '
                'prose.'
            : 'A story inspired by the roleplay between $charName and '
                '$userName.') +
        (recap.trim().isEmpty ? '' : '\n\nWhere the story stands: $recap'),
    useChatHistory: true,
    chatHistoryCharacterIds: [characterId],
    chatHistorySessionIds: [sessionId],
    faithfulMode: faithful,
    includeUserPersona: true,
    userPersonaRole: 'Protagonist',
    pov: pov,
    actCount: isShort ? 1 : 3,
    proseLength: isShort ? 'Short' : 'Standard',
    characterCardSnapshots: [
      {
        'name': charName,
        'role': 'Protagonist',
        'description': character.description,
        'personality': character.personality,
        'scenario': character.scenario,
      },
    ],
  );
}
