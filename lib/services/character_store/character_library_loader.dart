// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One full read of the character library (rows + PNG extensions + avatar
// rows), and the orphaned-portrait sweep that trusts its result.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/database/database.dart' as rows show AvatarImage;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_store/character_row_codec.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/utils/utils.dart' show StartupTrace;

class CharacterLibraryLoader {
  const CharacterLibraryLoader(this._storage);

  final StorageService _storage;

  /// Resolve a stored image path (basename or full path) to the local full path.
  String resolveImagePath(String stored) {
    final basename = toBasename(stored);
    return '${_storage.charactersDir.path}/$basename';
  }

  /// Clears [into] and fills it card by card from [db], so a reader during
  /// the load sees the list grow rather than a stale copy. Returns whether
  /// the storage root was known when the portraits were read.
  Future<bool> loadInto(AppDatabase db, List<CharacterCard> into) async {
    final dbChars = await db.getAllCharacters();
    StartupTrace.mark(
      'CharacterRepository: got ${dbChars.length} rows from DB',
    );

    into.clear();

    final missingPngNames = <String>[];
    final noCardDataNames = <String>[];

    // Every character's avatars in one query instead of one query per
    // character. Each Drift call is a round trip to the database isolate, so
    // the old N+1 cost grew with the size of the library for no reason.
    Map<String, List<rows.AvatarImage>> avatarsByCharacter = const {};
    try {
      avatarsByCharacter = await db.getAvatarImagesGroupedByCharacter();
    } catch (e) {
      debugPrint('[CharacterRepository] Failed to load avatar images: $e');
    }

    // Taken where the portraits start to resolve against the root.
    final hadRoot = _storage.rootPath != null;
    for (final c in dbChars) {
      final card = characterFromRow(c);

      // Normalize DB path to basename-only (one-time migration for old full paths).
      // Then resolve to local full path for runtime use.
      if (card.imagePath != null) {
        final basename = toBasename(card.imagePath!);
        if (basename != card.imagePath) {
          // DB still has a full path — strip it to basename for portability
          if (card.dbId != null) {
            await db.updateCharacterImagePath(card.dbId!, basename);
          }
        }
        // Always resolve to local full path for runtime use
        card.imagePath = resolveImagePath(basename);

        // Always read extensions fresh from PNG.
        // V2.5 extensions live only in the PNG tEXt chunk (not in DB).
        // We intentionally do NOT cache previous in-memory values here:
        // the old cache caused edits to be silently overwritten by stale
        // pre-edit values whenever loadCharacters() ran after an edit.
        // Logging here is summarised after the loop, not emitted per card:
        // debugPrint is NOT compiled out of release builds, so a 500-card
        // library was building 500+ log strings nobody reads on every load.
        try {
          final v2Service = V2CardService();
          final reloaded = await v2Service.readCard(card.imagePath!);
          if (reloaded != null) {
            card.frontPorchExtensions = reloaded.frontPorchExtensions;
            card.rawExtensions = reloaded.rawExtensions;
          } else {
            noCardDataNames.add(card.name);
          }
        } catch (e) {
          if (e is PathNotFoundException ||
              e.toString().contains('No such file')) {
            missingPngNames.add(card.name);
          } else {
            debugPrint(
              '[CharacterRepository] Failed to load PNG for ${card.name}: $e',
            );
          }
        }
      }

      // Avatar images come from the one grouped query above, so they still
      // survive hot reloads without a per-character round trip.
      if (card.dbId != null) {
        final driftAvatars = avatarsByCharacter[card.dbId!];
        if (driftAvatars != null && driftAvatars.isNotEmpty) {
          card.avatarImages = driftAvatars.map(avatarFromRow).toList();
        }
      }

      into.add(card);
    }

    // Summarize missing portrait files once.
    if (missingPngNames.isNotEmpty) {
      debugPrint(
        '[CharacterRepository] ${missingPngNames.length} characters are '
        'missing their portrait file: ${missingPngNames.join(", ")}',
      );
    }
    if (noCardDataNames.isNotEmpty) {
      debugPrint(
        '[CharacterRepository] ${noCardDataNames.length} PNGs carry no card '
        'data: ${noCardDataNames.join(", ")}',
      );
    }
    return hadRoot;
  }

  /// Delete PNG files in the Characters directory that no card in [library]
  /// references. Returns how many were deleted.
  Future<int> cleanOrphanedPngs(Iterable<CharacterCard> library) async {
    try {
      final charDir = _storage.charactersDir;
      if (!await charDir.exists()) return 0;

      // Collect the FILENAMES referenced by loaded characters. Comparing whole
      // path strings cannot work: referenced paths are built with a literal '/'
      // (`resolveImagePath`) while `Directory.list()` returns the platform
      // separator — on Windows that is '\', so no referenced path ever matched
      // its own file and every live portrait was classified as an orphan.
      // Case is folded because Windows/macOS filesystems match names that way;
      // a near-miss must err toward KEEPING the file.
      final referencedNames = <String>{};
      for (final c in library) {
        if (c.imagePath != null) {
          referencedNames.add(toBasename(c.imagePath!).toLowerCase());
        }
      }

      int deletedCount = 0;
      await for (final entity in charDir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
          if (!referencedNames.contains(
            toBasename(entity.path).toLowerCase(),
          )) {
            debugPrint(
              '[Cleanup] Deleting orphaned PNG: ${p.basename(entity.path)}',
            );
            await entity.delete();
            deletedCount++;
          }
        }
      }

      if (deletedCount > 0) {
        debugPrint('[Cleanup] Deleted $deletedCount orphaned character PNG(s)');
      }
      return deletedCount;
    } catch (e) {
      debugPrint('[Cleanup] Error cleaning orphaned PNGs: $e');
      return 0;
    }
  }
}
