// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The `preview` rows of the `/api/folders` payload: the up-to-4 member
// portraits the desktop folder tile paints as a 2×2 montage
// (lib/ui/pages/home/cards/folder_grid_card.dart). Split out of
// character_facade.dart, which sits at the 500-line cap.

import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart'
    show CharacterFolder, FolderService;

/// The full `/api/folders` payload: one row per folder with its counts (as
/// before) plus [folderPreviewMembers] rows. [placeholders] and
/// [avatarVersion] are the facade's probe cache and memoized version
/// resolver, passed in so this stays IO-cold on the hot refetch path.
List<Map<String, dynamic>> folderListPayload(
  FolderService svc,
  List<Character> characters,
  List<CharacterCard> cards,
  Set<String> Function(
    List<Character> characters,
    Map<String, CharacterCard> byDbId,
  )
  placeholders,
  int Function(
    String? imagePath,
    String characterId,
    Map<String, CharacterCard> byDbId,
  )
  avatarVersion,
) {
  // Same one-pass id→card index the character list builds (the hot-loop
  // fix its comment records) — no per-folder copy of the library.
  final byDbId = <String, CharacterCard>{};
  for (final card in cards) {
    final id = card.dbId;
    if (id != null) byDbId[id] = card;
  }
  final ph = placeholders(characters, byDbId);
  return svc.folders
      .map(
        (f) => {
          'id': f.id,
          'name': f.name,
          if (f.parentId != null) 'parentId': f.parentId,
          'characterCount': svc.getCharactersInFolderRecursive(f.id).length,
          'groupCount': svc.groupIdsInFolderRecursive(f.id).length,
          'preview': folderPreviewMembers(
            f,
            characters,
            byDbId,
            ph,
            avatarVersion,
          ),
        },
      )
      .toList();
}

/// Portraits of the first few characters inside [folder], in the folder's own
/// order — the same walk the desktop tile does in `_folderPreviewImages`
/// (first match by image filename, stop at [max]; empty folders preview
/// nothing and the web tile falls back to the folder glyph, as on desktop).
///
/// Rows carry the same fields the character and group grids already ride
/// (`id`, `name`, `hasAvatar`, `placeholderPortrait`, `avatarVersion`), so
/// the web reuses their avatar URLs and initial-fallback drawing unchanged.
///
/// [placeholders] comes from the facade's non-blocking probe cache and
/// [avatarVersion] from its memoized resolver — neither may do cold IO here:
/// `/api/folders` refetches on every `library_changed` broadcast.
List<Map<String, dynamic>> folderPreviewMembers(
  CharacterFolder folder,
  List<Character> characters,
  Map<String, CharacterCard> byDbId,
  Set<String> placeholders,
  int Function(
    String? imagePath,
    String characterId,
    Map<String, CharacterCard> byDbId,
  )
  avatarVersion, {
  int max = 4,
}) {
  if (folder.characterPaths.isEmpty) return const [];
  final byFilename = <String, Character>{};
  for (final c in characters) {
    final path = c.imagePath;
    if (path != null && path.isNotEmpty) {
      byFilename.putIfAbsent(p.basename(path), () => c);
    }
  }
  final out = <Map<String, dynamic>>[];
  for (final ref in folder.characterPaths) {
    final c = byFilename[p.basename(ref)];
    if (c == null) continue;
    out.add({
      'id': c.id,
      'name': c.name,
      'hasAvatar': c.imagePath != null && c.imagePath!.isNotEmpty,
      'placeholderPortrait': placeholders.contains(c.id),
      'avatarVersion': avatarVersion(c.imagePath, c.id, byDbId),
    });
    if (out.length >= max) break;
  }
  return out;
}
