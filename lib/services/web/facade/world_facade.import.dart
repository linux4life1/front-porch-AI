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

part of 'world_facade.dart';

/// World / lorebook import. CRUD and chat-places stay on [WorldFacade].
extension WorldFacadeImport on WorldFacade {
  /// Import .fpworld or bare lorebook JSON as a place. Routes through
  /// WorldRepository.importWorldJson — the same path desktop file import
  /// uses — so climate, place traits, lore, provenance, and name
  /// uniquifying behave identically on both surfaces.
  Future<bool> importWorld(Map<String, dynamic> json) async {
    // Reject payloads that are neither a package envelope nor a lorebook.
    final isEnvelope =
        json.containsKey('formatVersion') ||
        (json.containsKey('id') &&
            json.containsKey('name') &&
            (json.containsKey('lorebook') || json.containsKey('lorebooks')));
    if (!isEnvelope &&
        json['entries'] == null &&
        json['lorebook'] == null &&
        detectLorebookFormat(json) == LorebookFormat.fpaiOrSt) {
      return false;
    }
    try {
      await _worlds.importWorldJson(json);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Import a lorebook with a chosen destination — the web twin of the
  /// desktop Import Lorebook wizard. `dryRun` returns the review summary +
  /// destination availability without writing anything; a commit clones the
  /// decoded entries into exactly one home. Additive API; the plain
  /// [importWorld] endpoint is untouched for older clients.
  Future<Map<String, dynamic>?> importLorebook(
    Map<String, dynamic> json, {
    bool dryRun = false,
    String destination = 'world',
    String? name,
    String? description,
    List<String> characterIds = const [],
  }) async {
    if (json['entries'] == null &&
        json['lorebook'] == null &&
        detectLorebookFormat(json) == LorebookFormat.fpaiOrSt) {
      return null; // unrecognized shape → 400
    }
    final source = json['lorebook'] is Map
        ? Map<String, dynamic>.from(json['lorebook'] as Map)
        : json;
    final book = Lorebook.fromJson(source);
    final summary = LorebookImportSummary.analyze(json, book);

    if (dryRun) {
      return {
        'format': summary.formatLabel,
        'suggestedName': summary.suggestedName,
        'suggestedDescription': summary.suggestedDescription,
        'entryCount': summary.entryCount,
        'enabledCount': summary.enabledCount,
        'approxTokens': summary.approxTokens,
        'features': summary.features,
        'warnings': summary.warnings,
        'canGroup': _chat?.activeGroup != null,
        'canChat': _chat?.currentSessionId != null,
      };
    }
    if (book.entries.isEmpty) return null;

    Lorebook clonedBook() => cloneLorebook(book);
    List<LorebookEntry> cloned() => clonedBook().entries;

    switch (destination) {
      case 'world':
        var base = (name ?? summary.suggestedName).trim();
        if (base.isEmpty) base = 'Imported Lorebook';
        final taken = _worlds.worlds.map((w) => w.name).toSet();
        final candidate = uniqueWorldName(base, taken.contains);
        await _worlds.saveWorld(
          World(
            name: candidate,
            description: (description ?? summary.suggestedDescription).trim(),
            lorebook: clonedBook(),
          ),
        );
        return {'ok': true, 'where': 'world', 'name': candidate};
      case 'characters':
        final chars = _characters;
        if (chars == null || characterIds.isEmpty) return null;
        var count = 0;
        for (final c in chars.characters) {
          if (c.dbId == null || !characterIds.contains(c.dbId)) continue;
          final existing = c.lorebook;
          if (existing == null) {
            c.lorebook = clonedBook();
          } else {
            existing.entries.addAll(cloned());
          }
          await chars.updateCharacter(c);
          count++;
        }
        return count > 0
            ? {'ok': true, 'where': 'characters', 'count': count}
            : null;
      case 'group':
        final g = _chat?.activeGroup;
        final groups = _groups;
        if (g == null || groups == null) return null;
        g.groupLorebook = appendToGroupLorebookJson(g.groupLorebook, cloned());
        await groups.save(g);
        return {'ok': true, 'where': 'group', 'name': g.name};
      case 'chat':
        final chat = _chat;
        if (chat == null || chat.currentSessionId == null) return null;
        chat.chatLorebook.entries.addAll(cloned());
        await chat.commitChatLorebookEdit();
        return {'ok': true, 'where': 'chat'};
    }
    return null;
  }
}
