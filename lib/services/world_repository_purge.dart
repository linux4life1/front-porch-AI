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

part of 'world_repository.dart';

const _purgePrefKey = 'purged_character_linked_worlds_v1';

/// One-shot character-linked clone purge. CRUD stays on [WorldRepository].
extension WorldRepositoryPurge on WorldRepository {
  Future<void> _maybePurgeCharacterLinkedWorlds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_purgePrefKey) == true) return;
      final result = await purgeCharacterLinkedWorlds();
      // Only mark the one-shot done when every clone was exported+deleted —
      // a skipped world (failed recovery export) must be retried next launch,
      // not stranded forever behind the pref.
      if (result.skipped == 0) {
        await prefs.setBool(_purgePrefKey, true);
      } else {
        debugPrint(
          '[Worlds] purge left ${result.skipped} world(s) in place '
          '(recovery export failed) — retrying next launch',
        );
      }
      final n = result.deleted;
      if (n > 0) {
        final recovery = p.join(
          _storageService.worldsDir.path,
          'recovered_character_lore_clones',
        );
        debugPrint(
          '[Worlds] Purged $n character-linked lore clones '
          '(character card lore untouched; any edits that lived only on the '
          'world were saved as .fpworld under $recovery)',
        );
      }
    } catch (e) {
      debugPrint('[Worlds] character-linked purge skipped: $e');
    }
  }

  /// Delete every legacy character-world clone and strip references from
  /// characters / groups / chat_worlds. Character card lorebooks are untouched.
  ///
  /// **Safety:** each doomed world is exported as `.fpworld` into
  /// `worlds/recovered_character_lore_clones/` *before* the hard delete, so
  /// users who edited "Aerin's Lorebook" in the Worlds tab (edits that never
  /// flowed back to the card) can re-import those packages. A world whose
  /// export FAILS is not deleted — it stays in place and the caller retries
  /// on a later launch. Returns how many worlds were deleted and how many
  /// were skipped that way.
  Future<({int deleted, int skipped})> _purgeCharacterLinkedWorldsImpl() async {
    final doomed = _worlds.where(isCharacterLinkedWorld).toList();
    if (doomed.isEmpty) return (deleted: 0, skipped: 0);

    // Lossless edge case: export before hard delete (Claude review 2026-07-28).
    final recoveryDir = Directory(
      p.join(_storageService.worldsDir.path, 'recovered_character_lore_clones'),
    );
    try {
      await recoveryDir.create(recursive: true);
    } catch (e) {
      debugPrint('[Worlds] could not create recovery dir: $e');
    }

    final exportedWorlds = <model.World>[];
    var skipped = 0;
    for (final w in doomed) {
      // The export may be the user's only copy of world-only lore edits, so
      // a failed export means this world is NOT touched this launch.
      try {
        final safe = _safeFileStem(w.name);
        final idShort = w.id.length >= 8 ? w.id.substring(0, 8) : w.id;
        final out = p.join(recoveryDir.path, '${safe}_$idShort.fpworld');
        await exportFpWorld(w, out);
      } catch (e) {
        debugPrint(
          '[Worlds] recovery export failed for "${w.name}" (${w.id}) — '
          'keeping the world: $e',
        );
        skipped++;
        continue;
      }
      exportedWorlds.add(w);
    }
    if (exportedWorlds.isEmpty) {
      debugPrint(
        '[Worlds] purge: 0/${doomed.length} clones exportable '
        '($skipped kept) → ${recoveryDir.path}',
      );
      return (deleted: 0, skipped: skipped);
    }
    final ids = {for (final w in exportedWorlds) w.id};
    final names = {for (final w in exportedWorlds) w.name};

    // Strip refs BEFORE deleting rows (Grok review): if the strip throws,
    // nothing has been deleted yet, so the next launch re-dooms the same
    // worlds and retries the whole purge. Strip-after-delete had a pref-lock
    // hole — a partial run deleted worlds, the next launch saw no doomed
    // rows, reported clean, and locked the one-shot pref with dangling
    // character/group refs never stripped.
    await _db.stripWorldRefsFromCharactersAndGroups(ids: ids, names: names);

    // Keep in-memory character/group lists in sync without a full app restart.
    final charRepo = _characterRepository;
    if (charRepo != null) {
      for (final c in charRepo.characters) {
        final before = c.worldNames.length;
        c.worldNames = [
          for (final ref in c.worldNames)
            if (!ids.contains(ref) && !names.contains(ref)) ref,
        ];
        if (c.worldNames.length != before) {
          try {
            await charRepo.updateCharacter(c);
          } catch (e) {
            debugPrint('[Worlds] strip worldNames on ${c.name}: $e');
          }
        }
      }
    }
    final groupRepo = _groupRepository;
    if (groupRepo != null) {
      for (final g in List.of(groupRepo.groups)) {
        final before = g.worldIds.length;
        g.worldIds = [
          for (final ref in g.worldIds)
            if (!ids.contains(ref) && !names.contains(ref)) ref,
        ];
        if (g.worldIds.length != before) {
          try {
            await groupRepo.save(g);
          } catch (e) {
            debugPrint('[Worlds] strip worldIds on group ${g.name}: $e');
          }
        }
      }
    }

    // Delete only now that refs are gone. A failed delete leaves an
    // unreferenced clone row that the next launch re-dooms and retries.
    var deleted = 0;
    for (final w in exportedWorlds) {
      await _db.deleteChatWorldLinksForWorld(w.id);
      await _db.deleteWorldById(w.id);
      deleted++;
    }
    _worlds.removeWhere((w) => ids.contains(w.id));
    debugPrint(
      '[Worlds] purged $deleted/${doomed.length} clones '
      '($skipped kept on failed export) → ${recoveryDir.path}',
    );

    notify();
    return (deleted: deleted, skipped: skipped);
  }

  /// Filesystem-safe stem for recovery exports (no path separators).
  static String _safeFileStem(String name) {
    final cleaned = name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return 'world';
    return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  }
}
