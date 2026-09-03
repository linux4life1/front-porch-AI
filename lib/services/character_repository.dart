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

import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/portrait_promotion.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
// The Drift row class collides with the model of the same name (hidden above),
// so the grouped-avatar map names the row type through a prefix.
import 'package:front_porch_ai/database/database.dart' as rows show AvatarImage;
import 'package:front_porch_ai/utils/utils.dart'
    show StartupTrace, stableGroupIdFrom;

part 'character_repository.crud.dart';
part 'character_repository.import.dart';
part 'character_repository.media.dart';

/// Extract the basename from a potentially full path (handles / and \).
/// Returns the input unchanged if it's already a basename.
String _toBasename(String path) {
  return path.split(RegExp(r'[/\\]')).last;
}

class CharacterRepository extends ChangeNotifier {
  AppDatabase _db;
  final StorageService _storage;
  final List<CharacterCard> _characters = [];
  bool _isLoading = false;

  List<CharacterCard> get characters => List.unmodifiable(_characters);
  bool get isLoading => _isLoading;

  /// All unique tags across all characters (for autocomplete)
  List<String> get allTags {
    final tags = <String>{};
    for (final c in _characters) {
      tags.addAll(c.tags);
    }
    final sorted = tags.toList()..sort();
    return sorted;
  }

  /// Returns a CharacterCard by DB UUID (prefers in-memory list for freshness,
  /// falls back to DB query + parse). Used by export flows.
  Future<CharacterCard?> getCharacterCardById(String id) async {
    // Prefer in-memory (may have unsaved edits in edge cases, though normally DB is authoritative)
    for (final c in _characters) {
      if (c.dbId == id) return c;
    }
    // Fallback: query DB and parse (keeps export working even during partial loads)
    try {
      final row = await _db.getCharacterById(id);
      return _characterFromRow(row);
    } catch (_) {
      return null;
    }
  }

  CharacterRepository(this._db, this._storage) {
    loadCharacters();
  }

  /// Resolve a stored image path (basename or full path) to the local full path.
  String _resolveImagePath(String stored) {
    final basename = _toBasename(stored);
    return '${_storage.charactersDir.path}/$basename';
  }

  /// Update the database reference (e.g. after cloud sync replaces the DB file).
  void updateDatabase(AppDatabase db) {
    _db = db;
  }

  /// Plain (non-`@protected`) forwarder to the inherited `notifyListeners()`.
  /// Split-mechanism requirement, not a behavior change: `ChangeNotifier`
  /// marks `notifyListeners` `@protected`/`@visibleForTesting`, and Dart's
  /// protected-member check does not treat an extension `on CharacterRepository`
  /// as "within" the class the way an actual instance method is — so the
  /// crud/import part-file extensions (which need to notify after a mutation,
  /// same as the original in-class methods did) cannot call it directly.
  /// This unannotated wrapper is an ordinary library-private member, visible
  /// to every part via `part of`, and does nothing but forward the call.
  void _notify() => notifyListeners();

  Future<void> loadCharacters() async {
    // Re-entrancy guard: the toolbar refresh button (and other callers) can trigger
    // rapid or concurrent calls. Skip redundant work while a load is already in flight.
    // This prevents interleaved _characters mutations and flickering isLoading state.
    // A skipped call also skips the initial _isLoading=true/notify (no spurious flicker for that caller).
    // Fire-and-forget callers (e.g. some web server paths) may be dropped when busy;
    // the in-flight load will still deliver the final update to listeners.
    if (_isLoading) return;

    // Full reload = the path that picks up EXTERNAL changes (Character
    // Card Forge writes files/DB directly, manual PNG swaps, the toolbar
    // refresh) — the cover cache must not survive it, or a file replaced
    // on disk under an unchanged star/portrait key would render stale.
    _clearCoverCache();

    _isLoading = true;
    notifyListeners();
    final traceStart = DateTime.now();

    try {
      final dbChars = await _db.getAllCharacters();
      StartupTrace.mark(
        'CharacterRepository: got ${dbChars.length} rows from DB',
      );

      _characters.clear();

      final missingPngNames = <String>[];
      final noCardDataNames = <String>[];

      // Every character's avatars in one query instead of one query per
      // character. Each Drift call is a round trip to the database isolate, so
      // the old N+1 cost grew with the size of the library for no reason.
      Map<String, List<rows.AvatarImage>> avatarsByCharacter = const {};
      try {
        avatarsByCharacter = await _db.getAvatarImagesGroupedByCharacter();
      } catch (e) {
        debugPrint('[CharacterRepository] Failed to load avatar images: $e');
      }

      for (final c in dbChars) {
        final card = _characterFromRow(c);

        // Normalize DB path to basename-only (one-time migration for old full paths).
        // Then resolve to local full path for runtime use.
        if (card.imagePath != null) {
          final basename = _toBasename(card.imagePath!);
          if (basename != card.imagePath) {
            // DB still has a full path — strip it to basename for portability
            if (card.dbId != null) {
              await _db.updateCharacterImagePath(card.dbId!, basename);
            }
          }
          // Always resolve to local full path for runtime use
          card.imagePath = _resolveImagePath(basename);

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
            card.avatarImages = driftAvatars
                .map(
                  (a) => AvatarImage(
                    id: a.id,
                    characterId: a.characterId,
                    filename: a.filename,
                    label: a.label,
                    displayOrder: a.displayOrder,
                    createdAt: a.createdAt,
                  ),
                )
                .toList();
          }
        }

        _characters.add(card);
      }

      // Summarize missing PNGs once (common when developing from source or after cloud deletes)
      if (missingPngNames.isNotEmpty) {
        debugPrint(
          '[CharacterRepository] ${missingPngNames.length} characters have missing local PNG files '
          '(they can be restored via Cloud Sync): ${missingPngNames.join(", ")}',
        );
      }
      if (noCardDataNames.isNotEmpty) {
        debugPrint(
          '[CharacterRepository] ${noCardDataNames.length} PNGs carry no card '
          'data: ${noCardDataNames.join(", ")}',
        );
      }
    } catch (e) {
      debugPrint('[CharacterRepository] Error loading characters from DB: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
      StartupTrace.mark(
        'CharacterRepository.loadCharacters DONE — ${_characters.length} chars'
        ' in ${DateTime.now().difference(traceStart).inMilliseconds}ms'
        ' (home grid is now populated)',
      );
    }
  }

  /// Delete PNG files in the Characters directory that are not referenced
  /// by any character in the database. This cleans up orphans left behind
  /// when the DB is replaced via cloud sync or characters are deleted
  /// without their file being removed.
  Future<int> cleanOrphanedPngs() async {
    try {
      final charDir = _storage.charactersDir;
      if (!await charDir.exists()) return 0;

      // Collect the FILENAMES referenced by loaded characters. Comparing whole
      // path strings cannot work: referenced paths are built with a literal '/'
      // (`_resolveImagePath`) while `Directory.list()` returns the platform
      // separator — on Windows that is '\', so no referenced path ever matched
      // its own file and every live portrait was classified as an orphan.
      // Case is folded because Windows/macOS filesystems match names that way;
      // a near-miss must err toward KEEPING the file.
      final referencedNames = <String>{};
      for (final c in _characters) {
        if (c.imagePath != null) {
          referencedNames.add(_toBasename(c.imagePath!).toLowerCase());
        }
      }

      int deletedCount = 0;
      await for (final entity in charDir.list()) {
        if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
          if (!referencedNames.contains(
            _toBasename(entity.path).toLowerCase(),
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

  /// Convert a DB row into a CharacterCard model.
  CharacterCard _characterFromRow(Character c) {
    List<String> altGreetings = [];
    try {
      altGreetings = List<String>.from(jsonDecode(c.alternateGreetings));
    } catch (_) {}

    List<String> tags = [];
    try {
      tags = List<String>.from(jsonDecode(c.tags));
    } catch (_) {}

    List<String> worldNames = [];
    try {
      worldNames = List<String>.from(jsonDecode(c.worldNames));
    } catch (_) {}

    Lorebook? lorebook;
    if (c.lorebook != null) {
      try {
        lorebook = Lorebook.fromJson(jsonDecode(c.lorebook!));
      } catch (_) {}
    }

    final card = CharacterCard(
      name: c.name,
      description: c.description,
      personality: c.personality,
      scenario: c.scenario,
      firstMessage: c.firstMessage,
      mesExample: c.mesExample,
      systemPrompt: c.systemPrompt,
      postHistoryInstructions: c.postHistoryInstructions,
      alternateGreetings: altGreetings,
      tags: tags,
      imagePath: c.imagePath,
      ttsVoice: c.ttsVoice,
      lorebook: lorebook,
      worldNames: worldNames,
    );
    // Store DB id for lookups
    card.dbId = c.id;
    // Library "date added" — used by the home-screen "Import Date" sort. Reading
    // the real DB column (instead of parsing a timestamp out of the image
    // filename) means cards without the legacy `<name>_<epoch>.png` naming
    // (JSON imports, Chub downloads, renamed files) still sort correctly.
    card.createdAt = c.createdAt;
    card.primeAvatarIndex = c.primeAvatarIndex;
    return card;
  }

  /// Library characters whose display name equals [name] (exact match).
  /// Used by the single-file import collision dialog.
  List<CharacterCard> charactersWithName(String name) {
    return _characters.where((c) => c.name == name).toList(growable: false);
  }

  /// Library character whose PNG-carried stableId matches [stableId], if any.
  CharacterCard? findByStableId(String? stableId) {
    if (stableId == null || stableId.isEmpty) return null;
    for (final c in _characters) {
      if (c.frontPorchExtensions?.stableId == stableId) return c;
    }
    return null;
  }

  /// One deferred broadcast for surfaces that persisted silently
  /// (updateCharacter notify: false) — fired when their dialog closes.
  void notifyCharactersChanged() {
    _clearCoverCache();
    _bumpCoverEpoch();
    notifyListeners();
  }

  /// The file to bake as the character's exported / Stoop card cover: the ★
  /// starred avatar (a gallery look OR an expression image) when it's set and
  /// present on disk, else the library portrait (`imagePath`). Null when neither
  /// resolves. Lets a user pick their best render (an outfit, a mood) as the
  /// card's face without touching the in-app portrait.
  ///
  /// [card] must be a HYDRATED library card (`avatarImages` loaded) for the star
  /// to resolve — a bare card silently falls back to the portrait. Every PNG
  /// bake / upload path should route through this so the star works everywhere.
  /// Memo for [coverImageFileFor]: chat message bubbles resolve the cover
  /// on EVERY rebuild (dozens of bubbles × every streaming token batch),
  /// and the uncached path does a synchronous existsSync per call — near
  /// free on macOS/APFS, but 10-100x slower on Windows where Defender
  /// intercepts file stats. Field-reported as "the app got sluggish" in
  /// the 20260716 nightly. The key embeds the star id and portrait path,
  /// so changing either self-invalidates; mutations also clear the whole
  /// cache (updateCharacter / delete / notifyCharactersChanged) to cover
  /// files changing on disk under an unchanged key.
  final Map<String, File?> _coverCache = {};

  /// Bumped whenever cover bytes may have changed under a stable path (in-place
  /// portrait overwrite). Home grid [Image.file] keys include this so Done
  /// after gallery bootstrap refreshes the face without needing a ★ re-click.
  int coverEpoch = 0;

  void _clearCoverCache() => _coverCache.clear();

  void _bumpCoverEpoch() => coverEpoch++;

  File? coverImageFileFor(CharacterCard card) {
    final favId = card.frontPorchExtensions?.favoriteAvatarId;
    final key = '${card.name}|$favId|${card.imagePath}|$coverEpoch';
    if (_coverCache.containsKey(key)) return _coverCache[key];
    if (_coverCache.length > 512) _coverCache.clear();

    File? result;
    if (favId != null) {
      for (final a in card.avatarImages ?? const <AvatarImage>[]) {
        if (a.id == favId) {
          final f = a.resolveFile(_storage.characterBaseDir(card.name).path);
          if (f.existsSync()) result = f;
          break;
        }
      }
    }
    if (result == null) {
      final img = card.imagePath;
      if (img != null && img.isNotEmpty) {
        result = _storage.resolveCharacterImage(img);
      }
    }
    _coverCache[key] = result;
    return result;
  }
}
