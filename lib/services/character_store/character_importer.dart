// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Card import (single + bulk, PNG or standalone V2 JSON) and duplication
// (library copy + the group private-copy variant) for the character library.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_store/character_row_codec.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';

class CharacterImporter {
  CharacterImporter({
    required AppDatabase Function() db,
    required StorageService storage,
    required List<CharacterCard> Function() characters,
    required CharacterCard? Function(String? stableId) findByStableId,
    required Future<void> Function(CharacterCard card) updateCharacter,
    required Future<void> Function(String characterId) clearGalleryLooks,
    required void Function(CharacterCard card) addToLibrary,
  }) : _db = db,
       _storage = storage,
       _characters = characters,
       _findByStableId = findByStableId,
       _updateCharacter = updateCharacter,
       _clearGalleryLooks = clearGalleryLooks,
       _addToLibrary = addToLibrary;

  final AppDatabase Function() _db;
  final StorageService _storage;
  final List<CharacterCard> Function() _characters;
  final CharacterCard? Function(String? stableId) _findByStableId;
  final Future<void> Function(CharacterCard card) _updateCharacter;
  final Future<void> Function(String characterId) _clearGalleryLooks;
  final void Function(CharacterCard card) _addToLibrary;

  /// Read [file] (V2 PNG or standalone V2 JSON) and persist it. See
  /// [_persist] for the collision policy.
  Future<CharacterCard?> importFile(
    File file, {
    CharacterCard? forceReplaceTarget,
  }) async {
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

    return await _persist(
      card,
      // JSON has no image to copy; persist synthesizes a placeholder instead.
      sourceFileForCopy: isJson ? null : file,
      forceReplaceTarget: forceReplaceTarget,
    );
  }

  /// Persists an already-parsed CharacterCard.
  ///
  /// Collision policy (issue #161 + history-preserving reimport):
  /// - **stableId match** → update in place (reuse dbId + PNG path; chats kept)
  /// - **[forceReplaceTarget]** → same update path when the user explicitly
  ///   chose Replace on a same-name card that has no stableId match
  /// - **name-only collision** → fresh insert (never soft-delete peers)
  ///
  /// Ensures stableId is present before embedding via saveCardAsPng.
  /// When [sourceFileForCopy] is provided we use it as visual source for V2 embed.
  Future<CharacterCard?> _persist(
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
    final stableMatch = _findByStableId(card.frontPorchExtensions?.stableId);
    CharacterCard? target = stableMatch;
    if (target == null && forceReplaceTarget != null) {
      // Resolve against the live list by dbId so we don't hold a stale ref.
      final rid = forceReplaceTarget.dbId;
      if (rid != null) {
        for (final c in _characters()) {
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
        ? toBasename(card.imagePath!)
        : null;

    if (target != null) {
      // Update-in-place: reuse dbId so sessions/chat history survive.
      if (target.imagePath != null) {
        final oldBase = toBasename(target.imagePath!);
        final newBase = toBasename(destPath);
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
      await _clearGalleryLooks(card.dbId!);

      // updateCharacter does DB companion + list replace (re-embeds PNG; harmless).
      await _updateCharacter(card);
    } else {
      final dbId = await _db().insertCharacterReturningId(
        characterCompanion(card, dbImagePath: dbImagePath),
      );
      card.dbId = dbId;

      _addToLibrary(card);
    }

    // Imported lore stays on the card only (no auto-linked World).
    return card;
  }

  /// Bulk import via [importOne], one file at a time.
  static Future<Map<String, dynamic>> importAll(
    List<File> files, {
    required Future<CharacterCard?> Function(File file) importOne,
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
        final card = await importOne(file);
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

  /// Clone [card] with a fresh stableId, copying or generating its PNG.
  Future<CharacterCard> duplicate(
    CharacterCard card, {
    String? targetDirOverride,
    String? forcedBasename,
    bool skipLibraryInsert = false,
    String? newNameOverride,
  }) async {
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
          ? toBasename(clonedCard.imagePath!)
          : null;
      final dbId = await _db().insertCharacterReturningId(
        characterCompanion(clonedCard, dbImagePath: dbImagePath),
      );
      clonedCard.dbId = dbId;

      _addToLibrary(clonedCard);
    }
    return clonedCard;
  }
}
