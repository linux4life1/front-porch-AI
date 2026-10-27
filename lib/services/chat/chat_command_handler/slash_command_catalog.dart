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

/// One entry in the slash-command reference, used by the input "type /" helper
/// panel (and any cheat-sheet). [example] is what tapping the row inserts.
class SlashCommandInfo {
  const SlashCommandInfo(this.command, this.example, this.description);

  /// The bare command token (no slash), e.g. `create`.
  final String command;

  /// A usage example shown to the user, e.g. `/create <name>: <concept>`.
  final String example;

  /// One-line description of what it does.
  final String description;
}

/// The user-facing slash-command reference (single source of truth for the
/// "type /" helper panel). Order = display order. Aliases (/turn, /detect,
/// /expression-clear) are intentionally omitted to keep the list scannable.
const List<SlashCommandInfo> kSlashCommands = [
  SlashCommandInfo(
    'create',
    '/create <name>: <concept>',
    'Create a new guest NPC and bring them into the scene',
  ),
  SlashCommandInfo(
    'join',
    '/join [--full|--lite] [name]',
    'Bring a character in — lite is a Scene Guest (works in a group too); --full is a full member',
  ),
  SlashCommandInfo(
    'promote',
    '/promote [name]',
    'Named: that guest becomes a full member. Bare: a 1:1 becomes a group; guests stay Guest until you Promote them',
  ),
  SlashCommandInfo(
    'speak',
    '/speak [name]',
    'Anyone on the porch (host, guest, or group member) takes a turn now',
  ),
  SlashCommandInfo(
    'exit',
    '/exit [name]',
    'A guest leaves (narrated); in a group, removes that full member by name',
  ),
  SlashCommandInfo(
    'director',
    '/director [off]',
    'Step out of a group scene to direct it; /director off steps you back in',
  ),
  SlashCommandInfo(
    'whisper',
    '/whisper <name> <direction> | /whisper <name> off',
    'While directing: a private direction only that character sees, until you clear it',
  ),
  SlashCommandInfo(
    'goal',
    '/goal <where the scene should go> | /goal off',
    'While directing: pin a scene goal the cast steers toward every turn',
  ),
  SlashCommandInfo(
    'narrate',
    '/narrate [what happens]',
    'While directing: a narrator describes the scene, then the cast reacts',
  ),
  SlashCommandInfo(
    'turnorder',
    '/turnorder [random | <name>, …]',
    'Set how a group takes turns: round-robin, random, or an explicit order',
  ),
  SlashCommandInfo(
    'scan',
    '/scan',
    'Scan the scene for a new recurring character to add',
  ),
  SlashCommandInfo(
    'expression',
    '/expression [emotion]',
    "Set the character's expression (omit to clear it)",
  ),
  SlashCommandInfo(
    'afk',
    '/afk [off] [--messages N] [--time 5m]',
    'Keep the scene alive while you step away — N solitary auto-responses at a set interval',
  ),
  SlashCommandInfo(
    'image',
    '/image [me | char | raw <prompt> | <description>]',
    'Generate an image in chat — bare /image pictures the current scene',
  ),
  SlashCommandInfo(
    'search',
    '/search -- <what to look up>',
    'Look up these exact words on the web before she answers. Put your line first, then the command',
  ),
  SlashCommandInfo(
    'wiki',
    '/wiki -- <what to look up>',
    'Look up these exact words in this chat\'s wiki. Put your line first, then the command',
  ),
  SlashCommandInfo(
    'skip',
    '/skip <8h | 2d | morning | 07:30>',
    'Skip story time by exactly this much. Put your line first, then the command; alone, it only moves the clock',
  ),
];
