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
import 'package:front_porch_ai/services/chat/prompt_injection/world_injection.dart';
import 'package:front_porch_ai/services/story/prompts/studio_context.dart';
import 'package:front_porch_ai/services/story/story_world_brief.dart';

/// How a story's world enters each stage (docs/design/stories-in-worlds.md
/// §3.2): the setting brief for the bible, the places list for the planner,
/// the "setting now" block for the writer, and the place tags that rank
/// lore. Pure; both engines call the same functions so Quick and Studio
/// cannot drift.
abstract final class StoryWorldContext {
  /// The `<place>` value that asks for a place the world does not have.
  static const newPrefix = 'new:';

  /// Who `{{user}}` and `{{char}}` are in a copied world entry: the persona
  /// (the self-insert snapshot) and, for a one-character chat story, that
  /// character. Null leaves the macro for the writer to be told about.
  static ({String? user, String? lead}) names(StoryProject p) {
    String? user;
    String? lead;
    for (final snap in p.characterCardSnapshots) {
      final name = snap['name']?.trim();
      if (name == null || name.isEmpty) continue;
      if (snap['self_insert'] == 'true') {
        user ??= name;
      } else if (p.chatHistoryCharacterIds.length == 1) {
        lead ??= name;
      }
    }
    return (user: user, lead: lead);
  }

  /// Copy the world's book into the story's lore (Refresh semantics: world
  /// entries are replaced, story-grown ones kept). Nothing without a world.
  static void copyLore(StoryProject p, StoryWorldBrief world) {
    if (world.isEmpty) return;
    final who = names(p);
    p.lore = StoryWorldBrief.refresh(
      p.lore,
      world.loreEntries(userName: who.user, charName: who.lead),
    );
  }

  // ── Studio blocks ──────────────────────────────────────────────────────

  static String settingWorld(StoryWorldBrief world) =>
      StudioContext.block('setting_world', world.brief());

  /// Foundation rules that apply only when the story has a world.
  static const foundationRules = [
    'The world in <setting_world> is given. <status_quo> elaborates it and '
        'never contradicts it: its places, climate and facts are true as '
        'written.',
    'Name places from <setting_world>. You may add a place only inside this '
        'world, and only when the story needs one it lacks.',
    '<world_lore> is for facts the world does not already state. Do not '
        'restate its entries.',
    'Where an entry says {{char}}, it means the lead character.',
  ];

  static String places(StoryWorldBrief world) =>
      StudioContext.block('places', world.placesBody());

  /// Scene-planning rules that apply only when the story has a world.
  static List<String> sceneRules(StoryProject p) => [
    'Set every scene in a place from <places> and name it exactly in '
        '<place>. Move between the places the world has.',
    p.faithfulMode
        ? 'This is a faithful retelling: <place> is always one from '
              '<places>; no new places.'
        : 'Only when no place in <places> can hold the scene, write '
              '<place>$newPrefix Name</place> for a new place inside the world.',
  ];

  /// The place's own prose for the scene being written: the same text a
  /// chat set there would read, without the chat header.
  static String settingNow(StoryWorldBrief world, StoryScene scene) {
    if (world.isEmpty) return '';
    final text = buildWorldInjection(world.chainTo(scene.placeId));
    final lines = text.split('\n');
    return lines.length < 2 ? '' : lines.skip(1).join('\n');
  }

  /// Lore tags ranked nearest first: the scene's place, then its parents.
  static List<String> preferTags(StoryWorldBrief world, StoryScene scene) =>
      world.isEmpty
      ? const []
      : [
          for (final w in world.chainTo(scene.placeId))
            StoryWorldBrief.placeTag(w.id),
        ];

  /// Read the planner's `<place>` (or a Quick `<location>`) onto the scene:
  /// a known name sets [StoryScene.placeId]; `new: Name` keeps the name in
  /// the location and leaves the id empty; anything else is free text.
  static void resolvePlace(
    StoryWorldBrief world,
    StoryScene scene,
    String raw,
  ) {
    if (world.isEmpty) return;
    var text = raw.trim();
    if (text.isEmpty) return;
    final isNew = text.toLowerCase().startsWith(newPrefix);
    if (isNew) text = text.substring(newPrefix.length).trim();
    final name = text.split(RegExp(r'\s[—–-]\s|[,:;]')).first.trim();
    final place = isNew ? null : world.placeNamed(name);
    if (place != null) {
      scene.placeId = place.id;
      if (scene.location.trim().isEmpty) {
        scene.location = raw.trim();
      } else if (!scene.location.toLowerCase().contains(
        place.name.trim().toLowerCase(),
      )) {
        scene.location = '${place.name.trim()} — ${scene.location}';
      }
      return;
    }
    scene.placeId = '';
    if (isNew && name.isNotEmpty) {
      final loc = scene.location.trim();
      if (loc.isEmpty || loc.toLowerCase().startsWith(newPrefix)) {
        // A Quick <location> carries the prefix itself: drop it.
        scene.location = text;
      } else if (!loc.toLowerCase().contains(name.toLowerCase())) {
        scene.location = '$name — $loc';
      }
    }
  }

  // ── Quick blocks (plain text; the Quick prompts are not tagged) ────────

  static String quickWorld(StoryWorldBrief world) => world.isEmpty
      ? ''
      : 'SETTING WORLD (given — the status quo elaborates it and never '
            'contradicts it; name places from it and add places only inside '
            'it; world_lore is for facts it does not already state):\n'
            '${world.brief()}\n';

  static String quickPlaces(StoryWorldBrief world, StoryProject p) =>
      world.isEmpty
      ? ''
      : 'PLACES IN THE WORLD — every scene\'s <location> starts with one of '
            'these names exactly, then " — " and the time of day and what is '
            'in the room'
            '${p.faithfulMode ? ' (a faithful retelling: no new places)' : '; write "$newPrefix Name — …" only for a place the world lacks, inside the world'}:\n'
            '${world.placesBody()}\n';
}
