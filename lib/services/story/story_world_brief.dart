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
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/world_chain.dart';

/// Soft cap on the setting brief the bible and the planner read
/// (docs/design/stories-in-worlds.md §3.2). The place tree, the climate and
/// the always-on facts go in; everything else reaches the writer through
/// the lore index.
const int kStoryWorldBriefChars = 3000;

/// One place gets this much of its own description in the brief.
const int kStoryWorldPlaceLineChars = 160;

/// Who `{{user}}` is in a world's lore when the story has no persona.
const String kStoryWorldNoPersona = 'the newcomer';

/// Fill the chat macros a world's lore may carry. A world written from a
/// character spells the persona `{{user}}` by rule; the story engine has no
/// macro pass of its own, and the Lore page must never show a raw macro.
/// `{{char}}` is left alone without a [charName]: the writer is told what
/// it means instead of being handed the wrong person.
String resolveStoryMacros(String text, {String? userName, String? charName}) {
  var out = text.replaceAll(
    RegExp(r'\{\{\s*user\s*\}\}', caseSensitive: false),
    userName?.trim().isNotEmpty == true
        ? userName!.trim()
        : kStoryWorldNoPersona,
  );
  if (charName != null && charName.trim().isNotEmpty) {
    out = out.replaceAll(
      RegExp(r'\{\{\s*char\s*\}\}', caseSensitive: false),
      charName.trim(),
    );
  }
  return out;
}

/// Lore the model did not write: uploaded files and a world's book. The
/// bible appends its own `<world_lore>` to these and never replaces them.
bool isGroundingLore(StoryLoreEntry e) =>
    e.relatedTo.any((r) => r.startsWith('file:') || r.startsWith('world:'));

/// Entries copied from the story's world (`world:` tag).
bool isWorldLore(StoryLoreEntry e) =>
    e.relatedTo.any((r) => r.startsWith('world:'));

/// What a planning stage's `<world_lore>` does to the story's lore: the
/// grounding entries stay, model entries are appended, and a topic already
/// present (case-insensitive) is not written twice.
List<StoryLoreEntry> mergeParsedLore(
  List<StoryLoreEntry> existing,
  Iterable<StoryLoreEntry> parsed,
) {
  final lore = [...existing.where(isGroundingLore)];
  for (final entry in parsed) {
    if (entry.topic.isEmpty || entry.detail.isEmpty) continue;
    if (lore.any((l) => l.topic.toLowerCase() == entry.topic.toLowerCase())) {
      continue;
    }
    lore.add(entry);
  }
  return lore;
}

/// What the story reads from its world: the setting brief for the bible
/// and the planner, the places by name, and the book as story lore.
///
/// Pure. [chain] is the Setting chain leaf first (`WorldRepository.chainFor`
/// of the story's `worldId`), [places] every place inside the root, parents
/// before rooms (`placesInside`). An empty chain is a deleted world: the
/// brief is empty and nothing is copied, and the story keeps running.
class StoryWorldBrief {
  StoryWorldBrief({required this.chain, required this.places});

  /// Leaf first; the last is the top-level world.
  final List<World> chain;

  /// Every place inside the root, parents before their rooms.
  final List<World> places;

  bool get isEmpty => chain.isEmpty;

  World? get root => chain.isEmpty ? null : chain.last;

  /// Where the story starts: the picked place, or the root itself.
  World? get start => chain.isEmpty ? null : chain.first;

  static String worldTag(String id) => 'world:$id';
  static String placeTag(String id) => 'place:$id';

  /// The root and its places, the root first.
  Iterable<World> get _owners sync* {
    final r = root;
    if (r == null) return;
    yield r;
    for (final p in places) {
      if (p.id != r.id) yield p;
    }
  }

  Iterable<LorebookEntry> get _liveEntries sync* {
    for (final w in _owners) {
      for (final e in w.lorebook.entries) {
        if (e.enabled && e.content.trim().isNotEmpty) yield e;
      }
    }
  }

  /// Facts the brief states outright because the book marks them constant.
  int get constantCount => _liveEntries.where((e) => e.constant).length;

  /// Facts that reach the writer through the lore index.
  int get searchableCount => _liveEntries.where((e) => !e.constant).length;

  /// Place names the planner may use, the root included.
  List<String> get placeNames => [for (final w in _owners) w.name.trim()];

  /// The place in this world called [name], ignoring case; null otherwise.
  World? placeNamed(String name) {
    final want = name.trim().toLowerCase();
    if (want.isEmpty) return null;
    for (final w in _owners) {
      if (w.name.trim().toLowerCase() == want) return w;
    }
    return null;
  }

  /// The chain a scene set at [placeId] reads, leaf first up to the root:
  /// the same walk a chat's Setting makes. An unknown or empty id is the
  /// world at large, so a place the planner invented gets the root's prose
  /// and never another room's.
  List<World> chainTo(String placeId) {
    final r = root;
    if (r == null) return const [];
    final byId = {for (final w in _owners) w.id: w};
    final leaf = byId[placeId];
    if (leaf == null) return [r];
    final chain = worldChain(leaf, (id) => byId[id]);
    return chain.last.id == r.id ? chain : [...chain, r];
  }

  /// The `<places>` body: every place by name with a line of its own prose,
  /// the root first, so a planner can name where a scene happens.
  String placesBody() {
    final r = root;
    if (r == null) return '';
    return [
      for (final w in _owners)
        '- ${w.name.trim()}${w.id == r.id ? ' (the world at large)' : ''}'
            '${w.injectDescription && w.description.trim().isNotEmpty ? ': ${_clip(w.description.trim(), kStoryWorldPlaceLineChars)}' : ''}',
    ].join('\n');
  }

  /// The world's book as story lore, each entry tagged with the root and
  /// the place that owns it so Refresh can tell them from story-grown lore.
  List<StoryLoreEntry> loreEntries({String? userName, String? charName}) {
    final r = root;
    if (r == null) return const [];
    final out = <StoryLoreEntry>[];
    for (final w in _owners) {
      for (final e in w.lorebook.entries) {
        if (!e.enabled || e.content.trim().isEmpty) continue;
        final topic = e.name.trim().isNotEmpty
            ? e.name.trim()
            : (e.keys.isNotEmpty ? e.keys.first.trim() : 'Fact');
        out.add(
          StoryLoreEntry(
            topic: resolveStoryMacros(
              topic,
              userName: userName,
              charName: charName,
            ),
            detail: resolveStoryMacros(
              e.content.trim(),
              userName: userName,
              charName: charName,
            ),
            relatedTo: [worldTag(r.id), placeTag(w.id)],
          ),
        );
      }
    }
    return out;
  }

  /// Refresh from world: [fromWorld] replaces the entries that came from a
  /// world; uploads and story-grown entries are kept where they were.
  static List<StoryLoreEntry> refresh(
    List<StoryLoreEntry> existing,
    List<StoryLoreEntry> fromWorld,
  ) => [...fromWorld, ...existing.where((e) => !isWorldLore(e))];

  /// The `<setting_world>` text: the root, its climate, the place tree with
  /// the starting place marked, and the always-on facts, under
  /// [kStoryWorldBriefChars]. The root's description gives way first, then
  /// the facts from the end; the tree is never cut.
  String brief() {
    final r = root;
    if (r == null) return '';
    final head = StringBuffer()..writeln('World: ${r.name.trim()}');
    final climate = _climateLine();
    final tree = _tree();
    final facts = [
      for (final e in _liveEntries)
        if (e.constant)
          '- ${e.name.trim().isEmpty ? 'Always true' : e.name.trim()}: '
              '${e.content.trim()}',
    ];

    String assemble(String desc, List<String> factLines) => [
      head.toString().trimRight(),
      if (desc.isNotEmpty) desc,
      if (climate.isNotEmpty) climate,
      tree,
      if (factLines.isNotEmpty) 'Always true:\n${factLines.join('\n')}',
    ].join('\n');

    var desc = r.injectDescription ? r.description.trim() : '';
    var text = assemble(desc, facts);
    if (text.length <= kStoryWorldBriefChars) return text;

    final fixed = assemble('', facts).length;
    final descBudget = kStoryWorldBriefChars - fixed - 1;
    desc = descBudget >= 200 ? _clip(desc, descBudget) : '';
    text = assemble(desc, facts);
    final kept = [...facts];
    while (text.length > kStoryWorldBriefChars && kept.isNotEmpty) {
      kept.removeLast();
      text = assemble(desc, kept);
    }
    return text;
  }

  String _climateLine() {
    final author = climateAuthorOf(chain);
    if (author == null) return '';
    final biome = Biome.resolve(
      biomeId: author.biomeId,
      biomeJson: author.biomeJson,
    );
    final seasons = biome.seasonLabels.values
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final traits = [
      atmosphereLine(author.atmosphere),
      gravityLine(author.gravity),
    ].nonNulls.join(' ');
    return [
      'Climate: ${biome.displayName}.',
      if (seasons.isNotEmpty) 'Seasons: ${seasons.join(', ')}.',
      if (traits.isNotEmpty) traits,
    ].join(' ');
  }

  String _tree() {
    final r = root!;
    final s = start!;
    final where = s.id == r.id
        ? 'the story starts in ${r.name.trim()} at large'
        : 'the story starts at ${s.name.trim()}';
    final lines = <String>['Places ($where):'];
    final depth = <String, int>{r.id: 0};
    for (final p in places) {
      if (p.id == r.id) continue;
      final d = (depth[p.parentWorldId ?? ''] ?? 0) + 1;
      depth[p.id] = d;
      final mark = p.id == s.id ? ' (start)' : '';
      final desc = p.injectDescription
          ? _clip(p.description.trim(), kStoryWorldPlaceLineChars)
          : '';
      lines.add(
        '${'  ' * (d - 1)}- ${p.name.trim()}$mark'
        '${desc.isEmpty ? '' : ': $desc'}',
      );
    }
    if (lines.length == 1) lines.add('- (no places drawn inside it yet)');
    return lines.join('\n');
  }

  /// At most [max] characters, cut at a sentence end when one is near.
  static String _clip(String text, int max) {
    if (text.length <= max) return text;
    final head = text.substring(0, max);
    final stop = head.lastIndexOf(RegExp(r'[.!?]'));
    if (stop >= max ~/ 2) return head.substring(0, stop + 1);
    return '${head.trimRight()}…';
  }
}
