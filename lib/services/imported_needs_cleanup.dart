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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' show AppDatabase;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/storage/settings/realism_settings.dart'
    show RealismSettingsImportStamp;
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/utils/utils.dart' show PngMetadataUtils;

// Before the silent-card fix (#454) every card save wrote
// `needs_sim_enabled: false`, and the importer saves every card it imports,
// so each plain card imported before it carries a "no" it never had and
// ignores the Porch Life Needs switch. This one-time pass removes that "no"
// from imported cards (maintainer ruling 2026-10-10: automatic, accepting
// that a deliberate "off" on an imported card is cleared once).

/// Settings the app writes onto an imported card without the person
/// choosing anything about Realism or Needs (identity, the portrait star,
/// chat colours and font), so they do not make a card look hand-made.
const _cosmeticKeys = {
  'stable_id',
  'avatar_locked',
  'user_bubble_color',
  'user_text_color',
  'ai_bubble_color',
  'ai_text_color',
  'dialogue_color',
  'action_color',
  'chat_font_family',
  'favorite_avatar_id',
};

String _shape(FrontPorchExtensions ext) {
  final realism = Map<String, dynamic>.of(
    ext.toJson()['realism_engine'] as Map<String, dynamic>,
  )..removeWhere((key, _) => _cosmeticKeys.contains(key));
  return jsonEncode(realism);
}

final String _importerStamp = _shape(
  FrontPorchExtensions(needsSimEnabled: false),
);

/// Whether [ext] is the block the importer stamped on a plain card before
/// #454: a default [FrontPorchExtensions] with an explicit Needs "no" and
/// nothing else chosen (cosmetic settings aside). The card holds no import
/// marker, so this is a shape match. The app's creators default Needs on
/// since 2026-08-16 and a Scene Guest carries a tier, so neither matches.
/// One app-made shape does: Realism off, every Realism and Porch Life field
/// left at its default, Needs off. The creators hide the Needs switch while
/// Realism is off, and before 2026-08-16 it defaulted off, so those cards
/// got that off unasked; since then it takes switching Realism on, Needs
/// off, then Realism off again.
bool isImporterNeedsStamp(FrontPorchExtensions? ext) =>
    ext != null && ext.needsSimChoice == false && _shape(ext) == _importerStamp;

/// How one clean-up pass went.
class ImportedNeedsCleanupResult {
  const ImportedNeedsCleanupResult({required this.cleared, this.skipped = 0});
  final int cleared;
  final int skipped;
}

/// Clears the importer's Needs "no" from every library card that carries it.
/// Only the `needs_sim_enabled` key leaves the card's `chara` text; the rest
/// of the PNG, pixels included, stays byte for byte. A card whose settings
/// did not load is read from its PNG here. A card that cannot be read or
/// written is skipped and logged, never deleted. The file work runs on a
/// background isolate; each file is replaced in one rename, so a quit midway
/// leaves every card either untouched or cleared.
Future<ImportedNeedsCleanupResult> clearImportedNeedsStamps(
  CharacterRepository repo,
) async {
  final paths = [
    for (final c in repo.characters)
      if (c.imagePath != null &&
          (c.frontPorchExtensions == null ||
              isImporterNeedsStamp(c.frontPorchExtensions)))
        c.imagePath!,
  ];
  if (paths.isEmpty) return const ImportedNeedsCleanupResult(cleared: 0);

  final outcome = await _clearInBackground(paths);
  for (final entry in outcome.skipped.entries) {
    debugPrint('[ImportedNeeds] skipped ${entry.key}: ${entry.value}');
  }
  // Re-read the live list: a reload during the isolate's work replaced the
  // card objects, and those already read the cleared PNGs.
  final cleared = outcome.cleared.toSet();
  for (final c in repo.characters) {
    if (cleared.contains(c.imagePath)) {
      c.frontPorchExtensions?.needsSimChoice = null;
    }
  }
  if (cleared.isNotEmpty) repo.notifyCharactersChanged();
  return ImportedNeedsCleanupResult(
    cleared: cleared.length,
    skipped: outcome.skipped.length,
  );
}

/// The library repository as the app builds it: its constructor starts the
/// load, and the once-only clean-up waits for that load in the background,
/// so the first frame never waits on it.
CharacterRepository openCharacterRepository(
  AppDatabase db,
  StorageService storage,
) {
  final repo = CharacterRepository(db, storage);
  final cleanup = runImportedNeedsCleanupOnce(repo, storage);
  debugImportedNeedsCleanup = cleanup;
  unawaited(cleanup);
  return repo;
}

/// The clean-up the last [openCharacterRepository] started, for tests to
/// wait on.
@visibleForTesting
Future<ImportedNeedsCleanupResult?>? debugImportedNeedsCleanup;

/// Runs [clearImportedNeedsStamps] once per library, after the library has
/// loaded. Returns the result (null when it did not run) so a test can wait
/// for it.
Future<ImportedNeedsCleanupResult?> runImportedNeedsCleanupOnce(
  CharacterRepository repo,
  StorageService storage,
) async {
  try {
    await storage.initialized;
    if (storage.realismSettings.importedNeedsStampCleared) return null;
    await repo.whenLoaded;
    // A load that failed, or ran before the storage root was known, read no
    // card settings; deciding on it would set the flag over a library that
    // was never looked at. Read it once more now the root is known, and
    // failing that, try again next launch.
    if (!repo.libraryLoaded) await repo.loadCharacters();
    if (!repo.libraryLoaded) {
      debugPrint('[ImportedNeeds] library not loaded; trying next launch');
      return null;
    }
    final result = await clearImportedNeedsStamps(repo);
    // Done only when every card was looked at; a skipped card is tried
    // again next launch.
    if (result.skipped == 0) {
      await storage.realismSettings.markImportedNeedsStampCleared();
    }
    debugPrint(
      '[ImportedNeeds] ${result.cleared} imported card(s) now follow the '
      'Porch Life Needs switch; ${result.skipped} skipped'
      '${result.skipped == 0 ? '' : ', trying those next launch'}',
    );
    return result;
  } catch (e) {
    debugPrint('[ImportedNeeds] clean-up failed; trying next launch: $e');
    return null;
  }
}

typedef _FilesOutcome = ({List<String> cleared, Map<String, String> skipped});

// Its own function so the isolate's closure captures only [paths], never the
// caller's repository (which cannot cross to another isolate).
Future<_FilesOutcome> _clearInBackground(List<String> paths) =>
    Isolate.run(() => _clearStampsInFiles(paths));

Future<_FilesOutcome> _clearStampsInFiles(List<String> paths) async {
  final cleared = <String>[];
  final skipped = <String, String>{};
  for (final path in paths) {
    try {
      final reason = await _clearStampInFile(path);
      if (reason == null) {
        cleared.add(path);
      } else if (reason.isNotEmpty) {
        skipped[path] = reason;
      }
    } catch (e) {
      skipped[path] = '$e';
    }
  }
  return (cleared: cleared, skipped: skipped);
}

/// Null when cleared, '' when the card carries no stamp, or the reason it
/// was skipped.
Future<String?> _clearStampInFile(String path) async {
  final file = File(path);
  final before = await file.stat();
  final bytes = await file.readAsBytes();
  final chara = PngMetadataUtils.extractTextChunk(bytes, 'chara');
  if (chara == null) {
    // A readable PNG with no card data has no stamp to clear.
    return _isPng(bytes) ? '' : 'not a readable PNG';
  }
  final json = utf8.decode(base64Decode(chara));
  final payload = jsonDecode(json);
  final card = V2CardService().parseCardJson(json);
  if (card == null || payload is! Map) return 'card data could not be read';
  if (!isImporterNeedsStamp(card.frontPorchExtensions)) return '';

  // Same lookup as parseCardJson: the V2 envelope's data, or a flat card.
  // Only the one key changes; the card is not rebuilt from the model.
  final data = payload['data'] is Map ? payload['data'] as Map : payload;
  final extensions = data['extensions'] as Map;
  final realism = (extensions['front_porch'] as Map)['realism_engine'] as Map;
  realism.remove('needs_sim_enabled');
  final updated = PngMetadataUtils.replaceTextChunk(
    bytes,
    'chara',
    base64Encode(utf8.encode(jsonEncode(payload))),
  );
  if (updated == null) return 'card data is not in a plain text chunk';

  final tmp = File('$path.needs-clear.tmp');
  await tmp.writeAsBytes(updated, flush: true);
  final now = await file.stat();
  if (now.modified != before.modified || now.size != before.size) {
    await tmp.delete();
    return 'the card changed while it was being cleared';
  }
  await tmp.rename(path);
  return null;
}

bool _isPng(List<int> bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}
