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

part of 'character_repository.dart';

/// Card import (single + bulk, PNG or standalone V2 JSON) and duplication
/// (library copy + the group private-copy variant). Extracted verbatim from
/// `character_repository.dart` (zero behaviour change) to shrink the god
/// file — see the split map for that file. As `part of` the same library,
/// these reach the private DB/storage/list state — and `updateCharacter` /
/// `findByStableId` in the sibling parts — exactly as the in-class methods
/// did.
extension CharacterRepositoryImport on CharacterRepository {
  /// Import a character card file (V2 PNG or standalone V2 JSON).
  ///
  /// Update-in-place happens only when:
  /// - the incoming card's [FrontPorchExtensions.stableId] matches a library
  ///   character (FP reimport / realism edit path — preserves chats), or
  /// - [forceReplaceTarget] is set (user chose "Replace existing" in the
  ///   single-file name-collision dialog).
  ///
  /// Same display name alone never overwrites or soft-deletes. Bulk import
  /// and silent callers omit [forceReplaceTarget] so variants land as
  /// separate library entries (issue #161).
  Future<CharacterCard?> importCharacter(
    File file, {
    CharacterCard? forceReplaceTarget,
  }) async {
    _isLoading = true;
    _notify();
    try {
      final v2Service = V2CardService();

      // A standalone Character Card V2 `.json` file carries no avatar, so we
      // parse it as text and let the placeholder image be generated on persist.
      // PNG cards embed the same JSON in their `chara` chunk.
      final isJson = file.path.toLowerCase().endsWith('.json');

      CharacterCard? card = isJson
          ? await v2Service.readCardFromJsonFile(file.path)
          : await v2Service.readCard(file.path);

      // Fallback if no card data could be parsed
      card ??= CharacterCard(
        name: p.basenameWithoutExtension(file.path),
        description: '',
        imagePath: isJson ? null : file.path,
      );

      return await _persistImportedCharacterCard(
        card,
        // JSON has no image to copy; persist synthesizes a placeholder instead.
        sourceFileForCopy: isJson ? null : file,
        forceReplaceTarget: forceReplaceTarget,
      );
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Internal helper that persists an already-parsed CharacterCard.
  ///
  /// Collision policy (issue #161 + history-preserving reimport):
  /// - **stableId match** → update in place (reuse dbId + PNG path; chats kept)
  /// - **[forceReplaceTarget]** → same update path when the user explicitly
  ///   chose Replace on a same-name card that has no stableId match
  /// - **name-only collision** → fresh insert (never soft-delete peers)
  ///
  /// Ensures stableId is present before embedding via saveCardAsPng.
  /// When [sourceFileForCopy] is provided we use it as visual source for V2 embed.
  Future<CharacterCard?> _persistImportedCharacterCard(
    CharacterCard card, {
    File? sourceFileForCopy,
    CharacterCard? forceReplaceTarget,
  }) async {
    final charDir = _storage.charactersDir;
    if (!await charDir.exists()) {
      await charDir.create(recursive: true);
    }

    final safeName = card.name
        .replaceAll(RegExp(r'[^\w\s\-]'), '')
        .replaceAll(' ', '_');

    // Identity: stableId only. Name is never enough to overwrite or delete.
    // forceReplaceTarget is the explicit single-file "Replace existing" path.
    final stableMatch = findByStableId(card.frontPorchExtensions?.stableId);
    CharacterCard? target = stableMatch;
    if (target == null && forceReplaceTarget != null) {
      // Resolve against the live list by dbId so we don't hold a stale ref.
      final rid = forceReplaceTarget.dbId;
      if (rid != null) {
        for (final c in _characters) {
          if (c.dbId == rid) {
            target = c;
            break;
          }
        }
      }
      target ??= forceReplaceTarget;
    }

    // Ensure stableId before embed. On force-replace of a no-id incoming card,
    // carry the library character's stableId so future FP reimports still match.
    card.frontPorchExtensions ??= FrontPorchExtensions();
    final incomingStable = card.frontPorchExtensions!.stableId;
    if ((incomingStable == null || incomingStable.isEmpty) && target != null) {
      final keep = target.frontPorchExtensions?.stableId;
      if (keep != null && keep.isNotEmpty) {
        card.frontPorchExtensions!.stableId = keep;
      }
    }
    card.frontPorchExtensions!.ensureStableId();

    String destPath;
    // Reuse the target's PNG path on update-in-place to avoid filename churn.
    // Fresh timestamped name for new library entries.
    if (target != null && target.imagePath != null) {
      destPath = target.imagePath!;
    } else if (sourceFileForCopy != null) {
      destPath =
          '${charDir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.png';
    } else if (card.imagePath != null) {
      destPath =
          '${charDir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.png';
    } else {
      destPath =
          '${charDir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.png';
    }

    final v2Service = V2CardService();
    final sourcePathForEmbed = sourceFileForCopy?.path ?? card.imagePath;
    await v2Service.saveCardAsPng(card, destPath, sourcePathForEmbed);

    final destFile = File(destPath);
    if (!destFile.existsSync() || destFile.lengthSync() == 0) {
      debugPrint('[Import] Written file missing or empty: $destPath');
    }

    card.imagePath = destPath;

    final dbImagePath = card.imagePath != null
        ? _toBasename(card.imagePath!)
        : null;

    if (target != null) {
      // Update-in-place: reuse dbId so sessions/chat history survive.
      if (target.imagePath != null) {
        final oldBase = _toBasename(target.imagePath!);
        final newBase = _toBasename(destPath);
        if (oldBase != newBase) {
          try {
            final oldFile = File(target.imagePath!);
            if (await oldFile.exists()) {
              await oldFile.delete();
              debugPrint(
                '[Import] Deleted previous PNG for matched identity '
                '${card.name} (old=$oldBase)',
              );
            }
          } catch (e) {
            debugPrint(
              '[Import] Could not delete previous PNG on reimport: $e',
            );
          }
        }
      }
      card.dbId = target.dbId;
      // In-place update (stableId or Replace): gallery is the new card only.
      await clearGalleryLooks(card.dbId!);

      // updateCharacter does DB companion + list replace (re-embeds PNG; harmless).
      await updateCharacter(card);
    } else {
      final dbId = await _db.insertCharacterReturningId(
        CharactersCompanion(
          name: Value(card.name),
          description: Value(card.description),
          personality: Value(card.personality),
          scenario: Value(card.scenario),
          firstMessage: Value(card.firstMessage),
          mesExample: Value(card.mesExample),
          systemPrompt: Value(card.systemPrompt),
          postHistoryInstructions: Value(card.postHistoryInstructions),
          alternateGreetings: Value(jsonEncode(card.alternateGreetings)),
          tags: Value(jsonEncode(card.tags)),
          imagePath: Value(dbImagePath),
          ttsVoice: Value(card.ttsVoice),
          lorebook: Value(
            card.lorebook != null ? jsonEncode(card.lorebook!.toJson()) : null,
          ),
          worldNames: Value(jsonEncode(card.worldNames)),
        ),
      );
      card.dbId = dbId;

      _characters.add(card);
    }

    // Imported lore stays on the card only (no auto-linked World).
    return card;
  }

  /// Bulk import multiple character PNG files.
  /// [onProgress] is called after each file with (current, total, cardName, error).
  /// Returns a summary map: `{imported: int, failed: int, errors: List<String>}`.
  Future<Map<String, dynamic>> importCharacters(
    List<File> files, {
    void Function(int current, int total, String name, String? error)?
    onProgress,
    bool Function()? isCancelled,
  }) async {
    int imported = 0;
    int failed = 0;
    final List<String> errors = [];

    for (int i = 0; i < files.length; i++) {
      // Check cancellation
      if (isCancelled != null && isCancelled()) break;

      final file = files[i];
      final fileName = file.path.split(Platform.pathSeparator).last;
      try {
        final card = await importCharacter(file);
        if (card != null) {
          imported++;
          onProgress?.call(i + 1, files.length, card.name, null);
        } else {
          failed++;
          final err = 'No card data found in $fileName';
          errors.add(err);
          onProgress?.call(i + 1, files.length, fileName, err);
        }
      } catch (e) {
        failed++;
        final err = '$fileName: $e';
        errors.add(err);
        onProgress?.call(i + 1, files.length, fileName, e.toString());
      }
    }

    return {'imported': imported, 'failed': failed, 'errors': errors};
  }

  Future<CharacterCard?> duplicateCharacter(
    CharacterCard card, {
    // Generalized for decoupled group private copies (per plan "reuse duplicateCharacter pattern").
    // When targetDirOverride provided + skipLibraryInsert, performs clone + file copy + V2 re-embed
    // into the caller's dir (e.g. groups/<gid>/avatars/) without touching library DB or _characters list.
    String? targetDirOverride,
    String? forcedBasename,
    bool skipLibraryInsert = false,
    // AI Enhance passes '<Name> (Enhanced)'; default keeps the menu action's
    // behavior byte-for-byte.
    String? newNameOverride,
  }) async {
    _isLoading = true;
    _notify();
    try {
      final newName = newNameOverride ?? '${card.name} (duplicate)';

      // Clone the card model
      final clonedCard = CharacterCard(
        name: newName,
        description: card.description,
        personality: card.personality,
        scenario: card.scenario,
        firstMessage: card.firstMessage,
        mesExample: card.mesExample,
        systemPrompt: card.systemPrompt,
        postHistoryInstructions: card.postHistoryInstructions,
        alternateGreetings: List.from(card.alternateGreetings),
        tags: List.from(card.tags),
        ttsVoice: card.ttsVoice,
        lorebook: card.lorebook != null
            ? Lorebook(entries: List.from(card.lorebook!.entries))
            : null,
        worldNames: List.from(card.worldNames),
        // Deep copy realism extensions (not just reference copy)
        frontPorchExtensions: card.frontPorchExtensions != null
            ? card.frontPorchExtensions!.copyWith()
            : null,
        rawExtensions: card.rawExtensions != null
            ? Map<String, dynamic>.from(card.rawExtensions!)
            : null,
      );

      // Force a fresh stableId for the duplicate (new library identity + independent history).
      // CopyWith would have carried source's; explicit new UUID here per plan.
      if (clonedCard.frontPorchExtensions != null) {
        clonedCard.frontPorchExtensions!.stableId = const Uuid().v4();
      }

      // Handle image file duplication if exists (generalized target)
      if (card.imagePath != null) {
        final originalFile = File(card.imagePath!);
        if (await originalFile.exists()) {
          final charDir = targetDirOverride != null
              ? Directory(targetDirOverride)
              : _storage.charactersDir;
          if (!await charDir.exists()) {
            await charDir.create(recursive: true);
          }
          final baseForName = forcedBasename ?? newName;
          final safeName = baseForName
              .replaceAll(RegExp(r'[^\w\s\-]'), '')
              .replaceAll(' ', '_');
          final destPath = targetDirOverride != null
              ? '${charDir.path}/$safeName.png' // caller controls exact name (e.g. uuid)
              : '${charDir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.png';
          await originalFile.copy(destPath);
          clonedCard.imagePath = destPath;

          // Now write the V2 card data to the *new* PNG (always, for fidelity on extract)
          final v2Service = V2CardService();
          debugPrint(
            '[Duplicate] Saving PNG with extensions: ${clonedCard.frontPorchExtensions != null ? 'realism=${clonedCard.frontPorchExtensions!.realismEnabled}, bond=${clonedCard.frontPorchExtensions!.shortTermBond}' : 'none'}',
          );
          await v2Service.saveCardAsPng(clonedCard, destPath, destPath);
        }
      }

      // Guarantee a valid PNG always exists for the duplicate (protection for source
      // characters that have no avatar at all — common with older imports or stripped cards).
      // This ensures private group members are never dropped at load time and always
      // have something displayable (the V2CardService placeholder + full embedded metadata).
      if (clonedCard.imagePath == null) {
        final charDir = targetDirOverride != null
            ? Directory(targetDirOverride)
            : _storage.charactersDir;
        if (!await charDir.exists()) {
          await charDir.create(recursive: true);
        }
        final baseForName = forcedBasename ?? newName;
        final safeName = baseForName
            .replaceAll(RegExp(r'[^\w\s\-]'), '')
            .replaceAll(' ', '_');
        final destPath = targetDirOverride != null
            ? '${charDir.path}/$safeName.png'
            : '${charDir.path}/${safeName}_${DateTime.now().millisecondsSinceEpoch}.png';

        final v2Service = V2CardService();
        debugPrint(
          '[Duplicate] Source had no usable avatar — generating placeholder PNG for $newName at $destPath',
        );
        await v2Service.saveCardAsPng(clonedCard, destPath, null);
        clonedCard.imagePath = destPath;
      }

      if (!skipLibraryInsert) {
        // Insert into database (library path only)
        final dbImagePath = clonedCard.imagePath != null
            ? _toBasename(clonedCard.imagePath!)
            : null;
        final dbId = await _db.insertCharacterReturningId(
          CharactersCompanion(
            name: Value(clonedCard.name),
            description: Value(clonedCard.description),
            personality: Value(clonedCard.personality),
            scenario: Value(clonedCard.scenario),
            firstMessage: Value(clonedCard.firstMessage),
            mesExample: Value(clonedCard.mesExample),
            systemPrompt: Value(clonedCard.systemPrompt),
            postHistoryInstructions: Value(clonedCard.postHistoryInstructions),
            alternateGreetings: Value(
              jsonEncode(clonedCard.alternateGreetings),
            ),
            tags: Value(jsonEncode(clonedCard.tags)),
            imagePath: Value(dbImagePath),
            ttsVoice: Value(clonedCard.ttsVoice),
            lorebook: Value(
              clonedCard.lorebook != null
                  ? jsonEncode(clonedCard.lorebook!.toJson())
                  : null,
            ),
            worldNames: Value(jsonEncode(clonedCard.worldNames)),
          ),
        );
        clonedCard.dbId = dbId;

        _characters.add(clonedCard);
      }
      return clonedCard;
    } catch (e) {
      debugPrint('[Duplicate] Error duplicating character: $e');
      rethrow;
    } finally {
      _isLoading = false;
      _notify();
    }
  }
}
