// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One-shot purge of legacy character-linked world clones.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/utils/utils.dart';

const _purgePrefKey = 'purged_character_linked_worlds_v1';
const _recoveryDirName = 'recovered_character_lore_clones';

class CharacterLinkedWorldPurge {
  CharacterLinkedWorldPurge({
    required WorldRepository repo,
    required AppDatabase Function() db,
    required StorageService storage,
    required CharacterRepository? Function() characters,
    required GroupChatRepository? Function() groups,
    required void Function(Set<String> ids) dropFromCache,
  }) : _repo = repo,
       _db = db,
       _storage = storage,
       _characters = characters,
       _groups = groups,
       _dropFromCache = dropFromCache;

  final WorldRepository _repo;
  final AppDatabase Function() _db;
  final StorageService _storage;
  final CharacterRepository? Function() _characters;
  final GroupChatRepository? Function() _groups;
  final void Function(Set<String> ids) _dropFromCache;

  String get _recoveryPath => p.join(_storage.worldsDir.path, _recoveryDirName);

  /// Runs [WorldRepository.purgeCharacterLinkedWorlds] once per library.
  Future<void> maybePurge() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_purgePrefKey) == true) return;
      final result = await _repo.purgeCharacterLinkedWorlds();
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
        debugPrint(
          '[Worlds] Purged $n character-linked lore clones '
          '(character card lore untouched; any edits that lived only on the '
          'world were saved as .fpworld under $_recoveryPath)',
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
  Future<({int deleted, int skipped})> purge() async {
    final doomed = _repo.worlds.where(isCharacterLinkedWorld).toList();
    if (doomed.isEmpty) return (deleted: 0, skipped: 0);

    final recoveryDir = Directory(_recoveryPath);
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
        await _repo.exportFpWorld(w, out);
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

    // Strip refs BEFORE deleting rows: if the strip throws, nothing has been
    // deleted yet, so the next launch re-dooms the same worlds and retries
    // the whole purge. Strip-after-delete let a partial run lock the
    // one-shot pref with dangling character/group refs never stripped.
    await _db().stripWorldRefsFromCharactersAndGroups(ids: ids, names: names);
    await _stripInMemoryRefs(ids, names);

    // Delete only now that refs are gone. A failed delete leaves an
    // unreferenced clone row that the next launch re-dooms and retries.
    var deleted = 0;
    for (final w in exportedWorlds) {
      await _db().deleteChatWorldLinksForWorld(w.id);
      await _db().deleteWorldById(w.id);
      deleted++;
    }
    _dropFromCache(ids);
    debugPrint(
      '[Worlds] purged $deleted/${doomed.length} clones '
      '($skipped kept on failed export) → ${recoveryDir.path}',
    );

    _repo.notify();
    return (deleted: deleted, skipped: skipped);
  }

  /// Keep in-memory character/group lists in sync without a full restart.
  Future<void> _stripInMemoryRefs(Set<String> ids, Set<String> names) async {
    bool keep(String ref) => !ids.contains(ref) && !names.contains(ref);

    final charRepo = _characters();
    if (charRepo != null) {
      for (final c in charRepo.characters) {
        final before = c.worldNames.length;
        final loreBefore = c.loreWorldNames?.length;
        c.worldNames = [
          for (final ref in c.worldNames)
            if (keep(ref)) ref,
        ];
        final lore = c.loreWorldNames;
        if (lore != null) {
          c.loreWorldNames = [
            for (final ref in lore)
              if (keep(ref)) ref,
          ];
        }
        if (c.worldNames.length != before ||
            c.loreWorldNames?.length != loreBefore) {
          try {
            await charRepo.updateCharacter(c);
          } catch (e) {
            debugPrint('[Worlds] strip worldNames on ${c.name}: $e');
          }
        }
      }
    }
    final groupRepo = _groups();
    if (groupRepo != null) {
      for (final g in List.of(groupRepo.groups)) {
        final before = g.worldIds.length;
        final loreBefore = g.loreWorldIds?.length;
        g.worldIds = [
          for (final ref in g.worldIds)
            if (keep(ref)) ref,
        ];
        final lore = g.loreWorldIds;
        if (lore != null) {
          g.loreWorldIds = [
            for (final ref in lore)
              if (keep(ref)) ref,
          ];
        }
        if (g.worldIds.length != before ||
            g.loreWorldIds?.length != loreBefore) {
          try {
            await groupRepo.save(g);
          } catch (e) {
            debugPrint('[Worlds] strip worldIds on group ${g.name}: $e');
          }
        }
      }
    }
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
