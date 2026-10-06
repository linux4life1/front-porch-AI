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

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'porch_format.dart';
import 'porch_import_report.dart';
import 'porch_open_chat.dart';

/// Reads `.porch` and `.porchpack` files into the library. Any other file
/// is refused by name; a character the library already has is skipped.
class PorchImporter {
  PorchImporter({required this.repo, required this.chat});

  final CharacterRepository repo;
  final ChatService chat;

  Future<PorchImportReport> importFiles(
    List<({String name, Uint8List bytes})> files, {
    void Function(int done, int total, String name)? onProgress,
  }) {
    return keepingOpenChat(chat, () async {
      final report = PorchImportReport();
      for (final (i, f) in files.indexed) {
        onProgress?.call(i, files.length, f.name);
        final ext = p.extension(f.name).toLowerCase();
        try {
          if (ext == '.$kPorchExtension') {
            await _importOne(await _decodeOff(f.bytes, f.name), report);
          } else if (ext == '.$kPorchPackExtension') {
            for (final e in await _unpackOff(f.bytes, f.name)) {
              try {
                await _importOne(await _decodeOff(e.bytes, e.fileName), report);
              } on PorchRefused catch (r) {
                report.refused.add(r.message);
              }
            }
          } else {
            report.refused.add(
              '“${f.name}” isn’t a .porch or .porchpack file, so it wasn’t '
              'imported. Pick a file Front Porch AI exported as .porch or '
              '.porchpack.',
            );
          }
        } on PorchRefused catch (r) {
          report.refused.add(r.message);
        }
      }
      onProgress?.call(files.length, files.length, '');
      return report;
    });
  }

  /// "Already there" uses the identity the app already keys on: the id the
  /// card itself carries (what a card re-import updates in place), else the
  /// portrait basename that keys a character's chats, with the same name so
  /// two different cards that happen to share a file name stay apart.
  CharacterCard? _alreadyInLibrary(PorchCharacter c) {
    final byCard = repo.findByStableId(c.stableId);
    if (byCard != null) return byCard;
    for (final card in repo.characters) {
      if (card.stableGroupId == c.stableGroupId && card.name == c.name) {
        return card;
      }
    }
    return null;
  }

  Future<void> _importOne(PorchCharacter c, PorchImportReport report) async {
    final existing = _alreadyInLibrary(c);
    if (existing != null) {
      report.skipped.add(existing.name);
      return;
    }
    final tmp = await Directory.systemTemp.createTemp('fpai_porch_');
    try {
      final cardFile = File(p.join(tmp.path, '${porchSafeName(c.name)}.png'));
      await cardFile.writeAsBytes(c.cardPng, flush: true);
      if (await V2CardService().readCard(cardFile.path) == null) {
        throw PorchRefused(
          'The character card for “${c.name}” is damaged, so it wasn’t '
          'imported. Export it again, then import the new file.',
        );
      }
      final card = await repo.importCharacter(cardFile);
      final dbId = card?.dbId;
      if (card == null || dbId == null) {
        throw PorchRefused(
          '“${c.name}” couldn’t be added to the library. Try importing it '
          'again.',
        );
      }
      String? star;
      for (final look in c.looks) {
        final id = await repo.addLook(dbId, card.name, look.bytes);
        if (look.starred && id.isNotEmpty) star = id;
      }
      for (final face in c.expressions) {
        final id = await repo.addAvatar(
          dbId,
          card.name,
          face.bytes,
          face.label,
        );
        if (face.starred) star = id;
      }
      await _pointStar(card, star);
      report.chats += await chat.importChatPackagesOnto(card, c.chats);
      report.imported.add(card.name);
    } finally {
      try {
        await tmp.delete(recursive: true);
      } catch (e) {
        debugPrint('[porch] temp folder left behind: $e');
      }
    }
  }

  /// The card arrives naming the exporting library's ★ row id; point it at
  /// the row that now holds that image, or clear it back to the portrait.
  Future<void> _pointStar(CharacterCard card, String? star) async {
    final ext = card.frontPorchExtensions;
    if (ext == null || ext.favoriteAvatarId == star) return;
    ext.favoriteAvatarId = star;
    await repo.updateCharacter(card);
  }
}

// Top level, so each isolate closure captures only its arguments.
Future<PorchCharacter> _decodeOff(Uint8List bytes, String name) =>
    Isolate.run(() => decodePorch(bytes, fileName: name));

Future<List<({String fileName, Uint8List bytes})>> _unpackOff(
  Uint8List bytes,
  String name,
) => Isolate.run(() => decodePorchPack(bytes, fileName: name));
