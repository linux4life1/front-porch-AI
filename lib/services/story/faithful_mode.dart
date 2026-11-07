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
import 'package:front_porch_ai/services/story/story_chat_sources.dart';

/// The lead of a story made from a group chat when the user picks the
/// persona rather than a member (docs/design/stories-from-group-chats.md §1).
const String kStoryLeadPersona = 'persona';

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
    'between events, but every major beat must come from the timeline. '
    'The cast is the people who appear in the timeline: do not invent new '
    'characters, antagonists or NPCs, whatever was said above.';

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
  // The chat's Setting place, when it has one: the story is set where the
  // chat was (docs/design/stories-in-worlds.md §3.4).
  String? worldId,
  String worldName = '',
}) {
  final charName = character.name;
  final isShort = length == 'Short story';
  return StoryProject(
    worldId: worldId == null || worldId.isEmpty ? null : worldId,
    worldName: worldName,
    title: faithful
        ? 'The Story of $charName & $userName'
        : 'Inspired by $charName & $userName',
    concept:
        (faithful
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

/// The group twin of [buildChatStoryProject] for "Turn this chat into a
/// story…" in a group chat (docs/design/stories-from-group-chats.md §1):
/// every member of [members] joins the cast, [leadId] (a member id, or
/// [kStoryLeadPersona]; null means the first member) is the Protagonist,
/// the persona keeps Protagonist as in a 1:1 story, and everyone else is
/// Supporting. The member ids are the chat's speaker ids, so the distiller
/// names each line's speaker through them.
StoryProject buildGroupStoryProject({
  required String sessionId,
  required String groupId,
  required String groupName,
  required List<StoryChatMember> members,
  required String userName,
  required String recap,
  required bool faithful,
  required String length, // 'Short story' | 'Novella'
  required String pov,
  String? leadId,
  String? worldId,
  String worldName = '',
}) {
  final lead = members.any((m) => m.id == leadId) || leadId == kStoryLeadPersona
      ? leadId
      : members.firstOrNull?.id;
  final cast = joinCastNames(members.map((m) => m.name));
  final title = groupName.trim().isEmpty ? cast : groupName.trim();
  final isShort = length == 'Short story';
  return StoryProject(
    worldId: worldId == null || worldId.isEmpty ? null : worldId,
    worldName: worldName,
    chatGroupId: groupId,
    chatGroupName: groupName,
    title: faithful ? 'The Story of $title' : 'Inspired by $title',
    concept:
        (faithful
            ? 'A faithful novelization of the roleplay between $cast and '
                  '$userName — the real events of their group chat, retold '
                  'as prose.'
            : 'A story inspired by the roleplay between $cast and '
                  '$userName.') +
        (recap.trim().isEmpty ? '' : '\n\nWhere the story stands: $recap'),
    useChatHistory: true,
    chatHistoryCharacterIds: [for (final m in members) m.id],
    chatHistorySessionIds: [sessionId],
    faithfulMode: faithful,
    includeUserPersona: true,
    userPersonaRole: 'Protagonist',
    pov: pov,
    actCount: isShort ? 1 : 3,
    proseLength: isShort ? 'Short' : 'Standard',
    characterCardSnapshots: [
      for (final m in members)
        m.snapshot(m.id == lead ? 'Protagonist' : 'Supporting'),
    ],
  );
}
